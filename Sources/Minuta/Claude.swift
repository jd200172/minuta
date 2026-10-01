import Foundation

/// Classifies the meeting and writes the summaries with Claude (structured output).
struct ClaudeMinuter: Minuter {
    let apiKey: String
    let model: String

    func classify(transcript: Transcript) async throws -> Classification {
        let text = try await complete(
            system: MinutesPrompt.classifierSystem, schema: MinutesPrompt.classifierSchema,
            user: MinutesPrompt.classifierUser(transcript: transcript), effort: "low", maxTokens: 1000,
            what: "classificação")
        return try MinutesPrompt.decodeClassification(text)
    }

    func summarize(
        model summaryModel: SummaryModel, transcript: Transcript, start: Date, names: [String: String]
    ) async throws -> SummaryData {
        let text = try await complete(
            system: MinutesPrompt.system(for: summaryModel), schema: MinutesPrompt.schema(for: summaryModel),
            user: MinutesPrompt.user(transcript: transcript, start: start, names: names), effort: "medium",
            maxTokens: 16000, what: "resumo")
        return try MinutesPrompt.decodeSummary(text, model: summaryModel)
    }

    private func complete(
        system: String, schema: [String: Any], user: String, effort: String, maxTokens: Int, what: String
    ) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "fallbacks": "default",
            "system": system,
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema],
            ],
            "messages": [["role": "user", "content": user]],
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
            throw AppError("Anthropic (\(what)): resposta inválida.")
        }
        switch root["stop_reason"] as? String {
        case "refusal": throw AppError("Anthropic (\(what)): o modelo recusou a pergunta.")
        case "max_tokens": throw AppError("Anthropic (\(what)): resposta cortada por tamanho.")
        default: break
        }
        let blocks = (root["content"] as? [[String: Any]]) ?? []
        guard let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String else {
            throw AppError("Anthropic (\(what)): resposta sem texto.")
        }
        return text
    }
}
