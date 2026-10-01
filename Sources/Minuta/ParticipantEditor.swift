import Foundation

/// A voice in one ata. `label` is the original label ("Participante 2", or the recorder's name);
/// `name` is what the text shows instead, when there is one.
struct Speaker: Identifiable, Equatable {
    enum Kind: Equatable {
        /// No name: the text shows the label.
        case unnamed
        /// A name the user gave. Recorded in the front matter as `participantes`.
        case manual
        /// A name the model inferred from the conversation: "Marina (Participante 2)" in the transcript.
        case inferred
    }

    let label: String
    let kind: Kind
    let name: String
    let time: String
    let quote: String
    var id: String { label }
    var shown: String { name.isEmpty ? label : name }
}

/// Names the voices of one ata (ADR 0016). A name given by the user replaces the label everywhere in
/// that ata, and the front matter keeps `participantes: {"Participante 2": "Marina"}` so the change can be
/// undone. Nothing is shared with other atas: labels are numbered per meeting.
enum ParticipantEditor {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let transcriptPattern = #"^<a id="t-\d+"></a>\*\*\[(\d{2}:\d{2}:\d{2})\] (.+?):\*\* ?(.*)$"#
    private static let inferredPattern = #"^(.+) \((Participante \d+)\)$"#
    private static let wordEdge = #"(?<![\p{L}\p{N}_])"#
    private static let wordEnd = #"(?![\p{L}\p{N}_])"#

    // MARK: Reading

