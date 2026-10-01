import Foundation

/// Builds the Markdown file. Every cited segment ID is checked against the transcript.
enum MinutesRenderer {
    static func render(_ data: MinutesData, transcript: Transcript, job: Job) -> String {
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
        for p in data.participants {
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

        var out = "---\ninicio: \(Fmt.iso(job.startedAt))\nduracao_segundos: \(Int(job.durationSeconds))\n---\n\n"
        out += "# \(data.title)\n\n## Resumo\n\(data.summary)\n\n## Participantes\n"
        for label in labels {
            if label == userName {
                out += "- \(label) (canal do microfone)\n"
            } else if let name = names[label] {
                out += "- \(name) (\(label), nome inferido em \(evidence[label] ?? ""))\n"
            } else {
                out += "- \(label) (sem nome identificado)\n"
            }
        }

        out += "\n## Decisões\n"
        out += data.decisions.isEmpty ? "Nenhuma decisão registrada.\n"
            : data.decisions.map { "- \($0.text) \(links($0.sources))\n" }.joined()

        out += "\n## Itens de ação\n"
        if data.actions.isEmpty {
            out += "Nenhuma ação registrada.\n"
        } else {
            out += "| Ação | Responsável | Prazo | Origem |\n|---|---|---|---|\n"
            for a in data.actions {
                out += "| \(cell(a.text)) | \(cell(display(a.owner))) | \(cell(a.deadline)) | \(links(a.sources)) |\n"
            }
        }

        out += "\n## Pontos em aberto\n"
        out += data.openPoints.isEmpty ? "Nenhum ponto em aberto.\n"
            : data.openPoints.map { "- \($0.text) \(links($0.sources))\n" }.joined()

        out += "\n## Resumo por tema\n"
        for t in data.topics { out += "### \(t.title)\n\(t.text) \(links(t.sources))\n\n" }

        out += "## Transcrição\n"
        for s in transcript.segments {
            out += "<a id=\"\(s.id)\"></a>**[\(Fmt.clock(s.start))] \(display(s.speaker)):** \(s.text)\n\n"
        }
        return out
    }

    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    static func write(_ markdown: String, job: Job) throws -> URL {
        let dir = Config.outputDir
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stem = Fmt.fileStem(job.startedAt)
        var url = dir.appendingPathComponent("\(stem).md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(stem) \(n).md")
            n += 1
        }
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
