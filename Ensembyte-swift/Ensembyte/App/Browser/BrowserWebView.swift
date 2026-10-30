import AppKit
import SwiftUI
import WebKit

/// Hosts a tab's WKWebView in SwiftUI: the web view fills its slot and follows it on
/// every layout pass.
@MainActor
struct BrowserWebView: NSViewRepresentable {
    let model: BrowserPageModel

    func makeNSView(context: Context) -> BrowserWebContainer {
        BrowserWebContainer(webView: model.page.webView)
    }

    /// The web view belongs to the model, so it outlives the view; nothing to move
    /// between updates.
    func updateNSView(_ nsView: BrowserWebContainer, context: Context) {}
}

/// The slot a tab's web view lives in. The web view is framed to the container's
/// bounds on every layout pass, so it follows the panel's size without constraints
/// that could fight the layout.
@MainActor
final class BrowserWebContainer: NSView {
    private let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        wantsLayer = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }
}
