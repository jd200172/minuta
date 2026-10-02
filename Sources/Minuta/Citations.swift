import AppKit
import SwiftUI
import WebKit

/// One line of the transcript as written in the minutes file: `<a id="t-000010"></a>**[00:00:10] Nome:** texto`.
struct TranscriptSegment: Equatable {
    var id: String
    var clock: String
    var speaker: String
    var text: String

    static func parse(_ markdown: String) -> [TranscriptSegment] {
        let pattern = #"^<a id="(t-\d+)"></a>\*\*\[(\d{2}:\d{2}:\d{2})\] (.+?):\*\* ?(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var result: [TranscriptSegment] = []
        for line in markdown.components(separatedBy: "\n") {
            guard let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
            func group(_ i: Int) -> String { String(line[Range(m.range(at: i), in: line)!]) }
            result.append(TranscriptSegment(id: group(1), clock: group(2), speaker: group(3), text: group(4)))
        }
        return result
    }

    /// The cited segment and the one before and after it, in transcript order. Empty when `id` is not there.
    static func window(around id: String, in segments: [TranscriptSegment]) -> [(
        segment: TranscriptSegment, cited: Bool
    )] {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return [] }
        let range = max(0, index - 1)...min(segments.count - 1, index + 1)
        return range.map { (segments[$0], $0 == index) }
    }
}

/// Whether the transcript of each meeting is collapsed on the reading page, remembered per meeting (by `inicio`).
/// A meeting never seen opens collapsed, so the minutes come first.
enum TranscriptState {
    private static let key = "transcriptCollapsed"

    private static func id(_ markdown: String) -> String? {
        AtaStore.frontMatter(markdown)["inicio"]
    }

    static func isCollapsed(_ markdown: String, defaults: UserDefaults = .standard) -> Bool {
        guard let id = id(markdown), let saved = defaults.dictionary(forKey: key) as? [String: Bool] else {
            return true
        }
        return saved[id] ?? true
    }

    static func set(collapsed: Bool, for markdown: String, defaults: UserDefaults = .standard) {
        guard let id = id(markdown) else { return }
        var saved = (defaults.dictionary(forKey: key) as? [String: Bool]) ?? [:]
        saved[id] = collapsed
        defaults.set(saved, forKey: key)
    }
}

// MARK: - Balloon

private struct CitationRows: View {
    let rows: [(segment: TranscriptSegment, cited: Bool)]
    let goTo: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { i in
                let row = rows[i]
                let scale = row.cited ? 1 : BalloonStyle.contextScale
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button(action: { goTo(row.segment.id) }) {
                        Text(row.segment.clock)
                            .font(.system(size: BalloonStyle.chipFontSize * scale).monospacedDigit())
                            .foregroundStyle(Color(nsColor: .linkColor))
                            .padding(.horizontal, 6)
                            .background(
                                Color(nsColor: .linkColor).opacity(BalloonStyle.chipTint),
                                in: RoundedRectangle(cornerRadius: BalloonStyle.chipRadius))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ir ao ponto \(row.segment.clock) na transcrição")
                    (Text(row.segment.speaker + ":").fontWeight(.semibold) + Text(" " + row.segment.text))
                        .font(.system(size: BalloonStyle.fontSize * scale))
                        .foregroundStyle(row.cited ? .primary : .secondary)
                        .lineLimit(row.cited ? nil : BalloonStyle.contextLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, BalloonStyle.rowPaddingV)
                .padding(.horizontal, BalloonStyle.rowPaddingH)
                .background(
                    row.cited ? Color(nsColor: .linkColor).opacity(BalloonStyle.rowTint) : .clear,
                    in: RoundedRectangle(cornerRadius: BalloonStyle.rowRadius))
            }
        }
    }
}

/// The balloon a citation chip opens: the cited segment, in full, with the one before and the one after it dimmed,
/// smaller and cut after two lines. It is a `BalloonPanel` (the corner radius of the page's chips, an arrow on the
/// chip) and never scrolls: it grows taller first, and only when the room above or below the chip runs out does it
/// grow wider, up to the page card. The time of each line goes to that point of the transcript. It closes on Esc, on
/// a click outside, on scrolling the page, and on a second click on the chip that opened it.
@MainActor
final class CitationBalloon {
    /// The widths tried in turn; the last is the page card.
    static let widths: [CGFloat] = [340, 420]
    /// The least space between the balloon and the edge of the page card.
    static let cardMargin: CGFloat = 12

    private let panel = BalloonPanel(interactive: true)
    private var controller: NSViewController?
    /// The chip whose balloon is open, and the chip and moment of the last close. A click on the chip that has its
    /// balloon open closes the balloon and then arrives as a link; without this memory the link would open it again.
    private var shownRef: Int?
    private var closed: (ref: Int, at: Date)?
    /// Called when the balloon opens (true) and closes (false).
    var onVisibilityChange: ((Bool) -> Void)?

    init() {
        panel.onClose = { [weak self] in
            guard let self else { return }
            if let shownRef { self.closed = (shownRef, Date()) }
            self.shownRef = nil
            self.controller = nil
            self.onVisibilityChange?(false)
        }
    }

    var isShown: Bool { panel.isShown }

    /// The chip whose balloon is open now, if any.
    var openRef: Int? { panel.isShown ? shownRef : nil }

    func close() { panel.close() }

    /// True when the balloon of `ref` was closed an instant ago, which makes the click that arrives now a "close".
    func justClosed(_ ref: Int) -> Bool {
        guard let closed, closed.ref == ref else { return false }
        return Date().timeIntervalSince(closed.at) < 0.4
    }

    func show(
        rows: [(segment: TranscriptSegment, cited: Bool)], ref: Int, near chip: NSRect, within card: NSRect,
        in web: WKWebView, goTo: @escaping (String) -> Void
    ) {
        guard !rows.isEmpty else { return }
        close()
        let action: (String) -> Void = { [weak self] id in
            self?.close()
            goTo(id)
        }
        let padding = BalloonStyle.insets
        func content(width: CGFloat) -> NSHostingController<some View> {
            NSHostingController(
                rootView: CitationRows(rows: rows, goTo: action)
                    .padding(
                        EdgeInsets(
                            top: BalloonStyle.balloonPaddingV - BalloonStyle.rowPaddingV,
                            leading: padding.left - BalloonStyle.rowPaddingH,
                            bottom: BalloonStyle.balloonPaddingV - BalloonStyle.rowPaddingV,
                            trailing: padding.right - BalloonStyle.rowPaddingH)
                    )
                    .frame(width: width))
        }
        // Taller before wider: the first width whose height fits the room above or below the chip.
        let cardWidth = max(220, card.width - 2 * Self.cardMargin)
        var widths = Self.widths.map { min($0, cardWidth) }
        if widths.last != cardWidth { widths.append(cardWidth) }
        let room = panel.room(around: chip, in: web).map { max($0.below, $0.above) } ?? .greatestFiniteMagnitude
        var chosen = (width: widths[0], height: CGFloat(0), host: content(width: widths[0]))
        for width in widths {
            let host = content(width: width)
            let fit = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
            chosen = (width, ceil(fit.height), host)
            if fit.height <= room { break }
        }
        controller = chosen.host
        shownRef = ref
        panel.show(
            content: chosen.host.view, size: NSSize(width: chosen.width, height: chosen.height), anchor: chip,
            limit: card.insetBy(dx: Self.cardMargin, dy: 0), in: web)
        onVisibilityChange?(true)
    }
}
