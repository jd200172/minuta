import Foundation

struct Word {
    var text: String
    var speaker: String?
    var start: Double
    var end: Double
}

/// Transcribes one audio file with Gemini 3.5 Transcribe through the Interactions API.
struct GeminiTranscriber {
    let apiKey: String
    private let base = "https://generativelanguage.googleapis.com"

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }

    func transcribe(file: URL, diarize: Bool) async throws -> (text: String, words: [Word]) {
        let session = self.session
        let uploaded = try await upload(file, session: session)
        defer { Task { await delete(name: uploaded.name, session: session) } }

        var mode: [String: Any] = ["type": "verbatim", "timestamp_granularities": ["word"]]
        if diarize { mode["diarization_mode"] = "speaker" }
        let body: [String: Any] = [
            "model": Config.geminiModel,
            "input": [["type": "audio", "uri": uploaded.uri, "mime_type": "audio/m4a"]],
            "generation_config": [
                "transcription_config": ["language_codes": ["pt-BR"], "mode": mode],
            ],
        ]
        var request = URLRequest(url: URL(string: "\(base)/v1beta/interactions")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try httpCheck(response, data, provider: .google)
        return try parse(data)
    }

    private func upload(_ file: URL, session: URLSession) async throws -> (uri: String, name: String) {
        let payload = try Data(contentsOf: file)
        var start = URLRequest(url: URL(string: "\(base)/upload/v1beta/files")!)
        start.httpMethod = "POST"
        start.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        start.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        start.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        start.setValue(String(payload.count), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        start.setValue("audio/m4a", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        start.setValue("application/json", forHTTPHeaderField: "Content-Type")
        start.httpBody = Data(#"{"file":{"display_name":"minuta"}}"#.utf8)
        let (startData, startResponse) = try await session.data(for: start)
        try httpCheck(startResponse, startData, provider: .google)
        guard let http = startResponse as? HTTPURLResponse,
              let location = http.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: location) else {
            throw AppError("Google (envio do áudio): URL de upload ausente.")
        }

        var send = URLRequest(url: uploadURL)
        send.httpMethod = "POST"
        send.setValue(String(payload.count), forHTTPHeaderField: "Content-Length")
        send.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        send.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        let (data, response) = try await session.upload(for: send, from: payload)
        try httpCheck(response, data, provider: .google)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["file"] as? [String: Any],
              let uri = info["uri"] as? String, let name = info["name"] as? String else {
            throw AppError("Google (envio do áudio): resposta sem URI do arquivo.")
        }
        return (uri, name)
    }

    private func delete(name: String, session: URLSession) async {
        guard let url = URL(string: "\(base)/v1beta/\(name)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        _ = try? await session.data(for: request)
    }

    private func parse(_ data: Data) throws -> (text: String, words: [Word]) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError("Google (transcrição): resposta inválida.")
        }
        if let status = root["status"] as? String, status != "completed" {
            throw AppError("Google (transcrição): status \(status).")
        }
        var text = ""
        var words: [Word] = []
        for step in (root["steps"] as? [[String: Any]]) ?? [] where (step["type"] as? String) == "model_output" {
            for content in (step["content"] as? [[String: Any]]) ?? [] {
                text += (content["text"] as? String) ?? ""
                for note in (content["annotations"] as? [[String: Any]]) ?? []
                where (note["type"] as? String) == "word_info" {
                    words.append(Word(
                        text: (note["text"] as? String) ?? "",
                        speaker: note["speaker"] as? String,
                        start: seconds(note["start_offset"]),
                        end: seconds(note["end_offset"])))
                }
            }
        }
        return (text, words)
    }

    private func seconds(_ value: Any?) -> Double {
        if let number = value as? Double { return number }
        guard let text = value as? String else { return 0 }
        return Double(text.replacingOccurrences(of: "s", with: "")) ?? 0
    }
}

enum TranscriptBuilder {
    /// Groups words into utterances and labels the speakers.
    /// The microphone channel carries the user; the system channel is labelled "Participante N".
    static func build(mic: (text: String, words: [Word]), system: (text: String, words: [Word]),
                      micOffset: Double, systemOffset: Double) -> Transcript {
        var raw: [(start: Double, speaker: String, text: String)] = []
        for u in utterances(mic, offset: micOffset) { raw.append((u.start, Config.userName, u.text)) }

        var order: [String] = []
        for u in utterances(system, offset: systemOffset) {
            let key = u.speaker ?? "spk"
            if !order.contains(key) { order.append(key) }
            raw.append((u.start, "Participante \(order.firstIndex(of: key)! + 1)", u.text))
        }

        raw.sort { $0.start < $1.start }
        var used = Set<Int>()
        let segments = raw.map { item -> Segment in
            var second = Int(item.start)
            while used.contains(second) { second += 1 }
            used.insert(second)
            return Segment(id: String(format: "t-%06d", second), speaker: item.speaker,
                           start: item.start, text: item.text)
        }
        return Transcript(segments: segments)
    }

    private static func utterances(_ result: (text: String, words: [Word]), offset: Double)
        -> [(start: Double, speaker: String?, text: String)] {
        if result.words.isEmpty {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? [] : [(offset, nil, text)]
        }
        var output: [(start: Double, speaker: String?, text: String)] = []
        var current: (start: Double, speaker: String?, words: [String], end: Double)?
        for word in result.words {
            if let c = current, c.speaker == word.speaker, word.start - c.end <= 1.2 {
                current = (c.start, c.speaker, c.words + [word.text], word.end)
            } else {
                if let c = current { output.append((c.start + offset, c.speaker, c.words.joined(separator: " "))) }
                current = (word.start, word.speaker, [word.text], word.end)
            }
        }
        if let c = current { output.append((c.start + offset, c.speaker, c.words.joined(separator: " "))) }
        return output
    }
}
