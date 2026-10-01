import AVFoundation
import CoreGraphics
import ScreenCaptureKit

/// Records the microphone and the system audio into two mono AAC files (16 kHz).
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    var onInterrupted: (() -> Void)?

    private let queue = DispatchQueue(label: "app.minuta.audio")
    private let engine = AVAudioEngine()
    private var stream: SCStream?
    private var micFile: AVAudioFile?
    private var systemFile: AVAudioFile?
    private var micConverter: AVAudioConverter?
    private var systemConverter: AVAudioConverter?
    private var micStart: Double?
    private var systemStart: Double?

    func ensurePermissions() async throws {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw AppError("Permita o microfone em Ajustes do Sistema > Privacidade e Segurança.")
            }
        }
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            throw AppError("Permita Gravação de Tela e Áudio do Sistema em Ajustes do Sistema e reabra o minuta.")
        }
    }

    func start(micURL: URL, systemURL: URL) async throws {
        micFile = try makeFile(micURL)
        systemFile = try makeFile(systemURL)
        micStart = nil
        systemStart = nil
        micConverter = nil
        systemConverter = nil

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw AppError("Nenhuma tela disponível para captura.") }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1
        config.width = 64
        config.height = 64
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let micFile else { throw AppError("Arquivo do microfone indisponível.") }
        micConverter = AVAudioConverter(from: inputFormat, to: micFile.processingFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.handleMic(buffer, time)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(engineChanged), name: .AVAudioEngineConfigurationChange, object: engine)
        engine.prepare()
        try engine.start()

        try await scStream.startCapture()
        stream = scStream
    }

    /// Stops both captures, closes the files and returns each track's start offset in seconds.
    func stop() async -> (mic: Double, system: Double) {
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? await stream?.stopCapture()
        stream = nil
        queue.sync {}
        micFile = nil
        systemFile = nil
        let starts = [micStart, systemStart].compactMap { $0 }
        let base = starts.min() ?? 0
        return ((micStart ?? base) - base, (systemStart ?? base) - base)
    }

    @objc private func engineChanged() {
        onInterrupted?()
    }

    private func makeFile(_ url: URL) throws -> AVAudioFile {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000,
        ]
        return try AVAudioFile(forWriting: url, settings: settings)
    }

    private func handleMic(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        guard let file = micFile, let converter = micConverter else { return }
        if micStart == nil {
            micStart = AVAudioTime.seconds(forHostTime: time.hostTime)
        }
        convertAndWrite(buffer, converter: converter, file: file)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let file = systemFile,
              let buffer = pcmBuffer(from: sampleBuffer) else { return }
        if systemStart == nil {
            systemStart = CMTimeGetSeconds(sampleBuffer.presentationTimeStamp)
        }
        if systemConverter == nil {
            systemConverter = AVAudioConverter(from: buffer.format, to: file.processingFormat)
        }
        if let converter = systemConverter {
            convertAndWrite(buffer, converter: converter, file: file)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onInterrupted?()
    }

    private func convertAndWrite(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, file: AVAudioFile) {
        let ratio = file.processingFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 {
            try? file.write(from: out)
        }
    }

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return nil }
        var streamDescription = asbd.pointee
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList)
        return status == noErr ? pcm : nil
    }
}
