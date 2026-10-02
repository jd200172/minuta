import Foundation

/// The recordings of a meeting, kept after the transcript is written (ADR 0022). Each meeting has up to two files,
/// named with the stem of its sidecar, so the audio, the transcript and the summaries share one name:
///
///     2026-10-01 1906.resumos.json   transcript and summaries (ADR 0017)
///     2026-10-01 1906.mic.m4a        the user's microphone
///     2026-10-01 1906.system.m4a     the call (system audio)
///
/// The title is not part of the name, like the sidecar, so renaming the meeting never touches the audio.
enum AudioArchive {
    static let micSuffix = "mic.m4a"
    static let systemSuffix = "system.m4a"
    private static let sidecarSuffix = ".resumos.json"

    /// "2026-10-01 1906" from "2026-10-01 1906.resumos.json" (or "… (2).resumos.json").
    static func stem(ofSidecar url: URL) -> String {
        let name = url.lastPathComponent
        return name.hasSuffix(sidecarSuffix)
            ? String(name.dropLast(sidecarSuffix.count)) : url.deletingPathExtension().lastPathComponent
    }

    static func urls(stem: String, in dir: URL) -> (mic: URL, system: URL) {
        (
            dir.appendingPathComponent("\(stem).\(micSuffix)"),
            dir.appendingPathComponent("\(stem).\(systemSuffix)")
        )
    }

    /// The audio files of `stem` that exist.
    static func existing(stem: String, in dir: URL) -> [URL] {
        let pair = urls(stem: stem, in: dir)
        return [pair.mic, pair.system].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Moves the recordings that exist into `dir` under `stem` and returns how many were moved. A file already there
    /// with that name (the audio of a meeting whose files were deleted outside the app) goes to the Trash first.
    @discardableResult
    static func keep(mic: URL?, system: URL?, stem: String, in dir: URL) -> Int {
        let fm = FileManager.default
        let pair = urls(stem: stem, in: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var moved = 0
        for (source, destination) in [(mic, pair.mic), (system, pair.system)] {
            guard let source, fm.fileExists(atPath: source.path) else { continue }
            if fm.fileExists(atPath: destination.path) { try? fm.trashItem(at: destination, resultingItemURL: nil) }
            do {
                try fm.moveItem(at: source, to: destination)
                moved += 1
            } catch {
                continue
            }
        }
        return moved
    }

    /// Moves the recordings kept in the old Application Support folder into `dir` and returns how many were moved.
    /// A file that already exists in `dir` stays where it is, so nothing is overwritten. The old folder is removed
    /// once it is empty.
    @discardableResult
    static func migrateLegacy(from legacy: URL, to dir: URL) -> Int {
        let fm = FileManager.default
        guard legacy.standardizedFileURL != dir.standardizedFileURL,
            let names = try? fm.contentsOfDirectory(atPath: legacy.path)
        else { return 0 }
        let audio = names.filter { $0.hasSuffix(".\(micSuffix)") || $0.hasSuffix(".\(systemSuffix)") }
        guard !audio.isEmpty else {
            if names.isEmpty { try? fm.removeItem(at: legacy) }
            return 0
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var moved = 0
        for name in audio {
            let destination = dir.appendingPathComponent(name)
            guard !fm.fileExists(atPath: destination.path) else { continue }
            if (try? fm.moveItem(at: legacy.appendingPathComponent(name), to: destination)) != nil { moved += 1 }
        }
        if (try? fm.contentsOfDirectory(atPath: legacy.path))?.isEmpty == true { try? fm.removeItem(at: legacy) }
        return moved
    }
}
