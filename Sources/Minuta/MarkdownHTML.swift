import Foundation

/// Turns the minutes Markdown into a reading page. It only understands the subset `MinutesRenderer`
/// writes (headings, bullets, one table, bold, internal links, transcript anchors). All text is escaped, so
/// whatever the speech model or the LLM produced cannot inject markup.
enum MarkdownHTML {
    struct Document {
        var title: String
        var html: String
    }

    /// The controls under the title of a meeting written by the model flow (ADR 0027): the model menu button,
    /// the export buttons, a line of hint and the section chips.
    struct Controls {
        /// The model whose summary is in the file; nil when there is no summary yet.
        var shown: SummaryModel?
        /// The model being generated: the menu button stops being a link and shows a spinner.
        var generating: SummaryModel?
        /// One line under the bar: the suggestion, or what is happening.
        var hint: String
    }

    /// Counts the citation chips of one page, so each one gets its own element id (`rf-N`) for the viewer to measure.
    final class Refs {
        var next = 0
    }

    /// With `citations`, a transcript chip (`[00:00:10](#t-000010)`) is a `minuta://cite/<segment>/<N>` link that
    /// the viewer turns into a balloon with the cited text, and the element carries the id `rf-N`. Without it, the
    /// chip is a plain anchor to the transcript line, which also works in a browser.
    /// With `collapsed`, every "##" section heading is a `minuta://section/<title>` toggle, and what is below it is
    /// hidden when its title is in the set. Without it the sections are plain, as in the file.
    /// With `renamable`, each participant in the "Participantes" list gets an id on its text (`sp-N`, for the
    /// viewer to measure) and a pencil link (`minuta://rename/N`) that the viewer turns into an in-place rename.
    /// With `controls`, the title gets a pencil (`minuta://title`, text in `#ti`), and the date line becomes a bar
    /// with the model menu button (`minuta://models`, measured by its id `mdl`) and the export buttons
    /// (`minuta://export/html` and `/pdf`; e-mail is shown but inactive). Below it, one chip per "##" section
    /// (`minuta://goto/N`, where N is the section's place in `sectionTitles`), with the sections of the shown
    /// model highlighted. Every "##" heading gets the id `s-N`, the target of its chip.
    /// With `details`, for a page that runs outside the app, every "##" section is a `<details>` that starts closed
    /// and opens and closes with no script. `details` takes the place of `collapsed`.
    static func convert(
        _ markdown: String, renamable: Bool = false, controls: Controls? = nil, citations: Bool = false,
        collapsed: Set<String>? = nil, details: Bool = false
    ) -> Document {
        let refs: Refs? = citations ? Refs() : nil
        var inSection = false
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
        let sections = sectionTitles(markdown)
        var sectionIndex = 0
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
                if let controls {
                    body += "<h1>\(heading)</h1>\n\(controlsHTML(controls, meta: meta, sections: sections))"
                } else {
                    body += "<h1>\(heading)</h1>\n\(subtitle(meta))"
                }
            } else if line.hasPrefix("## ") {
                flush()
                section = String(line.dropFirst(3))
                if inSection {
                    body += details ? "</details>\n" : "</div>\n"
                    inSection = false
                }
                let id = "s-\(sectionIndex)"
                sectionIndex += 1
                if details {
                    body += detailsHeading(
                        section, id: id, count: section == SectionState.transcript ? segmentCount : nil)
                    inSection = true
                } else if let collapsed {
                    body += sectionHeading(
                        section, id: id, collapsed: collapsed.contains(section),
                        count: section == SectionState.transcript ? segmentCount : nil)
                    inSection = true
                } else {
                    body += "<h2 id=\"\(id)\">\(escape(section))</h2>\n"
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
        if inSection { body += details ? "</details>\n" : "</div>\n" }
        return Document(title: title, html: page(title: title.isEmpty ? "Ata" : title, body: body))
    }

    // MARK: Pieces

    private static let pencil =
        #"<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 20h4L18.5 9.5a2.828 2.828 0 0 0-4-4L4 16v4"/><path d="M13.5 6.5l4 4"/></svg>"#

    private static let selector =
        #"<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 9l4-4 4 4"/><path d="M16 15l-4 4-4-4"/></svg>"#

    private static let mail =
        #"<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 7l9 6 9-6"/></svg>"#

    private static let htmlIcon =
        #"<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 8l-4 4 4 4"/><path d="M16 8l4 4-4 4"/><path d="M13.5 5l-3 14"/></svg>"#

    private static let pdfIcon =
        #"<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/><path d="M9 13h6M9 17h4"/></svg>"#

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

    /// A section as a closed `<details>`: the title is its summary, and the section's content follows it.
    private static func detailsHeading(_ title: String, id: String, count: Int?) -> String {
        let amount = count.map { $0 == 1 ? "1 segmento" : "\($0) segmentos" }
        return
            "<details class=\"dt\" id=\"\(id)\"><summary>\(chevron)\(escape(title))\(amount.map { "<span class=\"ct\">\($0)</span>" } ?? "")</summary>\n"
    }

    /// A section heading as a toggle, and the opening of the block that holds the section. The transcript also
    /// says how many segments it has.
    private static func sectionHeading(_ title: String, id: String, collapsed: Bool, count: Int?) -> String {
        let label =
            (collapsed ? "Expandir " : "Recolher ")
            + (title == SectionState.transcript ? "a transcrição" : "a seção \(title)")
        let amount = count.map { $0 == 1 ? "1 segmento" : "\($0) segmentos" }
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let tip = escape(label)
        return
            "<h2 class=\"disc\(collapsed ? "" : " open")\" id=\"\(id)\"><a href=\"minuta://section/\(encoded)\" data-tip=\"\(tip)\" aria-label=\"\(tip)\" aria-expanded=\"\(collapsed ? "false" : "true")\">\(chevron)\(escape(title))\(amount.map { "<span class=\"ct\">\($0)</span>" } ?? "")</a></h2>\n<div class=\"sec\(collapsed ? " hide" : "")\">\n"
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

    /// The titles of the "##" sections, in order; the chip `minuta://goto/N` points at the N-th.
    static func sectionTitles(_ markdown: String) -> [String] {
        markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .filter { $0.hasPrefix("## ") }.map { String($0.dropFirst(3)) }
    }

    /// The date line with the model menu button and the export buttons, the hint, and the section chips.
    private static func controlsHTML(_ controls: Controls, meta: [String: String], sections: [String]) -> String {
        var html = "<div class=\"bar\">\n"
        let date = subtitleText(meta)
        if !date.isEmpty { html += "<span class=\"sub\">\(escape(date))</span>\n" }
        let name = escape(controls.generating?.title ?? controls.shown?.title ?? "Escolher")
        let label = "<span class=\"lb\">Modelo</span>"
        if controls.generating != nil {
            html += "<span class=\"mdl busy\" id=\"mdl\">\(label)\(name)<i class=\"sp\"></i></span>\n"
        } else {
            html +=
                "<a class=\"mdl\" id=\"mdl\" href=\"minuta://models\" data-tip=\"Modelo de resumo\" aria-haspopup=\"menu\" aria-label=\"Modelo de resumo: \(name)\">\(label)\(name)\(selector)</a>\n"
        }
        html += "<span class=\"grow\"></span>\n<span class=\"acts\" role=\"group\" aria-label=\"Exportar a ata\">"
        html +=
            "<span class=\"act off\" data-tip=\"Enviar por e-mail (em breve)\" role=\"button\" aria-disabled=\"true\" aria-label=\"Enviar por e-mail\">\(mail)</span>"
        html +=
            "<a class=\"act\" href=\"minuta://export/html\" data-tip=\"Salvar como HTML\" aria-label=\"Salvar como HTML\">\(htmlIcon)</a>"
        html +=
            "<a class=\"act\" href=\"minuta://export/pdf\" data-tip=\"Salvar como PDF\" aria-label=\"Salvar como PDF\">\(pdfIcon)</a>"
        html += "</span>\n</div>\n"
        if !controls.hint.isEmpty { html += "<p class=\"hint\">\(escape(controls.hint))</p>\n" }
        guard !sections.isEmpty else { return html }
        // Three groups: the opening sections, the sections of the model, and the closing ones.
        let own = Set(controls.shown?.sections.map(\.title) ?? [])
        html += "<nav class=\"toc\" aria-label=\"Seções da ata\">"
        var group = 0
        var seenModel = false
        for (index, title) in sections.enumerated() {
            let isModel = own.contains(title)
            if isModel { seenModel = true }
            let current = isModel ? 1 : (seenModel ? 2 : 0)
            if index > 0 && current != group { html += "<span class=\"sep\" aria-hidden=\"true\"></span>" }
            group = current
            html += "<a\(isModel ? "" : " class=\"fx\"") href=\"minuta://goto/\(index)\">\(escape(title))</a>"
        }
        return html + "</nav>\n"
    }

    private static func subtitle(_ meta: [String: String]) -> String {
        let text = subtitleText(meta)
        return text.isEmpty ? "" : "<p class=\"sub\">\(escape(text))</p>\n"
    }

    private static func subtitleText(_ meta: [String: String]) -> String {
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
        return parts.joined(separator: " · ")
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
        .bar { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 12px; margin: 0; }
        .bar .sub { margin: 0; }
        .bar .grow { flex: 1; }
        .mdl { display: inline-flex; align-items: center; gap: 6px; font-size: 13px; line-height: 1; padding: 5px 8px 5px 10px; border-radius: 6px; border: 0.5px solid color-mix(in srgb, CanvasText 28%, transparent); color: CanvasText; background: Canvas; white-space: nowrap; }
        a.mdl:hover { background: color-mix(in srgb, CanvasText 6%, Canvas); }
        .mdl .lb { color: GrayText; }
        .mdl svg { color: GrayText; }
        .mdl .sp { width: 10px; height: 10px; border-radius: 50%; border: 1.5px solid currentColor; border-top-color: transparent; animation: spin 0.8s linear infinite; }
        @keyframes spin { to { transform: rotate(360deg); } }
        .acts { display: inline-flex; gap: 2px; }
        .act { display: inline-flex; align-items: center; justify-content: center; width: 28px; height: 28px; border-radius: 6px; color: GrayText; }
        a.act:hover { background: color-mix(in srgb, CanvasText 7%, transparent); color: CanvasText; }
        .act.off { opacity: 0.4; }
        .hint { color: GrayText; font-size: 12px; line-height: 1.5; margin: 12px 0 0; }
        .toc { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; margin: 14px 0 0; }
        .toc a { font-size: 12px; line-height: 1.3; padding: 3px 10px; border-radius: 5px; background: color-mix(in srgb, LinkText 14%, transparent); white-space: nowrap; }
        .toc a.fx { background: transparent; color: GrayText; box-shadow: inset 0 0 0 0.5px color-mix(in srgb, CanvasText 25%, transparent); }
        .toc a:hover { background: color-mix(in srgb, LinkText 22%, transparent); }
        .toc a.fx:hover { color: CanvasText; background: color-mix(in srgb, CanvasText 6%, transparent); }
        .toc .sep { width: 1px; height: 14px; margin: 0 4px; background: color-mix(in srgb, CanvasText 22%, transparent); }
        .hint + h2, .toc + h2, .bar + h2, .sub + h2 { margin-top: 30px; }
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
        h2.disc { margin: 22px 0 6px; padding-top: 12px; border-top: 1px solid color-mix(in srgb, CanvasText 14%, transparent); }
        .hint + h2.disc, .toc + h2.disc, .bar + h2.disc, .sub + h2.disc { margin-top: 26px; }
        h2 { scroll-margin-top: 12px; }
        h2:target { animation: flash 1.6s ease-out; border-radius: 6px; }
        @keyframes flash { from { background: color-mix(in srgb, LinkText 18%, transparent); } to { background: transparent; } }
        h2.disc a { display: inline-flex; align-items: center; gap: 6px; color: GrayText; }
        h2.disc a:hover { color: CanvasText; }
        h2.disc .cv { transition: transform 0.12s; }
        h2.disc.open .cv { transform: rotate(90deg); }
        h2.disc .ct { font-weight: 400; font-size: 12px; color: GrayText; }
        h2.disc .ct::before { content: "· "; }
        .sec.hide { display: none; }
        details.dt { margin: 22px 0 6px; padding-top: 12px; border-top: 1px solid color-mix(in srgb, CanvasText 14%, transparent); }
        .hint + details.dt, .toc + details.dt, .bar + details.dt, .sub + details.dt { margin-top: 26px; }
        details.dt > summary { display: flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 600; color: GrayText; cursor: pointer; list-style: none; }
        details.dt > summary::-webkit-details-marker { display: none; }
        details.dt > summary:hover { color: CanvasText; }
        details.dt .cv { transition: transform 0.12s; }
        details.dt[open] > summary .cv { transform: rotate(90deg); }
        details.dt .ct { font-weight: 400; font-size: 12px; }
        details.dt .ct::before { content: "· "; }
        details.dt[open] > summary { margin-bottom: 6px; }
        .tm { color: GrayText; font-size: 12px; font-variant-numeric: tabular-nums; }
        @media print {
            :root { color-scheme: light; }
            html, body { background: none; }
            body { padding: 0; }
            .card { max-width: none; padding: 0; border: none; border-radius: 0; }
            h2, h3 { break-after: avoid; }
            p.tl, li, tr { break-inside: avoid; }
        }
        </style></head><body>
        <div class="card" id="card">
        \(body)</div></body></html>
        """
    }
}

extension String {
    fileprivate var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}
