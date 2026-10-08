import Foundation
import Testing
@testable import Kudos

/// Audit A19-1 and A19-2: what the web views that hold the AO3 session may load.
@Suite struct BrowserNavigationVerdictTests {
    private func verdict(_ address: String, main: Bool = true, demo: Bool = false) -> BrowserThemeStyle.NavigationVerdict {
        BrowserThemeStyle.navigationVerdict(for: URL(string: address), isMainFrame: main, isDemo: demo)
    }

    @Test func onlyAO3OverHTTPSStaysInTheWebView() {
        #expect(verdict("https://archiveofourown.org/works/1") == .allow)
        #expect(verdict("https://download.archiveofourown.org/x.epub") == .allow)
        #expect(verdict("https://example.com/") == .openOutside)
        #expect(verdict("http://archiveofourown.org/works/1") == .openOutside)
        #expect(verdict("https://archiveofourown.org.example.com/") == .openOutside)
    }

    @Test func otherSchemesGoNowhere() {
        #expect(verdict("javascript:document.title='x'") == .cancel)
        #expect(verdict("data:text/html,hello") == .cancel)
        #expect(verdict("file:///etc/hosts") == .cancel)
        #expect(verdict("kudos://open") == .cancel)
        #expect(BrowserThemeStyle.navigationVerdict(for: nil, isMainFrame: true, isDemo: false) == .cancel)
    }

    @Test func anEmbedFromAnotherHostIsAFrameNotThePage() {
        #expect(verdict("https://www.youtube.com/embed/x", main: false) == .allow)
        #expect(verdict("about:blank", main: false) == .allow)
        #expect(verdict("javascript:void(0)", main: false) == .cancel)
    }

    @Test func theDemoLoadsNothingRemote() {
        #expect(verdict("https://archiveofourown.org/", demo: true) == .cancel)
        #expect(verdict("https://www.youtube.com/embed/x", main: false, demo: true) == .cancel)
        #expect(verdict("about:blank", demo: true) == .allow)
    }

    @Test func onlyAPageFromAO3BecomesADownload() {
        let ao3 = URL(string: "https://download.archiveofourown.org/downloads/1/x.epub")
        #expect(BrowserThemeStyle.mayImportDownload(from: ao3, isForMainFrame: true))
        #expect(!BrowserThemeStyle.mayImportDownload(from: ao3, isForMainFrame: false))
        #expect(!BrowserThemeStyle.mayImportDownload(from: URL(string: "https://example.com/x.epub"), isForMainFrame: true))
    }
}
