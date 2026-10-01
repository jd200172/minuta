import Foundation

/// Turns the minutes Markdown into a reading page. It only understands the subset `MinutesRenderer`
/// writes (headings, bullets, one table, bold, internal links, transcript anchors). All text is escaped, so
/// whatever the speech model or the LLM produced cannot inject markup.
enum MarkdownHTML {
    struct Document {
        var title: String
        var html: String
    }

    static func convert(_ markdown: String) -> Document {
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

        var title = ""
        var body = ""
        var paragraph: [String] = []
        var list: [String] = []
        var table: [String] = []

        func flush() {
            if !paragraph.isEmpty {
                body +=
                    transcriptLine(paragraph.joined(separator: " "))
                    ?? "<p>\(inline(paragraph.joined(separator: " ")))</p>\n"
                paragraph = []
            }
            if !list.isEmpty {
                body += "<ul>\n" + list.map { "<li>\(inline($0))</li>\n" }.joined() + "</ul>\n"
                list = []
            }
            if !table.isEmpty {
                body += tableHTML(table)
                table = []
            }
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else if line.hasPrefix("# ") {
                flush()
                title = String(line.dropFirst(2))
                body += "<h1>\(escape(title))</h1>\n\(subtitle(meta))"
            } else if line.hasPrefix("## ") {
                flush()
                body += "<h2>\(escape(String(line.dropFirst(3))))</h2>\n"
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
        return Document(title: title.isEmpty ? "Ata" : title, html: page(title: title, body: body))
    }

    // MARK: Pieces

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Escapes, then turns `[00:00:10](#t-000010)` into a chip, other `[x](#id)` into links and `**x**` into bold.
    static func inline(_ text: String) -> String {
        var out = escape(text)
        out = out.replacingOccurrences(
            of: #"\[(\d{2}:\d{2}:\d{2})\]\((#[A-Za-z0-9_-]+)\)"#, with: #"<a class="chip" href="$2">$1</a>"#,
            options: .regularExpression)
        out = out.replacingOccurrences(
            of: #"\[([^\]]+)\]\((#[A-Za-z0-9_-]+)\)"#, with: #"<a href="$2">$1</a>"#, options: .regularExpression)
        out = out.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        return out
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

    private static func tableHTML(_ rows: [String]) -> String {
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
        var html = "<table>\n<tr>" + cells(header).map { "<th>\(inline($0))</th>" }.joined() + "</tr>\n"
        for row in rows.dropFirst() where !row.contains("---") {
            html += "<tr>" + cells(row).map { "<td>\(inline($0))</td>" }.joined() + "</tr>\n"
        }
        return html + "</table>\n"
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
        :root { color-scheme: light dark; }
        body { font: 14px/1.55 -apple-system, sans-serif; margin: 0; padding: 24px 28px 48px; max-width: 760px; color: CanvasText; background: Canvas; }
        h1 { font-size: 22px; font-weight: 600; margin: 0 0 2px; }
        .sub { color: GrayText; font-size: 13px; margin: 0 0 18px; }
        h2 { font-size: 13px; font-weight: 600; color: GrayText; margin: 24px 0 6px; }
        h3 { font-size: 14px; font-weight: 600; margin: 14px 0 2px; }
        p { margin: 6px 0; }
        ul { margin: 0; padding-left: 20px; }
        li { margin: 3px 0; }
        table { width: 100%; border-collapse: collapse; font-size: 13px; margin: 4px 0; }
        th { text-align: left; color: GrayText; font-weight: 500; }
        th, td { padding: 6px 10px 6px 0; vertical-align: top; border-bottom: 1px solid color-mix(in srgb, CanvasText 14%, transparent); }
        a { color: LinkText; text-decoration: none; }
        a.chip { font-size: 11px; padding: 0 6px; border-radius: 5px; background: color-mix(in srgb, LinkText 14%, transparent); margin-left: 2px; font-variant-numeric: tabular-nums; white-space: nowrap; }
        p.tl { display: grid; grid-template-columns: 64px 1fr; gap: 8px; padding: 3px 8px; margin: 0 -8px; border-radius: 6px; }
        p.tl:target { background: color-mix(in srgb, LinkText 16%, transparent); }
        .tm { color: GrayText; font-size: 12px; font-variant-numeric: tabular-nums; }
        </style></head><body>
        \(body)</body></html>
        """
    }
}

extension String {
    fileprivate var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() }
}
