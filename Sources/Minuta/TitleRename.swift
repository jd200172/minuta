import AppKit
import WebKit

/// Renames the meeting in place, like `ParticipantRename` does for a voice: the page stays inert and a native
/// text field sits exactly over the title. Return saves, Esc cancels, clicking elsewhere saves. Scrolling or
/// resizing cancels, because the field would no longer line up with the text. An empty title is allowed: the
/// meeting goes back to the name with only the time.
@MainActor
final class TitleRename: NSObject, NSTextFieldDelegate {
    static let maxLength = 120

    private let web: WKWebView
    private let current: String
    private let rect: CGRect
    /// Saves the new title; returns an error message to show, or nil when it worked.
    private let save: (String) -> String?
    private let done: () -> Void

    private let cover = NSView()
    private let field = NSTextField()
    private let hint = NSTextField(labelWithString: "")
    private var scrollMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
    private var finished = false

    init(
        web: WKWebView, current: String, rect: CGRect, save: @escaping (String) -> String?,
        done: @escaping () -> Void
    ) {
        self.web = web
        self.current = current
        self.rect = rect
        self.save = save
        self.done = done
        super.init()
    }

    func begin() {
        let height: CGFloat = 32
        let room = web.bounds.width - rect.minX - 28
        let width = min(max(rect.width + 24, 320), max(room, 200))
        let y = web.isFlipped ? rect.midY - height / 2 : web.bounds.height - rect.midY - height / 2
        field.frame = NSRect(x: rect.minX - 6, y: y, width: width, height: height)
        field.stringValue = current == MinutesRenderer.untitled ? "" : current
        field.placeholderString = "Título da reunião"
        field.font = .systemFont(ofSize: 20, weight: .semibold)
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.delegate = self
        field.setAccessibilityLabel("Título da reunião")

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .systemRed
        hint.drawsBackground = false
        hint.frame = NSRect(x: field.frame.minX + 4, y: field.frame.maxY + 2, width: width, height: 14)
        // A text field over web content stays see-through, so an opaque view hides the page text under it.
        cover.wantsLayer = true
        cover.frame = field.frame
        web.effectiveAppearance.performAsCurrentDrawingAppearance {
            cover.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }
        cover.layer?.cornerRadius = 6
        web.addSubview(cover)
        web.addSubview(field)
        web.addSubview(hint)

        web.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.finish()
            return event
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: web.window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    func cancel() {
        finish()
    }

    private var typed: String { field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func problem() -> String? {
        typed.count > Self.maxLength ? "Use no máximo \(Self.maxLength) caracteres." : nil
    }

    private func commit() {
        if let message = problem() {
            hint.stringValue = message
            NSSound.beep()
            return
        }
        if typed == (current == MinutesRenderer.untitled ? "" : current) {
            finish()
            return
        }
        if let message = save(typed) {
            hint.stringValue = message
            return
        }
        finish()
    }

    private func finish() {
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

    func controlTextDidChange(_ notification: Notification) {
        hint.stringValue = problem() ?? ""
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            finish()
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard !finished else { return }
        // Clicking elsewhere: save when valid and changed, otherwise drop the edit.
        if problem() == nil, typed != (current == MinutesRenderer.untitled ? "" : current) { _ = save(typed) }
        finish()
    }
}