    static func speakers(in text: String) -> [Speaker] {
        let (front, body) = split(text)
        let mapping = parseMapping(front)
        let labelByName = Dictionary(mapping.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        var result: [Speaker] = []
        var seen = Set<String>()
        for line in body {
            guard let m = groups(transcriptPattern, in: line), m.count == 3 else { continue }
            let raw = m[1].trimmingCharacters(in: .whitespaces)
            guard seen.insert(raw).inserted else { continue }
            let quote = String(m[2].prefix(120))
            if let parts = groups(inferredPattern, in: raw), parts.count == 2 {
                result.append(Speaker(label: parts[1], kind: .inferred, name: parts[0], time: m[0], quote: quote))
            } else if let label = labelByName[raw] {
                result.append(Speaker(label: label, kind: .manual, name: raw, time: m[0], quote: quote))
            } else {
                result.append(Speaker(label: raw, kind: .unnamed, name: "", time: m[0], quote: quote))
            }
        }
        return result
    }

    /// The names the user gave, by original label (front matter `participantes`).
    static func names(in text: String) -> [String: String] {
        parseMapping(split(text).0)
    }

    /// Why a name cannot be used, or nil. An empty name is valid: it clears the name.
    static func nameProblem(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.count > 60 { return "Use no máximo 60 caracteres." }
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: " .'’-"))
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Use só letras, números, espaços, ponto, hífen e apóstrofo."
        }
        return nil
    }

    /// True when `name` already appears as a word in the text of the ata (outside the front matter).
    static func nameAppears(_ name: String, in text: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let (_, body) = split(text)
        return body.contains { wordRegex(trimmed).firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            == b.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: Writing

    /// `desired` maps each original label to its new name ("" clears it). Returns the rewritten text.
    static func apply(_ desired: [String: String], to text: String) throws -> String {
        let current = speakers(in: text)
        struct Change {
            let speaker: Speaker
            let new: String
        }
        var changes: [Change] = []
        for speaker in current {
            guard let wanted = desired[speaker.label] else { continue }
            var new = wanted.trimmingCharacters(in: .whitespaces)
            if new == speaker.label { new = "" }
            if new == speaker.name { continue }
            if let problem = nameProblem(new) { throw Failure(message: problem) }
            changes.append(Change(speaker: speaker, new: new))
        }
        guard !changes.isEmpty else { return text }

        let finals = current.map { s in
            changes.first { $0.speaker.label == s.label }.map { $0.new.isEmpty ? s.label : $0.new } ?? s.shown
        }
        for (i, a) in finals.enumerated() {
            for b in finals[(i + 1)...] where same(a, b) {
                throw Failure(message: "Esse nome já está em uso nesta ata.")
            }
        }

        var (front, lines) = split(text, keepFront: true)
        let section = participantsRange(lines)

        // Two passes through private placeholders, so one speaker's new name is never replaced as
        // another speaker's old name.
        for (i, change) in changes.enumerated() {
            let token = "\u{E000}\(i)\u{E001}"
            let s = change.speaker
            let word = wordRegex(s.kind == .unnamed ? s.label : s.name)
            for index in lines.indices where !section.contains(index) {
                var line = lines[index]
                if s.kind == .inferred {
                    line = line.replacingOccurrences(of: "\(s.name) (\(s.label))", with: token)
                }
                lines[index] = replace(word, with: token, in: line)
            }
        }
        for (i, change) in changes.enumerated() {
            let token = "\u{E000}\(i)\u{E001}"
            let final = change.new.isEmpty ? change.speaker.label : change.new
            for index in lines.indices where !section.contains(index) {
                lines[index] = lines[index].replacingOccurrences(of: token, with: final)
            }
        }

        for change in changes {
            let s = change.speaker
            let oldHead = s.kind == .unnamed ? s.label : s.name
            let final = change.new.isEmpty ? s.label : change.new
            for index in section where listHead(lines[index]) == oldHead {
                lines[index] = change.new.isEmpty ? unnamedLine(s.label) : "- \(change.new)"
                break
            }
        }

        var mapping = parseMapping(front)
        for change in changes {
            mapping[change.speaker.label] = nil
            if !change.new.isEmpty { mapping[change.speaker.label] = change.new }
        }
        front.removeAll { $0.hasPrefix("participantes:") }
        if !mapping.isEmpty, let json = try? JSONSerialization.data(withJSONObject: mapping, options: [.sortedKeys]) {
            front.append("participantes: " + String(decoding: json, as: UTF8.self))
        }
        let head = front.isEmpty ? [] : ["---"] + front + ["---"]
        return (head + lines).joined(separator: "\n")
    }

    // MARK: Helpers

    /// Front matter lines and the body lines. With `keepFront` a missing front matter yields empty lines.
    private static func split(_ text: String, keepFront: Bool = false) -> ([String], [String]) {
        let lines = text.components(separatedBy: "\n")
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            return (Array(lines[1..<end]), Array(lines[(end + 1)...]))
        }
        return ([], lines)
    }

    private static func parseMapping(_ front: [String]) -> [String: String] {
        guard let line = front.first(where: { $0.hasPrefix("participantes:") }) else { return [:] }
        let json = line.dropFirst("participantes:".count).trimmingCharacters(in: .whitespaces)
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String]
        return object ?? [:]
    }

    private static func participantsRange(_ lines: [String]) -> Range<Int> {
        guard let start = lines.firstIndex(of: "## Participantes") else { return 0..<0 }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lines.count
        return (start + 1)..<end
    }

    /// The list line of a voice without a name: "Participante N" says so; the recorder's own label (the name
    /// from the settings) needs no note.
    private static func unnamedLine(_ label: String) -> String {
        label.range(of: #"^Participante \d+$"#, options: .regularExpression) != nil
            ? "- \(label) (sem nome identificado)" : "- \(label)"
    }

    /// "- Marina (Participante 2, nome inferido…)" -> "Marina".
    static func listHead(_ line: String) -> String? {
        guard line.hasPrefix("- ") else { return nil }
        let rest = line.dropFirst(2)
        let head = rest.range(of: " (").map { rest[..<$0.lowerBound] } ?? rest
        return head.trimmingCharacters(in: .whitespaces)
    }

    private static func wordRegex(_ word: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: wordEdge + NSRegularExpression.escapedPattern(for: word) + wordEnd)
    }

    private static func replace(_ regex: NSRegularExpression, with replacement: String, in line: String) -> String {
        regex.stringByReplacingMatches(
            in: line, range: NSRange(line.startIndex..., in: line),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: text).map { String(text[$0]) } }
    }
}
