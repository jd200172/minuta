import Foundation

/// Turns the minutes Markdown into a reading page. It only understands the subset `MinutesRenderer`
/// writes (headings, bullets, one table, bold, internal links, transcript anchors). All text is escaped, so
/// whatever the speech model or the LLM produced cannot inject markup.
enum MarkdownHTML {
    struct Document {
        var title: String
        var html: String
    }

    /// The summary-model chips under the title of a meeting written by the model flow (ADR 0017).
    struct Controls {
        struct Chip {
            var model: SummaryModel
            var selected: Bool
            /// The model already has a summary in the sidecar.
            var has: Bool
        }
        var chips: [Chip]
        /// The model being generated: the chips stop being links and the chip shows a spinner.
        var generating: SummaryModel?
        /// One line under the chips: the suggestion, or what is happening.
        var hint: String
        var canRedo: Bool
    }

    /// Counts the citation chips of one page, so each one gets its own element id (`rf-N`) for the viewer to measure.
    final class Refs {
        var next = 0
    }

    /// With `citations`, a transcript chip (`[00:00:10](#t-000010)`) is a `minuta://cite/<segment>/<N>` link that
    /// the viewer turns into a balloon with the cited text, and the element carries the id `rf-N`. Without it, the
    /// chip is a plain anchor to the transcript line, which also works in a browser.
    /// With `transcriptCollapsed`, the "Transcrição" heading is a `minuta://transcript` toggle, and the lines
    /// below it are hidden when collapsed. Without it the section is plain, as in the file.
    /// With `renamable`, each participant in the "Participantes" list gets an id on its text (`sp-N`, for the
    /// viewer to measure) and a pencil link (`minuta://rename/N`) that the viewer turns into an in-place rename.
    /// With `controls`, the title gets a pencil (`minuta://title`, text in `#ti`) and the model chips follow the
    /// date line; chips and the redo icon are `minuta://model/<id>` and `minuta://redo` links.
    static func convert(
        _ markdown: String, renamable: Bool = false, controls: Controls? = nil, citations: Bool = false,
        transcriptCollapsed: Bool? = nil
    ) -> Document {
        let refs: Refs? = citations ? Refs() : nil
        var inTranscript = false
        let speakers = renamable ? ParticipantEditor.speakers(in: markdown) : []
        var section = ""
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var meta: [String: String] = [:]
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                meta[line[..<colon].trimmingCharacters(in: .whitespaces)] =
                    line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            lines = Array(lines[(end + 1)...])
        }

        let segmentCount = markdown.components(separatedBy: "<a id=\"t-").count - 1
        var title = ""
        var body = ""
        var paragraph: [String] = []
        var list: [String] = []
        var table: [String] = []

        func listItem(_ item: String) -> String {
            guard section == "Participantes", let head = ParticipantEditor.listHead("- " + item),
                let index = speakers.firstIndex(where: { head == ($0.kind == .unnamed ? $0.label : $0.name) })
            else { return "<li>\(inline(item, refs: refs))</li>\n" }
            return
                "<li><span id=\"sp-\(index)\">\(inline(item, refs: refs))</span><a class=\"pen\" href=\"minuta://rename/\(index)\" data-tip=\"Renomear\" aria-label=\"Renomear participante\">\(pencil)</a></li>\n"
        }

