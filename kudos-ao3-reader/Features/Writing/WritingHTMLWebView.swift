import SwiftUI
import WebKit

@MainActor @Observable
final class WritingHTMLController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    var onChange: ((String) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var isReady = false
    private var text: String
    private var sourceMode = false
    private var appearance = ReaderTheme.light
    private var fontSize: Double = 17

    init(text: String) {
        self.text = text
        sourceMode = !WritingHTMLDocument.supportsRichEditing(text)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(
            source: WritingHTMLDocument.script, injectionTime: .atDocumentEnd,
            forMainFrameOnly: true, in: .defaultClient
        ))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(self, contentWorld: .defaultClient, name: "writing")
        webView.navigationDelegate = self
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #endif
        webView.loadHTMLString(WritingHTMLDocument.html, baseURL: nil)
    }

    func set(text: String, sourceMode: Bool) {
        guard self.text != text || self.sourceMode != sourceMode else { return }
        self.text = text
        self.sourceMode = sourceMode || !WritingHTMLDocument.supportsRichEditing(text)
        apply()
    }

    func setAppearance(_ theme: ReaderTheme, fontSize: Double = 17) {
        appearance = theme
        self.fontSize = fontSize
        applyAppearance()
    }

    private func applyAppearance() {
        guard isReady else { return }
        evaluate("""
        document.documentElement.style.color = foreground;
        document.documentElement.style.backgroundColor = background;
        document.documentElement.style.setProperty('--link', link);
        document.documentElement.style.fontSize = size + 'px';
        """, arguments: ["foreground": appearance.textHex, "background": appearance.backgroundHex,
                         "link": appearance.linkHex, "size": fontSize])
    }

    func command(_ tag: String, link: String = "") {
        guard isReady else { return }
        evaluate("window.writing.command(tag, href)", arguments: ["tag": tag, "href": link])
    }

    func flush() async throws {
        guard isReady else { return }
        let value = try await webView.callAsyncJavaScript(
            "return window.writing.snapshot()", contentWorld: .defaultClient
        )
        if let value = value as? String, value != text {
            text = value
            onChange?(value)
        }
    }

    func stop() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "writing", contentWorld: .defaultClient)
        webView.stopLoading()
        onChange = nil
        onError = nil
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let value = message.body as? String else { return }
        text = value
        onChange?(value)
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        isReady = true
        apply()
        applyAppearance()
    }

    func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.navigationType == .other && action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }

    private func apply() {
        guard isReady else { return }
        evaluate("window.writing.set(value, useSource)", arguments: ["value": text, "useSource": sourceMode])
    }

    private func evaluate(_ script: String, arguments: [String: Any]) {
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .defaultClient) { [weak self] result in
            if case let .failure(error) = result { self?.onError?(error.localizedDescription) }
        }
    }
}
