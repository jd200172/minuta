import Foundation

/// Generates the minutes from the segmented transcript with Claude (structured output).
struct ClaudeMinuter: Minuter {
    let apiKey: String
    let model: String

    func minutes(transcript: Transcript, job: Job) async throws -> MinutesData {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "system": MinutesPrompt.system,
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": MinutesPrompt.schema],
            ],
            "messages": [["role": "user", "content": MinutesPrompt.user(transcript: transcript, job: job)]],
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try httpCheck(response, data, provider: .anthropic)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError("Anthropic (ata): resposta inválida.")
        }
        switch root["stop_reason"] as? String {
        case "refusal": throw AppError("Anthropic (ata): o modelo recusou gerar a ata.")
        case "max_tokens": throw AppError("Anthropic (ata): resposta cortada por tamanho.")
        default: break
        }
        let blocks = (root["content"] as? [[String: Any]]) ?? []
        guard let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String else {
            throw AppError("Anthropic (ata): resposta sem texto.")
        }
        return try MinutesPrompt.decode(text)
    }
}
