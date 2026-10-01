import AVFoundation

/// Records a few seconds from both sources and reports whether each one carried sound.
enum CaptureTest {
    struct Result {
        var hasMicrophone: Bool
        var micPeak: Float
        var systemPeak: Float
        var micHasSignal: Bool { micPeak > 0.01 }
        var systemHasSignal: Bool { systemPeak > 0.01 }
    }

    static func run(seconds: Double = 5) async throws -> Result {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("minuta-capture-test")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = Recorder()
        try await recorder.ensurePermissions()
        let mic = dir.appendingPathComponent("mic.m4a")
        let system = dir.appendingPathComponent("system.m4a")
        try await recorder.start(micURL: mic, systemURL: system)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        let hasMic = recorder.micActive
        _ = await recorder.stop()
        return Result(hasMicrophone: hasMic, micPeak: hasMic ? peak(of: mic) : 0, systemPeak: peak(of: system))
    }

    private static func peak(of url: URL) -> Float {
        guard let file = try? AVAudioFile(forReading: url),
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384)
        else { return 0 }
        var peak: Float = 0
        while file.framePosition < file.length {
            do { try file.read(into: buffer) } catch { break }
            if buffer.frameLength == 0 { break }
            guard let data = buffer.floatChannelData?[0] else { break }
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
        }
        return peak
    }
}
