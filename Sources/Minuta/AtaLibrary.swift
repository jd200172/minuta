import Foundation

/// Why a file with a minutes file name cannot be shown as a normal ata.
enum AtaProblem: Equatable {
    case empty, unreadable, noHeader

    var label: String {
        switch self {
        case .empty: "Arquivo vazio"
        case .unreadable: "Não foi possível ler"
        case .noHeader: "Sem cabeçalho de ata"
        }
    }

    /// A file without a header still reads as a page; an empty or unreadable one has nothing to show.
    var canOpen: Bool { self == .noHeader }
}

enum FolderState: Equatable {
    case ok, missing, unreadable
}

struct Ata: Identifiable, Equatable {
    let url: URL
    let start: Date
    let title: String
    let duration: TimeInterval?
    /// The summary model shown in the file (ADR 0017). Files from before it have none.
    var model: SummaryModel? = nil
    /// The file was written without a summary yet.
    var noSummary = false
    var problem: AtaProblem?
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
    var model: SummaryModel?
    var noSummary = false

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
                if key == "titulo", !value.isEmpty { head.title = value }
                if key == "modelo" { head.model = SummaryModel(rawValue: value) }
                if key == "resumo" { head.noSummary = value == "nenhum" }
            }
            lines = Array(lines[(end + 1)...])
        }
        if head.title == nil, let line = lines.first(where: { $0.hasPrefix("# ") }) {
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
    @Published private(set) var folder: FolderState = .ok
    private var generation = 0

    func refresh() {
        pending = JobStore().load().filter { $0.stage != .recording }.sorted { $0.startedAt > $1.startedAt }
        generation += 1
        let current = generation
        let dir = Config.outputDir
        Task.detached {
            let result = AtaLibrary.scan(dir)
            await MainActor.run {
                guard current == self.generation else { return }
                self.atas = result.atas
                // A folder that was never there (first run, or a folder just chosen) is not a warning.
                // Only one that was seen before and is gone now is.
                if result.folder == .missing, Config.seenOutputDir != dir.path {
                    self.folder = .ok
                } else {
                    self.folder = result.folder
                    if result.folder == .ok { Config.seenOutputDir = dir.path }
                }
            }
        }
    }

    func trash(_ ata: Ata) throws {
        try AtaStore.trash(ata.url)
        atas.removeAll { $0.url == ata.url }
        refresh()
    }

    func discard(_ job: Job) {
        JobStore().delete(job.id)
        refresh()
    }

    /// Creates the folder again after it went missing.
    func recreateFolder() {
        try? FileManager.default.createDirectory(at: Config.outputDir, withIntermediateDirectories: true)
        refresh()
    }

    /// Most recent first; same start time: by title.
    nonisolated static func scan(_ dir: URL) -> (atas: [Ata], folder: FolderState) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ([], .missing)
        }
        guard
            let urls = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return ([], .unreadable) }

        let found: [Ata] = urls.compactMap { url in
            guard url.pathExtension.lowercased() == "md" else { return nil }
            let stem = url.deletingPathExtension().lastPathComponent
            let named = AtaName.parse(stem)
            let (head, problem) = inspect(url)
            // Files that do not look like minutes (personal notes) are not ours: only ata-named ones are flagged.
            if named == nil { guard problem == nil, head.start != nil else { return nil } }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return Ata(
                url: url, start: named?.start ?? head.start ?? modified ?? Date(),
                title: problem == nil ? (head.title ?? named?.title ?? "Sem título") : stem,
                duration: head.duration, model: head.model, noSummary: head.noSummary, problem: problem)
        }
        let sorted = found.sorted {
            $0.start != $1.start
                ? $0.start > $1.start : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        return (sorted, .ok)
    }

    /// Reads the first lines of a file and says what is wrong with it, if anything.
    nonisolated static func inspect(_ url: URL) -> (head: AtaHead, problem: AtaProblem?) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        if size == 0 { return (AtaHead(), .empty) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (AtaHead(), .unreadable) }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 2048), !data.isEmpty, let text = decodeHead(data) else {
            return (AtaHead(), .unreadable)
        }
        let head = AtaHead.parse(text)
        return (head, head.start == nil && head.title == nil ? .noHeader : nil)
    }

    /// UTF-8 text from a prefix of a file; the cut may land inside a multi-byte character.
    nonisolated static func decodeHead(_ data: Data) -> String? {
        for drop in 0...3 where data.count > drop {
            if let text = String(data: data.dropLast(drop), encoding: .utf8) { return text }
        }
        return nil
    }
}
