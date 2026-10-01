import AppKit
import Combine

/// The menu bar button (ADR 0014). The icon is always the microphone; the state shows in a coloured
/// background pill: green while recording (running clock), red while paused (frozen clock and a pause
/// symbol), yellow while processing (spinner). Recording and processing together show the recording colour
/// with the spinner. Idle is the plain template icon.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private struct Display: Equatable {
        enum Mode { case idle, recording, paused, processing }
        var mode: Mode
        var clock: String
        var spinner: Bool
    }

    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var subscription: AnyCancellable?
    private var current: Display?

    private let pill = PassThroughView()
    private let micView = NSImageView()
    private let clockLabel = NSTextField(labelWithString: "")
    private let pauseView = NSImageView()
    private let spinner = NSProgressIndicator()

    private let pillHeight: CGFloat = 20
    private let padding: CGFloat = 7
    private let gap: CGFloat = 5
    private let dark = NSColor(calibratedWhite: 0.1, alpha: 1)
    private let clockFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    init(model: AppModel) {
        self.model = model
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        pill.wantsLayer = true
        pill.layer?.cornerRadius = 5
        pill.autoresizingMask = [.minYMargin, .maxYMargin]
        pill.isHidden = true
        micView.image = symbol("mic", size: 13)
        pauseView.image = symbol("pause.fill", size: 10)
        clockLabel.font = clockFont
        clockLabel.isBordered = false
        clockLabel.drawsBackground = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        for view in [micView, clockLabel, pauseView, spinner] as [NSView] { pill.addSubview(view) }
        statusItem.button?.addSubview(pill)

        subscription = Publishers.CombineLatest4(
            model.$recordingStart, model.$isPaused, model.$elapsedText, model.$processing
        )
        .sink { [weak self] start, paused, clock, processing in
            guard let self else { return }
            let display: Display
            if start != nil {
                display = Display(
                    mode: paused ? .paused : .recording, clock: clock ?? "00:00", spinner: processing > 0)
            } else {
                display = Display(mode: processing > 0 ? .processing : .idle, clock: "", spinner: processing > 0)
            }
            self.apply(display)
        }
    }

    // MARK: Button

    private func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }

    private func apply(_ display: Display) {
        guard display != current, let button = statusItem.button else { return }
        let previous = current
        current = display
        button.setAccessibilityLabel(accessibilityLabel(display))

        guard display.mode != .idle else {
            pill.isHidden = true
            spinner.stopAnimation(nil)
            let image = symbol("mic", size: 15)
            image?.isTemplate = true
            button.image = image
            statusItem.length = NSStatusItem.variableLength
            return
        }

        let (background, foreground) = colors(display.mode)
        button.image = nil
        button.appearance = nil
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            pill.layer?.backgroundColor = background.cgColor
        }
        micView.contentTintColor = foreground
        pauseView.contentTintColor = foreground
        clockLabel.textColor = foreground
        spinner.appearance = NSAppearance(named: display.mode == .paused ? .darkAqua : .aqua)

        var x = padding
        func place(_ view: NSView, width: CGFloat, height: CGFloat) {
            view.frame = NSRect(x: x, y: (pillHeight - height) / 2, width: width, height: height)
            x += width + gap
        }
        place(micView, width: 15, height: 15)
        clockLabel.isHidden = display.mode == .processing
        if !clockLabel.isHidden {
            clockLabel.stringValue = display.clock
            let widest = max(textWidth("00:00"), textWidth(display.clock))
            place(clockLabel, width: widest, height: 16)
        }
        pauseView.isHidden = display.mode != .paused
        if !pauseView.isHidden { place(pauseView, width: 10, height: 12) }
        if display.spinner {
            place(spinner, width: 14, height: 14)
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        let width = x - gap + padding
        // Only the clock text changes once a second; the button size changes at state transitions.
        if previous?.mode != display.mode || previous?.spinner != display.spinner {
            statusItem.length = width + 4
        }
        let height = max(button.bounds.height, NSStatusBar.system.thickness)
        pill.frame = NSRect(x: 2, y: (height - pillHeight) / 2, width: width, height: pillHeight)
        pill.isHidden = false
    }

    private func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: clockFont]).width)
    }

    /// White text fails contrast on green and yellow, so those use a dark foreground; red keeps white.
    private func colors(_ mode: Display.Mode) -> (NSColor, NSColor) {
        switch mode {
        case .recording: (.systemGreen, dark)
        case .paused: (.systemRed, .white)
        case .processing: (.systemYellow, dark)
        case .idle: (.clear, .labelColor)
        }
    }

    private func accessibilityLabel(_ display: Display) -> String {
        let suffix = display.spinner ? ", gerando a ata" : ""
        switch display.mode {
        case .idle: return "minuta"
        case .recording: return "minuta, gravando, \(display.clock)\(suffix)"
        case .paused: return "minuta, gravação pausada, \(display.clock)\(suffix)"
        case .processing: return "minuta, gerando a ata"
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        AtaLibrary.shared.refresh()
        menu.removeAllItems()
        if model.recordingStart != nil {
            if model.isPaused {
                add(menu, "Continuar gravação", #selector(resume))
            } else {
                add(menu, "Pausar gravação", #selector(pause))
            }
            add(menu, "Encerrar gravação", #selector(end))
        } else {
            add(menu, "Iniciar gravação", #selector(start))
        }
        menu.addItem(.separator())
        let recent = Array(AtaLibrary.shared.atas.filter { $0.problem == nil }.prefix(5))
        if !recent.isEmpty {
            let header = NSMenuItem(title: "Atas recentes", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for ata in recent {
                let item = NSMenuItem(title: ata.title, action: #selector(openRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ata.url
                item.attributedTitle = recentTitle(ata)
                menu.addItem(item)
            }
        }
        add(menu, "Atas…", #selector(openAtas))
        menu.addItem(.separator())
        add(menu, "Configurações…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add(menu, "Sair do minuta", #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func start() { model.startRecording() }
    @objc private func pause() { model.pauseRecording() }
    @objc private func resume() { model.resumeRecording() }
    @objc private func end() { model.endRecording() }
    @objc private func openAtas() { AtasWindowController.shared.show() }
    @objc private func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { AtaViewerController.shared.open(url) }
    }

    /// "Título" on the left and "01/10 11:37" on the right, with a right-aligned tab stop.
    private func recentTitle(_ ata: Ata) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 300)]
        style.lineBreakMode = .byTruncatingTail
        let title = ata.title.count > 30 ? String(ata.title.prefix(29)) + "…" : ata.title
        let date = DateFormatter()
        date.locale = Locale(identifier: "pt_BR")
        date.dateFormat = "dd/MM HH:mm"
        let text = NSMutableAttributedString(
            string: title, attributes: [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: style])
        text.append(
            NSAttributedString(
                string: "\t" + date.string(from: ata.start),
                attributes: [
                    .font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style,
                ]))
        return text
    }
    @objc private func openSettings() { SettingsOpener.open() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// A container that lets clicks fall through to the status bar button underneath.
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
