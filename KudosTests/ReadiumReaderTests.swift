import Foundation
import Testing
@testable import Kudos

#if os(iOS)
@MainActor
struct ReadiumReaderTests {
    @Test func webLinksAreHandedToBrowseButOtherSchemesAreNot() throws {
        let book = ReadiumBook()
        var routedURL: URL?
        book.onOpenExternalURL = { routedURL = $0 }

        let httpsURL = try #require(URL(string: "https://archiveofourown.org/works/123"))
        #expect(book.routeWebURLToBrowse(httpsURL))
        #expect(routedURL == httpsURL)

        let httpURL = try #require(URL(string: "http://example.com"))
        #expect(book.routeWebURLToBrowse(httpURL))
        #expect(routedURL == httpURL)

        let mailURL = try #require(URL(string: "mailto:reader@example.com"))
        #expect(!book.routeWebURLToBrowse(mailURL))
        #expect(routedURL == httpURL)
    }

    @Test func webLinkFallsBackWhenBrowseHandlerIsUnavailable() throws {
        let book = ReadiumBook()
        let url = try #require(URL(string: "https://archiveofourown.org/tags/Example"))

        #expect(!book.routeWebURLToBrowse(url))
    }
}
#endif
