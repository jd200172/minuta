import AppKit
import UniformTypeIdentifiers
import WebKit

/// Saves a minutes file as a standalone page or as a PDF (ADR 0027). Both are the reading page without its
/// controls: the CSS is embedded, every section is open, the transcript is always included, and the citation
/// chips are plain anchors to the transcript line instead of balloons.
enum AtaExport {
    enum Kind: String {
        case html, pdf

        var type: UTType { self == .html ? .html : .pdf }
    }

    static func html(_ markdown: String) -> String {
        MarkdownHTML.convert(markdown).html
    }

    /// Asks where to save, in a sheet on `window`, and writes the file.
    @MainActor
    static func save(_ markdown: String, from url: URL, as kind: Kind, in window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind.type]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "." + kind.rawValue
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let target = panel.url else { return }
            switch kind {
            case .html:
                do {
                    try html(markdown).write(to: target, atomically: true, encoding: .utf8)
                } catch {
                    failed(error)
                }
            case .pdf:
                PDFExport.start(html: html(markdown), to: target) { error in
                    if let error { failed(error) }
                }
            }
        }
    }

    @MainActor
    private static func failed(_ error: Error) {
        Alerts.show(title: "Não foi possível salvar a ata", message: AppError.from(error).message, buttons: ["OK"])
    }
}

/// Prints a page to a PDF file in pages of the system paper size. The page is loaded in a web view of its own,
/// in light appearance, inside a window that is never shown; WebKit only prints a view that is in a window.
@MainActor
final class PDFExport: NSObject, WKNavigationDelegate {
    private static var running: Set<PDFExport> = []
    private let web: WKWebView
    private let window: NSWindow
    private let target: URL
    private let done: (Error?) -> Void

    static func start(html: String, to target: URL, done: @escaping (Error?) -> Void) {
        let export = PDFExport(target: target, done: done)
        running.insert(export)
        export.web.loadHTMLString(html, baseURL: nil)
    }

    private init(target: URL, done: @escaping (Error?) -> Void) {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let frame = NSRect(x: 0, y: 0, width: 760, height: 1000)
        web = WKWebView(frame: frame, configuration: config)
        web.appearance = NSAppearance(named: .aqua)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        self.target = target
        self.done = done
        super.init()
        web.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = target
        info.topMargin = 40
        info.bottomMargin = 40
        info.leftMargin = 40
        info.rightMargin = 40
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.view?.frame = webView.bounds
        operation.runModal(
            for: window, delegate: self, didRun: #selector(printed(_:success:context:)), contextInfo: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    @objc private func printed(_ operation: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?) {
        finish(success ? nil : CocoaError(.fileWriteUnknown))
    }

    private func finish(_ error: Error?) {
        web.navigationDelegate = nil
        window.close()
        done(error)
        Self.running.remove(self)
    }
}
