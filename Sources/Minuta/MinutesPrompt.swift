import Foundation

/// Provider-neutral instructions, JSON schemas and decoding for the summaries and the classifier. Every
/// `Minuter` reuses them; whatever the model returns is still checked by `MinutesRenderer` (ADR 0012).
/// A summary prompt is the common rules plus the block of the chosen model (ADR 0017).
enum MinutesPrompt {
    static let common = """
        Você resume reuniões em português do Brasil a partir de uma transcrição segmentada. \
        Cada linha da transcrição tem o formato "[ID] Falante: texto". O ID identifica o segmento.

        Regras:
        - Use somente o que está na transcrição. Não invente fatos, nomes, responsáveis nem prazos.
        - Seção sem conteúdo sustentado pela transcrição fica com a lista vazia. Não preencha seção só para \
        completar a estrutura.
        - Cada item e cada tema cita em "sources" os IDs dos segmentos que o sustentam: \
        no máximo 3, os mais diretos, em ordem cronológica. Não cite todos os segmentos do assunto.
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
        - Quando a mensagem trouxer nomes informados pelo usuário, eles identificam o falante com certeza. \
        Em "label" e "owner" continue usando o rótulo original. No texto corrido, use o nome.
        - Escreva em tom objetivo, sem adjetivos de avaliação.
        """

    static func system(for model: SummaryModel) -> String {
        common + "\n\n" + model.focus + "\n\nSeções desta reunião:\n"
            + model.sections.map { "- \"\($0.key)\" (\($0.title)): \($0.hint)" }.joined(separator: "\n")
    }

    static let classifierSystem = """
        Você classifica reuniões para escolher o modelo de resumo mais adequado e dar um título. \
        Cada linha da transcrição tem o formato "[ID] Falante: texto".

        Modelos:
        \(SummaryModel.allCases.map { "- \($0.rawValue) (\($0.title)): \($0.blurb)" }.joined(separator: "\n"))

        Regras:
        - Escolha o modelo pela função da reunião, não pelo assunto.
        - "confidence" é "alta" quando a função da reunião está clara e "baixa" quando a conversa mistura \
        funções, tem pouco conteúdo ou o assunto não é identificável.
        - "reason" é uma frase curta, objetiva, que cita o que na reunião levou à escolha.
        - "title" tem no máximo 8 palavras, descreve o assunto, sem nomes de pessoas e sem datas. Se o \
        assunto não é identificável, escreva um título genérico que não invente assunto.
        """

    static let cleanerSystem = """
        Você limpa a transcrição literal de uma reunião em português do Brasil para a leitura. \
        Cada linha tem o formato "[ID] Falante: texto". Devolva o texto de cada segmento sem o ruído da fala.

        Remova:
        - preenchimentos sem conteúdo ("ãh", "eh", "hum", "hã");
        - repetições gaguejadas ("tu tem tu tem aí um um um" vira "tu tem aí um");
        - falsos começos abandonados, quando a frase é retomada em seguida.

        Mantenha:
        - toda palavra de conteúdo, número, nome e negação;
        - respostas curtas ("Tá.", "Sim.", "Não.", "Isso.");
        - repetição que dá ênfase ("muito muito grande");
        - o registro oral do falante e a ordem das palavras.

        Regras:
        - Não reescreva, não troque palavras, não corrija gramática e não acrescente palavra que não esteja \
        no texto. Pontuação e maiúsculas podem mudar.
        - Não junte nem divida segmentos. Devolva todos os IDs recebidos, cada um com o seu texto.
        - Se o segmento é só ruído, sem conteúdo, devolva o texto vazio.
        """

    // MARK: Schemas

    static func object(_ properties: [String: Any]) -> [String: Any] {
        [
            "type": "object", "properties": properties, "required": Array(properties.keys),
            "additionalProperties": false,
        ]
    }

    private static let string: [String: Any] = ["type": "string"]

    private static func list(_ item: [String: Any]) -> [String: Any] { ["type": "array", "items": item] }

    static func stringArray() -> [String: Any] { list(string) }

    private static func entry(topic: Bool) -> [String: Any] {
        topic
            ? object(["title": string, "text": string, "sources": stringArray()])
            : object(["text": string, "sources": stringArray()])
    }

    static func schema(for model: SummaryModel) -> [String: Any] {
        var sections: [String: Any] = [:]
        for spec in model.sections { sections[spec.key] = list(entry(topic: spec.topics)) }
        return object([
            "summary": string,
            "participants": list(object(["label": string, "name": string, "sources": stringArray()])),
            "sections": object(sections),
            "actions": list(
                object(["text": string, "owner": string, "deadline": string, "sources": stringArray()])),
            "open_points": list(entry(topic: false)),
        ])
    }

    static var cleanerSchema: [String: Any] {
        object(["segments": list(object(["id": string, "text": string]))])
    }

    static var classifierSchema: [String: Any] {
        object([
            "model": ["type": "string", "enum": SummaryModel.allCases.map(\.rawValue)],
            "confidence": ["type": "string", "enum": ["alta", "baixa"]],
            "reason": string,
            "title": string,
        ])
    }

    // MARK: Messages

    private static func lines(_ transcript: Transcript) -> String {
        transcript.segments.map { "[\($0.id)] \($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    /// `names` maps an original label to the name the user gave.
    static func user(transcript: Transcript, start: Date, names: [String: String]) -> String {
        var text = "Data da reunião: \(Fmt.meetingDate(start)).\nRótulo de quem gravou: \(Config.userName).\n"
        if !names.isEmpty {
            let list = names.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" }.joined(separator: "; ")
            text += "Nomes informados pelo usuário: \(list).\n"
        }
        return text + "\nTranscrição:\n" + lines(transcript)
    }

    static func classifierUser(transcript: Transcript) -> String {
        "Transcrição:\n" + lines(transcript)
    }

    static func cleanerUser(segments: [Segment]) -> String {
        "Transcrição:\n" + segments.map { "[\($0.id)] \($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    // MARK: Decoding

    static func decodeCleaning(_ text: String) throws -> [String: String] {
        struct Raw: Decodable {
            struct Item: Decodable {
                var id: String
                var text: String
            }
            var segments: [Item]
        }
        do {
            let raw = try JSONDecoder().decode(Raw.self, from: Data(text.utf8))
            return Dictionary(raw.segments.map { ($0.id, $0.text) }) { first, _ in first }
        } catch {
            throw AppError("A limpeza da transcrição veio fora do formato esperado.")
        }
    }

    static func decodeSummary(_ text: String, model: SummaryModel) throws -> SummaryData {
        do {
            var data = try JSONDecoder().decode(SummaryData.self, from: Data(text.utf8))
            // Only the sections of this model exist.
            data.sections = data.sections.filter { key, _ in model.sections.contains { $0.key == key } }
            return data
        } catch {
            throw AppError("O resumo veio fora do formato esperado. Tente de novo.")
        }
    }

    static func decodeClassification(_ text: String) throws -> Classification {
        struct Raw: Decodable {
            var model: SummaryModel
            var confidence: String
            var reason: String
            var title: String
        }
        do {
            let raw = try JSONDecoder().decode(Raw.self, from: Data(text.utf8))
            return Classification(
                model: raw.model, confident: raw.confidence == "alta",
                reason: raw.reason.trimmingCharacters(in: .whitespacesAndNewlines),
                title: raw.title.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw AppError("A classificação veio fora do formato esperado.")
        }
    }
}