        func flush() {
            if !paragraph.isEmpty {
                body +=
                    transcriptLine(paragraph.joined(separator: " "))
                    ?? "<p>\(inline(paragraph.joined(separator: " "), refs: refs))</p>\n"
                paragraph = []
            }
            if !list.isEmpty {
                body += "<ul>\n" + list.map { listItem($0) }.joined() + "</ul>\n"
                list = []
            }
            if !table.isEmpty {
                body += tableHTML(table, refs: refs)
                table = []
            }
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else if line.hasPrefix("# ") {
                flush()
                title = String(line.dropFirst(2))
                let heading =
                    controls == nil
                    ? escape(title)
                    : "<span id=\"ti\">\(escape(title))</span><a class=\"pen\" href=\"minuta://title\" data-tip=\"Renomear\" aria-label=\"Renomear reunião\">\(pencil)</a>"
                body += "<h1>\(heading)</h1>\n\(subtitle(meta))\(controls.map(controlsHTML) ?? "")"
            } else if line.hasPrefix("## ") {
                flush()
                section = String(line.dropFirst(3))
                if inTranscript {
                    body += "</div>\n"
                    inTranscript = false
                }
                if section == "Transcrição", let collapsed = transcriptCollapsed {
                    body += transcriptHeading(count: segmentCount, collapsed: collapsed)
                    inTranscript = true
                } else {
                    body += "<h2>\(escape(section))</h2>\n"
                }
            } else if line.hasPrefix("### ") {
                flush()
                body += "<h3>\(escape(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("- ") {
                if !paragraph.isEmpty || !table.isEmpty { flush() }
                list.append(String(line.dropFirst(2)))
            } else if line.hasPrefix("|") {
                if !paragraph.isEmpty || !list.isEmpty { flush() }
                table.append(line)
            } else {
                if !list.isEmpty || !table.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        if inTranscript { body += "</div>\n" }
        return Document(title: title, html: page(title: title.isEmpty ? "Ata" : title, body: body))
    }

    // MARK: Pieces

    private static let pencil =
        #"<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h4L18.5 9.5a2.828 2.828 0 0 0-4-4L4 16v4"/><path d="M13.5 6.5l4 4"/></svg>"#

    private static let refresh =
        #"<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 11a8 8 0 0 0-14.9-3M4 5v4h4"/><path d="M4 13a8 8 0 0 0 14.9 3M20 19v-4h-4"/></svg>"#

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let bubble =
        #"<svg viewBox="0 0 24 24" width="11" height="11" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H8l-5 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>"#

    private static let chevron =
        #"<svg class="cv" viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg>"#

    /// Escapes, then turns `[00:00:10](#t-000010)` into a chip, other `[x](#id)` into links and `**x**` into bold.
    /// With `refs`, the chip opens a citation balloon instead of jumping to the transcript.
    static func inline(_ text: String, refs: Refs? = nil) -> String {
        var out = escape(text)
        if let refs {
            out = citationChips(out, refs)
        } else {
            out = out.replacingOccurrences(
                of: #"\[(\d{2}:\d{2}:\d{2})\]\((#[A-Za-z0-9_-]+)\)"#, with: #"<a class="chip" href="$2">$1</a>"#,
                options: .regularExpression)
        }
        out = out.replacingOccurrences(
            of: #"\[([^\]]+)\]\((#[A-Za-z0-9_-]+)\)"#, with: #"<a href="$2">$1</a>"#, options: .regularExpression)
        out = out.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        return out
    }

    /// Each transcript chip becomes `<a id="rf-N" href="minuta://cite/<segment>/N">`.
    private static func citationChips(_ text: String, _ refs: Refs) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{2}:\d{2}:\d{2})\]\(#([A-Za-z0-9_-]+)\)"#)
        else { return text }
        let source = text as NSString
        var out = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        var replacements: [String] = []
        for m in matches {
            let clock = source.substring(with: m.range(at: 1))
            let id = source.substring(with: m.range(at: 2))
            let n = refs.next
            refs.next += 1
            replacements.append(
                "<a class=\"chip\" id=\"rf-\(n)\" href=\"minuta://cite/\(id)/\(n)\" data-tip=\"Ver o trecho da conversa\" aria-label=\"Ver o trecho da conversa em \(clock)\">\(bubble)\(clock)</a>"
            )
        }
        for (m, replacement) in zip(matches, replacements).reversed() {
            out = out.replacingCharacters(in: m.range, with: replacement) as NSString
        }
        return out as String
    }

    /// The "Transcrição" heading as a toggle, and the opening of the block that holds the transcript lines.
    private static func transcriptHeading(count: Int, collapsed: Bool) -> String {
        let label = collapsed ? "Expandir a transcrição" : "Recolher a transcrição"
        let amount = count == 1 ? "1 segmento" : "\(count) segmentos"
        return
            "<h2 class=\"disc\(collapsed ? "" : " open")\"><a href=\"minuta://transcript\" data-tip=\"\(label)\" aria-label=\"\(label)\" aria-expanded=\"\(collapsed ? "false" : "true")\">\(chevron)Transcrição<span class=\"ct\">\(amount)</span></a></h2>\n<div class=\"tr\(collapsed ? " hide" : "")\">\n"
    }

