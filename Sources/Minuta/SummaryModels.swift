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

/// The five summary models (ADR 0017), one per function a meeting serves. The core of every summary
/// (resumo, participantes, itens de ação, pontos em aberto, transcrição) is shared; each model adds its own
/// sections between Participantes and Itens de ação.
enum SummaryModel: String, Codable, CaseIterable, Identifiable {
    case decisao, acompanhamento, problemas, informativa, geral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decisao: "Decisão"
        case .acompanhamento: "Acompanhamento"
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
        case .acompanhamento:
            "Reunião recorrente de acompanhamento do trabalho em curso: cada pessoa conta o avanço, o que está travado e os próximos passos."
        case .problemas:
            "Reunião para discutir um problema ou levantar ideias (brainstorm): muitas propostas, sem fechar escolha."
        case .informativa:
            "Reunião em que uma ou poucas pessoas transmitem conteúdo (apresentação, treinamento, palestra), com perguntas."
        case .geral:
            "Reunião de propósito misto, sem função dominante, ou com pouco conteúdo para classificar."
        }
    }

    /// What this model asks the LLM to emphasize, added to the common rules.
    var focus: String {
        switch self {
        case .decisao:
            """
            Esta reunião é de decisão. Decisão é o que o grupo concordou em fazer daqui para frente. \
            Proposta descartada, alternativa rejeitada e discussão sem conclusão não entram em "decisions"; \
            registre-as em "discarded", com o motivo.
            """
        case .acompanhamento:
            """
            Esta reunião é de acompanhamento. Organize por pessoa o que avançou ("progress"), o que está \
            travado ("blockers") e o que vem a seguir ("nextsteps"). Meta ou previsão dita por alguém não é \
            decisão do grupo.
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
            Esta reunião é informativa: alguém apresenta conteúdo. Em "mainpoints" registre os pontos \
            principais apresentados. Em "data" liste números, datas e fatos citados, como foram ditos. Em \
            "questions" registre as perguntas feitas e a resposta de cada uma. Recomendação geral dada ao \
            público não é ação com responsável.
            """
        case .geral:
            """
            Esta reunião mistura assuntos ou tem pouco conteúdo. Em "topics" resuma cada assunto tratado, em \
            um título curto e um texto objetivo. Proposta ou estimativa não é decisão. Se quase nada \
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
        case .acompanhamento:
            return [
                SectionSpec(
                    key: "progress", title: "Progresso", topics: false,
                    hint: "O que avançou, por pessoa.", empty: "Nenhum progresso registrado."),
                SectionSpec(
                    key: "blockers", title: "Bloqueios", topics: false,
                    hint: "O que está travado e por quê.", empty: "Nenhum bloqueio registrado."),
                SectionSpec(
                    key: "nextsteps", title: "Próximos passos", topics: false,
                    hint: "O que vem a seguir, com quem e quando foi dito.", empty: "Nenhum próximo passo registrado."),
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
}
