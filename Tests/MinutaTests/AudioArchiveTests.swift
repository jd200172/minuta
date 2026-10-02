import XCTest

@testable import Minuta

final class AudioArchiveTests: XCTestCase {
    private var atas: URL!
    private var audio: URL!
    private var pending: URL!
    private let meta = MeetingMeta(start: Date(timeIntervalSince1970: 1_790_000_000), duration: 240)
    private let transcript = Transcript(segments: [
        Segment(id: "t-000002", speaker: "Juliano", start: 2, text: "Vamos adiar o lançamento."),
        Segment(id: "t-000010", speaker: "Participante 1", start: 10, text: "Eu envio o relatório."),
    ])

    override func setUpWithError() throws {
        UserDefaults.standard.set("Juliano", forKey: Config.userNameKey)
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("minuta-audio-\(UUID().uuidString)")
        atas = base.appendingPathComponent("atas")
        audio = base.appendingPathComponent("audio")
        pending = base.appendingPathComponent("pending")
        for dir in [atas!, pending!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: atas.deletingLastPathComponent())
    }

    private func recording(_ name: String) throws -> URL {
        let url = pending.appendingPathComponent(name)
        try Data("audio de \(name)".utf8).write(to: url)
        return url
    }

    private func newAta(classification: Classification? = nil) throws -> URL {
        try AtaStore.create(
            meta: meta, transcript: transcript, classification: classification, in: atas, audioDir: audio)
    }

    func testStemComesFromTheSidecarName() {
        let dir = URL(fileURLWithPath: "/tmp")
        XCTAssertEqual(
            AudioArchive.stem(ofSidecar: dir.appendingPathComponent("2026-10-01 1906.resumos.json")), "2026-10-01 1906")
        XCTAssertEqual(
            AudioArchive.stem(ofSidecar: dir.appendingPathComponent("2026-10-01 1906 (2).resumos.json")),
            "2026-10-01 1906 (2)")
    }

    func testAudioIsKeptWithTheNameOfTheSidecar() throws {
        let url = try newAta()
        let text = try String(contentsOf: url, encoding: .utf8)
        let sidecar = try AtaStore.loadSidecar(for: url, text: text).url
        let stem = sidecar.lastPathComponent.replacingOccurrences(of: ".resumos.json", with: "")

        let kept = AtaStore.keepAudio(
            mic: try recording("mic.m4a"), system: try recording("system.m4a"), forMarkdown: url, audioDir: audio)
        XCTAssertEqual(kept, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.appendingPathComponent("\(stem).mic.m4a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.appendingPathComponent("\(stem).system.m4a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.appendingPathComponent("mic.m4a").path))
        XCTAssertEqual(AtaStore.audioFiles(forMarkdown: url, audioDir: audio).count, 2)
    }

    func testTheNameDoesNotChangeWhenTheMeetingIsRenamed() throws {
        let url = try newAta(
            classification: Classification(model: .geral, confident: true, reason: "r", title: "Primeiro título"))
        AtaStore.keepAudio(mic: try recording("mic.m4a"), system: nil, forMarkdown: url, audioDir: audio)
        let renamed = try AtaStore.rename(url, to: "Outro título")
        XCTAssertNotEqual(renamed.lastPathComponent, url.lastPathComponent)
        XCTAssertEqual(AtaStore.audioFiles(forMarkdown: renamed, audioDir: audio).count, 1)
    }

    func testOnlyTheFilesThatExistAreKept() throws {
        let url = try newAta()
        let kept = AtaStore.keepAudio(
            mic: pending.appendingPathComponent("nao-existe.m4a"), system: try recording("system.m4a"),
            forMarkdown: url, audioDir: audio)
        XCTAssertEqual(kept, 1)
        XCTAssertEqual(
            AtaStore.audioFiles(forMarkdown: url, audioDir: audio).map {
                $0.lastPathComponent.hasSuffix(".system.m4a")
            }, [true])
    }

    func testTrashingTheMeetingTrashesItsAudio() throws {
        let url = try newAta()
        AtaStore.keepAudio(
            mic: try recording("mic.m4a"), system: try recording("system.m4a"), forMarkdown: url, audioDir: audio)
        let files = AtaStore.audioFiles(forMarkdown: url, audioDir: audio)
        XCTAssertEqual(files.count, 2)
        try AtaStore.trash(url, audioDir: audio)
        for file in files { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAMeetingNeverTakesTheNameOfAudioThatIsStillKept() throws {
        let first = try newAta()
        AtaStore.keepAudio(mic: try recording("mic.m4a"), system: nil, forMarkdown: first, audioDir: audio)
        // The files of the first meeting are deleted outside the app; its recording stays.
        let text = try String(contentsOf: first, encoding: .utf8)
        try FileManager.default.removeItem(at: try AtaStore.loadSidecar(for: first, text: text).url)
        try FileManager.default.removeItem(at: first)

        let second = try newAta()
        let secondText = try String(contentsOf: second, encoding: .utf8)
        let sidecar = try AtaStore.loadSidecar(for: second, text: secondText).url
        XCTAssertTrue(sidecar.lastPathComponent.hasSuffix("(2).resumos.json"), sidecar.lastPathComponent)
        XCTAssertEqual(
            AtaStore.audioFiles(forMarkdown: second, audioDir: audio).count, 0, "o áudio antigo não vira o desta ata")
    }

    func testLegacyAudioMovesToTheFolderWithoutOverwriting() throws {
        let legacy = audio.deletingLastPathComponent().appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("novo".utf8).write(to: legacy.appendingPathComponent("2026-10-01 1906.mic.m4a"))
        try Data("novo".utf8).write(to: legacy.appendingPathComponent("2026-10-01 1906.system.m4a"))
        try Data("antigo".utf8).write(to: atas.appendingPathComponent("2026-10-01 1906.system.m4a"))

        XCTAssertEqual(AudioArchive.migrateLegacy(from: legacy, to: atas), 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: atas.appendingPathComponent("2026-10-01 1906.mic.m4a").path))
        XCTAssertEqual(
            try String(contentsOf: atas.appendingPathComponent("2026-10-01 1906.system.m4a"), encoding: .utf8), "antigo"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: legacy.appendingPathComponent("2026-10-01 1906.system.m4a").path))
    }
}
