import AppKit
import Combine
import WebKit

/// One reading window per minutes file: the Markdown rendered as a page, with JavaScript off and no
/// navigation away from the document (only jumps to transcript anchors). The pencil next to a participant
/// starts an in-place rename (`ParticipantRename`), and so does the pencil next to the title (`TitleRename`).
/// Meetings written by the model flow of ADR 0017 also get a bar under the title (ADR 0027): the model button opens
/// a menu of the summary models (choosing one shows its summary, generating it first when it does not exist yet),
/// the export buttons save the minutes as HTML or PDF, and a chip per section scrolls to that section. The page
/// keeps the head fixed, scrolls the text under it, and the app fills the chip of the section at the top. Buttons, chips and pencils are `minuta://` links that
/// this controller intercepts. So are the citation chips (`minuta://cite/...`, a balloon with the cited text; its
/// times show the transcript at that line).
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
    /// The title of the section at the top of each page's pane, whose chip is filled; the first one until the pane
    /// scrolls or a chip is clicked.
    private var selected: [URL: String] = [:]
    private var scrollMonitor: Any?
    private var spyWork: DispatchWorkItem?
    private var renaming: ParticipantRename?
    private var renamingTitle: TitleRename?
    private var scrollToRestore: Double?

    /// The parts of one window besides the window itself.
    @MainActor private final class Pane {
        let web: WKWebView
        var managed = false
        var tips: PageTips?
        var redo: NSButton?
        let balloon = CitationBalloon()

        init(web: WKWebView) { self.web = web }
    }

    override init() {
        super.init()
        SummaryService.shared.$running.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.runningChanged()
        }.store(in: &subscriptions)
        Retranscriber.shared.$running.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateRedoButtons()
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
        pane.tips = PageTips(web: web)
        pane.balloon.onVisibilityChange = { [weak pane] shown in pane?.tips?.suppressed = shown }
        windows[url] = nil
        panes[url] = pane
        let document = convert(text, url: url, pane: pane)
        web.loadHTMLString(document.html, baseURL: nil)

        let controller = NSViewController()
        controller.view = web
        let window = ClosableWindow(contentViewController: controller)
        window.title = document.title.isEmpty ? url.deletingPathExtension().lastPathComponent : document.title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Self.savedSize())
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.delegate = self
        window.center()
        if !windows.isEmpty { window.cascadeTopLeft(from: NSPoint(x: 40 * windows.count, y: 0)) }

        let reveal = NSButton(
            image: NSImage(systemSymbolName: "folder", accessibilityDescription: "Mostrar no Finder")!,
            target: self, action: #selector(reveal(_:)))
        reveal.bezelStyle = .texturedRounded
        reveal.setAccessibilityLabel("Mostrar no Finder")
        TipHost.attach("Mostrar no Finder", to: reveal)
        let transcript = NSButton(
            image: NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Corrigir a transcrição")!,
            target: self, action: #selector(openTranscript(_:)))
        transcript.bezelStyle = .texturedRounded
        transcript.setAccessibilityLabel("Corrigir a transcrição")
        TipHost.attach("Corrigir a transcrição", to: transcript)
        transcript.isEnabled = AtaStore.isManaged(text)
        let redo = NSButton(
            image: NSImage(
                systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Refazer a transcrição")!,
            target: self, action: #selector(redoTranscription(_:)))
        redo.bezelStyle = .texturedRounded
        redo.setAccessibilityLabel("Refazer a transcrição")
        TipHost.attach("Refazer a transcrição a partir do áudio", to: redo)
        pane.redo = redo
        updateRedoButton(url)
        let buttons = NSStackView(views: [redo, transcript, reveal])
        buttons.spacing = 8
        buttons.frame = NSRect(origin: .zero, size: buttons.fittingSize)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = buttons
        window.addTitlebarAccessoryViewController(accessory)

        windows[url] = window
        startWatchingScroll()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The size the user left a reading window at, shared by every reading window; the first one opens wide enough
    /// for the column of text to reach its 900 px with a margin of 32 px on each side.
    private static let sizeKey = "readingWindowSize"
    private static let defaultSize = NSSize(width: 964, height: 780)

    private static func savedSize() -> NSSize {
        guard let values = UserDefaults.standard.array(forKey: sizeKey) as? [Double], values.count == 2,
            values[0] >= 480, values[1] >= 320
        else { return defaultSize }
        return NSSize(width: values[0], height: values[1])
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let size = window.contentRect(forFrameRect: window.frame).size
        UserDefaults.standard.set([Double(size.width.rounded()), Double(size.height.rounded())], forKey: Self.sizeKey)
    }

    func close(_ url: URL) {
        windows[url]?.close()
    }

    @objc private func openTranscript(_ sender: NSButton) {
        guard let url = windows.first(where: { $0.value === sender.window })?.key else { return }
        TranscriptWindowController.shared.open(url)
    }

    @objc private func redoTranscription(_ sender: NSButton) {
        guard let url = windows.first(where: { $0.value === sender.window })?.key else { return }
        let choice = Alerts.show(
            title: "Refazer a transcrição?",
            message:
                "O áudio será transcrito de novo e a transcrição atual será substituída. As correções e os nomes dos participantes desta reunião serão perdidos, e os resumos existentes ficarão desatualizados até serem refeitos. A transcrição usa o serviço de STT e gera custo.",
            buttons: ["Refazer", "Cancelar"], destructive: 0, escape: 1)
        guard choice == 0 else { return }
        Task {
            do {
                try await Retranscriber.shared.redo(url)
            } catch {
                Alerts.show(
                    title: "Não foi possível refazer a transcrição", message: AppError.from(error).message,
                    buttons: ["OK"])
            }
        }
    }

    /// The redo button works only with a recording to transcribe, and not while the ata is being processed.
    private func updateRedoButton(_ url: URL) {
        guard let button = panes[url]?.redo else { return }
        let busy = Retranscriber.shared.running.contains(url) || SummaryService.shared.running[url] != nil
        let text = texts[url] ?? ""
        button.isEnabled = !busy && Retranscriber.canRedo(url, text: text)
    }

    private func updateRedoButtons() {
        for url in panes.keys { updateRedoButton(url) }
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
        defer { updateRedoButton(url) }
        return MarkdownHTML.convert(
            text, renamable: true, controls: controls(for: url, text: text), citations: true)
    }

    /// The controls under the title: the model whose summary is shown, the one being generated, and the line of state
    /// below them, which is empty when there is nothing to warn about.
    private func controls(for url: URL, text: String) -> MarkdownHTML.Controls? {
        guard AtaStore.isManaged(text) else { return nil }
        let classification = AtaStore.sidecar(forMarkdown: text, in: url.deletingLastPathComponent())
        let sidecar = classification?.sidecar
        let running = SummaryService.shared.running[url]
        let chosen = AtaStore.model(in: text)
        let hint: String
        if running == nil, let chosen, sidecar?.isOutdated(chosen) == true {
            hint =
                "A transcrição foi corrigida depois deste resumo. Para atualizá-lo, use Refazer este resumo, no menu Modelo."
        } else if let running {
            hint = "Gerando o resumo no modelo \(running.title)…"
        } else if chosen == nil, AtaStore.frontMatter(text)["modelo"] != nil {
            hint = "Este resumo usa um modelo que não existe mais. Escolha outro no menu Modelo."
        } else if chosen == nil, sidecar?.classification?.suggestion != nil {
            hint = "Resumo ainda não gerado. Escolha um modelo no menu Modelo."
        } else if chosen == nil {
            hint = "Não foi possível sugerir um modelo. Escolha um no menu Modelo, ou use Geral."
        } else {
            hint = ""
        }
        return MarkdownHTML.Controls(shown: chosen, generating: running, hint: hint, selected: selected[url])
    }

    /// Reads the file again and shows it, keeping the scroll position of the pane.
    private func reload(_ url: URL) {
        guard let pane = panes[url], let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        pane.tips?.hide()
        pane.balloon.close()
        let document = convert(text, url: url, pane: pane)
        windows[url]?.title = document.title.isEmpty ? url.deletingPathExtension().lastPathComponent : document.title
        pane.web.evaluateJavaScript("(document.getElementById('pane')||document.scrollingElement).scrollTop") {
            [weak self] value, _ in
            self?.scrollToRestore = (value as? NSNumber)?.doubleValue
            pane.web.loadHTMLString(document.html, baseURL: nil)
        }
    }

    /// Reloads the pages whose generation started or ended, so the model button shows it.
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

    /// The menu of the model button, below it: the four models, the current one checked, then the redo item.
    private func showModelMenu(_ web: WKWebView) {
        guard let url = url(of: web), let text = texts[url], SummaryService.shared.running[url] == nil else { return }
        let sidecar = AtaStore.sidecar(forMarkdown: text, in: url.deletingLastPathComponent())?.sidecar
        let chosen = AtaStore.model(in: text)
        let menu = NSMenu()
        menu.autoenablesItems = false
        for model in SummaryModel.allCases {
            let item = MenuAction.item("") { [weak self] in self?.generate(model, url: url, force: false) }
            item.attributedTitle = Self.menuTitle(model, has: model != chosen && sidecar?.has(model) == true)
            item.setAccessibilityLabel(model.title)
            item.state = model == chosen ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let redo = MenuAction.item("Refazer este resumo") { [weak self] in
            if let chosen { self?.generate(chosen, url: url, force: true) }
        }
        redo.isEnabled = chosen != nil
        menu.addItem(redo)
        panes[url]?.tips?.hide()
        measure(web, id: "mdl") { rect in
            menu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.maxY + 4), in: web)
        }
    }

    /// The model's name, "resumo gerado" when it already has one, and on a second line what it shows.
    private static func menuTitle(_ model: SummaryModel, has: Bool) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let small = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        let title = NSMutableAttributedString(string: model.title, attributes: [.font: font])
        if has {
            title.append(
                NSAttributedString(
                    string: "  resumo gerado",
                    attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        let shows = model.tooltip.components(separatedBy: "\n").first { $0.hasPrefix("Mostra") } ?? ""
        title.append(
            NSAttributedString(
                string: "\n" + shows, attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor]))
        return title
    }

    // MARK: Export

    private func export(_ kind: AtaExport.Kind, web: WKWebView) {
        guard let url = url(of: web), let window = windows[url],
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        panes[url]?.tips?.hide()
        AtaExport.save(text, from: url, as: kind, in: window)
    }

    private func url(of web: WKWebView) -> URL? {
        panes.first { $0.value.web === web }?.key
    }

    // MARK: Transcript and citations

    /// Opens the balloon of the chip `ref`, which cites segment `id`.
    private func showCitation(_ web: WKWebView, segment id: String, ref: Int) {
        guard let url = url(of: web), let pane = panes[url], let text = texts[url] else { return }
        let rows = TranscriptSegment.window(around: id, in: TranscriptSegment.parse(text))
        guard !rows.isEmpty else { return }
        // A second click on the chip that has its balloon open closes it.
        if pane.balloon.openRef == ref {
            pane.balloon.close()
            return
        }
        if pane.balloon.justClosed(ref) { return }
        pane.tips?.hide()
        measure(web, id: "rf-\(ref)") { [weak self, weak pane] chip in
            self?.measure(web, id: "card") { card in
                pane?.balloon.show(rows: rows, ref: ref, near: chip, within: card, in: web) { [weak self] id in
                    self?.goTo(id, url: url)
                }
            }
        }
    }

    /// Scrolls the pane to the section of chip `index` and fills that chip.
    private func goToSection(_ index: Int, url: URL) {
        guard let pane = panes[url], let text = texts[url] else { return }
        let titles = MarkdownHTML.sectionTitles(text)
        guard titles.indices.contains(index) else { return }
        showAnchor("s-\(index)", in: pane.web)
        fill(index, titles: titles, url: url)
        // The scroll this click causes must not be read back as the reader's own.
        spyWork?.cancel()
    }

    /// Scrolls the pane to a transcript line.
    private func goTo(_ id: String, url: URL) {
        guard let pane = panes[url], id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return }
        showAnchor(id, in: pane.web)
        scheduleSpy(url)
    }

    // MARK: Chip of the section on screen

    /// Marks chip `index` as the current one, in the page and in `selected`.
    private func fill(_ index: Int, titles: [String], url: URL) {
        guard titles.indices.contains(index), let pane = panes[url] else { return }
        selected[url] = titles[index]
        pane.web.evaluateJavaScript(
            "document.querySelectorAll('.toc a').forEach(function(e,n){e.classList.toggle('on',n===\(index));"
                + "if(n===\(index)){e.setAttribute('aria-current','true')}else{e.removeAttribute('aria-current')}})")
    }

    /// The pane scrolls with no script of its own, so the app watches the wheel, the keys and the mouse, and a
    /// moment after each asks the page which section is at the top.
    private func startWatchingScroll() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown, .leftMouseUp]) {
            [weak self] event in
            if let self, let url = self.windows.first(where: { $0.value === event.window })?.key {
                self.scheduleSpy(url)
            }
            return event
        }
    }

    private func scheduleSpy(_ url: URL) {
        spyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.spy(url) }
        spyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// The last section whose heading is at or above the top of the pane; the last one when the pane is at its end.
    private func spy(_ url: URL) {
        guard let pane = panes[url], let text = texts[url] else { return }
        let script = """
            (function(){var p=document.getElementById('pane');if(!p)return null;
            var top=p.getBoundingClientRect().top+40;var hs=p.querySelectorAll('h2[id^="s-"]');var best=0;
            for(var i=0;i<hs.length;i++){if(hs[i].getBoundingClientRect().top<=top){best=parseInt(hs[i].id.slice(2));}}
            if(hs.length&&p.scrollTop>0&&p.scrollHeight>p.clientHeight+2&&p.scrollTop+p.clientHeight>=p.scrollHeight-2){
            best=parseInt(hs[hs.length-1].id.slice(2));}
            return best;})()
            """
        pane.web.evaluateJavaScript(script) { [weak self] value, _ in
            guard let self, let index = (value as? NSNumber)?.intValue else { return }
            let titles = MarkdownHTML.sectionTitles(text)
            if titles.indices.contains(index), self.selected[url] != titles[index] {
                self.fill(index, titles: titles, url: url)
            }
        }
    }

    /// Setting the hash scrolls to the line and applies its `:target` highlight; the page runs no script of its own.
    private func showAnchor(_ id: String, in web: WKWebView) {
        web.evaluateJavaScript("location.hash='';location.hash='\(id)';")
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
        if Retranscriber.shared.running.contains(url) { return "Aguarde a transcrição terminar." }
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
            selected[new] = selected[old]
            selected[old] = nil
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
            panes[url]?.balloon.close()
            panes[url]?.tips?.stop()
            windows[url] = nil
            panes[url] = nil
            texts[url] = nil
            shownRunning[url] = nil
            selected[url] = nil
        }
        if windows.isEmpty, let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
            spyWork?.cancel()
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
            case "cite":
                let parts = url?.pathComponents.dropFirst() ?? []
                if parts.count == 2, let ref = Int(parts[parts.startIndex + 1]) {
                    showCitation(webView, segment: parts[parts.startIndex], ref: ref)
                }
            case "models":
                showModelMenu(webView)
            case "goto":
                if let index = Int(url?.lastPathComponent ?? ""), let file = self.url(of: webView) {
                    goToSection(index, url: file)
                }
            case "export":
                if let kind = AtaExport.Kind(rawValue: url?.lastPathComponent ?? "") { export(kind, web: webView) }
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
        if let y = scrollToRestore {
            scrollToRestore = nil
            webView.evaluateJavaScript(
                "var p=document.getElementById('pane');if(p){p.scrollTop=\(y)}else{window.scrollTo(0,\(y))}")
        }
    }
}

/// A menu item that runs a closure; the item keeps the closure alive.
@MainActor
private final class MenuAction: NSObject {
    private let run: () -> Void

    private init(_ run: @escaping () -> Void) { self.run = run }

    static func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        return item
    }

    @objc private func fire() { run() }
}
