import AppKit
import SwiftUI

/// What every balloon of the app shares, so they read as one language: the `BalloonPanel` (system material, the
/// corner radius and horizontal padding the page's model chips had before ADR 0027, an arrow that points at its
/// element), 12 pt text, semibold leads, and the link-colour tint the reading page uses for its chips and its
/// selected line. The tooltip
/// balloons (`TipBalloon`, `PageTips`, `.balloonTip`) and the citation balloon (`CitationBalloon`) read from here.
enum BalloonStyle {
    static let fontSize: CGFloat = 12
    /// The padding and corner radius of the former model chips of the page (8 px by 14 px, 16 px), kept as the shape of
    /// every balloon.
    static let insets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    static let radius: CGFloat = 16
    static let arrowHeight: CGFloat = 8
    static let arrowHalfWidth: CGFloat = 9
    static let maxTextWidth: CGFloat = 260
    /// Pause over an element before its tooltip opens.
    static let delay: TimeInterval = 0.4
    /// The chip of the page (`a.chip`): 11 pt digits on a 14 % link tint, 5 pt corners.
    static let chipFontSize: CGFloat = 11
    static let chipTint = 0.14
    static let chipRadius: CGFloat = 5
    /// The selected line of the page (`p.tl:target`): 16 % link tint, 6 pt corners.
    static let rowTint = 0.16
    static let rowRadius: CGFloat = 6
    /// The padding inside a highlighted row of the citation balloon. The balloon's own margin is the insets above
    /// minus this, so the text of a row starts at the same distance from the edge as the text of a tooltip.
    static let rowPaddingH: CGFloat = 6
    static let rowPaddingV: CGFloat = 4
    /// Space above the first row and below the last of the citation balloon, which holds more than a tooltip does.
    static let balloonPaddingV: CGFloat = 12
}

// MARK: - Panel

/// The outline of a balloon: a rounded body with an arrow on one side, drawn as one path so there is no seam where
/// the arrow meets the body. Coordinates are those of the panel (y up).
enum BalloonOutline {
    /// `arrowOnTop`: the arrow rises above the body (the balloon sits below its element); otherwise it hangs under
    /// the body. `arrowX` is the tip's distance from the left edge.
    static func path(body: NSSize, arrowX: CGFloat, arrowOnTop: Bool) -> CGPath {
        let w = body.width
        let h = body.height
        let a = BalloonStyle.arrowHeight
        let hw = BalloonStyle.arrowHalfWidth
        let r = min(BalloonStyle.radius, h / 2, w / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: r), radius: r)
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - r, y: h), radius: r)
        path.addLine(to: CGPoint(x: arrowX + hw, y: h))
        path.addLine(to: CGPoint(x: arrowX, y: h + a))
        path.addLine(to: CGPoint(x: arrowX - hw, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - r), radius: r)
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
        path.closeSubpath()
        if arrowOnTop { return path }
        // Arrow under the body: the same shape upside down.
        var flip = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -(h + a))
        return path.copy(using: &flip) ?? path
    }
}

/// The balloon of the whole app: a borderless panel in the system material, shaped by `BalloonOutline`, that sits
/// next to an element of a window and points at it. It replaces `NSPopover`, whose corner radius cannot be set. It
/// opens below the element, or above it when there is no room, never leaves the horizontal limit it is given, and
/// follows its window. An interactive balloon takes the mouse and closes on Esc, on a click outside, on scrolling
/// its window and when that window stops being key; a tip (not interactive) lets every event through.
@MainActor
final class BalloonPanel: NSObject {
    private final class Host: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    private var panel: NSPanel?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private let interactive: Bool
    /// Called once each time the balloon closes, whatever the cause.
    var onClose: (() -> Void)?

    init(interactive: Bool) {
        self.interactive = interactive
    }

    var isShown: Bool { panel?.isVisible == true }

    /// Where a balloon may sit: the content of the window, cut to the screen.
    private static func area(of window: NSWindow, on screen: NSScreen) -> NSRect {
        window.contentRect(forFrameRect: window.frame).intersection(screen.visibleFrame)
    }

