#if os(iOS)
import Testing
import WebKit
@testable import Kudos

/// T-404: the position card's page count is not measured from a page that is not there yet.
@MainActor
struct ReaderPageSampleTests {
    /// What a web view holds before a chapter loads. Sampled, it gave "Page 1 of 1" or
    /// "Page 1 of 980" for a chapter of four screens.
    @Test func aBlankPageGivesNoSample() async {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let sample = await ReadiumBook.evaluatePageSample(
            webView: webView, js: ReadiumBook.pageSampleJS, area: 1
        )
        #expect(sample == nil)
    }

    /// The same guard in a page with no body content: an empty `<body>` is the blank page.
    @Test func theGuardIsOnTheBodyAndTheWindow() {
        let js = ReadiumBook.pageSampleJS
        #expect(js.contains("!document.body.firstChild"))
        #expect(js.contains("window.innerWidth || 0) < 32"))
    }
}
#endif
