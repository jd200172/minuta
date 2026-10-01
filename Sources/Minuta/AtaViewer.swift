import AppKit
import WebKit

/// One reading window per minutes file: the Markdown rendered as a page, with JavaScript off and no
/// navigation away from the document (only jumps to transcript anchors). The pencil next to a participant
/// starts an in-place rename (`ParticipantRename`).
@MainActor
final class AtaViewerController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = AtaViewerController()
    private var windows: [URL: NSWindow] = [:]
    /// The Markdown each page was built from, so a pencil's index refers to the same participants.
    private var texts: [URL: String] = [:]
    private var renaming: ParticipantRename?
    private var scrollToRestore: Double?

    func open(_ url: URL) {
        if let window = windows[url] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            Alerts.show(
                title: "Não foi possível abrir a ata", message: "O arquivo não existe mais ou não pôde ser lido.",
                buttons: ["OK"])
            AtaLibrary.shared.refresh()
            return
        }
        let document = MarkdownHTML.convert(text, renamable: true)
        texts[url] = text
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.loadHTMLString(document.html, baseURL: nil)

        let controller = NSViewController()
        controller.view = web
        let window = ClosableWindow(contentViewController: controller)
        window.title = document.title.isEmpty ? url.deletingPathExtension().lastPathComponent : document.title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 780))
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        if !windows.isEmpty { window.cascadeTopLeft(from: NSPoint(x: 40 * windows.count, y: 0)) }

        let reveal = NSButton(
            image: NSImage(systemSymbolName: "folder", accessibilityDescription: "Mostrar no Finder")!,
            target: self, action: #selector(reveal(_:)))
        reveal.bezelStyle = .texturedRounded
        reveal.toolTip = "Mostrar no Finder"
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = reveal
        window.addTitlebarAccessoryViewController(accessory)

        windows[url] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ url: URL) {
        windows[url]?.close()
    }

    @objc private func reveal(_ sender: NSButton) {
        guard let url = windows.first(where: { $0.value === sender.window })?.key else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Asks the page where participant `index` is, then puts the rename field over it. The only thing sent to the
    /// page is a fixed script with a number.
    private func beginRename(_ web: WKWebView, index: Int) {
        guard renaming == nil, let entry = windows.first(where: { $0.value.contentViewController?.view === web }),
            let text = texts[entry.key]
        else { return }
        let speakers = ParticipantEditor.speakers(in: text)
        guard speakers.indices.contains(index) else { return }
        let script =
            "(function(){var e=document.getElementById('sp-\(index)');if(!e)return null;var r=e.getBoundingClientRect();return [r.left,r.top,r.width,r.height];})()"
        web.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, self.renaming == nil,
                let numbers = (result as? [NSNumber])?.map(\.doubleValue), numbers.count == 4
            else { return }
            let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
            let url = entry.key
            let rename = ParticipantRename(
                web: web, speakers: speakers, index: index, text: text, rect: rect,
                save: { [weak self] label, name in self?.saveName(name, for: label, url: url, web: web) },
                done: { [weak self] in self?.renaming = nil })
            self.renaming = rename
            rename.begin()
        }
    }

    /// Rewrites the file with the new name and reloads the page, keeping the scroll position.
    private func saveName(_ name: String, for label: String, url: URL, web: WKWebView) -> String? {
        do {
            let current = try String(contentsOf: url, encoding: .utf8)
            let updated = try ParticipantEditor.apply([label: name], to: current)
            if updated != current { try updated.write(to: url, atomically: true, encoding: .utf8) }
            texts[url] = updated
            web.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
                self?.scrollToRestore = (value as? NSNumber)?.doubleValue
                web.loadHTMLString(MarkdownHTML.convert(updated, renamable: true).html, baseURL: nil)
            }
            return nil
        } catch {
            return AppError.from(error).message
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        renaming?.cancel()
        texts = texts.filter { windows[$0.key] !== window }
        windows = windows.filter { $0.value !== window }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = action.request.url
        if url?.scheme == "minuta" {
            decisionHandler(.cancel)
            if url?.host == "rename", let index = Int(url?.lastPathComponent ?? "") {
                beginRename(webView, index: index)
            }
            return
        }
        // With no base URL the page is "about:blank"; Foundation does not parse a fragment out of it.
        let isAnchor = url?.absoluteString.hasPrefix("about:blank#") == true
        decisionHandler(action.navigationType == .other || isAnchor ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let y = scrollToRestore else { return }
        scrollToRestore = nil
        webView.evaluateJavaScript("window.scrollTo(0, \(y))")
    }
}
