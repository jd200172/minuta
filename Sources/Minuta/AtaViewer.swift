import AppKit
import Combine
import WebKit

/// One reading window per minutes file: the Markdown rendered as a page, with JavaScript off and no
/// navigation away from the document (only jumps to transcript anchors). The pencil next to a participant
/// starts an in-place rename (`ParticipantRename`). Meetings written by the model flow of ADR 0017 also get a
/// control with the five summary models above the page: a click shows the summary of that model, generating
/// it first when it does not exist yet.
@MainActor
final class AtaViewerController: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = AtaViewerController()
    private var windows: [URL: NSWindow] = [:]
    private var panes: [URL: Pane] = [:]
    private var subscriptions: [AnyCancellable] = []
    /// The Markdown each page was built from, so a pencil's index refers to the same participants.
    private var texts: [URL: String] = [:]
    private var renaming: ParticipantRename?
    private var scrollToRestore: Double?

    /// The parts of one window besides the page.
    private final class Pane {
        let web: WKWebView
        let header = NSStackView()
        let segments = NSSegmentedControl(
            labels: SummaryModel.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        let spinner = NSProgressIndicator()
        let status = NSTextField(wrappingLabelWithString: "")
        let more = NSPopUpButton(frame: .zero, pullsDown: true)
        var managed = false

        init(web: WKWebView) { self.web = web }
    }

    override init() {
        super.init()
        SummaryService.shared.$running.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refreshAll()
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
        let document = MarkdownHTML.convert(text, renamable: true)
        texts[url] = text
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.loadHTMLString(document.html, baseURL: nil)

        let pane = Pane(web: web)
        pane.managed = AtaStore.isManaged(text)
        let controller = NSViewController()
        controller.view = makeContent(pane, url: url)
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
        panes[url] = pane
        refresh(url)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Model control

    private func makeContent(_ pane: Pane, url: URL) -> NSView {
        let segments = pane.segments
        segments.segmentStyle = .rounded
        segments.target = self
        segments.action = #selector(modelClicked(_:))
        segments.setAccessibilityLabel("Resumo no modelo")
        for index in 0..<segments.segmentCount { segments.setWidth(0, forSegment: index) }

        pane.spinner.style = .spinning
        pane.spinner.controlSize = .small
        pane.spinner.isDisplayedWhenStopped = false

        pane.more.pullsDown = true
        pane.more.bezelStyle = .texturedRounded
        pane.more.addItem(withTitle: "")
        pane.more.item(at: 0)?.image = NSImage(
            systemSymbolName: "ellipsis.circle", accessibilityDescription: "Mais ações")
        pane.more.addItems(withTitles: ["Renomear reunião…", "Refazer este resumo"])
        for item in pane.more.itemArray.dropFirst() {
            item.target = self
        }
        pane.more.item(at: 1)?.action = #selector(renameMeeting(_:))
        pane.more.item(at: 2)?.action = #selector(redoSummary(_:))
        pane.more.setAccessibilityLabel("Mais ações")
        pane.more.setContentHuggingPriority(.required, for: .horizontal)

        let bar = NSStackView(views: [segments, pane.spinner, pane.more])
        bar.orientation = .horizontal
        bar.spacing = 8
        pane.status.font = .systemFont(ofSize: 11)
        pane.status.textColor = .secondaryLabelColor
        pane.status.maximumNumberOfLines = 2
        pane.header.orientation = .vertical
        pane.header.alignment = .leading
        pane.header.spacing = 6
        pane.header.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 8, right: 16)
        pane.header.setViews([bar, pane.status], in: .top)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalTo: pane.header.widthAnchor, constant: -32).isActive = true
        pane.status.translatesAutoresizingMaskIntoConstraints = false
        pane.status.widthAnchor.constraint(equalTo: pane.header.widthAnchor, constant: -32).isActive = true
        pane.header.isHidden = !pane.managed

        let root = NSStackView(views: [pane.header, pane.web])
        root.orientation = .vertical
        root.spacing = 0
        root.alignment = .leading
        pane.header.translatesAutoresizingMaskIntoConstraints = false
        pane.header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        pane.web.translatesAutoresizingMaskIntoConstraints = false
        pane.web.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        pane.web.setContentHuggingPriority(.defaultLow, for: .vertical)
        let container = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    /// Dots, selection and status line of one window, from the files on disk and the running generations.
    private func refresh(_ url: URL) {
        guard let pane = panes[url], pane.managed,
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        let sidecar = AtaStore.sidecar(forMarkdown: text, in: url.deletingLastPathComponent())?.sidecar
        let running = SummaryService.shared.running[url]
        let shown = running ?? AtaStore.model(in: text)
        for (index, model) in SummaryModel.allCases.enumerated() {
            let has = sidecar?.has(model) == true
            pane.segments.setLabel(has ? "\(model.title) •" : model.title, forSegment: index)
            pane.segments.setToolTip(has ? "Resumo gerado" : nil, forSegment: index)
        }
        pane.segments.selectedSegment = shown.flatMap { SummaryModel.allCases.firstIndex(of: $0) } ?? -1
        pane.segments.isEnabled = running == nil
        pane.more.isEnabled = running == nil
        pane.more.item(at: 2)?.isEnabled = AtaStore.model(in: text) != nil
        if running != nil { pane.spinner.startAnimation(nil) } else { pane.spinner.stopAnimation(nil) }

        if let running {
            pane.status.stringValue = "Gerando o resumo no modelo \(running.title)…"
        } else if let suggestion = sidecar?.classification?.suggestion, let reason = sidecar?.classification?.reason {
            pane.status.stringValue = "Sugerido: \(suggestion.title). \(reason)"
        } else if AtaStore.model(in: text) == nil {
            pane.status.stringValue = "Não foi possível sugerir um modelo. Escolha um, ou use Geral."
        } else {
            pane.status.stringValue = ""
        }
        pane.status.isHidden = pane.status.stringValue.isEmpty
    }

    private func refreshAll() {
        for url in panes.keys { refresh(url) }
    }

    private func url(of control: NSView?) -> URL? {
        guard let window = control?.window else { return nil }
        return windows.first { $0.value === window }?.key
    }

    @objc private func modelClicked(_ sender: NSSegmentedControl) {
        guard let url = url(of: sender), sender.selectedSegment >= 0 else { return }
        let model = SummaryModel.allCases[sender.selectedSegment]
        generate(model, url: url, force: false)
    }

    @objc private func redoSummary(_ sender: Any?) {
        guard let url = windows.first(where: { $0.value.isKeyWindow })?.key,
            let text = try? String(contentsOf: url, encoding: .utf8), let model = AtaStore.model(in: text)
        else { return }
        generate(model, url: url, force: true)
    }

    private func generate(_ model: SummaryModel, url: URL, force: Bool) {
        Task {
            do {
                try await SummaryService.shared.show(model, for: url, force: force)
            } catch {
                Alerts.show(
                    title: "Não foi possível gerar o resumo", message: AppError.from(error).message, buttons: ["OK"])
            }
            refresh(url)
        }
    }

    @objc private func renameMeeting(_ sender: Any?) {
        guard let url = windows.first(where: { $0.value.isKeyWindow })?.key,
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        if SummaryService.shared.running[url] != nil {
            Alerts.show(
                title: "Aguarde o resumo terminar",
                message: "A reunião só pode ser renomeada depois que o resumo for gerado.",
                buttons: ["OK"])
            return
        }
        let alert = NSAlert()
        alert.messageText = "Renomear reunião"
        alert.informativeText = "O título aparece na lista de atas e no nome do arquivo."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = AtaStore.title(in: text) ?? ""
        field.placeholderString = "Título"
        alert.accessoryView = field
        alert.addButton(withTitle: "Renomear")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let target = try AtaStore.rename(url, to: field.stringValue)
            moveWindow(from: url, to: target)
            AtaLibrary.shared.refresh()
        } catch {
            Alerts.show(
                title: "Não foi possível renomear", message: AppError.from(error).message, buttons: ["OK"])
        }
    }

    /// Keeps the window of a renamed file.
    private func moveWindow(from old: URL, to new: URL) {
        guard old != new else {
            reload(new)
            return
        }
        windows[new] = windows[old]
        windows[old] = nil
        panes[new] = panes[old]
        panes[old] = nil
        texts[new] = texts[old]
        texts[old] = nil
        reload(new)
    }

    /// Reads the file again and shows it, keeping the scroll position.
    private func reload(_ url: URL) {
        guard let pane = panes[url], let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        texts[url] = text
        pane.managed = AtaStore.isManaged(text)
        pane.header.isHidden = !pane.managed
        let document = MarkdownHTML.convert(text, renamable: true)
        windows[url]?.title = document.title.isEmpty ? url.deletingPathExtension().lastPathComponent : document.title
        pane.web.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
            self?.scrollToRestore = (value as? NSNumber)?.doubleValue
            pane.web.loadHTMLString(document.html, baseURL: nil)
        }
        refresh(url)
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
        guard renaming == nil, let entry = panes.first(where: { $0.value.web === web }),
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
        panes = panes.filter { windows[$0.key] !== window }
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
