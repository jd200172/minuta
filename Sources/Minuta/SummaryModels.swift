import Foundation

/// How a section of a summary is made: plain items, or titled topics.
struct SectionSpec {
    let key: String
    let title: String
    let topics: Bool
    /// What the model should put in the section.
    let hint: String
    /// Text shown when the model returns nothing for the section.
    let empty: String
}

/// The four summary models (ADRs 0017 and 0018): three with their own function and Geral for the rest. The
/// core of every summary (resumo, participantes, itens de ação, pontos em aberto, transcrição) is shared;
/// each model adds its own sections between Participantes and Itens de ação. Files written before ADR 0018
/// may name the removed "acompanhamento" model; they stay readable but it is no longer a model.
enum SummaryModel: String, Codable, CaseIterable, Identifiable {
    case decisao, problemas, informativa, geral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decisao: "Decisão"
        case .problemas: "Problemas e ideias"
        case .informativa: "Informativa"
        case .geral: "Geral"
        }
    }

    /// One line for the classifier.
    var blurb: String {
        switch self {
        case .decisao:
            "Reunião cujo resultado principal é decidir: o grupo avalia opções e fecha o que será feito."
        case .problemas:
            "Reunião para discutir um problema ou levantar ideias (brainstorm): muitas propostas, sem fechar escolha."
        case .informativa:
            "Reunião em que uma ou poucas pessoas expõem conteúdo ao grupo (apresentação, treinamento, palestra), com perguntas do público. Reunião de status, em que cada pessoa conta o próprio avanço, não é informativa."
        case .geral:
            "Reunião de propósito misto, sem função dominante, de status da equipe (cada pessoa conta o avanço, o que está travado e os próximos passos) ou com pouco conteúdo para classificar."
        }
    }

    /// The tooltip of the model's chip in the reading window: what it is for, what it shows, when to use it.
    var tooltip: String {
        switch self {
        case .decisao:
            """
            Serve para registrar o que o grupo decidiu.
            Mostra as decisões e as alternativas descartadas, com o motivo.
            Use quando o grupo avaliou opções e fechou uma escolha.
            """
        case .problemas:
            """
            Serve para organizar uma discussão sem escolha final.
            Mostra o problema, as ideias por tema (com quem sugeriu) e o que aprofundar.
            Use quando a reunião foi um brainstorm ou a discussão de um problema.
            """
        case .informativa:
            """
            Serve para registrar o conteúdo de uma exposição.
            Mostra os pontos principais, os dados citados e as perguntas com resposta.
            Use quando alguém apresentou, treinou ou deu palestra, e o grupo perguntou.
            """
        case .geral:
            """
            Serve para resumir reuniões sem função dominante.
            Mostra um resumo por tema (por pessoa, em reunião de status).
            Use quando a reunião mistura assuntos, é de status ou nenhum outro modelo se aplica.
            """
        }
    }

    /// What this model asks the LLM to emphasize, added to the common rules.
    var focus: String {
        switch self {
        case .decisao:
            """
            Esta reunião é de decisão. Decisão é o que o grupo concordou em fazer daqui para frente. \
            Proposta descartada, alternativa rejeitada e discussão sem conclusão não entram em "decisions"; \
            registre-as em "discarded", com o motivo. Meta, previsão ou estimativa dita por alguém não é decisão. \
            Se o grupo não decidiu nada, devolva "decisions" vazio.
            """
        case .problemas:
            """
            Esta reunião é de discussão de problemas ou de ideias. Em "problem" registre a pergunta ou o \
            problema tratado, com os números ditos. Em "ideas" agrupe as ideias em temas, cada tema com um \
            título e as ideias que o compõem; atribua cada ideia a quem a disse quando isso estiver claro. \
            Em "toexplore" liste o que o grupo quis aprofundar. Ideia levantada não é decisão. Assunto fora \
            do tema que o grupo deixou de lado não entra nas ideias.
            """
        case .informativa:
            """
            Esta reunião é informativa: uma ou poucas pessoas expõem conteúdo e o grupo pergunta. Em \
            "mainpoints" registre os pontos principais apresentados. Em "data" liste só números, datas e fatos \
            citados como foram ditos; proposta e estimativa não são dados. Em "questions" registre só perguntas \
            que alguém fez de fato, com a resposta de cada uma; não crie pergunta a partir de um assunto. \
            Recomendação geral dada ao público não é ação com responsável.
            """
        case .geral:
            """
            Esta reunião mistura assuntos, é de status da equipe ou tem pouco conteúdo. Em "topics" resuma cada \
            assunto tratado, em um título curto e um texto objetivo. Se for de status, use um tema por pessoa, \
            com o que avançou, o que está travado e o que vem a seguir. Proposta, meta ou estimativa não é \
            decisão. Se quase nada \
            concreto foi dito, diga isso no resumo; não invente assunto, decisão, responsável nem prazo.
            """
        }
    }

    var sections: [SectionSpec] {
        switch self {
        case .decisao:
            return [
                SectionSpec(
                    key: "decisions", title: "Decisões", topics: false,
                    hint: "O que o grupo decidiu.", empty: "Nenhuma decisão registrada."),
                SectionSpec(
                    key: "discarded", title: "Alternativas descartadas", topics: false,
                    hint: "Propostas rejeitadas e o motivo.", empty: "Nenhuma alternativa descartada."),
            ]
        case .problemas:
            return [
                SectionSpec(
                    key: "problem", title: "Problema", topics: false,
                    hint: "O problema ou a pergunta tratada.", empty: "Problema não definido."),
                SectionSpec(
                    key: "ideas", title: "Ideias por tema", topics: true,
                    hint: "Cada tema com título e as ideias que o compõem.", empty: "Nenhuma ideia registrada."),
                SectionSpec(
                    key: "toexplore", title: "A aprofundar", topics: false,
                    hint: "O que o grupo quis investigar melhor.", empty: "Nada marcado para aprofundar."),
            ]
        case .informativa:
            return [
                SectionSpec(
                    key: "mainpoints", title: "Pontos principais", topics: false,
                    hint: "Os pontos apresentados.", empty: "Nenhum ponto registrado."),
                SectionSpec(
                    key: "data", title: "Dados citados", topics: false,
                    hint: "Números, datas e fatos citados, como foram ditos.", empty: "Nenhum dado citado."),
                SectionSpec(
                    key: "questions", title: "Perguntas", topics: false,
                    hint: "Perguntas feitas e a resposta de cada uma.", empty: "Nenhuma pergunta registrada."),
            ]
        case .geral:
            return [
                SectionSpec(
                    key: "topics", title: "Resumo por tema", topics: true,
                    hint: "Cada assunto tratado, com título e texto.", empty: "Nenhum tema registrado.")
            ]
        }
    }
}

