import Foundation

struct Ata: Identifiable, Equatable {
    let url: URL
    let start: Date
    let title: String
    let duration: TimeInterval?
    var id: URL { url }
}

/// File names of the minutes: "yyyy-MM-dd HHmm Título.md" (older files: "yyyy-MM-dd HHmm.md").
enum AtaName {
    /// Title made safe for a file name: no path or reserved characters, collapsed spaces, at most 80 characters.
    static func sanitize(_ title: String) -> String {
        var text = title.replacingOccurrences(of: ":", with: " -")
        let invalid = CharacterSet(charactersIn: "/\\*?\"<>|").union(.controlCharacters).union(.newlines)
        text = text.components(separatedBy: invalid).joined(separator: " ")
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        text = String(text.prefix(80))
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
    }

    static func stem(start: Date, title: String) -> String {
        let safe = sanitize(title)
        return safe.isEmpty ? Fmt.fileStem(start) : "\(Fmt.fileStem(start)) \(safe)"
    }

    /// Start time and title from a file name without extension. Trailing " 2" or " (2)" collision
    /// suffixes are not part of the title.
    static func parse(_ stem: String) -> (start: Date, title: String?)? {
        guard stem.count >= 15 else { return nil }
        let prefix = String(stem.prefix(15))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        guard let start = f.date(from: prefix) else { return nil }
        var rest = String(stem.dropFirst(15)).trimmingCharacters(in: .whitespaces)
        if let range = rest.range(of: #"\s*\(\d+\)$"#, options: .regularExpression) { rest.removeSubrange(range) }
        if rest.range(of: #"^\d+$"#, options: .regularExpression) != nil { rest = "" }
        return (start, rest.isEmpty ? nil : rest)
    }
}

/// What the first lines of a minutes file say: start, duration and title.
struct AtaHead {
    var start: Date?
    var duration: TimeInterval?
    var title: String?

    static func parse(_ text: String) -> AtaHead {
        var head = AtaHead()
        var lines = text.components(separatedBy: "\n")
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if key == "inicio" { head.start = ISO8601DateFormatter().date(from: value) }
                if key == "duracao_segundos" { head.duration = Double(value) }
            }
            lines = Array(lines[(end + 1)...])
        }
        if let line = lines.first(where: { $0.hasPrefix("# ") }) {
            head.title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        return head
    }
}

/// The minutes in the output folder plus the recordings still being processed. The `.md` files are the
/// source of truth: the list is rebuilt from the folder, so edits and moves made in Finder show up.
@MainActor
final class AtaLibrary: ObservableObject {
    static let shared = AtaLibrary()

    @Published private(set) var atas: [Ata] = []
    @Published private(set) var pending: [Job] = []
    private var generation = 0

    func refresh() {
        pending = JobStore().load().filter { $0.stage != .recording }.sorted { $0.startedAt > $1.startedAt }
        generation += 1
        let current = generation
        let dir = Config.outputDir
        Task.detached {
            let found = AtaLibrary.scan(dir)
            await MainActor.run {
                if current == self.generation { self.atas = found }
            }
        }
    }

    func trash(_ ata: Ata) throws {
        try FileManager.default.trashItem(at: ata.url, resultingItemURL: nil)
        atas.removeAll { $0.url == ata.url }
        refresh()
    }

    func discard(_ job: Job) {
        JobStore().delete(job.id)
        refresh()
    }

    /// Most recent first; same start time: by title.
    nonisolated static func scan(_ dir: URL) -> [Ata] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let found: [Ata] = urls.compactMap { url in
            guard url.pathExtension.lowercased() == "md" else { return nil }
            let named = AtaName.parse(url.deletingPathExtension().lastPathComponent)
            let head = AtaHead.parse(readHead(url))
            guard named != nil || head.start != nil else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return Ata(
                url: url, start: named?.start ?? head.start ?? modified ?? Date(),
                title: head.title ?? named?.title ?? "Sem título", duration: head.duration)
        }
        return found.sorted {
            $0.start != $1.start
                ? $0.start > $1.start : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private nonisolated static func readHead(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 2048)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