    /// `<a id="t-000010"></a>**[00:00:10] Participante 1:** texto`
    private static func transcriptLine(_ text: String) -> String? {
        let pattern = #"^<a id="(t-\d+)"></a>\*\*\[(\d{2}:\d{2}:\d{2})\] (.+?):\*\* ?(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        func group(_ i: Int) -> String { String(text[Range(m.range(at: i), in: text)!]) }
        return """
            <p class="tl" id="\(group(1))"><span class="tm">\(group(2))</span><span><strong>\(escape(group(3))):</strong> \(escape(group(4)))</span></p>

            """
    }

    private static func tableHTML(_ rows: [String], refs: Refs? = nil) -> String {
        func cells(_ row: String) -> [String] {
            var result: [String] = []
            var current = ""
            var chars = Array(row.trimmingCharacters(in: .whitespaces))
            if chars.first == "|" { chars.removeFirst() }
            if chars.last == "|" && (chars.count < 2 || chars[chars.count - 2] != "\\") { chars.removeLast() }
            var index = 0
            while index < chars.count {
                if chars[index] == "\\", index + 1 < chars.count, chars[index + 1] == "|" {
                    current.append("|")
                    index += 2
                    continue
                }
                if chars[index] == "|" {
                    result.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                } else {
                    current.append(chars[index])
                }
                index += 1
            }
            result.append(current.trimmingCharacters(in: .whitespaces))
            return result
        }
        guard let header = rows.first else { return "" }
        var html = "<table>\n<tr>" + cells(header).map { "<th>\(inline($0, refs: refs))</th>" }.joined() + "</tr>\n"
        for row in rows.dropFirst() where !row.contains("---") {
            html += "<tr>" + cells(row).map { "<td>\(inline($0, refs: refs))</td>" }.joined() + "</tr>\n"
        }
        return html + "</table>\n"
    }