/// One cited statement: a plain item, or a topic when it has a title.
struct SummaryEntry: Codable, Equatable {
    var title: String?
    var text: String
    var sources: [String]
}

struct SummaryData: Codable, Equatable {
    struct Participant: Codable, Equatable {
        var label: String
        var name: String
        var sources: [String]
    }
    struct Action: Codable, Equatable {
        var text: String
        var owner: String
        var deadline: String
        var sources: [String]
    }
    var summary: String
    var participants: [Participant]
    /// Model-specific sections, keyed by `SectionSpec.key`.
    var sections: [String: [SummaryEntry]]
    var actions: [Action]
    var openPoints: [SummaryEntry]

    enum CodingKeys: String, CodingKey {
        case summary, participants, sections, actions
        case openPoints = "open_points"
    }
}

/// What the classifier says about a meeting. Without confidence there is no suggestion.
struct Classification: Codable, Equatable {
    var model: SummaryModel
    var confident: Bool
    var reason: String
    var title: String

    var suggestion: SummaryModel? { confident ? model : nil }

    init(model: SummaryModel, confident: Bool, reason: String, title: String) {
        self.model = model
        self.confident = confident
        self.reason = reason
        self.title = title
    }

    /// A classification written before ADR 0018 may name a model that no longer exists. It keeps the
    /// reason and the title and becomes a classification without a suggestion.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .model)
        let known = SummaryModel(rawValue: raw)
        model = known ?? .geral
        confident = try c.decode(Bool.self, forKey: .confident) && known != nil
        reason = try c.decode(String.self, forKey: .reason)
        title = try c.decode(String.self, forKey: .title)
    }

    enum CodingKeys: String, CodingKey { case model, confident, reason, title }
}
