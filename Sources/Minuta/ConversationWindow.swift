import AppKit
import WebKit

/// The window that shows the transcript of a meeting as a conversation (ADR 0034): one bubble per segment, read-only,
/// in the style of a messaging app. One window per minutes file, opened by the chat button of the reading window.
/// The page is built from the Markdown, so the names the user gave to participants show up; it is rebuilt when the
/// file changes (`.ataChanged`).
@MainActor
final class ConversationWindowController: NSObject, NSWindowDelegate {
    static let shared = ConversationWindowController()
    private var windows: [URL: NSWindow] = [:]

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: .ataChanged, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let url = note.object as? URL else { return }
                self.reload(url)
            }
        }
    }

    func open(_ url: URL) {
        if let window = windows[url] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            Alerts.show(
                title: "Não foi possível abrir a conversa", message: "O arquivo não existe mais ou não pôde ser lido.",
                buttons: ["OK"])
            return
        }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.loadHTMLString(ConversationHTML.page(markdown: text, mine: Config.userName), baseURL: nil)
        let controller = NSViewController()
        controller.view = web
        let window = ClosableWindow(contentViewController: controller)
        window.title = Self.title(of: text)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 720))
        window.contentMinSize = NSSize(width: 320, height: 320)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        if !windows.isEmpty { window.cascadeTopLeft(from: NSPoint(x: 40 * windows.count, y: 0)) }
        windows[url] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func title(of text: String) -> String {
        "Conversa · " + (AtaStore.title(in: text) ?? MinutesRenderer.untitled)
    }

    private func reload(_ url: URL) {
        guard let window = windows[url], let web = window.contentViewController?.view as? WKWebView,
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        window.title = Self.title(of: text)
        web.loadHTMLString(ConversationHTML.page(markdown: text, mine: Config.userName), baseURL: nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let key = windows.first(where: { $0.value === window })?.key
        else { return }
        windows[key] = nil
    }
}

/// The page of the conversation window: the transcript lines of the Markdown as bubbles (ADR 0034). The person who
/// recorded (`mine`) is on the right, in green and with no name; each other speaker has a color of their own, by order
/// of first appearance. The name shows on the first bubble of a turn, the clock time of the meeting (start plus the
/// segment's offset) on every bubble, and a chip with the date opens each day.
enum ConversationHTML {
    private static let palette = 6

    static func page(markdown: String, mine: String) -> String {
        let start = AtaStore.frontMatter(markdown)["inicio"].flatMap { ISO8601DateFormatter().date(from: $0) }
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .compactMap { MarkdownHTML.transcriptParts($0) }
        var colors: [String: Int] = [:]
        var body = ""
        var previous: String?
        var day: String?
        for line in lines {
            let seconds = offset(line.time)
            let moment = start.map { $0.addingTimeInterval(seconds) }
            if let moment {
                let label = dayFormatter.string(from: moment)
                if label != day {
                    body += "<div class=\"day\">\(MarkdownHTML.escape(label))</div>\n"
                    day = label
                    previous = nil
                }
            }
            let clock = moment.map { clockFormatter.string(from: $0) } ?? String(line.time.dropFirst(3))
            let isMine = line.speaker == mine
            let first = line.speaker != previous
            previous = line.speaker
            var classes = "b" + (isMine ? " me" : "") + (first ? " tail" : "")
            var name = ""
            if !isMine {
                let color = colors[line.speaker] ?? colors.count % palette
                colors[line.speaker] = color
                classes += " p\(color)"
                if first { name = "<div class=\"n\">\(MarkdownHTML.escape(line.speaker))</div>" }
            }
            body +=
                "<div class=\"\(classes)\" id=\"\(line.id)\">\(name)\(MarkdownHTML.escape(line.text))<span class=\"t\">\(clock)</span></div>\n"
        }
        if lines.isEmpty { body = "<div class=\"day\">Sem transcrição</div>" }
        return """
            <!doctype html>
            <html lang="pt-BR"><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
            <title>Conversa</title>
            <style>
            :root { color-scheme: light dark; --bg: #EFE7DE; --me: #D9FDD3; --ot: #FFFFFF; --tx: #111B21; --tm: #667781; --chip: rgba(255,255,255,0.85); --p0: #B3499A; --p1: #C77D00; --p2: #1F7AE0; --p3: #0F8F6B; --p4: #C0392B; --p5: #6C5CE7; }
            @media (prefers-color-scheme: dark) { :root { --bg: #0B141A; --me: #005C4B; --ot: #202C33; --tx: #E9EDEF; --tm: #8696A0; --chip: rgba(24,34,41,0.85); --p0: #E26AB6; --p1: #E0A34B; --p2: #53A6FA; --p3: #06CF9C; --p4: #F0766A; --p5: #A29BFE; } }
            html { background: var(--bg); }
            body { font: 14px/1.4 -apple-system, sans-serif; margin: 0; padding: 12px 16px 24px; color: var(--tx); background: var(--bg); display: flex; flex-direction: column; }
            .day { align-self: center; background: var(--chip); color: var(--tm); font-size: 12px; padding: 4px 10px; border-radius: 8px; margin: 6px 0 10px; }
            .b { position: relative; box-sizing: border-box; max-width: 78%; padding: 5px 9px 4px; border-radius: 8px; background: var(--ot); color: var(--tx); margin: 2px 0; box-shadow: 0 1px 0.5px rgba(11,20,26,0.13); overflow-wrap: anywhere; }
            .b::after { content: ""; display: block; clear: both; }
            .b.me { align-self: flex-end; background: var(--me); }
            .b.tail { margin-top: 9px; }
            .b.tail:not(.me) { border-top-left-radius: 0; }
            .b.tail.me { border-top-right-radius: 0; }
            .b.tail:not(.me)::before { content: ""; position: absolute; left: -7px; top: 0; border-top: 8px solid var(--ot); border-left: 8px solid transparent; }
            .b.tail.me::before { content: ""; position: absolute; right: -7px; top: 0; border-top: 8px solid var(--me); border-right: 8px solid transparent; }
            .n { font-size: 13px; font-weight: 600; margin-bottom: 1px; }
            .p0 .n { color: var(--p0); } .p1 .n { color: var(--p1); } .p2 .n { color: var(--p2); }
            .p3 .n { color: var(--p3); } .p4 .n { color: var(--p4); } .p5 .n { color: var(--p5); }
            .t { float: right; margin: 7px 0 0 12px; font-size: 11px; color: var(--tm); line-height: 1; font-variant-numeric: tabular-nums; }
            </style></head><body>
            \(body)</body></html>
            """
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        return formatter
    }()

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// `00:01:05` as seconds.
    private static func offset(_ time: String) -> TimeInterval {
        time.split(separator: ":").compactMap { Double($0) }.reduce(0) { $0 * 60 + $1 }
    }
}
