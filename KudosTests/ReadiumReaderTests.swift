import Foundation
import Testing

#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import UIKit
@testable import Kudos
#endif

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
            twoPageSpread: false
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

    @Test func customLightPaperOnDarkUsesTheLightReadiumTheme() {
        let preferences = ReadiumReaderStyleMapper.preferences(
            style: ReaderTextStyle(),
            theme: .dark,
            fontFamily: nil,
            readingMode: .scroll,
            twoPageSpread: false,
            backgroundHex: "#FFFFFF",
            textHex: "#000000"
        )
        #expect(preferences.theme == .light)
        #expect(preferences.backgroundColor?.rawValue == 0xFFFFFF)
        #expect(preferences.textColor?.rawValue == 0x000000)
    }

    @Test func sepiaPaperKeepsTheSepiaReadiumTheme() {
        let preferences = ReadiumReaderStyleMapper.preferences(
            style: ReaderTextStyle(),
            theme: .sepia,
            fontFamily: nil,
            readingMode: .scroll,
            twoPageSpread: false,
            backgroundHex: ReaderTheme.sepia.backgroundHex,
            textHex: ReaderTheme.sepia.textHex
        )
        #expect(preferences.theme == .sepia)
    }

    @Test func pagedColumnsHonorSpreadDecision() {
        let spread = ReadiumReaderStyleMapper.preferences(
            style: ReaderTextStyle(), theme: .light, fontFamily: nil,
            readingMode: .paged, twoPageSpread: true
        )
        let single = ReadiumReaderStyleMapper.preferences(
            style: ReaderTextStyle(), theme: .light, fontFamily: nil,
            readingMode: .paged, twoPageSpread: false
        )

        #expect(spread.columnCount == .auto)
        #expect(single.columnCount == .one)
    }

    @Test(arguments: [false, true])
    func scrollModeNeverForcesColumns(twoPageSpread: Bool) {
        let preferences = ReadiumReaderStyleMapper.preferences(
            style: ReaderTextStyle(), theme: .light, fontFamily: nil,
            readingMode: .scroll, twoPageSpread: twoPageSpread
        )

        #expect(preferences.columnCount == nil)
        #expect(preferences.scroll == true)
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

    // MARK: - Nested TOC flattening (A7-F8)

    @Test func nestedTOCChildrenBecomeTheirOwnNavigableSections() {
        let readingOrder: [ReadiumShared.Link] = [
            ReadiumShared.Link(href: "OEBPS/part1.xhtml"),
            ReadiumShared.Link(href: "OEBPS/chapter1.xhtml"),
            ReadiumShared.Link(href: "OEBPS/chapter2.xhtml")
        ]
        // A common hierarchical TOC shape: a Part heading with two Chapter
        // children nested under it, none listed at the top level.
        let toc: [ReadiumShared.Link] = [
            ReadiumShared.Link(
                href: "OEBPS/part1.xhtml",
                title: "Part One",
                children: [
                    ReadiumShared.Link(href: "OEBPS/chapter1.xhtml", title: "Chapter 1"),
                    ReadiumShared.Link(href: "OEBPS/chapter2.xhtml", title: "Chapter 2")
                ]
            )
        ]

        let sections = ReadiumBook.buildSections(toc: toc, readingOrder: readingOrder)

        #expect(sections.count == 3)
        #expect(sections.map(\.title) == ["Part One", "Chapter 1", "Chapter 2"])
        // Before flattening, an unvisited child fell back to `.other` and the
        // chapter sheet's `.filter { $0.kind != .other }` hid it entirely —
        // the exact A7-F8 symptom.
        #expect(sections.allSatisfy { $0.kind != .other })
    }

    @Test func deeplyNestedTOCFlattensInDocumentOrder() {
        let readingOrder: [ReadiumShared.Link] = [
            ReadiumShared.Link(href: "OEBPS/part1.xhtml"),
            ReadiumShared.Link(href: "OEBPS/chapter1.xhtml"),
            ReadiumShared.Link(href: "OEBPS/chapter1a.xhtml")
        ]
        let toc: [ReadiumShared.Link] = [
            ReadiumShared.Link(
                href: "OEBPS/part1.xhtml",
                title: "Part One",
                children: [
                    ReadiumShared.Link(
                        href: "OEBPS/chapter1.xhtml",
                        title: "Chapter 1",
                        children: [
                            ReadiumShared.Link(href: "OEBPS/chapter1a.xhtml", title: "Chapter 1a")
                        ]
                    )
                ]
            )
        ]

        let sections = ReadiumBook.buildSections(toc: toc, readingOrder: readingOrder)

        #expect(sections.map(\.title) == ["Part One", "Chapter 1", "Chapter 1a"])
    }

    /// A grouping node with no page of its own — "Part One" pointing at its first
    /// chapter's file — is an ordinary EPUB2 NCX shape. Flattening emits both it and
    /// that child for the same spine index, and `ReaderSectionBuilder.build` is
    /// last-write-wins, so without the outermost-wins dedup in `buildSections` the
    /// child would rename that spine item (here: "Part One" → "Chapter 1"), which is
    /// a behavior change beyond A7-F8's scope.
    @Test func partSharingItsFirstChildsHrefKeepsTheOutermostTitle() {
        let readingOrder: [ReadiumShared.Link] = [
            ReadiumShared.Link(href: "OEBPS/chapter1.xhtml"),
            ReadiumShared.Link(href: "OEBPS/chapter2.xhtml")
        ]
        let toc: [ReadiumShared.Link] = [
            ReadiumShared.Link(
                href: "OEBPS/chapter1.xhtml",
                title: "Part One",
                children: [
                    ReadiumShared.Link(href: "OEBPS/chapter1.xhtml", title: "Chapter 1"),
                    ReadiumShared.Link(href: "OEBPS/chapter2.xhtml", title: "Chapter 2")
                ]
            )
        ]

        let sections = ReadiumBook.buildSections(toc: toc, readingOrder: readingOrder)

        #expect(sections.count == 2)
        #expect(sections.map(\.title) == ["Part One", "Chapter 2"])
        // Chapter numbering must stay 1,2 — one section per spine item, no duplicate
        // consuming an extra story-chapter number.
        #expect(sections.map(\.storyChapterIndex) == [1, 2])
    }

    /// The same collision, but where the two titles classify differently: an
    /// "Afterword" parent losing to a chapter child would turn back matter into a
    /// numbered story chapter and shift the count.
    @Test func classificationDoesNotFlipWhenAParentSharesAChildsHref() {
        let readingOrder: [ReadiumShared.Link] = [
            ReadiumShared.Link(href: "OEBPS/chapter1.xhtml"),
            ReadiumShared.Link(href: "OEBPS/after.xhtml")
        ]
        let toc: [ReadiumShared.Link] = [
            ReadiumShared.Link(href: "OEBPS/chapter1.xhtml", title: "Chapter 1"),
            ReadiumShared.Link(
                href: "OEBPS/after.xhtml",
                title: "Afterword",
                children: [ReadiumShared.Link(href: "OEBPS/after.xhtml", title: "Chapter 2")]
            )
        ]

        let sections = ReadiumBook.buildSections(toc: toc, readingOrder: readingOrder)

        #expect(sections.map(\.kind) == [.chapter, .afterword])
        #expect(sections.storyChapterCount == 1)
    }

    @Test func topLevelOnlyTOCStillWorksUnchanged() {
        // Regression guard: a flat (non-nested) TOC — the shape every existing
        // fixture uses — must resolve exactly as before flattening was added.
        let readingOrder: [ReadiumShared.Link] = [
            ReadiumShared.Link(href: "OEBPS/preface.xhtml"),
            ReadiumShared.Link(href: "OEBPS/chapter1.xhtml")
        ]
        let toc: [ReadiumShared.Link] = [
            ReadiumShared.Link(href: "OEBPS/preface.xhtml", title: "Preface"),
            ReadiumShared.Link(href: "OEBPS/chapter1.xhtml", title: "Chapter 1")
        ]

        let sections = ReadiumBook.buildSections(toc: toc, readingOrder: readingOrder)

        #expect(sections.map(\.title) == ["Preface", "Chapter 1"])
        #expect(sections[0].kind == .preface)
        #expect(sections[1].kind == .chapter)
    }

    // MARK: - Duo5 host geometry and same-chapter reflow

    @Test func pageBoxUsesBothDimensionsAndMeaningfulInsetChanges() {
        let original = ReaderPageBoxGeometry(
            size: CGSize(width: 466, height: 678),
            safeInsets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        )
        let widthOnly = original.updating(
            size: CGSize(width: 951, height: 678),
            safeInsets: original.safeInsets, preserveStatusBarTop: true
        )
        #expect(widthOnly.size.width == 951)
        let heightOnly = original.updating(
            size: CGSize(width: 466, height: 669),
            safeInsets: original.safeInsets, preserveStatusBarTop: true
        )
        #expect(heightOnly.size.height == 669)
        // Side exclusions can change without either dimension changing.
        let safe = UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 48)
        let insetOnly = widthOnly.updating(
            size: widthOnly.size, safeInsets: safe, preserveStatusBarTop: false
        )
        #expect(insetOnly.safeInsets == safe)
        #expect(insetOnly.horizontalInsets(in: .leftToRight).leading == 62)
        #expect(insetOnly.horizontalInsets(in: .leftToRight).trailing == 48)
        #expect(insetOnly.horizontalInsets(in: .rightToLeft).leading == 48)
        #expect(insetOnly.horizontalInsets(in: .rightToLeft).trailing == 62)
        // A valid zero must replace a former inset; never fall back to stale data.
        #expect(insetOnly.updating(
            size: insetOnly.size, safeInsets: .zero, preserveStatusBarTop: false
        ).safeInsets == .zero)
    }

    @Test func pageBoxKeepsStatusBarClearanceButAcceptsRotationWithChromeHidden() {
        let portrait = ReaderPageBoxGeometry(
            size: CGSize(width: 466, height: 678),
            safeInsets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        )
        let hiddenStatus = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        #expect(portrait.updating(
            size: portrait.size, safeInsets: hiddenStatus, preserveStatusBarTop: true
        ) == portrait)
        let landscapeSafe = UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)
        #expect(portrait.updating(
            size: portrait.size, safeInsets: landscapeSafe, preserveStatusBarTop: true
        ).safeInsets == landscapeSafe)
        let landscape = portrait.updating(
            size: CGSize(width: 951, height: 669),
            safeInsets: landscapeSafe, preserveStatusBarTop: true
        )
        #expect(landscape.size == CGSize(width: 951, height: 669))
        #expect(landscape.safeInsets == landscapeSafe)
        let innerPortrait = landscape.updating(
            size: CGSize(width: 669, height: 951),
            safeInsets: portrait.safeInsets, preserveStatusBarTop: true
        )
        #expect(innerPortrait.size == CGSize(width: 669, height: 951))
        #expect(innerPortrait.safeInsets == portrait.safeInsets)
    }

    @Test func pageBoxIgnoresPrelayoutAndOnePointNoise() {
        let original = ReaderPageBoxGeometry(
            size: CGSize(width: 466, height: 678),
            safeInsets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        )
        for size in [CGSize.zero, CGSize(width: 466, height: 0), CGSize(width: 0, height: 678)] {
            #expect(original.updating(size: size, safeInsets: .zero, preserveStatusBarTop: false) == original)
        }
        #expect(original.updating(
            size: CGSize(width: 467, height: 677),
            safeInsets: UIEdgeInsets(top: 61, left: 1, bottom: 35, right: 1),
            preserveStatusBarTop: false
        ) == original)
        #expect(original.updating(
            size: CGSize(width: 467.1, height: 678),
            safeInsets: original.safeInsets, preserveStatusBarTop: false
        ) != original)
        let initial = ReaderPageBoxGeometry().updating(
            size: original.size, safeInsets: original.safeInsets, preserveStatusBarTop: true
        )
        #expect(initial == original)
    }

    @Test(arguments: [8, 24], [false, true])
    func aSameHrefWidthChangeSchedulesRemeasure(
        newCount: Int, horizontal: Bool
    ) async throws {
        let book = ReadiumBook()
        let source = GeometryTestNavigator()
        let size = CGSize(width: 466, height: 678)
        book.updatePageBoxGeometry(size: size, safeInsets: .zero)
        await book.pageBoxRemeasureTask?.value
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let locator = Locator(
            href: href, mediaType: .xhtml,
            locations: .init(fragments: ["passage"], progression: 0.4, totalProgression: 0.42)
        )
        book.navigator(source, locationDidChange: locator)
        book.acceptLayoutPageCount(12, measuredPage: 5, preferHorizontal: true, isFinalAttempt: false)
        book.acceptLayoutPageCount(12, measuredPage: 5, preferHorizontal: true, isFinalAttempt: false)
        #expect(book.pageBarReady)
        let generation = book.pageBarMeasureGeneration
        book.updatePageBoxGeometry(size: CGSize(width: 951, height: 678), safeInsets: .zero)
        #expect(book.pageBoxRemeasureTask != nil)
        #expect(!book.pageBarReady)
        #expect(book.visualPage == nil)
        #expect(book.visualPageCount == nil)
        let superseded = try #require(book.pageBoxRemeasureTask)
        book.updatePageBoxGeometry(size: CGSize(width: 951, height: 669), safeInsets: .zero)
        #expect(superseded.isCancelled)
        await book.pageBoxRemeasureTask?.value
        #expect(book.pageBoxRemeasureTask == nil)
        #expect(book.pageBarMeasureGeneration > generation)
        #expect(book.currentLocator == locator)
        #expect(!book.pageBarReady)
        // The new denominator may grow OR shrink; one sample is not enough.
        book.acceptLayoutPageCount(newCount, measuredPage: 3, preferHorizontal: horizontal, isFinalAttempt: false)
        #expect(!book.pageBarReady)
        book.acceptLayoutPageCount(newCount, measuredPage: 3, preferHorizontal: horizontal, isFinalAttempt: false)
        #expect(book.pageBarReady)
        #expect(book.visualPageCount == newCount)
        #expect(book.visualPage == 3)
        #expect(book.currentLocator == locator)
    }

    private static func progression(_ string: String?) -> Double? {
        string.flatMap { Locator(persistenceString: $0) }?.locations.progression
    }

    @Test func sameHrefLocationDuringResizeReachesCurrentLocatorAndPersistence() async throws {
        let book = ReadiumBook()
        let source = GeometryTestNavigator()
        book.updatePageBoxGeometry(size: CGSize(width: 466, height: 678), safeInsets: .zero)
        await book.pageBoxRemeasureTask?.value
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let initial = Locator(
            href: href, mediaType: .xhtml,
            locations: .init(progression: 0.4, totalProgression: 0.42)
        )
        book.navigator(source, locationDidChange: initial)
        book.acceptLayoutPageCount(12, measuredPage: 5, preferHorizontal: true, isFinalAttempt: false)
        book.acceptLayoutPageCount(12, measuredPage: 5, preferHorizontal: true, isFinalAttempt: false)
        #expect(book.pageBarReady)

        let persistence = ReadiumProgressPersistence()
        persistence.seed(persistedLocatorString: try #require(initial.persistenceString))
        defer { persistence.cancelTrailingWrite() }
        var writes: [String] = []
        persistence.onDebouncedWrite = { writes.append($0) }
        // Same wiring as ReadiumReaderView.openBook, including the real debounce.
        book.onLocatorChange = { locator in
            guard let string = locator.persistenceString else { return }
            persistence.note(locatorString: string, totalProgression: locator.locations.totalProgression)
        }

        book.updatePageBoxGeometry(size: CGSize(width: 951, height: 678), safeInsets: .zero)
        #expect(book.pageBoxRemeasureTask != nil)
        let moved = initial.copy(locations: {
            $0.progression = 0.6
            $0.totalProgression = 0.62
        })
        book.navigator(source, locationDidChange: moved)
        #expect(book.currentLocator == moved)
        // Compare positions, not strings: the stored form can carry the media type.
        #expect(Self.progression(persistence.latestLocatorString) == 0.6)
        #expect(writes.map { Self.progression($0) } == [0.6])

        // A second callback inside the write window still reaches a close or
        // background flush immediately, even though its streamed write waits.
        let latest = moved.copy(locations: {
            $0.progression = 0.7
            $0.totalProgression = 0.72
        })
        book.navigator(source, locationDidChange: latest)
        #expect(book.currentLocator == latest)
        #expect(Self.progression(persistence.latestLocatorString) == 0.7)
        #expect(writes.map { Self.progression($0) } == [0.6])
        #expect(Self.progression(persistence.locatorForFlush()) == 0.7)
        await book.pageBoxRemeasureTask?.value
        #expect(book.currentLocator == latest)
    }

    /// No production navigation seam is needed for a deleted call. Check the
    /// resize dispatch itself; the delegate-only fake cannot observe SDK calls.
    @Test func resizeDoesNotIssueARestoreGoTo() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift"),
            encoding: .utf8
        )
        let start = try #require(source.range(of: "func updatePageBoxGeometry("))
        let end = try #require(source.range(
            of: "func cancelPageBoxRemeasure()", range: start.upperBound..<source.endIndex
        ))
        let resize = source[start.lowerBound..<end.lowerBound]
        #expect(!resize.contains("go(to:"))
        #expect(!resize.contains("markFirstPagePresentedIfNeeded"))
        #expect(!source.contains("pageBoxResizeLocator"))
    }

    @Test func finalLayoutAttemptKeepsItsFallbackButVerticalShrinkStillNeedsAgreement() {
        let book = ReadiumBook()
        book.acceptLayoutPageCount(8, measuredPage: 3, preferHorizontal: false, isFinalAttempt: false)
        #expect(!book.pageBarReady)
        book.acceptLayoutPageCount(24, measuredPage: 3, preferHorizontal: false, isFinalAttempt: true)
        #expect(book.pageBarReady)
        #expect(book.visualPageCount == 24)
        book.acceptLayoutPageCount(8, measuredPage: 3, preferHorizontal: false, isFinalAttempt: true)
        #expect(book.visualPageCount == 24)
        book.acceptLayoutPageCount(8, measuredPage: 3, preferHorizontal: false, isFinalAttempt: true)
        #expect(book.visualPageCount == 8)
    }

    @Test func aSameSizeInsetChangeSchedulesButStatusBarHideDoesNot() async {
        let book = ReadiumBook()
        let size = CGSize(width: 466, height: 678)
        let safe = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        book.updatePageBoxGeometry(size: size, safeInsets: safe)
        await book.pageBoxRemeasureTask?.value
        book.updatePageBoxGeometry(
            size: size, safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        )
        #expect(book.pageBoxRemeasureTask == nil)
        #expect(book.pageBoxChromeSafeTop == 62)
        // The first showing-chrome layout can precede UIKit restoring its inset.
        book.chromeHidden = false
        book.updatePageBoxGeometry(
            size: size, safeInsets: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        )
        #expect(book.pageBoxRemeasureTask == nil)
        #expect(book.pageBoxChromeSafeTop == 62)
        book.updatePageBoxGeometry(
            size: size, safeInsets: UIEdgeInsets(top: 62, left: 48, bottom: 34, right: 62)
        )
        #expect(book.pageBoxRemeasureTask != nil)
        book.cancelPageBoxRemeasure()
        #expect(book.pageBoxRemeasureTask == nil)
    }

    @Test func startupInsetSettlingDoesNotSwallowOrdinaryPageTurns() async throws {
        let book = ReadiumBook()
        let source = GeometryTestNavigator()
        let size = CGSize(width: 402, height: 874)
        book.updatePageBoxGeometry(size: size, safeInsets: .zero)
        await book.pageBoxRemeasureTask?.value
        let href = try #require(AnyURL(string: "OEBPS/chapter1.xhtml"))
        let initial = Locator(href: href, mediaType: .xhtml, locations: .init(progression: 0.25))
        book.navigator(source, locationDidChange: initial)
        #expect(book.hasPresentedFirstPage)
        #expect(!book.pageBarReady)

        // A later host report supplies the Island/home-bar insets. No rotation
        // has occurred and the opening viewport has not yet been measured.
        book.updatePageBoxGeometry(
            size: size, safeInsets: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        )
        #expect(book.pageBoxRemeasureTask != nil)
        var recorded: [Locator] = []
        book.onLocatorChange = { recorded.append($0) }
        let thirdPage = initial.copy(locations: { $0.progression = 0.5 })
        let fourthPage = initial.copy(locations: { $0.progression = 0.75 })
        book.navigator(source, locationDidChange: thirdPage)
        book.navigator(source, locationDidChange: fourthPage)
        #expect(book.currentLocator == fourthPage)
        #expect(recorded == [thirdPage, fourthPage])
        await book.pageBoxRemeasureTask?.value
        #expect(book.pageBoxRemeasureTask == nil)

        // The opening schedule can expire without a usable web-view sample.
        // The next same-href settle must schedule a full measurement, not take
        // the ready-only digit path or keep waiting for a chapter change.
        let generation = book.pageBarMeasureGeneration
        book.navigator(source, locationDidChange: fourthPage)
        #expect(book.pageBarMeasureGeneration > generation)
        #expect(book.currentLocator == fourthPage)
        book.acceptLayoutPageCount(4, measuredPage: 4, preferHorizontal: true, isFinalAttempt: false)
        #expect(!book.pageBarReady)
        // Another settle may replace the retry schedule, but must preserve the
        // first agreeing sample so continuous navigation can still become ready.
        book.navigator(source, locationDidChange: fourthPage)
        book.acceptLayoutPageCount(4, measuredPage: 4, preferHorizontal: true, isFinalAttempt: false)
        #expect(book.pageBarReady)
        #expect(book.visualPage == 4)
        #expect(book.visualPageCount == 4)

        // Once ready, an ordinary turn still uses the existing digit refresh.
        let readyGeneration = book.pageBarMeasureGeneration
        book.navigator(source, locationDidChange: thirdPage)
        #expect(book.currentLocator == thirdPage)
        #expect(book.pageBarReady)
        #expect(book.visualPageCount == 4)
        #expect(book.pageBarMeasureGeneration == readyGeneration)
    }

}

/// Delegate input only: no web view, publication load, or network request.
private final class GeometryTestNavigator: @preconcurrency Navigator {
    let publication = Publication(manifest: Manifest())
    var currentLocation: Locator? { nil }
    func go(to locator: Locator, options: NavigatorGoOptions) async -> Bool { false }
    func go(to link: ReadiumShared.Link, options: NavigatorGoOptions) async -> Bool { false }
    func goForward(options: NavigatorGoOptions) async -> Bool { false }
    func goBackward(options: NavigatorGoOptions) async -> Bool { false }
}
#endif