    /// The room above and below `anchor` (in `view`'s coordinates) inside its window, for sizing before showing.
    func room(around anchor: NSRect, in view: NSView) -> (below: CGFloat, above: CGFloat)? {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return nil }
        let box = Self.screenRect(anchor, in: view, window: window)
        let area = Self.area(of: window, on: screen)
        let gap = BalloonStyle.arrowHeight + 2
        return (box.minY - gap - area.minY, area.maxY - box.maxY - gap)
    }

    private static func screenRect(_ rect: NSRect, in view: NSView, window: NSWindow) -> NSRect {
        window.convertToScreen(view.convert(rect, to: nil))
    }

    /// Shows `content` (already laid out at `size`) next to `anchor`, a rectangle in `view`'s coordinates.
    /// `limit` is the horizontal range, in the same coordinates, the balloon must stay inside.
    func show(content: NSView, size: NSSize, anchor: NSRect, limit: NSRect? = nil, in view: NSView) {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
        close()
        let a = BalloonStyle.arrowHeight
        let box = Self.screenRect(anchor, in: view, window: window)
        let visible = screen.visibleFrame
        let range: ClosedRange<CGFloat> = {
            guard let limit else { return visible.minX...visible.maxX }
            let r = Self.screenRect(limit, in: view, window: window)
            return max(r.minX, visible.minX)...min(r.maxX, visible.maxX)
        }()
        let width = min(size.width, range.upperBound - range.lowerBound)
        let x = min(max(box.midX - width / 2, range.lowerBound), range.upperBound - width)

        // Below the element when it fits inside the window, else above when that fits, else the roomier side.
        let gap: CGFloat = 2
        let area = Self.area(of: window, on: screen)
        let below = box.minY - gap - a - area.minY
        let above = area.maxY - box.maxY - gap - a
        let onBelow = size.height <= below || (size.height > above && below >= above)
        let arrowX = min(
            max(box.midX - x, BalloonStyle.radius + BalloonStyle.arrowHalfWidth),
            width - BalloonStyle.radius - BalloonStyle.arrowHalfWidth)
        let total = NSSize(width: width, height: size.height + a)
        var originY = onBelow ? box.minY - gap - total.height : box.maxY + gap
        originY = min(max(originY, visible.minY), visible.maxY - total.height)
        let frame = NSRect(origin: NSPoint(x: x, y: originY), size: total)

        let outline = BalloonOutline.path(
            body: NSSize(width: width, height: size.height), arrowX: arrowX, arrowOnTop: onBelow)
        let root = Host(frame: NSRect(origin: .zero, size: total))
        let material = NSVisualEffectView(frame: root.bounds)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = NSImage(size: total, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(outline)
            context.fillPath()
            return true
        }
        root.addSubview(material)
        let border = CAShapeLayer()
        border.path = outline
        border.fillColor = nil
        border.strokeColor = NSColor.separatorColor.cgColor
        border.lineWidth = 1
        let borderView = NSView(frame: root.bounds)
        borderView.wantsLayer = true
        borderView.layer?.addSublayer(border)
        root.addSubview(borderView)
        content.frame = NSRect(x: 0, y: onBelow ? 0 : a, width: width, height: size.height)
        root.addSubview(content)

        let panel = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = window.level
        panel.ignoresMouseEvents = !interactive
        panel.contentView = root
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        panel.invalidateShadow()
        self.panel = panel
        watch(window)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        onClose?()
    }

    private func watch(_ window: NSWindow) {
        var events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
        if !interactive { events = [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown] }
        monitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown {
                if self.interactive && event.keyCode != 53 { return event }
                self.close()
                return self.interactive ? nil : event
            }
            if event.window === panel { return event }
            self.close()
            return event
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.close() }
                })
        }
    }
}

// MARK: - Tooltip

/// A tooltip: a `BalloonPanel` with a short text. It takes neither the mouse nor the keyboard, and closes on any
/// click, scroll or key, like the system tooltip it replaces.
@MainActor
final class TipBalloon {
    private let panel = BalloonPanel(interactive: false)

    var isShown: Bool { panel.isShown }

    func hide() { panel.close() }

    /// The text with a little space between lines, and the lead of a model tooltip ("Serve para", "Mostra",
    /// "Use quando") in semibold.
    static func styled(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 4
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: BalloonStyle.fontSize), .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ])
        let leads = try? NSRegularExpression(
            pattern: #"^(Serve para|Mostra|Use quando)\b"#, options: .anchorsMatchLines)
        for match in leads?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? [] {
            result.addAttribute(
                .font, value: NSFont.systemFont(ofSize: BalloonStyle.fontSize, weight: .semibold), range: match.range)
        }
        return result
    }

    /// Opens the balloon next to `rect`, which is in the coordinates of `view`.
    func show(_ text: String, near rect: NSRect, of view: NSView) {
        guard let window = view.window, window.isKeyWindow else { return }
        let max = BalloonStyle.maxTextWidth
        let label = NSTextField(wrappingLabelWithString: "")
        label.isSelectable = false
        label.maximumNumberOfLines = 0
        label.attributedStringValue = Self.styled(text)
        label.preferredMaxLayoutWidth = max
        let fit =
            label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max, height: .greatestFiniteMagnitude))
            ?? NSSize(width: max, height: 20)
        let inset = BalloonStyle.insets
        let text = NSSize(width: ceil(fit.width), height: ceil(fit.height))
        let size = NSSize(width: text.width + inset.left + inset.right, height: text.height + inset.top + inset.bottom)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        label.frame = NSRect(x: inset.left, y: inset.bottom, width: text.width, height: text.height)
        content.addSubview(label)
        panel.show(content: content, size: size, anchor: rect.insetBy(dx: -2, dy: -2), in: view)
    }
}

/// Puts the tooltip balloon on a native control: it covers the control, lets every click through, and opens the
/// balloon after a pause over it. Replaces `toolTip` and `.help`, whose plain system tooltip looks like no other
/// balloon of the app.
@MainActor
final class TipHost: NSView {
    var text: String
    private let balloon = TipBalloon()
    private var timer: Timer?

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The box is measured downward, like the pages of the app.
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: BalloonStyle.delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.text.isEmpty else { return }
                self.balloon.show(self.text, near: self.bounds, of: self)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        hide()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hide() }
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        balloon.hide()
    }

    /// Adds the balloon over `control` and keeps it the size of the control.
    static func attach(_ text: String, to control: NSView) {
        let host = TipHost(text: text)
        host.frame = control.bounds
        host.autoresizingMask = [.width, .height]
        control.addSubview(host)
    }
}

private struct TipOverlay: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TipHost { TipHost(text: text) }
    func updateNSView(_ view: TipHost, context: Context) { view.text = text }
}

extension View {
    /// The app's tooltip balloon on a SwiftUI view, in place of `.help`.
    func balloonTip(_ text: String) -> some View {
        overlay(TipOverlay(text: text))
    }
}
