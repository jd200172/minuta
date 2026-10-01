import Foundation

struct MinutesData: Codable {
    struct Participant: Codable { var label: String; var name: String; var sources: [String] }
    struct Decision: Codable { var text: String; var sources: [String] }
    struct Action: Codable { var text: String; var owner: String; var deadline: String; var sources: [String] }
    struct Topic: Codable { var title: String; var text: String; var sources: [String] }
    var title: String
    var summary: String
    var participants: [Participant]
    var decisions: [Decision]
    var actions: [Action]
    var openPoints: [Decision]
    var topics: [Topic]
}

/// Generates the minutes from the segmented transcript with Claude Sonnet 5.5 (structured output).
struct ClaudeMinuter {
    let apiKey: String

    private static let systemPrompt = """
    Você gera atas de reuniões em português do Brasil a partir de uma transcrição segmentada. \
    Cada linha da transcrição tem o formato "[ID] Falante: texto". O ID identifica o segmento.

    Regras:
    - Use somente o que está na transcrição. Não invente fatos, nomes, responsáveis nem prazos.
    - Cada decisão, ação, ponto em aberto e tema cita em "sources" os IDs dos segmentos que o sustentam: \
    no máximo 3, os mais diretos, em ordem cronológica. Não cite todos os segmentos do assunto.
    - Decisão é o que o grupo concordou em fazer daqui para frente. Proposta descartada, alternativa \
    rejeitada e discussão sem conclusão não entram em "decisions"; registre a proposta descartada \
    apenas no resumo por tema, dizendo que foi descartada e por quê.
    - Ação exige uma tarefa concreta. Em "owner", use o rótulo exato do falante, como aparece na \
    transcrição. Se não houver responsável claro, escreva "não definido".
    - Em "deadline", converta prazos relativos em data (DD/MM/AAAA) usando a data da reunião informada. \
    Se não houver prazo, escreva "não definido".
    - Ponto em aberto é uma questão levantada que o grupo não resolveu e que ninguém assumiu. \
    Não liste como ponto em aberto o que já virou ação com responsável, nem uma consequência de \
    outra ação já listada. Se não houver nenhum, devolva a lista vazia.
    - Participantes: liste cada rótulo de falante em "label". Preencha "name" só quando a transcrição \
    identifica a própria pessoa (apresentação, saudação ou vocativo) e cite em "sources" o segmento \
    da evidência. Quem é apenas mencionado na conversa e não fala nela não é participante. \
    Sem evidência, deixe "name" vazio.
    - Escreva em tom objetivo, sem adjetivos de avaliação.
    """

    private static func stringArray() -> [String: Any] {
        ["type": "array", "items": ["type": "string"]]
    }

    private static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": Array(properties.keys),
         "additionalProperties": false]
    }

    private static var schema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        func list(_ item: [String: Any]) -> [String: Any] { ["type": "array", "items": item] }
        return object([
            "title": string,
            "summary": string,
            "participants": list(object(["label": string, "name": string, "sources": stringArray()])),
            "decisions": list(object(["text": string, "sources": stringArray()])),
            "actions": list(object(["text": string, "owner": string, "deadline": string,
                                    "sources": stringArray()])),
            "open_points": list(object(["text": string, "sources": stringArray()])),
            "topics": list(object(["title": string, "text": string, "sources": stringArray()])),
        ])
    }

    func minutes(transcript: Transcript, job: Job) async throws -> MinutesData {
        let lines = transcript.segments.map { "[\($0.id)] \($0.speaker): \($0.text)" }.joined(separator: "\n")
        let user = """
        Data da reunião: \(Fmt.meetingDate(job.startedAt)).
        Rótulo de quem gravou: \(Config.userName).

        Transcrição:
        \(lines)
        """
        let body: [String: Any] = [
            "model": Config.claudeModel,
            "max_tokens": 16000,
            "fallbacks": "default",
            "system": Self.systemPrompt,
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": Self.schema],
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
        try httpCheck(response, data, service: "Anthropic (ata)")

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
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(MinutesData.self, from: Data(text.utf8))
        } catch {
            throw AppError("Anthropic (ata): JSON fora do esquema.")
        }
    }
}
