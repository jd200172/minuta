import Foundation

struct Job: Codable, Identifiable {
    enum Stage: String, Codable { case recording, transcribing, minuting }
    var id: String
    var startedAt: Date
    var durationSeconds: Double
    var stage: Stage
    var micOffset: Double
    var systemOffset: Double
    var lastError: String?
}

struct Segment: Codable, Equatable {
    var id: String
    var speaker: String
    var start: Double
    var text: String
    /// What the speech-to-text returned, when the cleaning step (ADR 0031) changed `text`.
    var raw: String?
}

struct Transcript: Codable {
    var segments: [Segment]
}

final class JobStore {
    let root: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Minuta/pending")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func dir(_ id: String) -> URL {
        root.appendingPathComponent(id)
    }

    func makeDir(_ id: String) throws {
        try FileManager.default.createDirectory(at: dir(id), withIntermediateDirectories: true)
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func save(_ job: Job) {
        try? encoder.encode(job).write(to: dir(job.id).appendingPathComponent("job.json"))
    }

    func load() -> [Job] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return ids.compactMap { id in
            guard let data = try? Data(contentsOf: dir(id).appendingPathComponent("job.json")) else { return nil }
            return try? decoder.decode(Job.self, from: data)
        }.sorted { $0.startedAt < $1.startedAt }
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: dir(id))
    }

    func saveTranscript(_ transcript: Transcript, job: Job) throws {
        try encoder.encode(transcript).write(to: dir(job.id).appendingPathComponent("transcript.json"))
    }

    func loadTranscript(job: Job) throws -> Transcript {
        let data = try Data(contentsOf: dir(job.id).appendingPathComponent("transcript.json"))
        return try decoder.decode(Transcript.self, from: data)
    }
}
