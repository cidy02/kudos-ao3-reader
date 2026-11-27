import Foundation
import Testing
import WebKit
#if os(iOS)
import ReadiumNavigator
import ReadiumShared
#endif
@testable import Kudos

@MainActor
struct ReaderChapterEndHTMLTests {
    private final class FixtureBundleAnchor {}

    private func loadFixture(_ name: String) throws -> String {
        if let url = Bundle(for: FixtureBundleAnchor.self).url(
            forResource: name, withExtension: "xhtml"
        ) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        let fallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/\(name).xhtml")
        return try String(contentsOf: fallback, encoding: .utf8)
    }

    private func sampleCard(
        chapter: Int = 7,
        nextTitle: String = "Chapter 8: The Tide Table",
        nextHref: String = "ch8.xhtml",
        nextTime: String? = "About 15 min",
        footer: String = "Chapter 7 of 20 · 12 posted · or keep swiping to read on",
        showsAO3Actions: Bool = true,
        kudosGiven: Bool = false
    ) -> ReaderChapterEndCardContext {
        ReaderChapterEndCardContext(
            chapter: chapter,
            nextChapterTitle: nextTitle,
            nextChapterHref: nextHref,
            nextChapterTime: nextTime,
            footer: footer,
            showsAO3Actions: showsAO3Actions,
            kudosGiven: kudosGiven,
            style: .default
        )
    }

    private func isValidXML(_ xhtml: String) -> Bool {
        guard let data = xhtml.data(using: .utf8) else { return false }
        let parser = XMLParser(data: data)
        return parser.parse()
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        var count = 0
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    // MARK: - Core HTML transform on Fixtures

    @Test func sectionIsAppendedOnceBeforeClosingBodyAndRemainsValidXHTML() throws {
        let fixture = try loadFixture("epub_chapter_with_endnotes")
        let card = sampleCard()
        let once = ReaderChapterEndHTML.inject(into: fixture, card: card)

        #expect(occurrenceCount(of: "id=\"\(ReaderChapterEndHTML.sectionID)\"", in: once) == 1)
        let sectionRange = try #require(
            once.range(of: "<section id=\"\(ReaderChapterEndHTML.sectionID)\"")
        )
        let bodyClose = try #require(
            once.range(of: "</body>", options: [.caseInsensitive, .backwards])
        )
        #expect(sectionRange.upperBound < bodyClose.lowerBound)
        #expect(isValidXML(once))

