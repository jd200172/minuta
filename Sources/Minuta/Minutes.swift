import Foundation

/// When the meeting started and how long it lasted.
struct MeetingMeta: Equatable {
    var start: Date
    var duration: Double
}

/// Builds the Markdown file of a meeting (ADR 0017): front matter, title, summary (when there is one),
/// participants, the sections of the model, actions, open points and the transcript. Every cited segment
/// ID is checked against the transcript. Participants are written with their original labels; a name the
/// user gave is applied afterwards by `ParticipantEditor`.
enum MinutesRenderer {
    static let noSummaryText = "Resumo ainda não gerado. Escolha um modelo na janela de leitura."
    static let untitled = "Sem título"

    static func render(
        meta: MeetingMeta, title: String?, model: SummaryModel?, data: SummaryData?, transcript: Transcript
    ) -> String {
        let byID = Dictionary(uniqueKeysWithValues: transcript.segments.map { ($0.id, $0) })
        let userName = Config.userName

        func links(_ sources: [String]) -> String {
            let valid = sources.compactMap { byID[$0] }
            if valid.isEmpty { return "sem evidência na transcrição" }
            return valid.map { "[\(Fmt.clock($0.start))](#\($0.id))" }.joined(separator: " ")
        }

        // label -> display name, only with valid evidence
        var names: [String: String] = [:]
        var evidence: [String: String] = [:]
        for p in data?.participants ?? [] {
            let name = p.name.trimmingCharacters(in: .whitespaces)
            let valid = p.sources.compactMap { byID[$0] }
            if !name.isEmpty, !valid.isEmpty, p.label != userName {
                names[p.label] = name
                evidence[p.label] = links(p.sources)
            }
        }
        func display(_ label: String) -> String {
            guard let name = names[label] else { return label }
            return "\(name) (\(label))"
        }

        var labels: [String] = []
        for s in transcript.segments where !labels.contains(s.speaker) { labels.append(s.speaker) }
        labels.sort { a, b in
            if a == userName { return true }
            if b == userName { return false }
            return a < b
        }

        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var out = "---\ninicio: \(Fmt.iso(meta.start))\nduracao_segundos: \(Int(meta.duration))\n"
        if !cleanTitle.isEmpty { out += "titulo: \(cleanTitle.replacingOccurrences(of: "\n", with: " "))\n" }
        out += model.map { "modelo: \($0.rawValue)\n" } ?? "resumo: nenhum\n"
        out += "---\n\n# \(cleanTitle.isEmpty ? untitled : cleanTitle)\n\n"
        out += "## Resumo\n\(data?.summary ?? noSummaryText)\n\n## Participantes\n"
        for label in labels {
            if label == userName {
                out += "- \(label)\n"
            } else if let name = names[label] {
                out += "- \(name) (\(label), nome inferido em \(evidence[label] ?? ""))\n"
            } else {
                out += "- \(label) (sem nome identificado)\n"
            }
        }

        if let model, let data {
            for spec in model.sections {
                out += "\n## \(spec.title)\n"
                let entries = data.sections[spec.key] ?? []
                if entries.isEmpty {
                    out += "\(spec.empty)\n"
                } else if spec.topics {
                    for e in entries { out += "### \(e.title ?? "")\n\(e.text) \(links(e.sources))\n\n" }
                } else {
                    out += entries.map { "- \($0.text) \(links($0.sources))\n" }.joined()
                }
            }

            out += "\n## Itens de ação\n"
            if data.actions.isEmpty {
                out += "Nenhuma ação registrada.\n"
            } else {
                out += "| Ação | Responsável | Prazo | Origem |\n|---|---|---|---|\n"
                for a in data.actions {
                    out +=
                        "| \(cell(a.text)) | \(cell(display(a.owner))) | \(cell(a.deadline)) | \(links(a.sources)) |\n"
                }
            }

            out += "\n## Pontos em aberto\n"
            out +=
                data.openPoints.isEmpty
                ? "Nenhum ponto em aberto.\n"
                : data.openPoints.map { "- \($0.text) \(links($0.sources))\n" }.joined()
        }

        out += "\n## Transcrição\n"
        for s in transcript.segments {
            out += "<a id=\"\(s.id)\"></a>**[\(Fmt.clock(s.start))] \(display(s.speaker)):** \(s.text)\n\n"
        }
        return out
    }

    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }
}
