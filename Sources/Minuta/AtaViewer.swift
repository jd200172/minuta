import AppKit
import Combine
import WebKit

/// One reading window per minutes file: the Markdown rendered as a page, with JavaScript off and no
/// navigation away from the document (only jumps to transcript anchors). The pencil next to a participant
/// starts an in-place rename (`ParticipantRename`), and so does the pencil next to the title (`TitleRename`).
/// Meetings written by the model flow of ADR 0017 also show the five summary models as chips under the title:
/// a click shows the summary of that model, generating it first when it does not exist yet. Chips and pencils
/// are `minuta://` links that this controller intercepts.
@MainActor
final class AtaViewerController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = AtaViewerController()
    private var windows: [URL: NSWindow] = [:]
    private var panes: [URL: Pane] = [:]
    private var subscriptions: [AnyCancellable] = []
    /// The Markdown each page was built from, so a pencil's index refers to the same participants.
    private var texts: [URL: String] = [:]
    /// The model each page showed as being generated, to reload only when that changes.
    private var shownRunning: [URL: SummaryModel] = [:]
    private var renaming: ParticipantRename?
    private var renamingTitle: TitleRename?
    private var scrollToRestore: Double?

    /// The parts of one window besides the window itself.
    private final class Pane {
        let web: WKWebView
        var managed = false

        init(web: WKWebView) { self.web = web }
    }

    override init() {
        super.init()
        SummaryService.shared.$running.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.runningChanged()
        }.store(in: &subscriptions)
        NotificationCenter.default.addObserver(
            forName: .ataChanged, object: nil, queue: .main
        ) { [weak self] note in
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
                title: "Não foi possível abrir a ata", message: "O arquivo não existe mais ou não pôde ser lido.",
                buttons: ["OK"])
            AtaLibrary.shared.refresh()
            return
        }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        let pane = Pane(web: web)
        windows[url] = nil
        panes[url] = pane
        let document = convert(text, url: url, pane: pane)
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

    // MARK: Page

    private func convert(_ text: String, url: URL, pane: Pane) -> MarkdownHTML.Document {
        texts[url] = text
        pane.managed = AtaStore.isManaged(text)
        shownRunning[url] = SummaryService.shared.running[url]
        return MarkdownHTML.convert(text, renamable: true, controls: controls(for: url, text: text))
    }

    /// The chips under the title: which model is shown, which already have a summary, and the line below.
    private func controls(for url: URL, text: String) -> MarkdownHTML.Controls? {
        guard AtaStore.isManaged(text) else { return nil }
        let classification = AtaStore.sidecar(forMarkdown: text, in: url.deletingLastPathComponent())
        let sidecar = classification?.sidecar
        let running = SummaryService.shared.running[url]
        let chosen = AtaStore.model(in: text)
        let shown = running ?? chosen
        let chips = SummaryModel.allCases.map {
            MarkdownHTML.Controls.Chip(model: $0, selected: $0 == shown, has: sidecar?.has($0) == true)
        }
        let hint: String
        if let running {
            hint = "Gerando o resumo no modelo \(running.title)…"
        } else if let suggestion = sidecar?.classification?.suggestion, let reason = sidecar?.classification?.reason {
            hint = "Sugerido: \(suggestion.title). \(reason)"
        } else if chosen == nil {
            hint = "Não foi possível sugerir um modelo. Escolha um, ou use Geral."
        } else {
            hint = ""
        }
        return MarkdownHTML.Controls(
            chips: chips, generating: running, hint: hint, canRedo: running == nil && chosen != nil)
    }

    /// Reads the file again and shows it, keeping the scroll position.
    private func reload(_ url: URL) {
        guard let pane = panes[url], let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let document = convert(text, url: url, pane: pane)
        windows[url]?.title = document.title.isEmpty ? url.deletingPathExtension().lastPathComponent : document.title
        pane.web.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
            self?.scrollToRestore = (value as? NSNumber)?.doubleValue
            pane.web.loadHTMLString(document.html, baseURL: nil)
        }
    }

    /// Reloads the pages whose generation started or ended, so the chips show it.
    private func runningChanged() {
        for url in panes.keys where shownRunning[url] != SummaryService.shared.running[url] { reload(url) }
    }

    // MARK: Summary models

    private func generate(_ model: SummaryModel, url: URL, force: Bool) {
        Task {
            do {
                try await SummaryService.shared.show(model, for: url, force: force)
            } catch {
                Alerts.show(
                    title: "Não foi possível gerar o resumo", message: AppError.from(error).message, buttons: ["OK"])
                reload(url)
            }
        }
    }

    private func url(of web: WKWebView) -> URL? {
        panes.first { $0.value.web === web }?.key
    }

    // MARK: Title

    private func beginTitleRename(_ web: WKWebView) {
        guard renaming == nil, renamingTitle == nil, let url = url(of: web), let text = texts[url] else { return }
        let current = AtaStore.title(in: text) ?? MinutesRenderer.untitled
        measure(web, id: "ti") { [weak self] rect in
            guard let self, self.renamingTitle == nil else { return }
            let rename = TitleRename(
                web: web, current: current, rect: rect,
                save: { [weak self] title in self?.saveTitle(title, url: url) },
                done: { [weak self] in self?.renamingTitle = nil })
            self.renamingTitle = rename
            rename.begin()
        }
    }

    private func saveTitle(_ title: String, url: URL) -> String? {
        if SummaryService.shared.running[url] != nil { return "Aguarde o resumo terminar." }
        do {
            let target = try AtaStore.rename(url, to: title)
            moveWindow(from: url, to: target)
            AtaLibrary.shared.refresh()
            return nil
        } catch {
            return AppError.from(error).message
        }
    }

    /// Called by the list when it renamed a file that may be open here.
    func renamed(from old: URL, to new: URL) {
        guard windows[old] != nil else { return }
        moveWindow(from: old, to: new)
    }

    /// Keeps the window of a renamed file.
    private func moveWindow(from old: URL, to new: URL) {
        if old != new {
            windows[new] = windows[old]
            windows[old] = nil
            panes[new] = panes[old]
            panes[old] = nil
            texts[new] = texts[old]
            texts[old] = nil
            shownRunning[new] = shownRunning[old]
            shownRunning[old] = nil
        }
        reload(new)
    }

    // MARK: Participants

    /// Asks the page where an element is. The only thing sent to the page is a fixed script with an id.
    private func measure(_ web: WKWebView, id: String, then body: @escaping (CGRect) -> Void) {
        let script =
            "(function(){var e=document.getElementById('\(id)');if(!e)return null;var r=e.getBoundingClientRect();return [r.left,r.top,r.width,r.height];})()"
        web.evaluateJavaScript(script) { result, _ in
            guard let numbers = (result as? [NSNumber])?.map(\.doubleValue), numbers.count == 4 else { return }
            body(CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
        }
    }

    /// Puts the rename field over participant `index`.
    private func beginRename(_ web: WKWebView, index: Int) {
        guard renaming == nil, renamingTitle == nil, let url = url(of: web), let text = texts[url] else { return }
        let speakers = ParticipantEditor.speakers(in: text)
        guard speakers.indices.contains(index) else { return }
        measure(web, id: "sp-\(index)") { [weak self] rect in
            guard let self, self.renaming == nil else { return }
            let rename = ParticipantRename(
                web: web, speakers: speakers, index: index, text: text, rect: rect,
                save: { [weak self] label, name in self?.saveName(name, for: label, url: url) },
                done: { [weak self] in self?.renaming = nil })
            self.renaming = rename
            rename.begin()
        }
    }

    /// Rewrites the file with the new name and reloads the page, keeping the scroll position.
    private func saveName(_ name: String, for label: String, url: URL) -> String? {
        do {
            let current = try String(contentsOf: url, encoding: .utf8)
            let updated = try ParticipantEditor.apply([label: name], to: current)
            if updated != current { try updated.write(to: url, atomically: true, encoding: .utf8) }
            reload(url)
            return nil
        } catch {
            return AppError.from(error).message
        }
    }

    // MARK: Delegates

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        renaming?.cancel()
        renamingTitle?.cancel()
        let closed = windows.filter { $0.value === window }.map(\.key)
        for url in closed {
            windows[url] = nil
            panes[url] = nil
            texts[url] = nil
            shownRunning[url] = nil
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = action.request.url
        if url?.scheme == "minuta" {
            decisionHandler(.cancel)
            switch url?.host {
            case "rename":
                if let index = Int(url?.lastPathComponent ?? "") { beginRename(webView, index: index) }
            case "title":
                beginTitleRename(webView)
            case "model":
                if let model = SummaryModel(rawValue: url?.lastPathComponent ?? ""), let file = self.url(of: webView) {
                    generate(model, url: file, force: false)
                }
            case "redo":
                if let file = self.url(of: webView), let text = texts[file], let model = AtaStore.model(in: text) {
                    generate(model, url: file, force: true)
                }
            default:
                break
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
