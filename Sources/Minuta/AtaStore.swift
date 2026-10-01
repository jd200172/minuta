import Foundation

/// The second file of a meeting (ADR 0017): the segmented transcript with the original labels and every
/// summary generated for it, as structured output. The `.md` is rendered from it, so switching models
/// never calls the LLM again for a summary that already exists.
struct Sidecar: Codable, Equatable {
    var inicio: String
    var duracaoSegundos: Double
    var segments: [Segment]
    var classification: Classification?
    var summaries: [String: SummaryData]

    enum CodingKeys: String, CodingKey {
        case inicio, segments, classification, summaries
        case duracaoSegundos = "duracao_segundos"
    }

    func has(_ model: SummaryModel) -> Bool { summaries[model.rawValue] != nil }
}

/// Reads and writes the two files of a meeting. The key of a meeting is `inicio` (ISO 8601, with seconds
/// and time zone), written in both files; the file names are a convenience (ADR 0017).
enum AtaStore {
    // MARK: Front matter

    static func frontMatter(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return [:] }
        var result: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            result[line[..<colon].trimmingCharacters(in: .whitespaces)] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// The file was written by the model flow of ADR 0017 (it says which model, or that it has no summary).
    static func isManaged(_ text: String) -> Bool {
        let front = frontMatter(text)
        return front["modelo"] != nil || front["resumo"] != nil
    }

    static func model(in text: String) -> SummaryModel? {
        frontMatter(text)["modelo"].flatMap(SummaryModel.init(rawValue:))
    }

