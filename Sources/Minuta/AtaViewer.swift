import AppKit
import WebKit

/// One reading window per minutes file: the Markdown rendered as a page, with JavaScript off and no
/// navigation away from the document (only jumps to transcript anchors).
@MainActor
final class AtaViewerController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = AtaViewerController()
    private var windows: [URL: NSWindow] = [:]

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
        let document = MarkdownHTML.convert(text)
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.loadHTMLString(document.html, baseURL: nil)

        let controller = NSViewController()
        controller.view = web
        let window = ClosableWindow(contentViewController: controller)
        window.title = document.title
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

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = action.request.url
        // With no base URL the page is "about:blank"; Foundation does not parse a fragment out of it.
        let isAnchor = url?.absoluteString.hasPrefix("about:blank#") == true
        decisionHandler(action.navigationType == .other || isAnchor ? .allow : .cancel)
    }
}