    private static func controlsHTML(_ controls: Controls) -> String {
        var html = "<div class=\"models\" role=\"group\" aria-label=\"Resumo no modelo\">\n"
        for chip in controls.chips {
            let busy = controls.generating == chip.model
            var css = "mc"
            if chip.selected || busy { css += " on" }
            if controls.generating != nil && !busy { css += " off" }
            var inner = escape(chip.model.title)
            let tip = escape(chip.model.tooltip).replacingOccurrences(of: "\n", with: "&#10;")
            if busy {
                inner += "<i class=\"sp\"></i>"
            } else if chip.has {
                inner += "<i class=\"dt\" data-tip=\"Resumo gerado\" role=\"img\" aria-label=\"Resumo gerado\"></i>"
            }
            if controls.generating != nil {
                html += "<span class=\"\(css)\" data-tip=\"\(tip)\" aria-description=\"\(tip)\">\(inner)</span>\n"
            } else {
                html +=
                    "<a class=\"\(css)\" href=\"minuta://model/\(chip.model.rawValue)\" data-tip=\"\(tip)\" aria-description=\"\(tip)\"\(chip.selected ? " aria-current=\"true\"" : "")>\(inner)</a>\n"
            }
        }
        if controls.canRedo {
            html +=
                "<a class=\"pen redo\" href=\"minuta://redo\" data-tip=\"Refazer este resumo\" aria-label=\"Refazer este resumo\">\(refresh)</a>\n"
        }
        html += "</div>\n"
        if !controls.hint.isEmpty { html += "<p class=\"hint\">\(escape(controls.hint))</p>\n" }
        return html
    }

    private static func subtitle(_ meta: [String: String]) -> String {
        var parts: [String] = []
        if let value = meta["inicio"], let date = ISO8601DateFormatter().date(from: value) {
            let time = DateFormatter()
            time.locale = Locale(identifier: "pt_BR")
            time.dateFormat = "HH:mm"
            parts.append(Fmt.meetingDate(date).capitalizingFirst)
            parts.append(time.string(from: date))
        }
        if let value = meta["duracao_segundos"], let seconds = Double(value) {
            parts.append(Fmt.shortDuration(seconds))
        }
        return parts.isEmpty ? "" : "<p class=\"sub\">\(escape(parts.joined(separator: " · ")))</p>\n"
    }

    private static func page(title: String, body: String) -> String {
        """
        <!doctype html>
        <html lang="pt-BR"><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <title>\(escape(title))</title>
        <style>
        :root { color-scheme: light dark; --page: color-mix(in srgb, CanvasText 5%, Canvas); }
        @media (prefers-color-scheme: dark) { :root { --page: color-mix(in srgb, black 25%, Canvas); } }
        html { background: var(--page); }
        body { font: 14px/1.55 -apple-system, sans-serif; margin: 0; padding: 20px 16px 24px; color: CanvasText; background: var(--page); }
        .card { box-sizing: border-box; max-width: 760px; margin: 0 auto; padding: 22px 28px; background: Canvas; border: 0.5px solid color-mix(in srgb, CanvasText 20%, transparent); border-radius: 10px; }
        h1 { font-size: 22px; font-weight: 600; margin: 0 0 2px; }
        h1 a.pen { margin-left: 10px; vertical-align: 3px; }
        .sub { color: GrayText; font-size: 13px; margin: 0 0 18px; }
        .models { display: flex; flex-wrap: wrap; align-items: center; gap: 10px 8px; margin: 0; }
        .mc { display: inline-flex; align-items: center; gap: 7px; font-size: 13px; line-height: 1; padding: 8px 14px; border-radius: 16px; border: 1px solid color-mix(in srgb, CanvasText 20%, transparent); color: CanvasText; background: Canvas; white-space: nowrap; }
        a.mc:hover { background: color-mix(in srgb, CanvasText 7%, transparent); }
        .mc.on { background: color-mix(in srgb, LinkText 14%, transparent); border-color: color-mix(in srgb, LinkText 50%, transparent); color: LinkText; font-weight: 600; }
        .mc.off { opacity: 0.45; }
        .mc .dt { width: 5px; height: 5px; border-radius: 50%; background: currentColor; opacity: 0.55; }
        .mc .sp { width: 10px; height: 10px; border-radius: 50%; border: 1.5px solid currentColor; border-top-color: transparent; animation: spin 0.8s linear infinite; }
        @keyframes spin { to { transform: rotate(360deg); } }
        a.redo { margin-left: 6px; padding: 6px; }
        .hint { color: GrayText; font-size: 12px; line-height: 1.5; margin: 14px 0 0; }
        .hint + h2, .models + h2 { margin-top: 30px; }
        h2 { font-size: 13px; font-weight: 600; color: GrayText; margin: 24px 0 6px; }
        h3 { font-size: 14px; font-weight: 600; margin: 14px 0 2px; }
        p { margin: 6px 0; }
        ul { margin: 0; padding-left: 20px; }
        li { margin: 3px 0; }
        table { width: 100%; border-collapse: collapse; font-size: 13px; margin: 4px 0; }
        th { text-align: left; color: GrayText; font-weight: 500; }
        th, td { padding: 6px 10px 6px 0; vertical-align: top; border-bottom: 1px solid color-mix(in srgb, CanvasText 14%, transparent); }
        a { color: LinkText; text-decoration: none; }
        a.pen { display: inline-block; margin-left: 6px; color: GrayText; vertical-align: -2px; opacity: 0.7; }
        a.pen:hover { color: LinkText; opacity: 1; }
        a.chip { font-size: 11px; padding: 0 6px; border-radius: 5px; background: color-mix(in srgb, LinkText 14%, transparent); margin-left: 2px; font-variant-numeric: tabular-nums; white-space: nowrap; }
        p.tl { display: grid; grid-template-columns: 64px 1fr; gap: 8px; padding: 3px 8px; margin: 0 -8px; border-radius: 6px; }
        p.tl:target { background: color-mix(in srgb, LinkText 16%, transparent); }
        a.chip svg { vertical-align: -1px; margin-right: 3px; }
        h2.disc { margin: 30px 0 6px; padding-top: 12px; border-top: 1px solid color-mix(in srgb, CanvasText 14%, transparent); }
        h2.disc a { display: inline-flex; align-items: center; gap: 6px; color: GrayText; }
        h2.disc a:hover { color: CanvasText; }
        h2.disc .cv { transition: transform 0.12s; }
        h2.disc.open .cv { transform: rotate(90deg); }
        h2.disc .ct { font-weight: 400; font-size: 12px; color: GrayText; }
        h2.disc .ct::before { content: "· "; }
        .tr.hide { display: none; }
        .tm { color: GrayText; font-size: 12px; font-variant-numeric: tabular-nums; }
        </style></head><body>
        <div class="card" id="card">
        \(body)</div></body></html>
        """
    }
}

extension String {
    fileprivate var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}