    static func title(in text: String) -> String? {
        frontMatter(text)["titulo"].flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Sidecar location

    private static func candidates(in dir: URL, start: Date) -> [URL] {
        let base = Fmt.fileStem(start)
        return (1...9).map {
            dir.appendingPathComponent($0 == 1 ? "\(base).resumos.json" : "\(base) (\($0)).resumos.json")
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    private static func read(_ url: URL) -> Sidecar? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Sidecar.self, from: data)
    }

    /// The sidecar of a meeting, found by `inicio`.
    static func sidecar(forMarkdown text: String, in dir: URL) -> (sidecar: Sidecar, url: URL)? {
        guard let inicio = frontMatter(text)["inicio"], let start = ISO8601DateFormatter().date(from: inicio) else {
            return nil
        }
        for url in candidates(in: dir, start: start) {
            if let sidecar = read(url), sidecar.inicio == inicio { return (sidecar, url) }
        }
        return nil
    }

    static func loadSidecar(for url: URL, text: String) throws -> (sidecar: Sidecar, url: URL) {
        if let found = sidecar(forMarkdown: text, in: url.deletingLastPathComponent()) { return found }
        throw AppError("Não foi possível ler os resumos guardados desta reunião.")
    }

    /// Where the sidecar of a meeting would be, whether or not it exists. Used to move it with the ata.
    static func sidecarURL(forMarkdown text: String, in dir: URL) -> URL? {
        sidecar(forMarkdown: text, in: dir)?.url
    }

    private static func save(_ sidecar: Sidecar, to url: URL) throws {
        try encoder.encode(sidecar).write(to: url, options: .atomic)
    }

    // MARK: Writing

    /// Renders the Markdown for the current state, keeping the names the user gave to participants.
    private static func compose(
        _ sidecar: Sidecar, title: String?, model: SummaryModel?, names: [String: String]
    ) throws -> String {
        let start = ISO8601DateFormatter().date(from: sidecar.inicio) ?? Date()
        let data = model.flatMap { sidecar.summaries[$0.rawValue] }
        var text = MinutesRenderer.render(
            meta: MeetingMeta(start: start, duration: sidecar.duracaoSegundos), title: title,
            model: data == nil ? nil : model, data: data, transcript: Transcript(segments: sidecar.segments))
        if !names.isEmpty { text = try ParticipantEditor.apply(names, to: text) }
        return text
    }

    private static func uniqueURL(dir: URL, stem: String, ignoring current: URL? = nil) -> URL {
        var url = dir.appendingPathComponent("\(stem).md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path), url.path != current?.path {
            url = dir.appendingPathComponent("\(stem) (\(n)).md")
            n += 1
        }
        return url
    }

    /// Writes the sidecar and the `.md` of a new meeting, with no summary yet. The title comes from the
    /// classification when there is one.
    static func create(
        meta: MeetingMeta, transcript: Transcript, classification: Classification?, in dir: URL
    ) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let sidecar = Sidecar(
            inicio: Fmt.iso(meta.start), duracaoSegundos: meta.duration, segments: transcript.segments,
            classification: classification, summaries: [:])
        guard let sidecarURL = candidates(in: dir, start: meta.start).first(where: { !fm.fileExists(atPath: $0.path) })
        else { throw AppError("Há reuniões demais começando no mesmo minuto na pasta de atas.") }
        let title = classification?.title
        let url = uniqueURL(dir: dir, stem: AtaName.stem(start: meta.start, title: title ?? ""))
        let text = try compose(sidecar, title: title, model: nil, names: [:])
        try save(sidecar, to: sidecarURL)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            try? fm.removeItem(at: sidecarURL)
            throw error
        }
        return url
    }

    /// Keeps a generated summary in the sidecar and makes it the one shown in the `.md`.
    static func commit(_ data: SummaryData, model: SummaryModel, to url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var (sidecar, sidecarURL) = try loadSidecar(for: url, text: text)
        sidecar.summaries[model.rawValue] = data
        try save(sidecar, to: sidecarURL)
        try write(model: model, sidecar: sidecar, current: text, to: url)
    }

    /// Shows an already generated summary in the `.md`, without calling the LLM.
    static func select(_ model: SummaryModel, in url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let (sidecar, _) = try loadSidecar(for: url, text: text)
        guard sidecar.has(model) else { throw AppError("Esta reunião ainda não tem resumo no modelo \(model.title).") }
        try write(model: model, sidecar: sidecar, current: text, to: url)
    }

    private static func write(model: SummaryModel, sidecar: Sidecar, current: String, to url: URL) throws {
        let text = try compose(
            sidecar, title: title(in: current), model: model, names: ParticipantEditor.names(in: current))
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Changes the title in the `.md` and in its file name. The sidecar keeps its name. Returns the new URL.
    /// Files without a sidecar (older atas) get the new title in the `# ` line and in the file name only.
    static func rename(_ url: URL, to newTitle: String) throws -> URL {
        let text = try String(contentsOf: url, encoding: .utf8)
        let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated: String
        let start: Date
        if isManaged(text), let (sidecar, _) = sidecar(forMarkdown: text, in: url.deletingLastPathComponent()) {
            updated = try compose(
                sidecar, title: clean, model: model(in: text), names: ParticipantEditor.names(in: text))
            start = ISO8601DateFormatter().date(from: sidecar.inicio) ?? Date()
        } else if isManaged(text) {
            throw AppError("Não foi possível ler os resumos guardados desta reunião.")
        } else {
            updated = retitled(text, to: clean)
            start =
                AtaName.parse(url.deletingPathExtension().lastPathComponent)?.start
                ?? frontMatter(text)["inicio"].flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        }
        let target = uniqueURL(
            dir: url.deletingLastPathComponent(), stem: AtaName.stem(start: start, title: clean), ignoring: url)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        if target.path != url.path { try FileManager.default.moveItem(at: url, to: target) }
        return target
    }

    /// The text with a new title in the first `# ` line, or one added after the front matter.
    static func retitled(_ text: String, to title: String) -> String {
        let heading = "# " + (title.isEmpty ? MinutesRenderer.untitled : title)
        var lines = text.components(separatedBy: "\n")
        var body = 0
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { body = end + 1 }
        if let index = lines[body...].firstIndex(where: { $0.hasPrefix("# ") }) {
            lines[index] = heading
        } else {
            lines.insert(contentsOf: [heading, ""], at: body)
        }
        return lines.joined(separator: "\n")
    }

    /// Moves the `.md` and its sidecar to the Trash.
    static func trash(_ url: URL) throws {
        let fm = FileManager.default
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let companion = sidecarURL(forMarkdown: text, in: url.deletingLastPathComponent())
        try fm.trashItem(at: url, resultingItemURL: nil)
        if let companion { try? fm.trashItem(at: companion, resultingItemURL: nil) }
    }
}
