import Foundation
import WebKit

/// One browser tab's page: the WKWebView and the navigation policy around it.
///
/// The web view is made and used on the main actor, as WebKit requires.
@MainActor
final class BrowserPage: NSObject, WKNavigationDelegate {
    /// The web view the panel hosts.
    let webView: WKWebView

    /// Called with the page's new state after every change WebKit reports.
    var stateHandler: ((BrowserPageState) -> Void)?

    /// The URL the last load asked for, kept while the page answers: the address bar
    /// shows what was asked for, not the page's intermediate redirects.
    private var requestedURL: String?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    /// The page's state as it stands.
    var state: BrowserPageState {
        BrowserPageState(
            url: requestedURL ?? webView.url?.absoluteString,
            title: webView.title ?? "",
            loading: webView.isLoading,
            canBack: webView.canGoBack,
            canForward: webView.canGoForward,
            error: currentError
        )
    }

    /// The message the page last failed with, if any.
    private var currentError: String?

    func load(_ url: URL) {
        currentError = nil
        requestedURL = url.absoluteString
        webView.load(URLRequest(url: url))
        publish()
    }

    func reload() {
        currentError = nil
        // Retrying the requested URL works after a failed provisional load too, where
        // the page never committed and holds no history to reload.
        if let requestedURL, let url = URL(string: requestedURL) {
            webView.load(URLRequest(url: url))
        } else {
            webView.reload()
        }
        publish()
    }

    func goBack() {
        webView.goBack()
        publish()
    }

    func goForward() {
        webView.goForward()
        publish()
    }

    /// Stops the page and lets it go.
    func stop() {
        webView.stopLoading()
    }

    private func publish() {
        stateHandler?(state)
    }

    private func fail(_ message: String) {
        currentError = message
        publish()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // A frame's own documents are web content too; a top-frame navigation is
        // only ever http/https.
        let allowed = navigationAction.targetFrame?.isMainFrame == true
            ? BrowserURLPolicy.allowedNavigation(url)
            : BrowserURLPolicy.allowedFrameNavigation(url)
        guard allowed else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            requestedURL = url.absoluteString
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.canShowMIMEType else {
            // A file WebKit cannot show is a download; the panel cannot host one.
            fail("This file can't be previewed here. Open it in your default browser.")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        currentError = nil
        publish()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        publish()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        publish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // A cancelled load (-999) is our own policy or a superseded navigation: it is
        // not a failure the user needs told about.
        let nsError = error as NSError
        guard nsError.code != -999 else { return }
        fail("Check the address and make sure your server is running, then try again.")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard nsError.code != -999 else { return }
        fail("The connection was interrupted. Try loading this page again.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("The page stopped responding. Reload to continue.")
    }

    /// A page that opens a window: the target is loaded in this same tab, and no new
    /// web view is handed back, so the panel keeps one page per tab.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, BrowserURLPolicy.allowedNavigation(url) {
            load(url)
        }
        return nil
    }
}
