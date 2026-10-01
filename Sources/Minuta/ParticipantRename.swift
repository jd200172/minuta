import AppKit
import WebKit

/// Renames one voice in place (ADR 0016). The page stays inert, with JavaScript off: the viewer asks the
/// page where the name is, and this puts a native text field exactly over it. Return saves, Esc cancels,
/// clicking elsewhere saves when the name is valid. Scrolling or resizing cancels, because the field would
/// no longer line up with the text.
@MainActor
final class ParticipantRename: NSObject, NSTextFieldDelegate {
    private let web: WKWebView
    private let speaker: Speaker
    private let others: [Speaker]
    private let text: String
    private let rect: CGRect
    /// Saves the new name for a label; returns an error message to show, or nil when it worked.
    private let save: (String, String) -> String?
    private let done: () -> Void

    private let cover = NSView()
    private let field = NSTextField()
    private let hint = NSTextField(labelWithString: "")
    private var scrollMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
    private var finished = false

    init(
        web: WKWebView, speakers: [Speaker], index: Int, text: String, rect: CGRect,
        save: @escaping (String, String) -> String?, done: @escaping () -> Void
    ) {
        self.web = web
        self.speaker = speakers[index]
        self.others = speakers.enumerated().filter { $0.offset != index }.map(\.element)
        self.text = text
        self.rect = rect
        self.save = save
        self.done = done
        super.init()
    }

    func begin() {
        let width = max(rect.width, 220)
        let height: CGFloat = 24
        let y = web.isFlipped ? rect.midY - height / 2 : web.bounds.height - rect.midY - height / 2
        field.frame = NSRect(x: rect.minX - 2, y: y, width: width, height: height)
        field.stringValue = speaker.name
        field.placeholderString = "Nome"
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.delegate = self
        field.setAccessibilityLabel("Nome de \(speaker.label)")

        hint.font = .systemFont(ofSize: 11)
        hint.drawsBackground = false
        hint.lineBreakMode = .byTruncatingTail
        hint.frame = NSRect(
            x: field.frame.maxX + 34, y: y + 3, width: max(60, web.bounds.width - field.frame.maxX - 50), height: 16)
        // A text field over web content stays see-through, so an opaque view hides the page text under it.
        cover.wantsLayer = true
        cover.frame = field.frame
        web.effectiveAppearance.performAsCurrentDrawingAppearance {
            cover.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }
        cover.layer?.cornerRadius = 5
        web.addSubview(cover)
        web.addSubview(field)
        web.addSubview(hint)
        updateHint()

        web.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.finish(commit: false)
            return event
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: web.window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(commit: false) }
        }
    }

    func cancel() {
        finish(commit: false)
    }

    // MARK: Validation

    private var typed: String { field.stringValue.trimmingCharacters(in: .whitespaces) }

    private func problem() -> String? {
        if let problem = ParticipantEditor.nameProblem(typed) { return problem }
        let mine = typed.isEmpty ? speaker.label : typed
        if others.contains(where: { ParticipantEditor.same(mine, $0.shown) }) {
            return "Esse nome já está em uso nesta ata."
        }
        return nil
    }

    private func updateHint() {
        if let problem = problem() {
            hint.stringValue = problem
            hint.textColor = .systemRed
        } else if typed != speaker.name, ParticipantEditor.nameAppears(typed, in: text) {
            hint.stringValue = "“\(typed)” já aparece no texto; se você desfizer depois, essas menções também mudam."
            hint.textColor = .secondaryLabelColor
        } else {
            hint.stringValue = ""
        }
    }

    // MARK: Finishing

    private func commit() {
        if let message = problem() {
            hint.stringValue = message
            hint.textColor = .systemRed
            NSSound.beep()
            return
        }
        if typed == speaker.name || (typed.isEmpty && speaker.name.isEmpty) {
            finish(commit: false)
            return
        }
        if let message = save(speaker.label, typed) {
            hint.stringValue = message
            hint.textColor = .systemRed
            return
        }
        finish(commit: true)
    }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        field.delegate = nil
        field.removeFromSuperview()
        cover.removeFromSuperview()
        hint.removeFromSuperview()
        web.window?.makeFirstResponder(web)
        done()
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        updateHint()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finish(commit: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard !finished else { return }
        // Clicking elsewhere: save when valid and changed, otherwise drop the edit.
        if problem() == nil, typed != speaker.name, save(speaker.label, typed) == nil {
            finish(commit: true)
        } else {
            finish(commit: false)
        }
    }
}
