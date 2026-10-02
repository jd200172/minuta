import AVFoundation

/// Records a few seconds from both sources and reports whether each one carried sound.
enum CaptureTest {
    struct Result {
        var hasMicrophone: Bool
        var micPeak: Float
        var systemPeak: Float
        /// Average level of each channel, in dB below full scale (0 = full scale), over the whole test.
        var micLevel: Float = -120
        var systemLevel: Float = -120
        /// How closely the loudness of the microphone follows the loudness of the system channel, 0 to 1. High means
        /// the microphone is hearing the call through the speakers.
        var bleed: Float = 0
        var echoCancelled = false
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
        let cancelled = recorder.echoCancelled
        _ = await recorder.stop()
        var result = Result(hasMicrophone: hasMic, micPeak: hasMic ? peak(of: mic) : 0, systemPeak: peak(of: system))
        result.echoCancelled = cancelled
        if hasMic, let micSamples = samples(of: mic), let systemSamples = samples(of: system) {
            result.micLevel = level(micSamples)
            result.systemLevel = level(systemSamples)
            result.bleed = bleed(mic: micSamples, system: systemSamples)
        }
        return result
    }

    private static func samples(of url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384)
        else { return nil }
        var out: [Float] = []
        while file.framePosition < file.length {
            do { try file.read(into: buffer) } catch { break }
            if buffer.frameLength == 0 { break }
            guard let data = buffer.floatChannelData?[0] else { break }
            out.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        }
        return out
    }

    static func level(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -120 }
        let power = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        return max(-120, 10 * log10(max(power, 1e-12)))
    }

    /// The loudness of each channel in 50 ms frames, compared at delays up to half a second: the largest correlation.
    static func bleed(mic: [Float], system: [Float], frame: Int = 800, maxLag: Int = 10) -> Float {
        func envelope(_ x: [Float]) -> [Float] {
            stride(from: 0, to: x.count - frame, by: frame).map { start in
                sqrt(x[start..<start + frame].reduce(Float(0)) { $0 + $1 * $1 } / Float(frame))
            }
        }
        let a = envelope(mic)
        let b = envelope(system)
        let n = min(a.count, b.count)
        guard n > 2 * maxLag else { return 0 }
        func correlation(_ lag: Int) -> Float {
            let range = max(0, lag)..<min(n, n + lag)
            let x = range.map { a[$0] }
            let y = range.map { b[$0 - lag] }
            let mx = x.reduce(0, +) / Float(x.count)
            let my = y.reduce(0, +) / Float(y.count)
            var sxy: Float = 0
            var sxx: Float = 0
            var syy: Float = 0
            for i in 0..<x.count {
                sxy += (x[i] - mx) * (y[i] - my)
                sxx += (x[i] - mx) * (x[i] - mx)
                syy += (y[i] - my) * (y[i] - my)
            }
            return sxx > 0 && syy > 0 ? sxy / sqrt(sxx * syy) : 0
        }
        return (-maxLag...maxLag).map { abs(correlation($0)) }.max() ?? 0
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
