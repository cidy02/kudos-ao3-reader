import Foundation
import Testing
import ReadiumNavigator
import ReadiumShared
@testable import Kudos

#if os(iOS)
@MainActor
struct ReadiumReaderTests {
    @Test func typographyMappingMatchesLegacyUnitsAndColors() {
        let style = ReaderTextStyle(
            customize: true,
            bold: true,
            fontSizePt: 18,
            lineHeight: 1.65,
            letterSpacing: 0.04,
            wordSpacing: 0.2,
            margin: 28,
            justify: true
        )
        let preferences = ReadiumReaderStyleMapper.preferences(
            style: style,
            theme: .sepia,
            fontFamily: FontFamily(rawValue: "Georgia"),
            readingMode: .paged,
            columnCount: .one
        )

        #expect(preferences.backgroundColor?.rawValue == 0xFBF0D9)
        #expect(preferences.textColor?.rawValue == 0x5B4636)
        #expect(preferences.fontSize == 1.125)
        #expect(preferences.fontWeight == 1.5)
        #expect(preferences.letterSpacing == 0.08)
        #expect(preferences.wordSpacing == 0.2)
        #expect(preferences.lineHeight == 1.65)
        #expect(preferences.pageMargins == 28)
        #expect(preferences.publisherStyles == false)
        #expect(preferences.scroll == false)
        #expect(preferences.textAlign == .justify)

        let properties = ReadiumReaderStyleMapper.readingSystemProperties.cssProperties()
        #expect(properties["--RS__pageGutter"] == "1.00000px")
    }

    @Test func builtInFontsKeepFallbacksAndImportedFontsInjectFontFace() throws {
        let customURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KudosTestFont.ttf")
        try Data([0, 1, 2, 3]).write(to: customURL)
        defer { try? FileManager.default.removeItem(at: customURL) }

        let system = ReaderFontOption(
            id: "system",
            name: "System",
            cssFamily: "-apple-system, system-ui, sans-serif",
            customFileURL: nil
        )
        let builtIn = ReaderFontOption(
            id: "nyserif",
            name: "New York",
            cssFamily: "'New York', ui-serif, Georgia, serif",
            customFileURL: nil
        )
        let custom = ReaderFontOption(
            id: "custom:test.ttf",
            name: "Test Font",
            cssFamily: "serif",
            customFileURL: customURL
        )
        let declarations = ReadiumReaderStyleMapper.fontFamilyDeclarations(
            options: [system, builtIn, custom]
        )

        #expect(ReadiumReaderStyleMapper.fontFamily(for: system)?.rawValue == "-apple-system")
        #expect(declarations.count == 3)
        #expect(declarations[0].fontFamily.rawValue == "-apple-system")
        #expect(declarations[0].alternates.map(\.rawValue) == ["system-ui", "sans-serif"])
        #expect(declarations[1].fontFamily.rawValue == "New York")
        #expect(declarations[1].alternates.map(\.rawValue) == ["ui-serif", "Georgia", "serif"])
        #expect(declarations[2].fontFamily.rawValue == "Kudos User Font custom:test.ttf")
        #expect(declarations[2].alternates.map(\.rawValue) == ["serif"])

        let url = try #require(URL(string: "https://example.com/KudosTestFont.ttf"))
        let servedURL = try #require(HTTPURL(url: url))
        let html = try declarations[2].inject(
            in: "<html><head></head><body>Font test</body></html>",
            servingFile: { file in
                #expect(file.path == customURL.path)
                return servedURL
            }
        )
        #expect(html.contains("@font-face"))
        #expect(html.contains("Kudos User Font custom:test.ttf"))
        #expect(html.contains("https://example.com/KudosTestFont.ttf"))
    }

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

    // MARK: - True-end completion (A7-F1)

    // The completion rule: only the final reading-order resource, visible with
    // its trailing edge at exactly 1.0 (Readium's clamped end state), may
    // finish a work. Progression thresholds like 0.99/0.999 never may.

    private static let readingOrder: [ReadiumShared.Link] = [
        ReadiumShared.Link(href: "OEBPS/preface.xhtml"),
        ReadiumShared.Link(href: "OEBPS/chapter1.xhtml"),
        ReadiumShared.Link(href: "OEBPS/chapter2.xhtml")
    ]

    /// A viewport whose visible resources are built through the same
    /// `Link.url()` normalization the navigator uses.
    private static func viewport(
        _ resources: [(link: ReadiumShared.Link, visible: ClosedRange<Double>)],
        total: ClosedRange<Double>
    ) -> NavigatorViewport {
        NavigatorViewport(
            resources: resources.map {
                NavigatorViewport.Resource(href: $0.link.url(), progression: $0.visible)
            },
            progression: total
        )
    }

    @Test func trailingEdgeAt99PercentDoesNotComplete() {
        // 0.99 through the final resource — the last 1% is real unread content.
        let viewport = Self.viewport([(Self.readingOrder[2], 0.93 ... 0.99)], total: 0.97 ... 0.996)
        #expect(!ReadiumReaderCompletion.isAtEnd(viewport: viewport, readingOrder: Self.readingOrder))
    }

    @Test func trailingEdgeAt999PermilleDoesNotComplete() {
        let viewport = Self.viewport([(Self.readingOrder[2], 0.94 ... 0.999)], total: 0.98 ... 0.9997)
        #expect(!ReadiumReaderCompletion.isAtEnd(viewport: viewport, readingOrder: Self.readingOrder))
    }

    @Test func midFinalResourceDoesNotComplete() {
        let viewport = Self.viewport([(Self.readingOrder[2], 0.4 ... 0.6)], total: 0.75 ... 0.85)
        #expect(!ReadiumReaderCompletion.isAtEnd(viewport: viewport, readingOrder: Self.readingOrder))
    }

    @Test func trueEndOfTheFinalResourceCompletes() {
        let viewport = Self.viewport([(Self.readingOrder[2], 0.93 ... 1.0)], total: 0.97 ... 1.0)
        #expect(ReadiumReaderCompletion.isAtEnd(viewport: viewport, readingOrder: Self.readingOrder))
    }

    @Test func endOfANonFinalResourceDoesNotComplete() {
        // Trailing edge 1.0, but of chapter 1 — the publication continues.
        let viewport = Self.viewport([(Self.readingOrder[1], 0.9 ... 1.0)], total: 0.55 ... 0.66)
        #expect(!ReadiumReaderCompletion.isAtEnd(viewport: viewport, readingOrder: Self.readingOrder))
    }

    @Test func trueEndIsRecognizedInATwoResourceSpread() {
        let viewport = Self.viewport(
            [(Self.readingOrder[1], 0.9 ... 1.0), (Self.readingOrder[2], 0.0 ... 1.0)],
            total: 0.6 ... 1.0
        )
        #expect(ReadiumReaderCompletion.isAtEnd(viewport: viewport, readingOrder: Self.readingOrder))
    }

    @Test func missingViewportOrReadingOrderNeverCompletes() {
        #expect(!ReadiumReaderCompletion.isAtEnd(viewport: nil, readingOrder: Self.readingOrder))
        let viewport = Self.viewport([(Self.readingOrder[2], 0.0 ... 1.0)], total: 0.0 ... 1.0)
        #expect(!ReadiumReaderCompletion.isAtEnd(viewport: viewport, readingOrder: []))
    }
}
#endif