        // Re-running the transform on already-transformed HTML never appends a second card.
        let twice = ReaderChapterEndHTML.inject(into: once, card: card)
        #expect(twice == once)
        #expect(occurrenceCount(of: "id=\"\(ReaderChapterEndHTML.sectionID)\"", in: twice) == 1)
    }

    @Test func endNoteAndTitleAreEscapedAndExpandToggleIsCSSOnly() throws {
        let fixture = try loadFixture("epub_chapter_with_endnotes")
        let card = sampleCard(nextTitle: "Chapter 8: \"Salt & <Tide>\"")
        let output = ReaderChapterEndHTML.inject(into: fixture, card: card)

        // End note special characters from the fixture must be escaped, never emitted raw.
        #expect(output.contains(
            "Thank you &amp; watch out for &lt;spoilers&gt; in &quot;Chapter 8&quot;"
        ))
        #expect(!output.contains("<spoilers>"))
        #expect(output.contains("Chapter 8: &quot;Salt &amp; &lt;Tide&gt;&quot;"))

        // CSS-only four-line clamp + checkbox toggle; no inline <script> injected.
        #expect(output.contains("type=\"checkbox\""))
        #expect(output.contains("for=\"\(ReaderChapterEndHTML.noteToggleID)\""))
        #expect(output.contains("-webkit-line-clamp: 4"))
        #expect(output.contains(">More<"))
        #expect(output.contains(">Less<"))
        #expect(!output.lowercased().contains("<script"))
        #expect(isValidXML(output))
    }

    @Test func noteHidingCSSIsPresentOnlyWhenChapterHasAnEndNote() throws {
        let withNote = try loadFixture("epub_chapter_with_endnotes")
        let withoutNote = try loadFixture("epub_chapter_no_endnotes")

        let transformedWith = ReaderChapterEndHTML.inject(into: withNote, card: sampleCard())
        #expect(transformedWith.contains("class=\"kudos-ce-note\""))
        let ao3HideRule = "[id^=\"endnotes\"], div.end.notes, div.endnotes { display: none !important; }"
        #expect(transformedWith.contains(ao3HideRule))
        #expect(!transformedWith.contains("aside.author-note:last-of-type"))

        let transformedWithout = ReaderChapterEndHTML.inject(into: withoutNote, card: sampleCard())
        #expect(!transformedWithout.contains("class=\"kudos-ce-note\""))
        #expect(!transformedWithout.contains("[id^=\"endnotes\"]"))
        #expect(!transformedWithout.contains("div.endnotes"))
        #expect(!transformedWithout.contains("aside.author-note"))
        #expect(isValidXML(transformedWithout))
    }

    @Test func convertedTrailingAuthorNoteHidesOnlyTrailingAside() {
        let trailing = """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Ch 1</title></head><body>
        <aside class="author-note"><p>Opening note stays visible.</p></aside>
        <p>Story prose.</p>
        <aside class="author-note"><p>Closing note &lt;moves&gt; into card.</p></aside>
        </body></html>
        """
        let output = ReaderChapterEndHTML.inject(into: trailing, card: sampleCard())
        #expect(output.contains("Closing note &lt;moves&gt; into card."))
        #expect(output.contains("aside.author-note:last-of-type { display: none !important; }"))
        #expect(!output.contains("[id^=\"endnotes\"]"))
        #expect(isValidXML(output))

        let leadingOnly = """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Ch 1</title></head><body>
        <aside class="author-note"><p>Opening note only.</p></aside>
        <p>Story prose.</p>
        </body></html>
        """
        let leadingOutput = ReaderChapterEndHTML.inject(into: leadingOnly, card: sampleCard())
        #expect(!leadingOutput.contains("class=\"kudos-ce-note\""))
        #expect(!leadingOutput.contains("aside.author-note"))
        #expect(isValidXML(leadingOutput))
    }

    // MARK: - Last chapter, next-chapter href, and card states

    @Test func lastChapterAndFrontOrBackMatterReceiveNoCard() {
        let sections = [
            ReaderSection(
                href: "OEBPS/preface.xhtml", title: "Preface",
                kind: .preface, spineIndex: 0, storyChapterIndex: nil
            ),
            ReaderSection(
                href: "OEBPS/ch1.xhtml", title: "Low Water",
                kind: .chapter, spineIndex: 1, storyChapterIndex: 1
            ),
            ReaderSection(
                href: "OEBPS/interlude.xhtml", title: "Art",
                kind: .other, spineIndex: 2, storyChapterIndex: nil
            ),
            ReaderSection(
                href: "OEBPS/ch2.xhtml", title: "The Tide Table",
                kind: .chapter, spineIndex: 3, storyChapterIndex: 2
            ),
            ReaderSection(
                href: "OEBPS/afterword.xhtml", title: "Afterword",
                kind: .afterword, spineIndex: 4, storyChapterIndex: nil
            ),
        ]
        let work = ReaderChapterEndWorkContext(
            chapterWordCounts: [2000, 2800],
            totalChapters: 20,
            postedChapters: 12,
            isComplete: false,
            showsAO3Actions: true,
            kudosState: ReaderChapterEndKudosState(isGiven: false),
            style: .default
        )

        #expect(ReaderChapterEndHTML.cardContext(forSpineIndex: 0, sections: sections, work: work) == nil)
        #expect(ReaderChapterEndHTML.cardContext(forSpineIndex: 2, sections: sections, work: work) == nil)
        #expect(ReaderChapterEndHTML.cardContext(forSpineIndex: 3, sections: sections, work: work) == nil)
        #expect(ReaderChapterEndHTML.cardContext(forSpineIndex: 4, sections: sections, work: work) == nil)

        let ch1Card = ReaderChapterEndHTML.cardContext(forSpineIndex: 1, sections: sections, work: work)
        #expect(ch1Card?.chapter == 1)
        #expect(ch1Card?.nextChapterTitle == "Chapter 2: The Tide Table")
        #expect(ch1Card?.nextChapterHref == "ch2.xhtml")
        #expect(ch1Card?.nextChapterTime == "About 15 min")
        #expect(ch1Card?.footer == "Chapter 1 of 20 · 12 posted · or keep swiping to read on")
    }

    @Test func nextChapterRelativeHrefResolvesAcrossDirectories() throws {
        #expect(
            ReaderChapterEndHTML.relativeHref(from: "OEBPS/ch1.xhtml", to: "OEBPS/ch2.xhtml")
                == "ch2.xhtml"
        )
        #expect(ReaderChapterEndHTML.relativeHref(from: "ch1.xhtml", to: "ch2.xhtml") == "ch2.xhtml")
        #expect(
            ReaderChapterEndHTML.relativeHref(from: "OEBPS/part1/ch1.xhtml", to: "OEBPS/part2/ch2.xhtml")
                == "../part2/ch2.xhtml"
        )
        #expect(
            ReaderChapterEndHTML.relativeHref(from: "OEBPS/ch1.xhtml", to: "OEBPS/text/ch%202.xhtml")
                == "text/ch%202.xhtml"
        )
        #expect(
            ReaderChapterEndHTML.relativeHref(from: "/OEBPS/ch1.xhtml", to: "/OEBPS/ch2.xhtml")
                == "ch2.xhtml"
        )

        let fixture = try loadFixture("epub_chapter_no_endnotes")
        let output = ReaderChapterEndHTML.inject(
            into: fixture, card: sampleCard(nextHref: "../part2/ch8.xhtml")
        )
        let expectedLink = "id=\"\(ReaderChapterEndHTML.nextLinkID)\" "
            + "class=\"kudos-ce-next\" href=\"../part2/ch8.xhtml\""
        #expect(output.contains(expectedLink))
    }

    @Test func ao3ActionsRespectShowsFlagAndKudosGivenState() throws {
        let fixture = try loadFixture("epub_chapter_no_endnotes")

        let noAO3 = ReaderChapterEndHTML.inject(into: fixture, card: sampleCard(showsAO3Actions: false))
        #expect(!noAO3.contains(ReaderChapterEndHTML.commentLinkID))
        #expect(!noAO3.contains(ReaderChapterEndHTML.kudosLinkID))

        let ungiven = ReaderChapterEndHTML.inject(into: fixture, card: sampleCard(kudosGiven: false))
        #expect(ungiven.contains("href=\"\(ReaderChapterEndAction.comment(chapter: 7).urlString)\""))
        #expect(ungiven.contains("href=\"\(ReaderChapterEndAction.kudos.urlString)\""))
        #expect(ungiven.contains("Give Kudos"))
        #expect(ungiven.contains("data-kudos-given=\"false\""))

        let given = ReaderChapterEndHTML.inject(into: fixture, card: sampleCard(kudosGiven: true))
        #expect(given.contains("Kudos Given"))
        #expect(given.contains("data-kudos-given=\"true\""))
        #expect(given.contains("aria-pressed=\"true\""))
        #expect(!given.contains("href=\"\(ReaderChapterEndAction.kudos.urlString)\""))

        #expect(ReaderChapterEndHTML.markKudosGivenJS.contains("Kudos Given"))
        #expect(ReaderChapterEndHTML.markKudosGivenJS.contains(ReaderChapterEndHTML.kudosLinkID))
    }

    @Test func stylesheetFollowsThemesFontSizeAndReduceMotionWithoutXMLHazards() throws {
        let fixture = try loadFixture("epub_chapter_with_endnotes")
        let output = ReaderChapterEndHTML.inject(into: fixture, card: sampleCard())

        let styleStart = try #require(
            output.range(of: "<style id=\"\(ReaderChapterEndHTML.styleID)\">")
        )
        let styleEnd = try #require(
            output.range(of: "</style>", range: styleStart.upperBound..<output.endIndex)
        )
        let css = String(output[styleStart.upperBound..<styleEnd.lowerBound])

        #expect(css.contains("--USER__textColor"))
        #expect(css.contains("currentColor"))
        #expect(css.contains("readium-night-on"))
        #expect(css.contains("readium-sepia-on"))
        #expect(css.contains("prefers-reduced-motion: reduce"))
        #expect(css.contains("rem"))
        #expect(!css.contains("<"))
        #expect(!css.contains(">"))
        #expect(!css.contains("&"))
    }

    // MARK: - Kudos URL round trip & navigation guard

    @Test func kudosActionURLsRoundTripAndRejectInvalidURLs() throws {
        let comment = ReaderChapterEndAction.comment(chapter: 7)
        let commentURL = comment.url
        #expect(commentURL.scheme == ReaderChapterEndAction.urlScheme)
        #expect(ReaderChapterEndAction(url: commentURL) == comment)
        #expect(commentURL.absoluteString == comment.urlString)

        let kudos = ReaderChapterEndAction.kudos
        let kudosURL = kudos.url
        #expect(kudosURL.scheme == ReaderChapterEndAction.urlScheme)
        #expect(ReaderChapterEndAction(url: kudosURL) == kudos)
        #expect(kudosURL.absoluteString == kudos.urlString)

        let invalid = [
            "https://archiveofourown.org/works/123",
            "readium://abc/OEBPS/ch1.xhtml",
            "\(ReaderChapterEndAction.urlScheme)://unknown",
            "\(ReaderChapterEndAction.urlScheme)://comment",
            "\(ReaderChapterEndAction.urlScheme)://comment?chapter=0",
            "\(ReaderChapterEndAction.urlScheme)://comment?chapter=-3",
            "\(ReaderChapterEndAction.urlScheme)://comment?chapter=abc",
        ]
        for raw in invalid {
            let url = try #require(URL(string: raw))
            #expect(ReaderChapterEndAction(url: url) == nil)
        }
    }

    @Test func navigationGuardForwardsTappedKudosActionLinkAndBlocksScriptedNavigation() {
        let webView = WKWebView()
        let spy = ChapterEndSpyNavigationDelegate()
        let navGuard = ReaderWebNavigationGuard(
            original: spy,
            origin: .readiumScheme,
            onOpenExternalURL: nil
        )
        let kudosURL = ReaderChapterEndAction.kudos.url

        // The custom scheme is never allowed as an in-reader navigation target.
        #expect(!ReaderWebNavigationPolicy.allowsInReaderNavigation(
            to: kudosURL, origin: .readiumScheme
        ))

        // Script-driven navigation (.other) is cancelled without forwarding to Readium.
        var scriptedPolicy: WKNavigationActionPolicy?
        navGuard.webView(
            webView,
            decidePolicyFor: ChapterEndTestNavigationAction(url: kudosURL, type: .other)
        ) { scriptedPolicy = $0 }
        #expect(scriptedPolicy == .cancel)
        #expect(spy.receivedURLs.isEmpty)

        // User-tapped link (.linkActivated) forwards to Readium so the navigator delegate
        // receives `presentExternalURL`, while the guard still cancels web navigation.
        var tappedPolicy: WKNavigationActionPolicy?
        navGuard.webView(
            webView,
            decidePolicyFor: ChapterEndTestNavigationAction(url: kudosURL, type: .linkActivated)
        ) { tappedPolicy = $0 }
        #expect(tappedPolicy == .cancel)
        #expect(spy.receivedURLs == [kudosURL])
    }

    // MARK: - Readium pipeline integration & position preservation (iOS)

    #if os(iOS)
    @Test func publicationLoaderTransformsOnlyNonFinalChaptersAndPreservesPositionsAndSearch() async throws {
        let ch1XHTML = try loadFixture("epub_chapter_with_endnotes")
        let ch2XHTML = try loadFixture("epub_chapter_no_endnotes")
        let epubURL = try makeTwoChapterFixtureEPUB(ch1XHTML: ch1XHTML, ch2XHTML: ch2XHTML)
        defer { try? FileManager.default.removeItem(at: epubURL) }

        let kudosState = ReaderChapterEndKudosState(isGiven: false)
        let workContext = ReaderChapterEndWorkContext(
            chapterWordCounts: [1200, 2800],
            totalChapters: 10,
            postedChapters: 2,
            isComplete: false,
            showsAO3Actions: true,
            kudosState: kudosState,
            style: .default
        )

        let baseline = try await ReadiumPublicationLoader.openEPUB(at: epubURL)
        let transformed = try await ReadiumPublicationLoader.openEPUB(
            at: epubURL, chapterEnd: workContext
        )

        // Positions (archive entry lengths) must be identical — card adds zero positions.
        let basePositions = try await baseline.positionsByReadingOrder().get()
        let transformedPositions = try await transformed.positionsByReadingOrder().get()
        #expect(basePositions == transformedPositions)

        // Spine: 0=Preface, 1=Ch1 (gets card), 2=Ch2 (last chapter, no card), 3=Afterword (no card).
        #expect(transformed.readingOrder.count == 4)
        let prefaceHTML = try await readResourceString(
            transformed.get(transformed.readingOrder[0])
        )
        let ch1HTML = try await readResourceString(
            transformed.get(transformed.readingOrder[1])
        )
        let ch2HTML = try await readResourceString(
            transformed.get(transformed.readingOrder[2])
        )
        let afterwordHTML = try await readResourceString(
            transformed.get(transformed.readingOrder[3])
        )

        #expect(!prefaceHTML.contains(ReaderChapterEndHTML.sectionID))
        #expect(ch1HTML.contains("id=\"\(ReaderChapterEndHTML.sectionID)\""))
        #expect(ch1HTML.contains("href=\"ch2.xhtml\""))
        #expect(ch1HTML.contains("About 15 min"))
        #expect(ch1HTML.contains("Give Kudos"))
        #expect(isValidXML(ch1HTML))
        #expect(!ch2HTML.contains(ReaderChapterEndHTML.sectionID))
        #expect(!afterwordHTML.contains(ReaderChapterEndHTML.sectionID))

        // Raw container service keeps original chapter HTML for Read Aloud.
        let rawService = try #require(transformed.findService(RawEPUBContainerService.self))
        let rawCh1 = try await readResourceString(
            rawService.resource(for: transformed.readingOrder[1])
        )
        #expect(!rawCh1.contains(ReaderChapterEndHTML.sectionID))

        // Search reads raw content, so injected UI text never appears in Find in Work.
        let searchIterator = try await transformed.search(query: "Give Kudos").get()
        let firstBatch = try await searchIterator.next().get()
        #expect(firstBatch == nil)

        // Once kudos is given, subsequent reads of chapter resources already show "Kudos Given".
        kudosState.isGiven = true
        let ch1AfterKudos = try await readResourceString(
            transformed.get(transformed.readingOrder[1])
        )
        #expect(ch1AfterKudos.contains("Kudos Given"))
        #expect(!ch1AfterKudos.contains("href=\"\(ReaderChapterEndAction.kudos.urlString)\""))
    }

    @Test func bookRoutesChapterEndActionsWithoutFallingThroughToExternalOpen() throws {
        let book = ReadiumBook()
        var received: [ReaderChapterEndAction] = []
        book.onChapterEndAction = { received.append($0) }

        #expect(book.routeChapterEndActionURL(ReaderChapterEndAction.comment(chapter: 3).url))
        #expect(book.routeChapterEndActionURL(ReaderChapterEndAction.kudos.url))
        #expect(received == [.comment(chapter: 3), .kudos])

        // Even an unrecognised path under the Kudos-only scheme is claimed and swallowed.
        let unknown = try #require(URL(string: "\(ReaderChapterEndAction.urlScheme)://other"))
        #expect(book.routeChapterEndActionURL(unknown))
        #expect(received.count == 2)

        // Regular web and mailto URLs are not claimed by chapter-end routing.
        let ao3URL = try #require(URL(string: "https://archiveofourown.org/works/1"))
        let mailURL = try #require(URL(string: "mailto:reader@example.com"))
        #expect(!book.routeChapterEndActionURL(ao3URL))
        #expect(!book.routeChapterEndActionURL(mailURL))
    }

    @Test func locatorNormalizationPreservesOriginalReadingPositionAcrossCardLength() throws {
        #expect(
            ReaderChapterEndProgress.normalizedHrefKey("/OEBPS/Ch%201.xhtml#top")
                == ReaderChapterEndProgress.normalizedHrefKey("OEBPS/ch 1.xhtml")
        )

        let ch1Href = try #require(AnyURL(string: "OEBPS/ch1.xhtml"))
        let ch2Href = try #require(AnyURL(string: "OEBPS/ch2.xhtml"))
        let readingOrder = [
            ReadiumShared.Link(href: "OEBPS/ch1.xhtml"),
            ReadiumShared.Link(href: "OEBPS/ch2.xhtml"),
        ]
        // 10 positions in ch1 (totalProgression 0.0..<0.5), 10 in ch2 (0.5..<1.0).
        let ch1Positions = (0..<10).map { idx in
            Locator(
                href: ch1Href,
                mediaType: .xhtml,
                locations: .init(
                    progression: Double(idx) / 10.0,
                    totalProgression: Double(idx) / 20.0,
                    position: idx + 1
                )
            )
        }
        let ch2Positions = (0..<10).map { idx in
            Locator(
                href: ch2Href,
                mediaType: .xhtml,
                locations: .init(
                    progression: Double(idx) / 10.0,
                    totalProgression: 0.5 + Double(idx) / 20.0,
                    position: idx + 11
                )
            )
        }
        let positions = [ch1Positions, ch2Positions]

        // 5 prose pages + 1 card page -> contentRatio = 5/6.
        let ratio = 5.0 / 6.0
        // Original page 3 of 5 is progression 0.4; with the card, Readium sees 2/6 = 0.3333...
        let rawMid = Locator(
            href: ch1Href,
            mediaType: .xhtml,
            locations: .init(
                progression: 2.0 / 6.0,
                totalProgression: (2.0 / 6.0) * 0.5,
                position: 4
            )
        )
        let normalizedMid = ReaderChapterEndProgress.normalizeLocator(
            rawMid,
            contentRatio: ratio,
            readingOrder: readingOrder,
            positionsByReadingOrder: positions
        )
        let midProg = try #require(normalizedMid.locations.progression)
        let midTotal = try #require(normalizedMid.locations.totalProgression)
        #expect(abs(midProg - 0.4) < 1e-9)
        #expect(abs(midTotal - 0.2) < 1e-9)
        #expect(normalizedMid.locations.position == 5)

        // Swiping onto the card page (5/6) clamps cleanly to the end of the chapter (1.0).
        let rawOnCard = Locator(
            href: ch1Href,
            mediaType: .xhtml,
            locations: .init(
                progression: 5.0 / 6.0,
                totalProgression: (5.0 / 6.0) * 0.5,
                position: 9
            )
        )
        let normalizedEnd = ReaderChapterEndProgress.normalizeLocator(
            rawOnCard,
            contentRatio: ratio,
            readingOrder: readingOrder,
            positionsByReadingOrder: positions
        )
        #expect(normalizedEnd.locations.progression == 1.0)
        #expect(normalizedEnd.locations.position == 10)
        #expect(abs((normalizedEnd.locations.totalProgression ?? 0) - 0.5) < 1e-9)

        // With no extra card length (ratio == 1.0), the locator passes through unchanged.
        let unchanged = ReaderChapterEndProgress.normalizeLocator(
            rawMid,
            contentRatio: 1.0,
            readingOrder: readingOrder,
            positionsByReadingOrder: positions
        )
        #expect(unchanged == rawMid)
    }

    private func readResourceString(_ resource: Resource?) async throws -> String {
        let unwrapped = try #require(resource)
        return try await unwrapped.read().asString().get()
    }

    private func makeTwoChapterFixtureEPUB(ch1XHTML: String, ch2XHTML: String) throws -> URL {
        let container = """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0" encoding="utf-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="id">chapter-end-fixture</dc:identifier>
            <dc:title>Tide Table</dc:title>
            <dc:language>en</dc:language>
          </metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="pre" href="preface.xhtml" media-type="application/xhtml+xml"/>
            <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
            <item id="aft" href="afterword.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="pre"/>
            <itemref idref="c1"/>
            <itemref idref="c2"/>
            <itemref idref="aft"/>
          </spine>
        </package>
        """
        let ncx = """
        <?xml version="1.0" encoding="utf-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <navMap>
            <navPoint id="n1" playOrder="1">
              <navLabel><text>Preface</text></navLabel>
              <content src="preface.xhtml"/>
            </navPoint>
            <navPoint id="n2" playOrder="2">
              <navLabel><text>Low Water</text></navLabel>
              <content src="ch1.xhtml"/>
            </navPoint>
            <navPoint id="n3" playOrder="3">
              <navLabel><text>The Tide Table</text></navLabel>
              <content src="ch2.xhtml"/>
            </navPoint>
            <navPoint id="n4" playOrder="4">
              <navLabel><text>Afterword</text></navLabel>
              <content src="afterword.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """
        let preface = """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Preface</title></head><body><p>Summary.</p></body>
        </html>
        """
        let afterword = """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Afterword</title></head><body><p>End.</p></body>
        </html>
        """
        let data = try MiniZip.archiveData([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/toc.ncx", Data(ncx.utf8)),
            ("OEBPS/preface.xhtml", Data(preface.utf8)),
            ("OEBPS/ch1.xhtml", Data(ch1XHTML.utf8)),
            ("OEBPS/ch2.xhtml", Data(ch2XHTML.utf8)),
            ("OEBPS/afterword.xhtml", Data(afterword.utf8)),
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChapterEndFixture-\(UUID().uuidString)")
            .appendingPathExtension("epub")
        try data.write(to: url)
        return url
    }
    #endif
}

private final class ChapterEndTestNavigationAction: WKNavigationAction {
    private let urlRequest: URLRequest
    private let actionType: WKNavigationType

    override var request: URLRequest { urlRequest }
    override var navigationType: WKNavigationType { actionType }

    init(url: URL, type: WKNavigationType) {
        urlRequest = URLRequest(url: url)
        actionType = type
        super.init()
    }
}

private final class ChapterEndSpyNavigationDelegate: NSObject, WKNavigationDelegate {
    var receivedURLs: [URL] = []

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url {
            receivedURLs.append(url)
        }
        // Deliberately answer `.allow` to verify the guard still forces `.cancel`.
        decisionHandler(.allow)
    }
}
