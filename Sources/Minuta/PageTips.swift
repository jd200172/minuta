import AppKit
import WebKit

/// The tooltips of a reading page as system popovers: a speech balloon with an arrow, in the system material
/// (Liquid Glass where the system draws it). A page element asks for one with `data-tip`; an HTML `title` would
/// show the plain system tooltip, which cannot be styled. The page runs no JavaScript of its own, so the mouse is
/// followed here: each move asks the page which `data-tip` element is under the pointer (the same
/// `evaluateJavaScript` the in-place renames use to measure) and the balloon opens after a short delay.
@MainActor
final class PageTips: NSObject {
    private weak var web: WKWebView?
    private let balloon = TipBalloon()
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// The element under the pointer (text and box), shown or about to be shown.
    private var current: String?
    private var timer: Timer?
    private var asking = false
    private var latest: CGPoint?
    /// While a citation balloon is open, tooltips stay closed so two balloons never overlap.
    var suppressed = false {
        didSet { if suppressed { hide() } }
    }

    init(web: WKWebView) {
        self.web = web
        super.init()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown,
        ]) { [weak self] event in
            self?.handle(event)
            return event
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    MainActor.assumeIsolated {
                        if let self, note.object as? NSWindow === self.web?.window { self.hide() }
                    }
                })
        }
    }

    /// Stops following the mouse. Call when the window closes.
    func stop() {
        hide()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        current = nil
        latest = nil
        balloon.hide()
    }

    // MARK: Pointer

    private func handle(_ event: NSEvent) {
        guard !suppressed, let web, let window = web.window, event.window === window else { return }
        guard event.type == .mouseMoved else { return hide() }
        let point = web.convert(event.locationInWindow, from: nil)
        guard web.bounds.contains(point) else { return hide() }
        latest = point
        ask()
    }

    /// One question at a time; if the pointer moved meanwhile, the last position is asked next.
    private func ask() {
        guard !asking, let web, let point = latest else { return }
        asking = true
        latest = nil
        let script =
            "(function(x,y){var e=document.elementFromPoint(x,y);e=e&&e.closest('[data-tip]');if(!e)return null;"
            + "var r=e.getBoundingClientRect();return [e.getAttribute('data-tip'),r.left,r.top,r.width,r.height];})"
            + "(\(point.x),\(point.y))"
        web.evaluateJavaScript(script) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.asking = false
                self.answer(result)
                if self.latest != nil { self.ask() }
            }
        }
    }

    private func answer(_ result: Any?) {
        guard let items = result as? [Any], items.count == 5, let text = items[0] as? String else {
            if current != nil { hide() }
            return
        }
        let box = items[1...].compactMap { ($0 as? NSNumber)?.doubleValue }
        guard box.count == 4 else { return }
        let key = text + box.map { String(Int($0)) }.joined(separator: ",")
        if key == current { return }
        let resume = latest
        hide()
        latest = resume
        current = key
        let rect = NSRect(x: box[0], y: box[1], width: box[2], height: box[3])
        timer = Timer.scheduledTimer(withTimeInterval: BalloonStyle.delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.show(text, near: rect) }
        }
    }

    // MARK: Balloon

    private func show(_ text: String, near rect: NSRect) {
        guard let web else { return }
        // The page is flipped like its CSS: the element's box is in the same coordinates, and `maxY` is below it.
        balloon.show(text, near: rect, of: web)
    }
}
