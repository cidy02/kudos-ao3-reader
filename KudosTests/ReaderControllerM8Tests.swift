import Testing
import Foundation
import WebKit
@testable import Kudos

#if os(macOS)
@MainActor
@Suite("ReaderController M8 Tests")
struct ReaderControllerM8Tests {
    class DelegateProxy: NSObject, WKNavigationDelegate {
        let target: WKNavigationDelegate
        var decidedPolicy: WKNavigationActionPolicy?
        
        init(target: WKNavigationDelegate) {
            self.target = target
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            target.webView?(webView, decidePolicyFor: navigationAction) { policy in
                self.decidedPolicy = policy
                decisionHandler(.cancel) // Always cancel in test to avoid side effects
            }
        }
    }

    @Test("Unrecognized file navigation is rejected (M8)")
    @MainActor func unrecognizedFileNavigationRejected() async throws {
        let controller = ReaderController()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir.appendingPathComponent("chapter1"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempDir.appendingPathComponent("chapter2"), withIntermediateDirectories: true)
        
        let loadedURL = tempDir.appendingPathComponent("chapter1/index.xhtml")
        let secretURL = tempDir.appendingPathComponent("chapter2/secret.txt")
        try? "chapter1".write(to: loadedURL, atomically: true, encoding: .utf8)
        try? "secret".write(to: secretURL, atomically: true, encoding: .utf8)
        
        controller.load(loadedURL, readAccess: tempDir, landOnLast: false)
        let webView = controller.webView
        
        let proxy = DelegateProxy(target: webView.navigationDelegate!)
        webView.navigationDelegate = proxy
        
        var crossSpineCalled = false
        controller.onCrossSpineNavigation = { _ in crossSpineCalled = true }
        controller.recognizesSpineURL = { _ in false }
        
        let html = "<html><body></body></html>"
        webView.loadHTMLString(html, baseURL: loadedURL)
        
        // Give it a moment to load the base URL
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Trigger a navigation to the secret URL directly so WebKit definitely calls decidePolicyFor
        webView.load(URLRequest(url: secretURL))
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        print("M8 TEST DEBUG: decidedPolicy = \\(String(describing: proxy.decidedPolicy))")
        
        // If the fix is MISSING, ReaderController decides .allow (because recognizesSpineURL is false).
        // If the fix is PRESENT, ReaderController decides .cancel.
        #expect(!crossSpineCalled, "Path traversal was not rejected")
        #expect(proxy.decidedPolicy == .cancel, "Path traversal policy was not .cancel")
    }
}
#endif
