import OSLog
import SwiftData
import SwiftUI
#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import UIKit
import WebKit
#endif

/// Platform router for the book reader. iOS/iPadOS use the new Readium navigator;
/// macOS keeps the legacy WKWebView reader, because Readium's navigator is a
/// `UIViewController` (UIKit) and has no AppKit/`NSViewController` form — see the
/// macOS note in the Phase 2 summary. Both call sites use this so the choice is
/// made in one place.
struct BookReaderView: View {
    let work: SavedWork

    var body: some View {
        #if os(iOS)
        ReadiumReaderView(work: work)
        #else
        ReaderView(work: work)
        #endif
    }
}

#if os(iOS)

/// Owns a Readium `EPUBNavigatorViewController` for one work: opens the EPUB,
/// builds the navigator, applies preferences live, and reports position + taps.
@Observable
@MainActor
final class ReadiumBook: NSObject, EPUBNavigatorDelegate {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    /// Flat table of contents (falls back to the reading order / spine).
    private(set) var toc: [ReadiumShared.Link] = []
    /// The full spine, in reading order — kept so synthesized `ReaderSection`s
    /// (e.g. AO3's un-navigable Summary page) can still be navigated to via
    /// `go(toSpineIndex:)`, not just the entries `toc` itself lists.
    private(set) var readingOrder: [ReadiumShared.Link] = []
    /// `toc`/`readingOrder` reconciled into AO3-aware sections (Preface/Summary/
    /// Chapter/Afterword), one per spine item. See `ReaderSection`.
    private(set) var sections: [ReaderSection] = []
    private(set) var currentLocator: Locator?
    /// Whether the viewport's trailing edge rests at the very end of the final
    /// reading-order resource — the only state that may auto-finish a work.
    /// See `ReadiumReaderCompletion`. Kept as a boolean (not the full viewport)
    /// so scroll-driven viewport updates don't thrash `@Observable` dependents
    /// on every settle.
    private(set) var isAtPublicationEnd = false
    private(set) var navigator: EPUBNavigatorViewController?
    /// Kept so Find in Work can drive Readium's own search service; the navigator
    /// does not expose the publication it was built from.
    private(set) var publication: Publication?

    /// The reader's own selection-menu entries, alongside Readium's defaults.
    /// The selectors must match `ReaderHighlightHostController`'s, which is what
    /// actually receives them off the responder chain.
    static let selectionEditingActions: [EditingAction] = EditingAction.defaultActions + [
        EditingAction(title: "Highlight",
                      action: #selector(ReaderHighlightHostController.kudosHighlightSelection(_:))),
        EditingAction(title: "Add Note",
                      action: #selector(ReaderHighlightHostController.kudosAddNoteToSelection(_:)))
    ]

    /// The text the reader currently has selected, if any.
    var currentSelection: Selection? {
        navigator?.currentSelection
    }

    func clearSelection() {
        navigator?.clearSelection()
    }

    /// Draws the given highlights over the page. Replaces the whole group each
    /// time, which is how Readium's decoration API is meant to be driven — it
    /// diffs internally, so re-applying an unchanged list is cheap.
    func applyHighlightDecorations(_ decorations: [Decoration]) {
        Task { @MainActor in
            await navigator?.apply(decorations: decorations, in: Self.highlightDecorationGroup)
        }
    }

    /// Registers a tap handler for highlight decorations. Call once per open
    /// book; Readium appends callbacks, so we gate on `highlightTapsInstalled`.
    /// `onActivate` receives the decoration id (the annotation's UUID string).
    func observeHighlightTaps(onActivate: @escaping (String) -> Void) {
        guard !highlightTapsInstalled, let navigator else { return }
        highlightTapsInstalled = true
        navigator.observeDecorationInteractions(inGroup: Self.highlightDecorationGroup) { event in
            onActivate(event.decoration.id)
        }
    }

    static let highlightDecorationGroup = "kudos-highlights"
    /// Ensures `observeHighlightTaps` only registers once per navigator lifetime.
    private var highlightTapsInstalled = false
    /// Readium's static position list grouped by reading-order item (chapter).
    /// Used for time estimates and persistence — **not** for the "Page X of Y"
    /// label (that is swipe screens only; see `visualPage` / `pageBarReady`).
    private(set) var positionsByReadingOrder: [[Locator]] = []
    /// Swipe-scale page digit (1-based). Only meaningful when `pageBarReady`.
    private(set) var visualPage: Int?
    /// Swipe-scale page count for the current resource. Only when `pageBarReady`.
    private(set) var visualPageCount: Int?
    /// Bottom bar "Page X of Y" is hidden until the first accepted swipe-scale
    /// measure. Prevents the thrash: position-list (2/13) → visual (6/103).
    private(set) var pageBarReady = false
    /// Cancels in-flight open remeasures when chapter/resource changes.
    private var pageBarMeasureGeneration = 0
    /// Retained WKScriptMessageHandler for live swipe updates after ready.
    private let visualPageBridge = VisualPageMessageBridge()
    /// True while swipe-down dismiss is freezing the page. Freeze mutates scroll
    /// offsets (and can hide WebKit under a snapshot); those side-effects must
    /// not rewrite `currentLocator`, visual page metrics, or durable progress.
    private(set) var isDismissInteractionActive = false
    /// Latched on a successful drag-to-dismiss until this book is deallocated.
    /// Survives unfreeze / late WebKit settles so exit flush cannot re-record a
    /// freeze- or TTS-corrupted locator after the pre-exit snapshot.
    private(set) var isDismissExitLatched = false
    /// Locator / visual / viewport ingestion is blocked for the freeze *and*
    /// the entire successful-exit teardown window.
    var isLocatorIngestionBlocked: Bool {
        isDismissInteractionActive || isDismissExitLatched
    }
    /// Toggled by tapping the page; the view hides/shows its chrome on this.
    var chromeHidden = false

    /// The body's rendered line height in points — font size × the line-height
    /// multiplier, mirrored from the view's `ReaderTextStyle` whenever
    /// preferences are submitted. `navigatorContentInset` uses it to end the
    /// paged page box on a whole line; it must track the *effective* style
    /// (`.resolved`), since the Customize toggle can override the multiplier.
    var renderedLineHeightPoints: Double =
        ReaderTextStyle.defaultFontSizePt * ReaderTextStyle.defaultLineHeight

    /// Effective page margin (pt) from Customize / defaults — same value fed to
    /// Readium `pageMargins` (horizontal CSS gutters only; vertical page box
    /// uses frozen window safe area + line-height snap, not this field).
    var renderedPageMarginPoints: Double = ReaderTextStyle.defaultMargin

    /// Frozen window geometry for the page box. Updated on real size changes
    /// (rotation / multitasking), **not** on chrome show/hide (status bar
    /// hide would otherwise grow the box and thrash swipe pageCount).
    private var frozenPageBoxViewHeight: CGFloat = 0
    private var frozenPageBoxSafeTop: CGFloat = 0
    private var frozenPageBoxSafeBottom: CGFloat = 0

    /// Safe-area top used for floating chrome (close / fan). Prefer frozen page-box
    /// values so chrome and text share one geometry source; fall back to live
    /// window insets until the first freeze (navigator not ready yet).
    var pageBoxChromeSafeTop: CGFloat {
        frozenPageBoxSafeTop > 0 ? frozenPageBoxSafeTop : Self.liveWindowSafeArea.top
    }
    var pageBoxChromeSafeBottom: CGFloat {
        frozenPageBoxSafeBottom > 0 ? frozenPageBoxSafeBottom : Self.liveWindowSafeArea.bottom
    }

    /// Seed freeze from the key window before the navigator's first inset query
    /// (chrome can render while still `.loading`).
    func seedPageBoxGeometryFromWindowIfNeeded() {
        let safe = Self.liveWindowSafeArea
        let height = UIScreen.main.bounds.height
        refreshFrozenPageBoxGeometry(
            viewHeight: height, safeTop: safe.top, safeBottom: safe.bottom
        )
    }

    private static var liveWindowSafeArea: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        return window?.safeAreaInsets ?? .zero
    }

    /// Fires on every position change. The view records this for the progress
    /// pill and feeds a debounced persistence path — it must not force a
    /// SwiftData save on every call (scrolled-mode hang). Completion is
    /// signaled separately by `onReachedPublicationEnd`.
    var onLocatorChange: ((Locator) -> Void)?
    /// Fires once each time the viewport newly reaches the publication's true
    /// end (`ReadiumReaderCompletion.isAtEnd`) — used to auto-finish completed
    /// works. Never fired for intermediate progressions such as 0.99/0.999.
    var onReachedPublicationEnd: (() -> Void)?
    /// Hands web links in EPUB content to the app's in-app Browse tab.
    var onOpenExternalURL: ((URL) -> Void)?

    /// Fraction through the whole publication (0...1), when known.
    var totalProgression: Double? {
        currentLocator?.locations.totalProgression
    }

    /// A compact reading position for the progress pill: overall percent, chapter
    /// place, and **swipe-scale** page within the chapter (never ~1KB positions
    /// as "Page X of Y" — that was the "2 of 13 vs 6 of 103" bug).
    struct ReadingPosition: Equatable {
        let percent: Int
        let chapter: Int
        let chapterCount: Int
        let page: Int
        let pageCount: Int
        /// False until the first accepted swipe-scale measure — UI hides "Page X of Y".
        let pageBarReady: Bool
    }

    var readingPosition: ReadingPosition? {
        guard let locator = currentLocator else { return nil }
        let percent = Int(((locator.locations.totalProgression ?? 0) * 100).rounded())
        let chapterIndex: Int = {
            if let globalPos = locator.locations.position,
               !positionsByReadingOrder.isEmpty,
               let idx = positionsByReadingOrder.firstIndex(where: { chapter in
                   guard let first = chapter.first?.locations.position,
                         let last = chapter.last?.locations.position else { return false }
                   return globalPos >= first && globalPos <= last
               }) {
                return idx
            }
            let key = ReaderSectionBuilder.hrefKey(locator.href.string)
            if let idx = readingOrder.firstIndex(where: {
                ReaderSectionBuilder.hrefKey($0.href) == key
            }) {
                return idx
            }
            return 0
        }()
        let chapterCount = max(
            1,
            positionsByReadingOrder.isEmpty ? readingOrder.count : positionsByReadingOrder.count
        )

        // Single source for the page line: swipe metrics only, atomic with ready.
        // Prefer live visual digit (1:1 with swipe) once we have it; progression
        // only when visual is missing (first layout publish). Forcing progression
        // over live JS on every locator settle caused next/back digit snap.
        if pageBarReady,
           let vCount = visualPageCount, vCount > 0 {
            let page: Int = {
                if let vPage = visualPage {
                    return min(vCount, max(1, vPage))
                }
                if let prog = locator.locations.progression, prog.isFinite, vCount > 1 {
                    return ReaderPageMetrics.page(progression: prog, pageCount: vCount)
                }
                return 1
            }()
            return ReadingPosition(
                percent: percent,
                chapter: chapterIndex + 1,
                chapterCount: chapterCount,
                page: page,
                pageCount: vCount,
                pageBarReady: true
            )
        }

        // Chapter / percent only — no fake position-list "Page 2 of 13".
        return ReadingPosition(
            percent: percent,
            chapter: chapterIndex + 1,
            chapterCount: chapterCount,
            page: 1,
            pageCount: 1,
            pageBarReady: false
        )
    }

    /// Clears swipe-scale bar metrics (open / chapter change). Bumps generation
    /// so in-flight remeasures cannot publish for a previous resource.
    fileprivate func clearVisualPageMetrics() {
        pageBarMeasureGeneration += 1
        pageDigitRefreshGeneration += 1
        visualPage = nil
        visualPageCount = nil
        pageBarReady = false
        pendingLayoutPageCount = nil
        pendingLayoutAgrees = 0
        pendingVerticalShrinkCount = nil
        pendingVerticalShrinkAgrees = 0
        // Covers the front-loaded remeasure ticks plus headroom so neighbor
        // touch-armed posts can't fight the opening measure. Kept in step with
        // `schedulePageBarRemeasure`'s schedule — an over-long mute also
        // swallows live scroll updates for that whole window, which is half of
        // why the bar felt slow to come alive after a chapter turn.
        userScrollMuteUntil = Date().addingTimeInterval(1.0)
    }

    /// Suppresses touch-scroll bar updates after chapter/open clear.
    private var userScrollMuteUntil: Date = .distantPast
    /// True while the reader drags the position slider. Live seek fires a
    /// `go(to:)` per page crossed, and each one lands a locator change — the
    /// 220 ms settle-digit refresh those would each schedule is pure waste
    /// mid-drag (the card reads the slider directly while scrubbing) and its
    /// late arrival is what made the digit flicker on release.
    var isScrubbing = false
    /// Debounces same-resource digit refresh Tasks (latest quiet window wins).
    private var pageDigitRefreshGeneration = 0
    /// Layout measures must agree twice before first publish (kills next/back snap).
    private var pendingLayoutPageCount: Int?
    private var pendingLayoutAgrees = 0
    /// Vertical pageCount shrink must agree twice before it's allowed (C3).
    private var pendingVerticalShrinkCount: Int?
    private var pendingVerticalShrinkAgrees = 0

    /// Publishes swipe-scale metrics **atomically**.
    fileprivate func publishPageBar(page: Int, pageCount: Int, allowShrink: Bool = false) {
        let pageCount = max(1, pageCount)
        let page = min(pageCount, max(1, page))
        if pageBarReady, let existing = visualPageCount, pageCount < existing, !allowShrink {
            return
        }
        guard visualPage != page || visualPageCount != pageCount || !pageBarReady else { return }
        visualPage = page
        visualPageCount = pageCount
        pageBarReady = true
        pendingLayoutPageCount = nil
        pendingLayoutAgrees = 0
    }

    /// Live swipe update from the JS bridge (touch-armed scroll only).
    /// Layout dual-agree owns the **first** publish; JS never first-publishes
    /// (neighbor/partial counts were a wrong-then-right snap on next/back).
    fileprivate func applyVisualPageFromUserScroll(page: Int, pageCount: Int) {
        guard !isLocatorIngestionBlocked else { return }
        guard Date() >= userScrollMuteUntil else { return }
        // First paint is layout-only. Until ready, ignore all scroll posts.
        guard pageBarReady, let known = visualPageCount, known > 0 else { return }
        let pageCount = max(1, pageCount)
        // Accept digit updates whose pageCount is within jitter tolerance of the
        // trusted layout count (continuous-scroll height noise — see the C4
        // comment in `acceptLayoutPageCount`) — a genuinely different count
        // (neighbor preload) still must not rewrite the bar. Publish under the
        // *trusted* `known` count, not the live-sampled one, so the "of N"
        // denominator stays stable while the user is mid-scroll instead of
        // flickering with the same noise.
        guard abs(pageCount - known) <= 1 else { return }
        let page = min(known, max(1, page))
        // Live swipe/scroll: trust settled JS digit 1:1 (do not snap to progression).
        publishPageBar(page: page, pageCount: known, allowShrink: false)
    }

    /// Approximate content size for rejecting early "1 page" pre-layout flashes.
    private var chapterPositionCountHint: Int {
        currentChapterPositions?.count ?? 0
    }

    /// Marks the swipe-down dismiss interaction. While active, locator + visual
    /// page updates from freeze side-effects are ignored so resume stays put.
    /// Clearing is a no-op once a successful exit is latched.
    func setDismissInteractionActive(_ active: Bool) {
        if !active && isDismissExitLatched { return }
        isDismissInteractionActive = active
    }

    /// Successful drag-dismiss: permanently block locator/visual/completion
    /// ingestion until this `ReadiumBook` is torn down with the view.
    func latchDismissExit() {
        isDismissExitLatched = true
        isDismissInteractionActive = true
    }

    /// Seeks within the current resource by progression (0…1). Used when the
    /// bottom slider is driven by visual page counts rather than position list.
    func goToProgressionInCurrentResource(_ progression: Double) {
        guard let locator = currentLocator else { return }
        let prog = min(1, max(0, progression))
        let target = locator.copy(locations: {
            $0.progression = prog
            // Clear discrete position so Readium honours progression.
            $0.position = nil
        })
        go(to: target)
    }

    /// Latest-wins seek for the live scrub. `go(to:)` spawns an unstructured
    /// `Task` per call, so firing one per page crossed let a fast drag pile up
    /// a queue of navigations that kept resolving *after* the finger moved on —
    /// the reader visibly lagged the thumb, and a late one could even land last
    /// and leave the wrong page showing. This keeps at most one navigation in
    /// flight and always redirects it to the newest thumb position, so cost
    /// stays flat no matter how fast the drag is.
    func scrubToProgressionInCurrentResource(_ progression: Double) {
        pendingScrubProgression = min(1, max(0, progression))
        guard !isScrubSeekInFlight else { return }
        isScrubSeekInFlight = true
        Task { @MainActor [weak self] in
            defer { self?.isScrubSeekInFlight = false }
            while let self, let next = self.pendingScrubProgression {
                self.pendingScrubProgression = nil
                guard let locator = self.currentLocator else { return }
                let target = locator.copy(locations: {
                    $0.progression = next
                    $0.position = nil
                })
                await self.navigator?.go(to: target, options: NavigatorGoOptions())
            }
        }
    }

    private var isScrubSeekInFlight = false
    private var pendingScrubProgression: Double?

    /// The current chapter's Readium positions, in reading order — the slider's
    /// seek targets (`positionsByReadingOrder[chapterIndex]`).
    var currentChapterPositions: [Locator]? {
        guard let locator = currentLocator else { return nil }
        let chapterIndex: Int = {
            if let globalPos = locator.locations.position,
               !positionsByReadingOrder.isEmpty,
               let idx = positionsByReadingOrder.firstIndex(where: { chapter in
                   guard let first = chapter.first?.locations.position,
                         let last = chapter.last?.locations.position else { return false }
                   return globalPos >= first && globalPos <= last
               }) {
                return idx
            }
            let key = ReaderSectionBuilder.hrefKey(locator.href.string)
            return readingOrder.firstIndex(where: {
                ReaderSectionBuilder.hrefKey($0.href) == key
            }) ?? 0
        }()
        guard positionsByReadingOrder.indices.contains(chapterIndex) else { return nil }
        return positionsByReadingOrder[chapterIndex]
    }

    /// Remaining content for time estimates. When visual pages are live, chapter
    /// remaining is scaled from visual pages onto the chapter's position count
    /// so "min left" still reflects content, not an inflated visual page total.
    var remainingPositions: (chapter: Int, work: Int)? {
        guard let pos = readingPosition else { return nil }
        let totalPositions = positionsByReadingOrder.reduce(0) { $0 + $1.count }
        let workRemaining = ReaderPageMetrics.workRemainingPositions(
            globalPosition: currentLocator?.locations.position,
            totalPositions: totalPositions
        )
        let chapterRemaining: Int = {
            if pageBarReady, visualPage != nil, visualPageCount != nil,
               let chapterPositions = currentChapterPositions, !chapterPositions.isEmpty {
                return ReaderPageMetrics.chapterRemainingPositions(
                    page: pos.page,
                    pageCount: pos.pageCount,
                    chapterPositionCount: chapterPositions.count
                )
            }
            // Before page bar is ready, estimate from position list if available.
            if let chapterPositions = currentChapterPositions, !chapterPositions.isEmpty,
               let globalPos = currentLocator?.locations.position,
               let first = chapterPositions.first?.locations.position {
                let page = min(chapterPositions.count, max(1, globalPos - first + 1))
                return max(0, chapterPositions.count - page)
            }
            return 0
        }()
        return (chapter: chapterRemaining, work: workRemaining)
    }

    /// Opens the work's EPUB and builds the navigator at `initialLocator` with the
    /// given configuration (preferences + custom-font declarations). The file
    /// already lives in the app sandbox, so (unlike the POC) it's opened in place.
    /// `fallbackSpineIndex` migrates legacy progress: when there's no saved Readium
    /// `Locator`, resume at the start of that reading-order item (the work's last
    /// chapter from the old WKWebView reader). Intra-chapter offset isn't recovered.
    func open(fileURL: URL, initialLocator: Locator?, fallbackSpineIndex: Int? = nil,
              config: EPUBNavigatorViewController.Configuration) async {
        phase = .loading
        // Drop previous work's locator/metrics so the position card never shows
        // another book's last page while this EPUB is still opening.
        currentLocator = nil
        clearVisualPageMetrics()
        isDismissInteractionActive = false
        isDismissExitLatched = false
        do {
            let publication = try await ReadiumPublicationLoader.openEPUB(at: fileURL)
            var initial = initialLocator
            if initial == nil, let index = fallbackSpineIndex,
               publication.readingOrder.indices.contains(index) {
                initial = await publication.locate(publication.readingOrder[index])
            }
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initial,
                config: config
            )
            navigator.delegate = self
            let tocLinks = await (try? publication.tableOfContents().get()) ?? []
            self.navigator = navigator
            self.publication = publication
            visualPageBridge.book = self
            clearVisualPageMetrics()
            highlightTapsInstalled = false
            readingOrder = publication.readingOrder
            toc = tocLinks.isEmpty ? readingOrder : tocLinks
            positionsByReadingOrder = await (try? publication.positionsByReadingOrder().get()) ?? []
            sections = Self.buildSections(toc: toc, readingOrder: readingOrder)
            // Seed locator for chapter/percent; page line waits for swipe-scale measure.
            if let initial {
                currentLocator = initial
            }
            phase = .ready
            // Single owner of open pageCount: delayed WKWebView measures.
            schedulePageBarRemeasure()
            Log.epub.info("Opened EPUB (Readium): \(self.toc.count) TOC entries")
        } catch {
            phase = .failed(error.localizedDescription)
            Log.epub.error("Couldn't open EPUB (Readium): \(error.localizedDescription, privacy: .public)")
        }
    }

    func submit(_ preferences: EPUBPreferences) {
        navigator?.submitPreferences(preferences)
    }

    func goForward() {
        Task { @MainActor in await navigator?.goForward() }
    }

    func goBackward() {
        Task { @MainActor in await navigator?.goBackward() }
    }

    func go(to link: ReadiumShared.Link) {
        Task { @MainActor in await navigator?.go(to: link) }
    }

    /// Navigates directly to a `Locator` — used by the position card's slider to
    /// seek within the current chapter's Readium positions.
    func go(to locator: Locator) {
        Task { @MainActor in await navigator?.go(to: locator, options: NavigatorGoOptions()) }
    }

    /// Navigates to a spine position directly — needed for `ReaderSection`s (like
    /// AO3's synthesized Summary) that have no TOC `Link` of their own to pass to
    /// `go(to:)`.
    func go(toSpineIndex index: Int) {
        guard readingOrder.indices.contains(index) else { return }
        go(to: readingOrder[index])
    }

    /// Resolves `toc`'s `Link`s to spine indices (by href, fragment/path-insensitive)
    /// and reconciles them against the full `readingOrder` into normalized sections.
    private static func buildSections(
        toc: [ReadiumShared.Link],
        readingOrder: [ReadiumShared.Link]
    ) -> [ReaderSection] {
        let spineHrefs = readingOrder.map(\.href)
        let spineKeys = spineHrefs.map(ReaderSectionBuilder.hrefKey)
        let rawTOC: [ReaderSectionBuilder.RawTOCEntry] = toc.compactMap { link in
            let key = ReaderSectionBuilder.hrefKey(link.href)
            guard let spineIndex = spineKeys.firstIndex(of: key) else { return nil }
            return ReaderSectionBuilder.RawTOCEntry(
                title: link.title ?? "Section \(spineIndex + 1)",
                spineIndex: spineIndex
            )
        }
        return ReaderSectionBuilder.build(tocEntries: rawTOC, spineHrefs: spineHrefs)
    }

    // MARK: EPUBNavigatorDelegate

    func navigator(_: Navigator, locationDidChange locator: Locator) {
        // Freeze `setContentOffset` / hide-under-snapshot can emit spurious
        // location settles. Ignoring them keeps `currentLocator` (and flush)
        // at the pre-gesture reading position. Exit latch keeps the gate up
        // through successful dismiss teardown so a late settle cannot corrupt
        // the flushed resume point.
        guard !isLocatorIngestionBlocked else { return }
        let previousHref = currentLocator.map { ReaderSectionBuilder.hrefKey($0.href.string) }
        let newHref = ReaderSectionBuilder.hrefKey(locator.href.string)
        if previousHref != newHref {
            // Chapter / resource turn: hide page line until the new resource is
            // measured twice. Do not rewrite digits from intermediate locators.
            clearVisualPageMetrics()
            schedulePageBarRemeasure()
        } else if pageBarReady, !isScrubbing {
            // Same-resource settle (edge tap / goForward / programmatic seek):
            // touch-armed JS may never fire. Refresh digit from the primary
            // webview scroll position after a short quiet window — never from
            // progression alone (mid-animation progression was the old snap).
            // Skipped mid-scrub: the slider is the source of truth there, and a
            // refresh landing after release is what briefly showed a stale page.
            scheduleSettledPageDigitRefresh()
        }
        currentLocator = locator
        // Mid-scrub locator settles are transient — the reader is flying past
        // these pages, not reading them. `currentLocator` still advances (so a
        // dismiss mid-drag flushes the right spot), but the debounced progress
        // write is skipped until release, which commits the final position.
        guard !isScrubbing else { return }
        onLocatorChange?(locator)
    }

    /// One-shot digit refresh after same-resource navigation settles. Debounced
    /// so rapid locator settles only apply the last quiet sample; only updates
    /// page when pageCount still matches the trusted layout count.
    private func scheduleSettledPageDigitRefresh() {
        // Chapter-turn mute: layout schedule owns the bar; skip digit races.
        guard Date() >= userScrollMuteUntil else { return }
        pageDigitRefreshGeneration += 1
        let refreshGen = pageDigitRefreshGeneration
        let barGen = pageBarMeasureGeneration
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self else { return }
            guard self.pageDigitRefreshGeneration == refreshGen else { return }
            guard self.pageBarMeasureGeneration == barGen else { return }
            guard self.pageBarReady, !self.isLocatorIngestionBlocked else { return }
            guard Date() >= self.userScrollMuteUntil else { return }
            await self.remeasureAndPublishBest(
                generation: barGen, isFinalAttempt: false, digitOnly: true
            )
        }
    }

    /// Delayed swipe-scale measures at **absolute** times from schedule start
    /// (0.5 / 1.0 / 1.6s), not sequential sleeps that stacked to ~3.1s and outran
    /// the user-scroll mute. Each tick is independent so a cancelled gen aborts
    /// only that tick's publish. If the fixed schedule still hasn't reached
    /// dual-agree by the last tick, keep retrying on a slower cadence (bounded)
    /// rather than ever unmasking an unconfirmed count (C4) — a late-but-correct
    /// digit beats an early-but-wrong one.
    fileprivate func schedulePageBarRemeasure() {
        let gen = pageBarMeasureGeneration
        // Front-loaded: dual-agree needs two ticks, so the *second* delay is
        // when the bar can first appear — at the old 0.5/1.0/1.6 spacing that
        // was a full second of "Page …" even on a fast device, which read as
        // sluggish. 250/450 gets the same two samples in well under half that
        // while the later, wider-spaced ticks still catch a slow first layout.
        scheduleRemeasureTicks(
            generation: gen, delaysMs: [250, 450, 750, 1200, 1700], continuationsRemaining: 3
        )
    }

    /// `isFinalAttempt` (passed to `acceptLayoutPageCount`) means "last tick of
    /// the whole bounded sequence" — it still lets a stale single-page hint
    /// (C5) be overridden on the very last try. It must **not** bypass the
    /// dual-agree requirement itself (C4); that gate is unconditional in
    /// `acceptLayoutPageCount` regardless of this flag.
    private func scheduleRemeasureTicks(generation: Int, delaysMs: [UInt64], continuationsRemaining: Int) {
        for (index, delayMs) in delaysMs.enumerated() {
            let isLastInBatch = index == delaysMs.count - 1
            let isFinal = isLastInBatch && continuationsRemaining == 0
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                guard let self else { return }
                guard self.pageBarMeasureGeneration == generation else { return }
                guard !self.isLocatorIngestionBlocked else { return }
                await self.remeasureAndPublishBest(generation: generation, isFinalAttempt: isFinal)
                guard isLastInBatch, !self.pageBarReady, continuationsRemaining > 0 else { return }
                self.scheduleRemeasureTicks(
                    generation: generation, delaysMs: [1000], continuationsRemaining: continuationsRemaining - 1
                )
            }
        }
    }

    private struct WebViewPageSample {
        let pageCount: Int
        let page: Int
        let horizontal: Bool
        let area: CGFloat
    }

    private func remeasureAndPublishBest(
        generation: Int,
        isFinalAttempt: Bool,
        digitOnly: Bool = false
    ) async {
        guard pageBarMeasureGeneration == generation else { return }
        guard let root = navigator?.view else { return }
        // Readium preloads neighboring spreads as full-size, non-hidden WKWebViews.
        // Taking max pageCount across them published the *longest loaded chapter*
        // (e.g. 103) while reading a short one. Measure only the web view that
        // actually intersects the navigator viewport the most — and only if it
        // covers a real majority of the root (mid-turn co-visible preload must
        // not dual-agree as primary then get corrected later).
        let rootBounds = root.bounds
        let rootArea = max(1, rootBounds.width * rootBounds.height)
        let candidates = Self.allWKWebViews(in: root).compactMap { web -> (WKWebView, CGFloat)? in
            guard web.bounds.width > 32, web.bounds.height > 32,
                  !web.isHidden, web.alpha > 0.01
            else { return nil }
            let frameInRoot = web.convert(web.bounds, to: root)
            let intersection = frameInRoot.intersection(rootBounds)
            guard !intersection.isNull, intersection.width > 32, intersection.height > 32
            else { return nil }
            let visibleArea = intersection.width * intersection.height
            // Require majority coverage so a half-slid neighbor never wins primary.
            guard visibleArea >= rootArea * 0.55 else { return nil }
            return (web, visibleArea)
        }
        // Only the single most-visible majority web view.
        let ranked = candidates.sorted { $0.1 > $1.1 }
        guard let primary = ranked.first else { return }
        let webViewsToSample = [primary.0]

        // pageCount + scroll-derived page from the same sample so first unmask
        // is not progression-mapped (progression ≠ CSS page boxes → snap).
        let js = """
        (function() {
            var se = document.scrollingElement || document.documentElement;
            if (!se) return null;
            var vw = Math.max(1, window.innerWidth || 1);
            var vh = Math.max(1, window.innerHeight || 1);
            var scrollW = se.scrollWidth || vw;
            var scrollH = se.scrollHeight || vh;
            var x = Math.abs(window.scrollX || se.scrollLeft || 0);
            var y = window.scrollY || se.scrollTop || 0;
            var horizontal = scrollW > vw * 1.15;
            var page, pageCount;
            if (horizontal) {
                pageCount = Math.max(1, Math.round(scrollW / vw));
                page = Math.min(pageCount, Math.max(1, Math.round(x / vw) + 1));
            } else {
                pageCount = Math.max(1, Math.round(scrollH / vh));
                page = Math.min(pageCount, Math.max(1, Math.round(y / vh) + 1));
            }
            return { pageCount: pageCount, page: page, horizontal: horizontal };
        })();
        """

        var samples: [WebViewPageSample] = []
        for webView in webViewsToSample {
            let area = webView.bounds.width * webView.bounds.height
            if let sample = await Self.evaluatePageSample(webView: webView, js: js, area: area) {
                samples.append(sample)
            }
        }
        guard pageBarMeasureGeneration == generation else { return }
        guard !samples.isEmpty else { return }

        // Among *visible* webviews only: prefer horizontal, then larger count.
        let bestHorizontal = samples.filter(\.horizontal).max(by: { $0.pageCount < $1.pageCount })
        let bestAny = samples.max(by: {
            if $0.pageCount != $1.pageCount { return $0.pageCount < $1.pageCount }
            return $0.area < $1.area
        })
        guard let best = bestHorizontal ?? bestAny else { return }

        if digitOnly {
            // Settled same-resource refresh: digit only, trusted count must match.
            guard pageBarReady, let known = visualPageCount, known == best.pageCount else { return }
            publishPageBar(page: best.page, pageCount: known, allowShrink: false)
            return
        }

        acceptLayoutPageCount(
            best.pageCount,
            measuredPage: best.page,
            preferHorizontal: best.horizontal,
            isFinalAttempt: isFinalAttempt
        )
    }

    private static func evaluatePageSample(
        webView: WKWebView,
        js: String,
        area: CGFloat
    ) async -> WebViewPageSample? {
        await withCheckedContinuation { cont in
            webView.evaluateJavaScript(js) { result, _ in
                guard let dict = result as? [String: Any] else {
                    cont.resume(returning: nil)
                    return
                }
                let pageCount = (dict["pageCount"] as? Int)
                    ?? (dict["pageCount"] as? NSNumber)?.intValue
                let page = (dict["page"] as? Int)
                    ?? (dict["page"] as? NSNumber)?.intValue
                let horizontal = (dict["horizontal"] as? Bool)
                    ?? (dict["horizontal"] as? NSNumber)?.boolValue
                    ?? false
                guard let pageCount else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: WebViewPageSample(
                    pageCount: pageCount,
                    page: max(1, page ?? 1),
                    horizontal: horizontal,
                    area: area
                ))
            }
        }
    }

    /// Accept a layout-measured swipe pageCount. First-publish digit prefers the
    /// same-webview scroll `measuredPage` (not progression). Later ticks may
    /// refine count but must not reseed the digit from progression.
    private func acceptLayoutPageCount(
        _ pageCount: Int,
        measuredPage: Int?,
        preferHorizontal: Bool,
        isFinalAttempt: Bool
    ) {
        guard !isLocatorIngestionBlocked else { return }
        let pageCount = max(1, pageCount)
        // Reject single-page pre-layout on multi-position chapters until last try.
        if pageCount == 1, chapterPositionCountHint > 3, !isFinalAttempt {
            return
        }
        // Before ready: require two agreeing measures. Continuous-scroll layout
        // height can jitter by a pixel or two between reads (web-font swap,
        // async image load, WebKit sub-pixel rounding) in a way paginated/
        // CSS-column layout never does — two *bit-exact* matches could take
        // several ticks (feels sluggish) or, if the height keeps drifting by
        // ±1 forever, never arrive at all (page bar, and the seek slider that
        // stays disabled until `pageBarReady`, permanently dead). Treat counts
        // within 1 of each other as agreeing so real jitter converges on the
        // very first close pair instead of restarting the count every tick;
        // `isFinalAttempt` — true only once the whole bounded retry sequence in
        // `scheduleRemeasureTicks` (up to ~6s) is spent — remains as a last
        // resort for the rare case that doesn't even manage that.
        if !pageBarReady {
            if let pending = pendingLayoutPageCount, abs(pending - pageCount) <= 1 {
                pendingLayoutAgrees += 1
            } else {
                pendingLayoutAgrees = 1
            }
            pendingLayoutPageCount = pageCount
            if pendingLayoutAgrees < 2, !isFinalAttempt {
                return
            }
        }
        // Vertical shrink must never be one-shot (C3): an inflated Y count from
        // an early layout pass should not stick forever, but a single smaller
        // sample shouldn't overwrite it either — require the same dual-agree
        // shape used before first publish.
        let isVerticalShrinkCandidate = pageBarReady && !preferHorizontal
            && (visualPageCount.map { pageCount < $0 } ?? false)
        let allowShrink: Bool
        if pageBarReady, preferHorizontal, let existing = visualPageCount, pageCount != existing {
            allowShrink = abs(pageCount - existing) > max(2, existing / 10)
        } else if isVerticalShrinkCandidate {
            if pendingVerticalShrinkCount == pageCount {
                pendingVerticalShrinkAgrees += 1
            } else {
                pendingVerticalShrinkCount = pageCount
                pendingVerticalShrinkAgrees = 1
            }
            guard pendingVerticalShrinkAgrees >= 2 else { return }
            allowShrink = true
        } else {
            allowShrink = false
        }
        if !isVerticalShrinkCandidate {
            pendingVerticalShrinkCount = nil
            pendingVerticalShrinkAgrees = 0
        }
        // After ready: never reseed digit from progression and never proportionally
        // rescale when count grows (that was a wrong-page-then-correct snap).
        // Prefer a fresh scroll-measured page when count is unchanged; otherwise
        // clamp the live digit into the new count only.
        let page: Int = {
            if pageBarReady, let existingCount = visualPageCount, existingCount == pageCount,
               let measured = measuredPage {
                return min(pageCount, max(1, measured))
            }
            if pageBarReady, let vPage = visualPage {
                return min(pageCount, max(1, vPage))
            }
            // First publish: scroll-measured page from the same sample as count.
            if let measured = measuredPage {
                return min(pageCount, max(1, measured))
            }
            // Fallback only if evaluate omitted page (should be rare).
            if let prog = currentLocator?.locations.progression, prog.isFinite, pageCount > 1 {
                return ReaderPageMetrics.page(progression: prog, pageCount: pageCount)
            }
            return 1
        }()
        publishPageBar(page: page, pageCount: pageCount, allowShrink: allowShrink)
    }

    private static func allWKWebViews(in view: UIView) -> [WKWebView] {
        var result: [WKWebView] = []
        if let web = view as? WKWebView { result.append(web) }
        for sub in view.subviews {
            result.append(contentsOf: allWKWebViews(in: sub))
        }
        return result
    }

    /// True-end completion check only. Readium updates `viewport` with
    /// `currentLocation`; we derive a boolean and only publish it when the
    /// end state flips so scrolled settles don't invalidate SwiftUI for free.
    /// Rising-edge only for `onReachedPublicationEnd`.
    func navigator(_: any ViewportObservingNavigator, viewportDidChange viewport: NavigatorViewport?) {
        // Same freeze/exit gate as locator — dismiss must not flip completion.
        guard !isLocatorIngestionBlocked else { return }
        let atEnd = ReadiumReaderCompletion.isAtEnd(viewport: viewport, readingOrder: readingOrder)
        let wasAtEnd = isAtPublicationEnd
        if atEnd != wasAtEnd {
            isAtPublicationEnd = atEnd
        }
        if atEnd, !wasAtEnd {
            onReachedPublicationEnd?()
        }
    }

    /// The only delegate method without a default implementation.
    func navigator(_: Navigator, presentError error: NavigatorError) {
        phase = .failed(error.localizedDescription)
    }

    /// Readium's default implementation opens every external URL in the system
    /// browser. Keep HTTP(S) links inside Kudos, matching the legacy reader, while
    /// preserving the system behavior for schemes such as `mailto:`.
    func navigator(_: Navigator, presentExternalURL url: URL) {
        if !routeWebURLToBrowse(url) {
            UIApplication.shared.open(url)
        }
    }

    func navigator(_: VisualNavigator, didTapAt _: CGPoint) {
        chromeHidden.toggle()
    }

    /// Injects the one CSS safeguard Readium CSS has no preference for, matching
    /// what the legacy reader's own stylesheet already does (see
    /// `ReaderStylesheet.css`): let a "word" break only when it cannot fit on a
    /// line by itself.
    ///
    /// Without it a long unbreakable token — AO3 prose is full of them, e.g.
    /// `'Control...you...can't...ritual.'`, where ellipses join words with no
    /// break opportunity, plus bare URLs — overflows its page box horizontally,
    /// spills into the adjacent column, and leaves a fragment of itself visible
    /// on the following page.
    ///
    /// `overflow-wrap: break-word` leaves ordinary words intact; `word-break`
    /// would split them mid-character as a side effect, which is why the legacy
    /// stylesheet rejected it too. Applied at document level as a user script
    /// because `EPUBPreferences`/`CSSRSProperties` expose no equivalent knob.
    func navigator(_: EPUBNavigatorViewController, setupUserScripts controller: WKUserContentController) {
        let css = """
        html, body, p, div, span, li, blockquote, td, th, h1, h2, h3, h4, h5, h6, a {
            overflow-wrap: break-word;
        }
        """
        let overflowSource = """
        (function() {
            var id = 'kudos-overflow-guard';
            function inject() {
                if (!document.head || document.getElementById(id)) return;
                var style = document.createElement('style');
                style.id = id;
                style.textContent = \(Self.javaScriptStringLiteral(css));
                document.head.appendChild(style);
            }
            inject();
            // Readium swaps resources into the same web view, so a document that
            // had no <head> yet at injection time still gets the rule.
            document.addEventListener('DOMContentLoaded', inject);
        })();
        """
        controller.addUserScript(WKUserScript(
            source: overflowSource, injectionTime: .atDocumentStart, forMainFrameOnly: false
        ))

        // Live swipe updates only (touch-armed). Open pageCount comes solely from
        // Swift `scheduleVisualLayoutRemeasure` — no competing JS settle posts.
        controller.removeScriptMessageHandler(forName: VisualPageMessageBridge.handlerName)
        controller.add(visualPageBridge, name: VisualPageMessageBridge.handlerName)
        // Debounce to scroll settle (not first mid-animation sample). Throttle-on-
        // first was posting an intermediate page then the true page → bar snap.
        let visualPageSource = """
        (function() {
            if (window.__kudosVisualPageInstalled) return;
            window.__kudosVisualPageInstalled = true;
            var pending = null;
            var allowUntil = 0;
            var lastLiveSent = 0;
            var liveInterval = 100;
            function armUserGesture() {
                allowUntil = Date.now() + 900;
            }
            window.addEventListener('touchstart', armUserGesture, { passive: true, capture: true });
            window.addEventListener('pointerdown', armUserGesture, { passive: true, capture: true });
            function measure() {
                var se = document.scrollingElement || document.documentElement;
                if (!se) return null;
                var vw = Math.max(1, window.innerWidth || 1);
                var vh = Math.max(1, window.innerHeight || 1);
                var scrollW = se.scrollWidth || vw;
                var scrollH = se.scrollHeight || vh;
                var x = Math.abs(window.scrollX || se.scrollLeft || 0);
                var y = window.scrollY || se.scrollTop || 0;
                var horizontal = scrollW > vw * 1.15;
                var page, pageCount;
                if (horizontal) {
                    pageCount = Math.max(1, Math.round(scrollW / vw));
                    page = Math.min(pageCount, Math.max(1, Math.round(x / vw) + 1));
                } else {
                    pageCount = Math.max(1, Math.round(scrollH / vh));
                    page = Math.min(pageCount, Math.max(1, Math.round(y / vh) + 1));
                }
                return { page: page, pageCount: pageCount, fromUserScroll: true };
            }
            function post(m) {
                webkit.messageHandlers.\(VisualPageMessageBridge.handlerName).postMessage(m);
            }
            function reportFromScroll() {
                try {
                    if (Date.now() > allowUntil) return;
                    // Keep arm alive while the page-turn animation is scrolling so
                    // the settle sample after finger-up still posts.
                    allowUntil = Math.max(allowUntil, Date.now() + 280);
                    // Continuous-scroll mode needs *live* updates: a pure debounce
                    // (clearTimeout on every scroll event) never fires mid-gesture,
                    // so the bar sat frozen until the scroll stopped. Throttle a
                    // sample out at most every `liveInterval` ms while the finger
                    // moves. Paged mode deliberately stays debounce-only — there,
                    // an intermediate sample lands mid-page-turn-animation and was
                    // the original wrong-then-right digit snap.
                    var now = Date.now();
                    if (now - lastLiveSent >= liveInterval) {
                        var live = measure();
                        if (live && !live.horizontal) {
                            lastLiveSent = now;
                            post(live);
                        }
                    }
                    // Trailing settle sample (both modes) — the authoritative one.
                    if (pending) clearTimeout(pending);
                    pending = setTimeout(function() {
                        pending = null;
                        if (Date.now() > allowUntil) return;
                        var m = measure();
                        if (!m) return;
                        post(m);
                    }, 140);
                } catch (e) {}
            }
            window.addEventListener('scroll', reportFromScroll, { passive: true });
        })();
        """
        controller.addUserScript(WKUserScript(
            source: visualPageSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false
        ))
    }


    /// Encodes a string as a JavaScript literal via JSON, so quotes, newlines and
    /// backslashes in the CSS can't break out of it.
    private static func javaScriptStringLiteral(_ value: String) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "\"\""
    }

    /// Trims Readium's default reflowable content insets (the navigator treats
    /// iPhone portrait as the `.regular` vertical size class and reserves 62 pt
    /// top and bottom) and sizes the **paged** page box so the text band ends on
    /// a whole line for the current text size.
    ///
    /// Geometry rules (C2 — corrected for Readium CSS):
    /// 1. **One system source** — window safe area, frozen across chrome
    ///    show/hide so status-bar hide cannot grow the box mid-read.
    /// 2. **Vertical clearance = full frozen safe area** — first/last ink sit at
    ///    `contentInset` only. Readium `pageMargins` are **horizontal** only
    ///    (`padding: 0 calc(gutter × margins)` with our 1px gutter); they must
    ///    not be subtracted from safe top/bottom (that under-cleared the island).
    /// 3. **Customize padding** still matters: horizontal gutters via
    ///    `pageMargins` / `renderedPageMarginPoints`; changing margin re-submits
    ///    CSS and remeasures the swipe page bar.
    /// 4. **Text size** — whole-line snap uses `renderedLineHeightPoints` on the
    ///    real page-box height (`view − top − bottom`), then we force a spread
    ///    inset refresh after preference submit so snap is not stale.
    ///
    /// In paged mode this inset sets page box height (`bottomConstraint` in
    /// Readium's `EPUBReflowableSpreadView`); the navigator is full-screen under
    /// `.ignoresSafeArea()`.
    func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
        let view = (navigator as? UIViewController)?.view
        let window = view?.window
        let liveHeight = view?.bounds.height ?? 0
        // Ignore zero-height pre-layout queries so a good seed is not clobbered.
        if liveHeight > 1 {
            let liveTop = window?.safeAreaInsets.top ?? 0
            let liveBottom = window?.safeAreaInsets.bottom ?? 0
            refreshFrozenPageBoxGeometry(
                viewHeight: liveHeight, safeTop: liveTop, safeBottom: liveBottom
            )
        }
        let height = frozenPageBoxViewHeight > 0
            ? frozenPageBoxViewHeight
            : max(liveHeight, 0)
        let insets = Self.pageBoxContentInsets(
            viewHeight: height,
            safeTop: frozenPageBoxSafeTop > 0 ? frozenPageBoxSafeTop : (window?.safeAreaInsets.top ?? 0),
            safeBottom: frozenPageBoxSafeBottom > 0
                ? frozenPageBoxSafeBottom
                : (window?.safeAreaInsets.bottom ?? 0),
            lineHeight: CGFloat(renderedLineHeightPoints)
        )
        return UIEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0)
    }

    /// Accept new safe-area / height only when the navigator's bounds change
    /// (rotation, split view). Chrome-driven status-bar hide keeps the freeze.
    /// Never accepts `viewHeight == 0` (pre-layout) as a geometry change.
    private func refreshFrozenPageBoxGeometry(
        viewHeight: CGFloat, safeTop: CGFloat, safeBottom: CGFloat
    ) {
        guard viewHeight > 1 else { return }
        let heightChanged = frozenPageBoxViewHeight <= 1
            || abs(viewHeight - frozenPageBoxViewHeight) > 1
        if heightChanged {
            frozenPageBoxViewHeight = viewHeight
            frozenPageBoxSafeTop = max(0, safeTop)
            frozenPageBoxSafeBottom = max(0, safeBottom)
            return
        }
        // Same height: keep freeze. Prefer non-zero live values if we froze
        // before the window was ready (0,0).
        if frozenPageBoxSafeTop == 0, safeTop > 0 { frozenPageBoxSafeTop = safeTop }
        if frozenPageBoxSafeBottom == 0, safeBottom > 0 { frozenPageBoxSafeBottom = safeBottom }
    }

    /// After typography / preference submit, Readium updates CSS but does not
    /// always re-call spread `applySettings` → `updateContentInset`. Nudge
    /// reflowable spreads via `safeAreaInsetsDidChange()` so they re-query
    /// `navigatorContentInset` with the new line height.
    func forcePageBoxContentInsetRefresh() {
        guard let root = navigator?.view else { return }
        Self.forceReflowableContentInsetRefresh(in: root)
    }

    private static func forceReflowableContentInsetRefresh(in view: UIView) {
        let typeName = String(describing: type(of: view))
        if typeName.contains("Reflowable") {
            view.safeAreaInsetsDidChange()
        }
        for sub in view.subviews {
            forceReflowableContentInsetRefresh(in: sub)
        }
    }

    /// Clearance kept at the box edge (never flush to the web-view pixel edge).
    static let minimumBottomInset: CGFloat = 8

    /// Pure page-box top/bottom content insets for **vertical** geometry.
    ///
    /// - `top` = full `safeTop` (island / status) — first ink at content inset.
    /// - `bottom` ≥ `max(minimumEdge, safeBottom)` plus line remainder so the
    ///   band `viewHeight − top − bottom` is a whole number of `lineHeight`s.
    /// - Customize **pageMargins are horizontal** in Readium CSS and are
    ///   intentionally **not** part of this vertical formula.
    nonisolated static func pageBoxContentInsets(
        viewHeight: CGFloat,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        lineHeight: CGFloat,
        minimumEdge: CGFloat = minimumBottomInset
    ) -> (top: CGFloat, bottom: CGFloat) {
        let top = max(0, safeTop)
        let minBottom = max(minimumEdge, safeBottom)
        let availableForText = viewHeight - top - minBottom
        guard lineHeight > 0, availableForText > lineHeight else {
            return (top, minBottom)
        }
        let remainder = availableForText.truncatingRemainder(dividingBy: lineHeight)
        return (top, minBottom + remainder)
    }

    /// Legacy name kept for existing page-box tests. Bottom snap with
    /// `safeBottom` folded into `minimum` (old API shape).
    nonisolated static func snappedBottomInset(
        viewHeight: CGFloat, safeTop: CGFloat, lineHeight: CGFloat,
        minimum: CGFloat = minimumBottomInset
    ) -> CGFloat {
        pageBoxContentInsets(
            viewHeight: viewHeight,
            safeTop: safeTop,
            safeBottom: minimum,
            lineHeight: lineHeight,
            minimumEdge: minimum
        ).bottom
    }

    @discardableResult
    func routeWebURLToBrowse(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let onOpenExternalURL
        else { return false }
        onOpenExternalURL(url)
        return true
    }
}

/// Owns the interactive dismiss peel. Once latched, peels a **bitmap snapshot**
/// of the whole card in the key window — never the live SwiftUI/WebKit tree —
/// so host updates cannot bounce or fight the gesture.
@MainActor
final class ReaderDismissDragSurface {
    weak var cardView: UIView?
    weak var dimView: UIView?
    /// Full-card still used for the peel; strongly retained while installed.
    private var peelSnapshot: UIImageView?
    private(set) var offset: CGFloat = 0
    private(set) var isAnimating = false

    /// The view that actually moves (snapshot if peeling, else live card).
    private var transformTarget: UIView? { peelSnapshot ?? cardView }

    func lockTransformForExit() {
        isAnimating = true
    }

    /// Capture the full reader card and peel that bitmap. Call once on latch.
    func beginCardSnapshotIfNeeded() {
        guard peelSnapshot == nil, let card = cardView, card.bounds.width > 1,
              let window = card.window
        else { return }
        card.layoutIfNeeded()
        let frameInWindow = card.convert(card.bounds, to: window)
        guard frameInWindow.width > 1, frameInWindow.height > 1 else { return }

        let format = UIGraphicsImageRendererFormat()
        format.scale = card.traitCollection.displayScale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: card.bounds, format: format)
        let image = renderer.image { _ in
            card.drawHierarchy(in: card.bounds, afterScreenUpdates: false)
        }
        guard image.size.width > 1 else { return }

        let snap = UIImageView(image: image)
        snap.frame = frameInWindow
        snap.contentMode = .scaleToFill
        snap.clipsToBounds = true
        snap.isUserInteractionEnabled = false
        window.addSubview(snap)
        peelSnapshot = snap
        // Live tree stays for hit-testing freeze only — not visible under the peel.
        card.isHidden = true
        // Carry any in-progress offset onto the snapshot.
        applyTransformOnly(y: offset, reduceMotion: false)
    }

    func endCardSnapshot() {
        peelSnapshot?.removeFromSuperview()
        peelSnapshot = nil
        if let card = cardView {
            card.isHidden = false
            card.transform = .identity
            card.layer.cornerRadius = 0
            card.layer.masksToBounds = false
        }
    }

    func applyInteractiveOffset(_ raw: CGFloat, reduceMotion: Bool) {
        let y = max(0, raw)
        offset = y
        applyTransformOnly(y: y, reduceMotion: reduceMotion)
    }

    func reassertTransform(reduceMotion: Bool) {
        applyTransformOnly(y: offset, reduceMotion: reduceMotion)
    }

    private func applyTransformOnly(y: CGFloat, reduceMotion: Bool) {
        guard let target = transformTarget else { return }
        target.transform = CGAffineTransform(translationX: 0, y: y)
        if reduceMotion {
            target.layer.cornerRadius = 0
            target.layer.masksToBounds = false
        } else {
            let peeling = y > 0.5
            target.layer.cornerRadius = peeling ? 14 : 0
            target.layer.cornerCurve = .continuous
            target.layer.masksToBounds = peeling
        }
        dimView?.alpha = CGFloat(min(y / 280, 1) * 0.35)
    }

    func animate(
        to raw: CGFloat,
        reduceMotion: Bool,
        duration: TimeInterval,
        spring: Bool,
        completion: (() -> Void)? = nil
    ) {
        isAnimating = true
        let target = max(0, raw)
        let finish: () -> Void = {
            self.isAnimating = false
            self.applyInteractiveOffset(target, reduceMotion: reduceMotion)
            completion?()
        }
        if reduceMotion || duration <= 0 {
            applyInteractiveOffset(target, reduceMotion: reduceMotion)
            finish()
            return
        }
        reassertTransform(reduceMotion: reduceMotion)
        if spring {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.2,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.applyInteractiveOffset(target, reduceMotion: reduceMotion)
            } completion: { _ in finish() }
        } else {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.curveEaseIn, .beginFromCurrentState]
            ) {
                self.applyInteractiveOffset(target, reduceMotion: reduceMotion)
            } completion: { _ in finish() }
        }
    }

    func reset(reduceMotion: Bool) {
        isAnimating = false
        applyInteractiveOffset(0, reduceMotion: reduceMotion)
        endCardSnapshot()
    }
}

/// Outer UIKit container whose **own** view is transformed for the peel.
/// The SwiftUI tree lives in a child `UIHostingController` so `rootView =`
/// never zeros the peel transform (that was the bounce-up / wrong dismiss).
private final class ReaderDismissPeelContainerController<Content: View>: UIViewController {
    let host: UIHostingController<Content>
    let surface: ReaderDismissDragSurface
    var reduceMotion: Bool

    init(content: Content, surface: ReaderDismissDragSurface, reduceMotion: Bool) {
        self.host = UIHostingController(rootView: content)
        self.surface = surface
        self.reduceMotion = reduceMotion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        // Transform the container, never the hosting child.
        surface.cardView = view
    }

    func update(content: Content) {
        // During an interactive peel / fly-off, skip rootView churn so chrome
        // doesn't rebuild mid-gesture (transform still lives on `view`).
        if surface.isAnimating || surface.offset > 0.5 {
            surface.cardView = view
            return
        }
        host.rootView = content
        surface.cardView = view
        surface.reassertTransform(reduceMotion: reduceMotion)
    }
}

/// Hosts the full dismissable card (page + chrome) so the peel transform applies
/// to one real UIView — not a SwiftUI `.background` sibling (which would leave
/// chrome behind) and not per-sample `@State` (which rebuilt the reader tree).
private struct ReaderDismissPeelHost<Content: View>: UIViewControllerRepresentable {
    let surface: ReaderDismissDragSurface
    let reduceMotion: Bool
    let content: Content

    init(
        surface: ReaderDismissDragSurface,
        reduceMotion: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.surface = surface
        self.reduceMotion = reduceMotion
        self.content = content()
    }

    func makeUIViewController(context: Context) -> ReaderDismissPeelContainerController<Content> {
        ReaderDismissPeelContainerController(
            content: content,
            surface: surface,
            reduceMotion: reduceMotion
        )
    }

    func updateUIViewController(
        _ container: ReaderDismissPeelContainerController<Content>,
        context: Context
    ) {
        container.reduceMotion = reduceMotion
        container.update(content: content)
    }
}

/// Registers a full-screen dim layer updated only from UIKit during the peel.
private struct ReaderDismissDimAnchor: UIViewRepresentable {
    let surface: ReaderDismissDragSurface

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .black
        view.alpha = 0
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surface.dimView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        surface.dimView = uiView
    }
}

/// Thin SwiftUI host for an already-built `EPUBNavigatorViewController`. Adds a
/// downward swipe gesture on top of Readium so the reader can be dismissed without
/// interfering with the navigator's built-in page turns.
struct ReadiumNavigatorContainer: UIViewControllerRepresentable {
    let controller: EPUBNavigatorViewController
    let readingMode: ReadingMode
    /// UIKit peel surface — pan samples set `transform` here, not SwiftUI `@State`.
    let dismissSurface: ReaderDismissDragSurface
    let reduceMotion: Bool
    /// Fired on pan `.began` / after unfreeze so progress + visual metrics freeze.
    let onDismissInteractionActiveChange: (Bool) -> Void
    /// `shouldDismiss` plus an `unfreeze` callback the view invokes after cancel
    /// spring-back completes (or immediately when there is nothing to animate).
    /// Successful dismiss must **not** call `unfreeze` — leave the page frozen
    /// until view teardown so locator ingestion stays blocked.
    let onDismissDragEnded: (_ shouldDismiss: Bool, _ unfreeze: @escaping () -> Void) -> Void
    /// Selection-menu callbacks, delivered via the host controller because
    /// Readium routes custom editing actions through the responder chain.
    var onHighlight: () -> Void = {}
    var onAddNote: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> ReaderHighlightHostController {
        let host = ReaderHighlightHostController(navigator: controller)
        host.onHighlight = onHighlight
        host.onAddNote = onAddNote
        context.coordinator.update(
            readingMode: readingMode,
            dismissSurface: dismissSurface,
            reduceMotion: reduceMotion,
            onDismissInteractionActiveChange: onDismissInteractionActiveChange,
            onDismissDragEnded: onDismissDragEnded
        )
        context.coordinator.install(on: controller)
        return host
    }

    func updateUIViewController(_ host: ReaderHighlightHostController, context: Context) {
        host.onHighlight = onHighlight
        host.onAddNote = onAddNote
        context.coordinator.update(
            readingMode: readingMode,
            dismissSurface: dismissSurface,
            reduceMotion: reduceMotion,
            onDismissInteractionActiveChange: onDismissInteractionActiveChange,
            onDismissDragEnded: onDismissDragEnded
        )
        context.coordinator.install(on: controller)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var readingMode: ReadingMode = .scroll
        private weak var dismissSurface: ReaderDismissDragSurface?
        private var reduceMotion = false
        private var onDismissInteractionActiveChange: (Bool) -> Void = { _ in }
        private var onDismissDragEnded: (Bool, @escaping () -> Void) -> Void = { _, unfreeze in unfreeze() }
        private weak var installedView: UIView?
        private var dismissPan: UIPanGestureRecognizer?
        /// Latched once a drag is recognized as a downward dismiss, so minor sideways
        /// wobble mid-drag doesn't snap the sheet back to rest (the old jank source).
        private var dismissLatched = false
        /// Scroll views frozen for the duration of a latched dismiss.
        /// One scroll view's pre-freeze state, captured so the dismiss freeze can
        /// restore exactly what it changed if the gesture is cancelled. A named
        /// type rather than a 5-wide tuple: the members are all read back
        /// individually in `unfreezePage`, where positional tuple access would
        /// be easy to transpose silently (`bounces` and `alwaysBounce` are both
        /// `Bool` and adjacent).
        private struct FrozenScroll {
            let scrollView: UIScrollView
            let offset: CGPoint
            let wasEnabled: Bool
            let bounces: Bool
            let alwaysBounce: Bool
        }

        private var frozenScrolls: [FrozenScroll] = []
        /// Lightweight cover of the live EPUB for the whole dismiss gesture + settle
        /// (`snapshotView`, not a CPU `drawHierarchy` bitmap). Strongly retained while
        /// installed so hierarchy churn mid-drag cannot drop it.
        private var pageSnapshotView: UIView?
        /// Subviews hidden under the snapshot so WebKit stops compositing every frame
        /// while the card peels.
        private var hiddenUnderSnapshot: [UIView] = []
        /// Bumped on each dismiss `.began` so a late cancel-spring unfreeze from a
        /// previous gesture cannot thaw a newer freeze.
        private var dismissGeneration = 0

        func update(
            readingMode: ReadingMode,
            dismissSurface: ReaderDismissDragSurface,
            reduceMotion: Bool,
            onDismissInteractionActiveChange: @escaping (Bool) -> Void,
            onDismissDragEnded: @escaping (Bool, @escaping () -> Void) -> Void
        ) {
            self.readingMode = readingMode
            self.dismissSurface = dismissSurface
            self.reduceMotion = reduceMotion
            self.onDismissInteractionActiveChange = onDismissInteractionActiveChange
            self.onDismissDragEnded = onDismissDragEnded
        }

        func install(on controller: EPUBNavigatorViewController) {
            guard let view = controller.view else { return }
            guard installedView !== view else { return }

            if let dismissPan {
                dismissPan.view?.removeGestureRecognizer(dismissPan)
            }

            let dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan))
            // Touches must still reach the web view for tap-to-toggle chrome.
            // Scroll rubber-band is stopped via `shouldBeRequiredToFailBy` + an
            // immediate pin on `.began`, not by cancelling touches.
            dismissPan.cancelsTouchesInView = false
            dismissPan.delegate = self
            view.addGestureRecognizer(dismissPan)
            self.dismissPan = dismissPan

            installedView = view
        }

        // MARK: Swipe-down dismiss

        @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)

            switch gesture.state {
            case .began:
                dismissLatched = false
                // Invalidate any pending cancel-spring unfreeze from a prior peel.
                dismissGeneration += 1
                // Freeze progress/visual BEFORE any setContentOffset side-effects.
                onDismissInteractionActiveChange(true)
                // Pin the page the instant our pan begins (shouldBegin already
                // gated top+downward). Waiting until the 8pt latch let UIScrollView
                // rubber-band first — text slid under the title pill.
                freezePageForDismiss(in: view, includeSnapshot: false)
            case .changed:
                // Only fight scroll until the still cover is in place — after that,
                // underlying WebKit is hidden and per-frame offset pinning is wasted work.
                if pageSnapshotView == nil {
                    reinstateFrozenOffsets()
                }
                if !dismissLatched {
                    // Latch the *card* peel once the drag is clearly intentional.
                    // Scroll is already frozen from `.began`.
                    let startsDismiss = translation.y > 8
                        && translation.y > abs(translation.x) * 1.1
                    guard startsDismiss else { return }
                    dismissLatched = true
                    // Freeze WebKit + peel a full-card bitmap in the window.
                    // Live SwiftUI is hidden; only the bitmap moves.
                    freezePageForDismiss(in: view, includeSnapshot: true)
                    dismissSurface?.beginCardSnapshotIfNeeded()
                }
                // UIKit transform only — never touch SwiftUI @State per sample.
                let y = rubberBandedDistance(max(0, translation.y))
                dismissSurface?.applyInteractiveOffset(y, reduceMotion: reduceMotion)
            case .ended:
                if dismissLatched {
                    let passesDistance = translation.y > 110
                    let passesVelocity = translation.y > 40 && velocity.y > 900
                    let shouldDismiss = passesDistance || passesVelocity
                    // Keep freeze through spring-back / fly-off; surface animates
                    // in the SwiftUI handler via the shared dismissSurface.
                    // Cancel path unfreezes from the spring completion (not a fixed
                    // timer). Successful dismiss must leave freeze latched until
                    // teardown — do not call `unfreeze` on that path.
                    let generation = dismissGeneration
                    onDismissDragEnded(shouldDismiss) { [weak self] in
                        guard let self, self.dismissGeneration == generation else { return }
                        self.unfreezePageAfterDismiss()
                    }
                } else {
                    // Began (and froze) but never latched — release immediately.
                    dismissSurface?.reset(reduceMotion: reduceMotion)
                    let generation = dismissGeneration
                    onDismissDragEnded(false) { [weak self] in
                        guard let self, self.dismissGeneration == generation else { return }
                        self.unfreezePageAfterDismiss()
                    }
                }
                dismissLatched = false
            case .cancelled, .failed:
                dismissSurface?.reset(reduceMotion: reduceMotion)
                let generation = dismissGeneration
                onDismissDragEnded(false) { [weak self] in
                    guard let self, self.dismissGeneration == generation else { return }
                    self.unfreezePageAfterDismiss()
                }
                dismissLatched = false
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let velocity = pan.velocity(in: view)
            let translation = pan.translation(in: view)

            // Dismiss pan: downward, vertical-dominant, top-of-page in scroll mode.
            let downwardIntent = velocity.y > 0 || translation.y > 0
            let verticalVelocity = abs(velocity.y) > abs(velocity.x) * 1.25
            let verticalTranslation = translation.y > abs(translation.x) * 1.25
            guard downwardIntent, verticalVelocity || verticalTranslation else { return false }
            return readingMode != .scroll || isAtTop(in: view)
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool {
            // Scroll must not track alongside us — rubber-band was the remaining
            // "text under title pill" motion. Competing pans wait on us via
            // `shouldBeRequiredToFailBy` so dismiss still wins at top-of-page.
            false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Competing pans (UIScrollView / page-turn) wait for our dismiss pan
            // to fail. At top+downward we begin and they never start. Otherwise
            // shouldBegin is false, we fail, and they proceed as normal.
            guard gestureRecognizer === dismissPan else { return false }
            return otherGestureRecognizer is UIPanGestureRecognizer
        }

        /// Pin scroll (and optionally cover with a still snapshot).
        /// - Parameter includeSnapshot: false on `.began` (cheap pin only); true
        ///   once the card peel latches so settle animations stay frozen.
        private func freezePageForDismiss(in root: UIView, includeSnapshot: Bool) {
            // Keep existing freeze bookkeeping if we're only upgrading to a snapshot.
            if frozenScrolls.isEmpty {
                let scrolls = collectScrollViews(in: root)
                frozenScrolls = scrolls.map { sv in
                    let top = -sv.adjustedContentInset.top
                    // Clamp out any in-progress top overscroll so we don't freeze
                    // mid-rubber-band (text already under the title pill).
                    var offset = sv.contentOffset
                    if offset.y < top {
                        offset = CGPoint(x: offset.x, y: top)
                    }
                    // Only write offset when it actually changes — a no-op
                    // setContentOffset still makes WebKit/Readium re-settle and
                    // was corrupting resume position on swipe-down dismiss.
                    if sv.contentOffset != offset {
                        sv.setContentOffset(offset, animated: false)
                    }
                    sv.layer.removeAllAnimations()
                    return FrozenScroll(
                        scrollView: sv,
                        offset: offset,
                        wasEnabled: sv.isScrollEnabled,
                        bounces: sv.bounces,
                        alwaysBounce: sv.alwaysBounceVertical
                    )
                }
                for entry in frozenScrolls {
                    entry.scrollView.isScrollEnabled = false
                    entry.scrollView.bounces = false
                    entry.scrollView.alwaysBounceVertical = false
                    entry.scrollView.panGestureRecognizer.isEnabled = false
                }
            } else {
                reinstateFrozenOffsets()
            }

            guard includeSnapshot, pageSnapshotView == nil else { return }
            guard root.bounds.width > 1, root.bounds.height > 1 else { return }
            // Prefer `snapshotView` (reuses the composited layer tree). Fall back to
            // a one-shot CPU render only if WebKit refuses a live snapshot — that path
            // was the multi‑ms hitch at peel latch on ProMotion, so keep it rare.
            let snapshot: UIView
            if let live = root.snapshotView(afterScreenUpdates: false) {
                snapshot = live
            } else if let image = cpuSnapshotImage(for: root) {
                let imageView = UIImageView(image: image)
                imageView.contentMode = .scaleToFill
                imageView.clipsToBounds = true
                snapshot = imageView
            } else {
                return
            }
            snapshot.frame = root.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            snapshot.isUserInteractionEnabled = false
            snapshot.accessibilityElementsHidden = true
            // One still layer for the rest of the gesture — no per-frame WebKit paint.
            snapshot.layer.shouldRasterize = true
            snapshot.layer.rasterizationScale = root.traitCollection.displayScale
            root.addSubview(snapshot)
            pageSnapshotView = snapshot
            // Hide everything under the cover so WKWebView / tiles stop compositing
            // while SwiftUI translates the card (the main continuous-chug source).
            hiddenUnderSnapshot = root.subviews.filter { $0 !== snapshot && !$0.isHidden }
            for subview in hiddenUnderSnapshot {
                subview.isHidden = true
            }
        }

        /// Last-resort full-frame CPU raster. Avoid on the hot path — only when
        /// `snapshotView` is unavailable.
        private func cpuSnapshotImage(for root: UIView) -> UIImage? {
            let format = UIGraphicsImageRendererFormat()
            format.scale = root.traitCollection.displayScale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(bounds: root.bounds, format: format)
            return renderer.image { _ in
                root.drawHierarchy(in: root.bounds, afterScreenUpdates: false)
            }
        }

        private func reinstateFrozenOffsets() {
            for entry in frozenScrolls where entry.scrollView.contentOffset != entry.offset {
                entry.scrollView.setContentOffset(entry.offset, animated: false)
            }
        }

        private func unfreezePageAfterDismiss() {
            for subview in hiddenUnderSnapshot {
                subview.isHidden = false
            }
            hiddenUnderSnapshot = []
            pageSnapshotView?.removeFromSuperview()
            pageSnapshotView = nil
            for entry in frozenScrolls {
                entry.scrollView.panGestureRecognizer.isEnabled = true
                entry.scrollView.isScrollEnabled = entry.wasEnabled
                entry.scrollView.bounces = entry.bounces
                entry.scrollView.alwaysBounceVertical = entry.alwaysBounce
                if entry.scrollView.contentOffset != entry.offset {
                    entry.scrollView.setContentOffset(entry.offset, animated: false)
                }
            }
            frozenScrolls = []
            // Re-enable locator/visual updates only after freeze teardown so a
            // late scroll notification cannot overwrite the flushed position.
            // (No-op when exit is latched — `setDismissInteractionActive(false)`
            // refuses to clear once a successful dismiss committed.)
            onDismissInteractionActiveChange(false)
        }

        private func rubberBandedDistance(_ distance: CGFloat) -> CGFloat {
            guard distance > 150 else { return distance }
            return 150 + (distance - 150) * 0.5
        }

        private func isAtTop(in view: UIView) -> Bool {
            guard let scrollView = primaryScrollView(in: view) else { return true }
            let top = -scrollView.adjustedContentInset.top
            return scrollView.contentOffset.y <= top + 18
        }

        private func primaryScrollView(in view: UIView) -> UIScrollView? {
            let scrollViews = collectScrollViews(in: view)
            return scrollViews.first {
                !$0.isHidden && $0.alpha > 0 && $0.contentSize.height > $0.bounds.height + 1
            } ?? scrollViews.first
        }

        private func collectScrollViews(in view: UIView) -> [UIScrollView] {
            var result = (view as? UIScrollView).map { [$0] } ?? []
            for subview in view.subviews {
                result.append(contentsOf: collectScrollViews(in: subview))
            }
            return result
        }
    }

}

/// The Readium-backed reader screen. Mirrors the legacy `ReaderView`'s chrome
/// (immersive page, tap-to-toggle bars, Chapters / Display sheets) but renders
/// with `EPUBNavigatorViewController` and drives Readium's `EPUBPreferences` from
/// the app's existing reader settings + `ThemeManager`.
struct ReadiumReaderView: View {
    @Bindable var work: SavedWork

    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]
    /// Every annotation in the store; narrowed to this work by `annotations`.
    /// A `#Predicate` can't compare an optional relationship's id, so the filter
    /// is done in Swift — the list is small (per-reader marks, not the library).
    @Query(sort: \ReadingAnnotation.progression) private var allAnnotations: [ReadingAnnotation]
    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("readerTwoPage") private var twoPageEnabled = false
    @AppStorage("readerFontID") private var fontID: String = "system"
    // Apple Books–style typography; layout options are gated by `customizeEnabled`
    // (mirrored from the legacy reader via `ReaderTextStyle.resolved`).
    @AppStorage("readerCustomize") private var customizeEnabled = false
    @AppStorage("readerBoldText") private var boldText = false
    @AppStorage("readerFontPt") private var fontSizePt: Double = ReaderTextStyle.defaultFontSizePt
    @AppStorage("readerLineHeight") private var lineHeight: Double = ReaderTextStyle.defaultLineHeight
    @AppStorage("readerLetterSpacing") private var letterSpacing: Double = 0
    @AppStorage("readerWordSpacing") private var wordSpacing: Double = 0
    @AppStorage("readerMargin") private var pageMargin: Double = ReaderTextStyle.defaultMargin
    @AppStorage("readerJustify") private var justifyText = false
    /// Voice id only — rate/pitch are read live from UserDefaults per utterance.
    @AppStorage(ReaderSpeechPreferences.voiceIDKey) private var speechVoiceID = ""

    /// The reader-scoped rotation lock. Shared (not per-view) because iOS asks
    /// the app delegate, not this view, which orientations are supported.
    private var orientationLock: ReaderOrientationLock { .shared }

    @State private var book = ReadiumBook()
    /// Debounces SwiftData writes for the Readium locator stream (see
    /// `ReadiumProgressPersistence`). UI locator / progress pill stay live.
    @State private var progressPersistence = ReadiumProgressPersistence()
    /// Native comments sheet over the reader (only for AO3-backed works).
    @State private var showingComments = false

    /// The afterword's own AO3 boilerplate — "Please drop by the Archive and
    /// comment…" — links straight at `/works/<id>/comments/new`, which this
    /// work's native comments sheet already covers. Opens that instead of the
    /// AO3 web form when the URL is for *this* work.
    ///
    /// The link itself is untouched (nothing removed from the EPUB) and every
    /// other URL — including this same link for a different work, or if this
    /// check simply doesn't match — still falls through to the normal
    /// `router.openAO3Link` path below, so the original in-app-browser fallback
    /// is never lost.
    private func openCommentsLinkIfMatching(_ url: URL) -> Bool {
        guard let ao3WorkID, (url.host ?? "").contains("archiveofourown.org") else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3, parts[0] == "works", Int(parts[1]) == ao3WorkID, parts[2] == "comments"
        else { return false }
        showingComments = true
        return true
    }

    private var ao3WorkID: Int? {
        work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)
    }
    /// UIKit peel surface — interactive samples never touch SwiftUI state.
    @State private var dismissSurface = ReaderDismissDragSurface()
    @State private var isDismissingByDrag = false

    // MARK: Chrome state

    /// One inset for every floating chrome layer. The back button, the fan
    /// button, and the position card all sit exactly this far from the screen
    /// edge — previously the top bar double-padded (layer + its own internal
    /// padding), so the back button sat twice as far in as the fan button.
    /// The card uses it on all three of its free edges, so its bottom gap
    /// matches its sides.
    private static let chromeInset: CGFloat = 12

    @State private var fanMenuOpen = false
    @State private var searchModel = ReaderSearchModel()
    /// The highlight whose note is being written, if the editor is open.
    @State private var editingNote: ReadingAnnotation?
    /// Note editor queued from inside the Contents sheet, opened only once that
    /// sheet has finished dismissing (see the `onDismiss` on the panel sheet).
    @State private var pendingNoteAfterPanelDismiss: ReadingAnnotation?
    /// Annotation that just got a **Highlight** and still has the floating
    /// colour bar up — nil when the bar is dismissed.
    @State private var colorBarAnnotationID: UUID?
    /// Title-pill → work details, as a sheet over the live reader (see the
    /// `.sheet(isPresented: $showingWorkDetail)` below for why — not a push).
    @State private var showingWorkDetail = false
    @State private var speech = ReaderSpeechController()
    /// Which tab the Contents sheet opens on — the fan's "Contents" and
    /// "Bookmarks & Highlights" pills both route here, differing only in this.
    @State private var contentsSegment: ReaderContentsSegment = .chapters
    /// Chapter-relative seek fraction (0...1) shown by the position card's slider.
    /// Driven from `book.readingPosition` while not being dragged; only pushed to
    /// the navigator on editing-ended, so it never fights `locationDidChange`.
    @State private var sliderValue: Double = 0
    @State private var isEditingSlider = false
    /// Last page live-seeked to during the current drag, so `handleScrubSeek`
    /// fires once per page crossed rather than once per slider sample.
    @State private var lastScrubSeekPage: Int?
    /// Session was playing when hold-seek began — resume speaking on release.
    /// (Kept here with the other stored state; the hold-seek *methods* live in
    /// the speech/scrub extension below, which can't hold stored properties.)
    @State private var speechSeekWasPlaying = false
    /// True while a hold-seek is in progress (suppresses page-follow thrash).
    @State private var speechSeekHolding = false
    /// 0…1 thumb position when the chapter slider scrub began — origin `|` tick.
    @State private var sliderScrubOrigin: Double?
    /// Session-only "kudos left" flag — there's no persisted per-work kudos state
    /// (AO3 doesn't expose one to check), so this reflects only this reading
    /// session's own successful tap, same honesty rule as `AO3WorkActionsModel`.
    @State private var kudosGiven = false
    @State private var kudosWorking = false
    @State private var kudosBanner: String?

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// The effective typography (layout options collapse to defaults when Customize
    /// is off; font weight + size always apply) — same rule as the legacy reader.
    private var textStyle: ReaderTextStyle {
        ReaderTextStyle(
            customize: customizeEnabled, bold: boldText, fontSizePt: fontSizePt,
            lineHeight: lineHeight, letterSpacing: letterSpacing, wordSpacing: wordSpacing,
            margin: pageMargin, justify: justifyText
        ).resolved
    }

    /// Reader chrome (bars) visibility — driven by tapping the page.
    private var chromeVisible: Bool {
        !book.chromeHidden
    }

    /// Collapses colour-bar dismiss triggers into one `onChange` dependency so
    /// `body` stays type-checkable. Any change clears the bar (chrome-hide is
    /// handled separately so it can also close the fan).
    private var colorBarDismissToken: String {
        let position = book.currentLocator?.locations.position.map(String.init) ?? "-"
        return "\(fanMenuOpen)|\(router.panel)|\(showingComments)|\(showingWorkDetail)|\(position)"
    }

    /// The reader's effective theme (app theme while linked).
    private var readerTheme: ReaderTheme {
        themeManager.readerTheme
    }

    private var preferences: EPUBPreferences {
        ReadiumReaderStyleMapper.preferences(
            style: textStyle,
            theme: readerTheme,
            fontFamily: readiumFontFamily,
            readingMode: readingMode,
            // .auto lets Readium show a two-page spread on wide screens (iPad)
            // and one column when narrow; iPhone stays single-column.
            columnCount: (twoPageEnabled && !isPhone) ? .auto : .one
        )
    }

    /// The selected font as a Readium `FontFamily`: a quote-safe custom family
    /// declared via `fontFamilyDeclarations`, or a built-in's primary name.
    /// System is explicit because Readium's default family is serif, while the
    /// legacy System choice is Apple's sans-serif UI stack.
    private var readiumFontFamily: FontFamily? {
        let option = ReaderFontOption.current(id: fontID, customFonts: customFonts)
        return ReadiumReaderStyleMapper.fontFamily(for: option)
    }

    /// `@font-face` declarations for the user's imported fonts, so the navigator can
    /// load and apply them, plus fallback stacks for the built-in choices.
    private var fontFamilyDeclarations: [AnyHTMLFontFamilyDeclaration] {
        ReadiumReaderStyleMapper.fontFamilyDeclarations(
            options: ReaderFontOption.options(customFonts: customFonts)
        )
    }

    /// Re-submit preferences whenever any mapped setting changes (instant updates).
    private var preferencesToken: String {
        "\(readingMode.rawValue)|\(readerTheme.rawValue)|\(fontID)|\(twoPageEnabled)|\(textStyle.token)"
    }

    /// Font declarations are fixed when Readium builds its navigator. Recreate it
    /// after an import or deletion so a newly selected font works immediately.
    private var bookLoadToken: String {
        let fontFiles = customFonts.map(\.fileName).joined(separator: "|")
        return "\(work.id.uuidString)|\(fontFiles)"
    }

    /// Chapters / Display share the app-wide panel slot so only one opens at once.
    private var readerPanelBinding: Binding<Bool> {
        Binding(
            get: {
                router.panel == .readerChapters || router.panel == .readerDisplay
                    || router.panel == .readerFind
            },
            set: { if !$0 { router.panel = .none } }
        )
    }

    var body: some View {
        // Dim + card peel are driven in UIKit during the gesture (see
        // `ReaderDismissDragSurface`) so pan samples don't rebuild this tree.
        ZStack {
            readerTheme.backgroundColor
                .ignoresSafeArea()
            ReaderDismissDimAnchor(surface: dismissSurface)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            dismissableReaderCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(readerTheme.colorScheme)
        .navigationTitle(work.title)
        .navigationBarTitleDisplayMode(.inline)
        // The floating top bar replaces the system nav bar entirely. Hide the
        // bar *and* its background so the Library's top-leading menu can't draw
        // over the reader during the push transition.
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
            // `onDismiss` is what makes Contents → Add Note work. These are two
            // sibling sheets on one presenter, and SwiftUI won't present the
            // second while the first is still dismissing — setting both in the
            // same update simply drops the editor. Handing it off here runs it
            // once the panel is really gone.
            .sheet(isPresented: readerPanelBinding, onDismiss: presentPendingNoteEditor) {
                readerSheet
            }
            .commentsSheet(
                isPresented: $showingComments,
                workID: ao3WorkID ?? 0,
                context: .init(savedWork: work),
                initialChapterPosition: currentAO3Chapter
            )
            .sheet(item: $editingNote) { annotation in
                ReaderNoteEditor(annotation: annotation) {
                    try? modelContext.save()
                    FolderSyncService.markDirty()
                    refreshHighlightDecorations()
                } onDelete: {
                    deleteAnnotation(annotation)
                    refreshHighlightDecorations()
                }
                .preferredColorScheme(readerTheme.colorScheme)
            }
            // Title pill → work details as a *sheet*, not a navigation push.
            // Pushing via `navigationDestination(isPresented:)` while the reader
            // has `.toolbar(.hidden, for: .navigationBar)` + statusBarHidden
            // frozen the UI mid-transition (nav stack and status-bar ownership
            // fight). A sheet keeps the immersive reader underneath intact and
            // avoids Detail→Reader→Detail stack bloat.
            .sheet(isPresented: $showingWorkDetail) {
                NavigationStack {
                    WorkDetailView(work: work, openedFromReader: true)
                }
                .preferredColorScheme(readerTheme.colorScheme)
                .presentationDragIndicator(.visible)
            }
            // Highlights made in an earlier session have to be drawn when the
            // book opens, not only when one is created.
            .onChange(of: book.phase) { _, phase in
                guard phase == .ready else { return }
                // Seed slider from initialLocator-backed readingPosition before
                // the first visual JS report can briefly claim last page.
                if !book.isLocatorIngestionBlocked {
                    syncSliderFromPosition(book.readingPosition)
                }
                refreshHighlightDecorations()
                // Tap a highlight on the page → colour / note / delete editor.
                book.observeHighlightTaps { id in
                    openHighlight(id: id)
                }
                speech.prepare(
                    publication: book.publication,
                    title: work.title,
                    author: work.author,
                    totalPositions: book.positionsByReadingOrder.reduce(0) { $0 + $1.count }
                )
                // Keep the page with the voice as it moves between utterances.
                // Blocked during dismiss freeze / successful-exit latch so TTS
                // cannot seek the navigator (or corrupt the flushed locator).
                speech.onAdvance = { locator in
                    // Dismiss freeze/exit latch, and hold-to-seek — never fight
                    // the user (or corrupt a committed exit flush) by page-follow.
                    guard !book.isLocatorIngestionBlocked, !speechSeekHolding else { return }
                    book.go(to: locator)
                }
                // Lock Screen / Island previous-next track = chapter skip (mini player).
                speech.onSkipPrevious = { handleSpeechSkipBack() }
                speech.onSkipNext = { handleSpeechSkipForward() }
            }
            // Voice changes from the Display sheet apply on the next utterance.
            .onChange(of: speechVoiceID) { _, _ in speech.applyPreferences() }
            .onChange(of: chromeVisible) { _, visible in
                if !visible {
                    fanMenuOpen = false
                    colorBarAnnotationID = nil
                }
            }
            // Single token so we don't hang the type-checker with a forest of
            // .onChange on `body` (colour bar is contextual — drop when context ends).
            .onChange(of: colorBarDismissToken) { _, _ in
                colorBarAnnotationID = nil
            }
            .alert("AO3", isPresented: kudosBannerPresented) {
                Button("OK", role: .cancel) { kudosBanner = nil }
            } message: {
                Text(kudosBanner ?? "")
            }
            // Immersive reading: hide the tab bar; the status bar follows the chrome.
            .toolbar(.hidden, for: .tabBar)
            .statusBarHidden(!chromeVisible)
            .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
            .animation(.easeInOut(duration: 0.25), value: book.chromeHidden)
            .animation(.easeInOut(duration: 0.25), value: speech.isSessionActive)
            // Readium's WebView swallows the system edge-swipe; add our own.
            .edgeSwipeToGoBack { dismissReader() }
            .task(id: bookLoadToken) {
                // Seed page-box inputs before the navigator exists: first
                // content-inset query runs during setup.
                book.renderedLineHeightPoints = textStyle.fontSizePt * textStyle.lineHeight
                book.renderedPageMarginPoints = max(0, textStyle.margin)
                book.seedPageBoxGeometryFromWindowIfNeeded()
                await openBook()
            }
            .onChange(of: preferencesToken) { _, _ in applyReaderPreferences() }
            // The Display / Customize controls live in a sheet over the reader; a
            // behind-the-sheet onChange can be missed, so re-apply when it closes.
            .onChange(of: router.panel) { _, panel in
                if panel == .none {
                    applyReaderPreferences()
                    speech.applyPreferences()
                    // Drop results (and any in-flight search) with the sheet, so
                    // reopening Find starts clean instead of on a stale query.
                    searchModel.reset()
                }
            }
            .onChange(of: book.readingPosition) { _, newValue in
                // Dismiss freeze / exit latch: never move the scrub bar.
                guard !book.isLocatorIngestionBlocked else { return }
                syncSliderFromPosition(newValue)
            }
            .onChange(of: scenePhase) { _, phase in
                // Force-quit safety: flush when leaving the foreground so a
                // debounced window can't lose the last settle.
                // - `.background`: full shelf stamp (Continue Reading).
                // - `.inactive` (Control Center / app switcher): position only —
                //   avoid rewriting lastReadDate on every transient inactive flip.
                switch phase {
                case .background:
                    flushProgress(shelfStamp: true)
                case .inactive:
                    flushProgress(shelfStamp: false)
                default:
                    break
                }
            }
            .onDisappear {
                // Safety net: `isScrubbing` gates the debounced progress write,
                // so a drag that never delivers `onEditingChanged(false)` (view
                // torn down mid-gesture, slider disabled mid-drag) would leave
                // it latched and silently stop persisting progress for the rest
                // of the session. Releasing it here costs nothing when the flag
                // is already clear, which is the normal case.
                book.isScrubbing = false
                isEditingSlider = false
                // Flush the exact final position so resume lands precisely, even if the
                // last scroll's debounce window hadn't elapsed before we left.
                flushProgress(shelfStamp: true)
                WorkLifecycle.freeEPUBIfFinished(work, in: modelContext)
                try? modelContext.save()
                scheduleFolderSyncOnReaderClose()
                // The lock is the reader's, not the app's — never leave the rest
                // of the app pinned to whatever orientation reading ended in.
                orientationLock.release()
                // Reading aloud is bound to this reader: leaving a *work* tears
                // down speech + remote commands + Now Playing. Backgrounding the
                // app with the reader still open keeps TTS (system Now Playing).
                // Mini-player stop still uses `stop()` only — see `stopReadingAloud`.
                speech.tearDown()
                if router.panel == .readerChapters || router.panel == .readerDisplay {
                    router.panel = .none
                }
            }
    }

    /// Ends speech and collapses the mini-player strip. Shared by the fan-menu
    /// waveform control (when active) and the mini player's stop button.
    /// Leaving the reader uses `speech.tearDown()` instead so remote commands
    /// are removed (not only paused/stopped).
    private func stopReadingAloud() {
        speech.stop()
    }

    /// Fan-menu waveform: start from the current page when idle; otherwise the
    /// same full stop as the mini player (not pause).
    private func toggleReadingAloud() {
        if speech.status != .stopped {
            stopReadingAloud()
        } else {
            speech.toggle(from: book.currentLocator)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch book.phase {
        case .loading:
            // Opaque page skeleton so the Library toolbar/menu can't show through
            // during the push transition, and so opening matches the rest of the app.
            ReaderPageSkeleton()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(readerTheme.backgroundColor)
        case let .failed(message):
            ContentUnavailableView("Couldn't open this EPUB", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(readerTheme.backgroundColor)
        case .ready:
            if let navigator = book.navigator {
                ReadiumNavigatorContainer(
                    controller: navigator,
                    readingMode: readingMode,
                    dismissSurface: dismissSurface,
                    reduceMotion: reduceMotion,
                    onDismissInteractionActiveChange: handleDismissInteractionActiveChange,
                    onDismissDragEnded: handleDismissDragEnded,
                    onHighlight: { createAnnotationFromSelection(withNote: false) },
                    onAddNote: { createAnnotationFromSelection(withNote: true) }
                )
                .ignoresSafeArea()
            } else {
                // Keep a full-size host even if the navigator is momentarily nil
                // so chrome overlays never re-collapse to a zero-size anchor.
                ReaderPageSkeleton()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(readerTheme.backgroundColor)
            }
        }
    }

    private func handleDismissInteractionActiveChange(_ active: Bool) {
        // Successful exit keeps the gate latched until the book is deallocated.
        if !active && (isDismissingByDrag || book.isDismissExitLatched) { return }
        book.setDismissInteractionActive(active)
    }

    private func handleDismissDragEnded(_ shouldDismiss: Bool, unfreeze: @escaping () -> Void) {
        guard !isDismissingByDrag else { return }
        if shouldDismiss {
            // Lock the peel transform *before* flush/latch. Those touch
            // @State/@Observable and rebuild the peel host; without the lock the
            // card snaps to identity (bounce up), re-applies finger offset
            // (comes down), then flies off.
            dismissSurface.lockTransformForExit()
            // Flush *before* latching so live (still freeze-stable) locator is
            // recorded once; subsequent flushes skip re-record.
            flushProgress(shelfStamp: true)
            isDismissingByDrag = true
            book.latchDismissExit()
            // Leave page freeze in place until view teardown — never call
            // `unfreeze` on the success path (would re-enable ingestion mid-exit).
            if reduceMotion {
                dismissSurface.endCardSnapshot()
                dismissSurface.reset(reduceMotion: true)
                dismissReader()
                return
            }
            // Fly the card snapshot off-screen, then pop.
            dismissSurface.animate(
                to: 1400,
                reduceMotion: false,
                duration: 0.22,
                spring: false
            ) {
                self.dismissSurface.endCardSnapshot()
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { self.dismissReader() }
            }
            return
        }
        // Cancel: spring snapshot back, restore live card, unfreeze WebKit.
        if dismissSurface.offset != 0 {
            dismissSurface.animate(
                to: 0,
                reduceMotion: reduceMotion,
                duration: 0.38,
                spring: true
            ) {
                self.dismissSurface.endCardSnapshot()
                unfreeze()
            }
        } else {
            dismissSurface.endCardSnapshot()
            unfreeze()
        }
    }

    // MARK: In-book annotations

    /// Creates a highlight from the reader's current text selection, optionally
    /// opening the note editor straight afterwards.
    ///
    /// Re-highlighting the same passage with **Highlight** compares the
    /// currently-picked colour against the existing mark's (ANN-2, product
    /// decision 2026-07-28): the *same* colour again toggles it off, same as
    /// tapping your own highlighter twice; a *different* colour recolours it
    /// in place instead of stacking a second mark over the same words.
    /// **Add Note** on an existing mark opens its editor either way.
    ///
    /// New marks use the last-picked colour, then surface the floating colour
    /// bar so the reader can refine without a second trip through the editor.
    ///
    /// The anchor is the selection's own `Locator` — it carries the CFI//text
    /// range Readium needs to redraw the highlight over the exact words — and
    /// `text.highlight` is stored alongside it as the passage snapshot.
    private func createAnnotationFromSelection(withNote: Bool) {
        guard let selection = book.currentSelection,
              let locatorString = selection.locator.persistenceString
        else { return }

        if let existing = existingHighlight(matching: selection.locator) {
            book.clearSelection()
            if withNote {
                colorBarAnnotationID = nil
                editingNote = existing
            } else if existing.color == ReadingAnnotationColor.lastUsed {
                colorBarAnnotationID = nil
                deleteAnnotation(existing)
            } else {
                applyHighlightColor(ReadingAnnotationColor.lastUsed, to: existing)
            }
            return
        }

        let color = ReadingAnnotationColor.lastUsed
        let spineIndex = (book.readingPosition?.chapter ?? 1) - 1
        let annotation = ReadingAnnotation(
            work: work,
            kind: .highlight,
            locatorString: locatorString,
            selectedText: selection.locator.text.highlight ?? "",
            color: color,
            progression: selection.locator.locations.totalProgression ?? 0,
            spineIndex: spineIndex,
            chapterTitle: chapterTitle(forSpineIndex: spineIndex)
        )
        modelContext.insert(annotation)
        try? modelContext.save()
        FolderSyncService.markDirty()

        book.clearSelection()
        refreshHighlightDecorations()
        if withNote {
            colorBarAnnotationID = nil
            editingNote = annotation
        } else {
            // Immediate colour refine — the system menu can't host a picker.
            colorBarAnnotationID = annotation.id
        }
    }

    private func applyHighlightColor(_ color: ReadingAnnotationColor, to annotation: ReadingAnnotation) {
        guard annotation.color != color else {
            colorBarAnnotationID = nil
            return
        }
        annotation.color = color
        annotation.markModified()
        ReadingAnnotationColor.lastUsed = color
        try? modelContext.save()
        FolderSyncService.markDirty()
        refreshHighlightDecorations()
        // One tap applies and dismisses — refining again is a tap on the mark.
        colorBarAnnotationID = nil
    }

    /// The live highlight that covers this selection, if any.
    /// Match is **locator-string equality only** (see `ReadingAnnotationMatching`).
    private func existingHighlight(matching locator: Locator) -> ReadingAnnotation? {
        guard let selectionLocator = locator.persistenceString, !selectionLocator.isEmpty
        else { return nil }

        return annotations
            .filter { $0.kind == .highlight }
            .first { annotation in
                ReadingAnnotationMatching.isSamePassage(
                    existingLocator: annotation.locatorString,
                    selectionLocator: selectionLocator
                )
            }
    }

    /// Redraws every highlight for this work over the page. Called after any
    /// change to the set, and once the book is ready (a highlight made in a
    /// previous session has to be drawn on open, not just when created).
    private func refreshHighlightDecorations() {
        let decorations: [Decoration] = annotations
            .filter { $0.kind == .highlight }
            .compactMap { annotation in
                guard let locator = Locator(persistenceString: annotation.locatorString) else { return nil }
                let tint = UIColor(annotation.color.tint)
                // Underline is a rule, not a fill — match the palette swatch.
                let style: Decoration.Style = annotation.color == .underline
                    ? .underline(tint: tint)
                    : .highlight(tint: tint)
                return Decoration(
                    id: annotation.id.uuidString,
                    locator: locator,
                    style: style
                )
            }
        book.applyHighlightDecorations(decorations)
    }

    /// Adds a bookmark at the current page, or removes the one already there.
    /// Deletion records a `.readingAnnotation` tombstone so a restore from an
    /// older archive can't resurrect it (see the merge rules in
    /// `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`).
    private func toggleBookmarkAtCurrentPosition() {
        if let existing = bookmarkAtCurrentPosition {
            modelContext.insert(SyncTombstone(
                recordID: existing.id,
                recordType: .readingAnnotation,
                sourceURL: work.sourceURL,
                ao3WorkID: ao3WorkID
            ))
            modelContext.delete(existing)
            try? modelContext.save()
            FolderSyncService.markDirty()
        } else if let locator = book.currentLocator {
            addBookmark(at: locator)
        }
    }

    /// `book.sections`' spine index for a locator's resource, matched by href.
    ///
    /// All three index spaces here are the same length — `ReaderSectionBuilder`
    /// emits one `ReaderSection` per spine href, and Readium builds
    /// `positionsByReadingOrder` as `readingOrder.map { ... ?? [] }`, keeping
    /// empty entries. The reason to prefer href is not length, it's *derivation*:
    /// `readingPosition.chapter` resolves the chapter by scanning global
    /// position ranges, so it only answers for locators that carry a
    /// `locations.position`. Search results don't (Readium's search service
    /// emits progression only), and neither does a locator mid-navigation — for
    /// those it silently falls through to a different answer than href matching
    /// gives. Since `ReaderSearchGrouping` buckets results by href, deriving the
    /// reader's own index any other way let the two disagree, which is why
    /// "This Chapter" didn't reliably pin first.
    private func spineIndex(for locator: Locator) -> Int? {
        let key = ReaderSectionBuilder.hrefKey(locator.href.string)
        return book.sections.first { ReaderSectionBuilder.hrefKey($0.href) == key }?.spineIndex
    }

    /// The reader's live chapter, on the same `sections`-href basis as
    /// `spineIndex(for:)` — see its doc comment for why that matters.
    private var currentSpineIndex: Int? {
        book.currentLocator.flatMap(spineIndex(for:))
    }

    /// Adds a bookmark at an arbitrary locator (e.g. a Find in Work result),
    /// unlike `toggleBookmarkAtCurrentPosition` which only ever targets the
    /// reader's live position.
    /// Returns the bookmark now at this spot — the newly created one, or the
    /// existing one when there already was a bookmark there — so callers that
    /// need to act on it (Contents' **Add Note**, which opens the editor on it)
    /// don't have to re-find it and can't accidentally create a second.
    @discardableResult
    private func addBookmark(at locator: Locator) -> ReadingAnnotation? {
        let locator = resolvedPositionLocator(for: locator)
        guard let locatorString = locator.persistenceString else { return nil }
        // Don't stack a second bookmark on a spot that already has one. Matched
        // on `position` (not the whole locator string) for the same reason
        // `bookmarkAtCurrentPosition` does: a search-result locator and a
        // live-reading locator for the same page carry different progression
        // and text, so string equality would see two distinct marks where the
        // reader sees one page.
        if let position = locator.locations.position,
           let existing = bookmarkAnnotations.first(where: {
               Locator(persistenceString: $0.locatorString)?.locations.position == position
           }) {
            return existing
        }
        let spineIndex = spineIndex(for: locator) ?? 0
        let bookmark = ReadingAnnotation(
            work: work,
            kind: .bookmark,
            locatorString: locatorString,
            progression: locator.locations.totalProgression ?? 0,
            spineIndex: spineIndex,
            chapterTitle: chapterTitle(forSpineIndex: spineIndex)
        )
        modelContext.insert(bookmark)
        try? modelContext.save()
        FolderSyncService.markDirty()
        return bookmark
    }


    /// Backfills `locations.position` when it's missing, so bookmarks created
    /// away from the live navigator still participate in `bookmarkAtCurrentPosition`'s
    /// position-based matching. Readium's search service returns locators with
    /// `progression` but not `position` (that's a separate `PositionsService`
    /// cross-reference the search index doesn't do) — storing one of those
    /// as-is meant a Find in Work bookmark could never be recognized as
    /// "already bookmarked" by the regular bookmark button, silently allowing
    /// a duplicate at the same spot. Finds the closest position-list entry in
    /// the same chapter by progression and borrows its `position`, leaving
    /// every other field (href, progression, text) untouched.
    private func resolvedPositionLocator(for locator: Locator) -> Locator {
        guard locator.locations.position == nil,
              let progression = locator.locations.progression,
              let spineIndex = spineIndex(for: locator),
              book.positionsByReadingOrder.indices.contains(spineIndex)
        else { return locator }
        let candidates = book.positionsByReadingOrder[spineIndex]
        guard let nearest = candidates.min(by: {
            abs(($0.locations.progression ?? 0) - progression) < abs(($1.locations.progression ?? 0) - progression)
        }), let resolvedPosition = nearest.locations.position else { return locator }
        return locator.copy(locations: { $0.position = resolvedPosition })
    }

    /// The section title to stamp on a new annotation, so its list row reads
    /// well even before the book's sections are loaded.
    private func chapterTitle(forSpineIndex index: Int) -> String {
        guard book.sections.indices.contains(index) else { return "" }
        return book.sections[index].title
    }

    /// Jumps to an annotation's anchor and closes the sheet. Highlights also
    /// open the note/colour/delete editor so a bare mark is editable in place.
    private func goToAnnotation(_ annotation: ReadingAnnotation) {
        if let locator = Locator(persistenceString: annotation.locatorString) {
            book.go(to: locator)
        }
        router.panel = .none
        if annotation.kind == .highlight {
            editingNote = annotation
        }
    }

    private func deleteAnnotation(_ annotation: ReadingAnnotation) {
        if editingNote?.id == annotation.id {
            editingNote = nil
        }
        if colorBarAnnotationID == annotation.id {
            colorBarAnnotationID = nil
        }
        modelContext.insert(SyncTombstone(
            recordID: annotation.id,
            recordType: .readingAnnotation,
            sourceURL: work.sourceURL,
            ao3WorkID: ao3WorkID
        ))
        modelContext.delete(annotation)
        try? modelContext.save()
        FolderSyncService.markDirty()
        refreshHighlightDecorations()
    }

    /// Opens the editor for a highlight the reader tapped on the page.
    private func openHighlight(id decorationID: String) {
        guard let annotation = annotations.first(where: {
            $0.kind == .highlight && $0.id.uuidString == decorationID
        }) else { return }
        editingNote = annotation
    }

    /// Submits mapped preferences and keeps page-box inputs in step with Customize:
    /// - **Text size / line height** → `renderedLineHeightPoints` + forced spread
    ///   content-inset refresh so whole-line snap is not stale.
    /// - **Page margin** → Readium horizontal `pageMargins` (vertical box uses
    ///   frozen safe area only; margin is not subtracted from safe top/bottom).
    private func applyReaderPreferences() {
        book.renderedLineHeightPoints = textStyle.fontSizePt * textStyle.lineHeight
        book.renderedPageMarginPoints = max(0, textStyle.margin)
        book.submit(preferences)
        // Typography submit updates CSS but may not re-run spread updateContentInset.
        book.forcePageBoxContentInsetRefresh()
        // Font/columns/mode/margin change swipe pageCount — remeasure instead of sticky Y.
        book.clearVisualPageMetrics()
        book.schedulePageBarRemeasure()
    }

    private func dismissReader() {
        // Close button / edge swipe: kill TTS page-follow, flush the live locator
        // once, then latch so `onDisappear`'s second flush cannot re-record a
        // speech- or teardown-corrupted position. Swipe-down already flushed +
        // latched before fly-off; latch is idempotent.
        speech.onAdvance = nil
        if !book.isDismissExitLatched {
            flushProgress(shelfStamp: true)
            book.latchDismissExit()
            isDismissingByDrag = true
        } else {
            // Already committed on peel success — shelf stamp only if needed.
            flushProgress(shelfStamp: true)
        }
        dismiss()
    }

    /// Flush point (dismiss / background / disappear): always persist the latest
    /// locator when it differs from disk, and refresh Continue Reading order.
    /// Bypasses the debounce window — a flush must never be dropped.
    private func flushProgress(shelfStamp: Bool) {
        progressPersistence.cancelTrailingWrite()
        // Prefer the live navigator locator; fall back to the last noted string.
        // After exit has committed (swipe peel or close/edge), never re-record a
        // live locator — freeze release / late TTS can still mutate `currentLocator`
        // while the view is tearing down.
        let exitCommitted = isDismissingByDrag || book.isDismissExitLatched
        if !exitCommitted, let live = book.currentLocator?.persistenceString {
            progressPersistence.record(
                locatorString: live,
                totalProgression: book.currentLocator?.locations.totalProgression
            )
        }
        let now = Date()
        if let toWrite = progressPersistence.locatorForFlush() {
            if shelfStamp {
                work.readiumLocator = toWrite
                work.markProgressModified(now)
            } else {
                work.applyDebouncedReadiumLocator(toWrite, at: now)
            }
            progressPersistence.markPersisted(
                locatorString: toWrite,
                totalProgression: book.currentLocator?.locations.totalProgression
                    ?? progressPersistence.latestTotalProgression,
                at: now
            )
            try? modelContext.save()
            FolderSyncService.markDirty()
        } else if shelfStamp, progressPersistence.hasSessionPosition {
            // Locator already on disk — still bump lastReadDate so the shelf
            // reflects this reading session on a quick open/close.
            work.markProgressModified(now)
            try? modelContext.save()
        }
    }

    /// Reader close is a natural batch point for reading progress, so it gets a
    /// near-immediate sync-up rather than waiting out the normal debounce window —
    /// but it must never block dismissal, so this fires a detached, best-effort Task.
    private func scheduleFolderSyncOnReaderClose() {
        FolderSyncService.markDirty()
        guard FolderSyncService.snapshot().isConnected, FolderSyncService.snapshot().autoSyncEnabled else { return }
        let context = modelContext
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            _ = try? await FolderSyncService.syncUp(in: context)
        }
    }

    // MARK: Chrome

    /// Page + floating chrome as one surface, so drag-to-dismiss moves the whole
    /// reader (not only the EPUB text) — Apple Books card behaviour.
    ///
    /// Host must always fill the screen: while `.loading`, bare `content` would
    /// be a centred ProgressView and chrome overlays would flash mid-screen.
    /// Sheets / lifecycle modifiers stay *outside* this tree so they are not
    /// scaled/offset with the card.
    private var dismissableReaderCard: some View {
        // UIKit host owns the peel transform for page + chrome as one unit.
        ReaderDismissPeelHost(surface: dismissSurface, reduceMotion: reduceMotion) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Each chrome layer sizes to its own content (no infinite-frame
                // hit-test area), so taps between controls still reach the page.
                .overlay(alignment: .top) { topBarLayer }
                // Bottom stack: colour bar + position card / decoupled mini player.
                .overlay(alignment: .bottom) { bottomChromeLayer }
                .overlay { fanDismissBackdropLayer }
                .overlay(alignment: .topTrailing) { fanMenuLayer }
                .background(readerTheme.backgroundColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // `host.safeAreaRegions = []` (inside the peel host) only stops the
        // *inner* UIHostingController from handing safe-area insets down to its
        // own SwiftUI content — it has no effect on how the *outer* SwiftUI
        // layout treats `ReaderDismissPeelHost` itself. Without this, SwiftUI
        // still shrinks this representable into the safe sub-rectangle by
        // default, and the manual `pageBoxChromeSafeTop`/`Bottom` chrome padding
        // below then stacks a second inset on top of that — the double top/
        // bottom padding bug. This is the modifier the "peel host zeroes SwiftUI
        // safe regions" comments elsewhere assumed was already in effect.
        .ignoresSafeArea()
    }

    private var topBarLayer: some View {
        ReaderChromeTopBar(
            title: work.title, author: work.author,
            tint: themeManager.effectiveTint, titleHidden: fanMenuOpen,
            onClose: dismissReader,
            onOpenDetails: { showingWorkDetail = true }
        )
        // Peel host zeroes SwiftUI safe regions — pad from the same frozen
        // window safe area the page box uses (plus chromeInset).
        .padding(.top, book.pageBoxChromeSafeTop + 8)
        .allowsHitTesting(chromeVisible)
        .opacity(chromeVisible ? 1 : 0)
    }

    /// Present only while the fan is open — otherwise a screen-sized tap target
    /// would swallow every tap meant for the page's own chrome toggle.
    @ViewBuilder
    private var fanDismissBackdropLayer: some View {
        if fanMenuOpen, chromeVisible {
            ReaderFanMenu.dismissBackdrop(isOpen: $fanMenuOpen, reduceMotion: reduceMotion)
        }
    }

    private var fanMenuLayer: some View {
        ReaderFanMenu(isOpen: $fanMenuOpen, pills: fanPills, shareURL: shareURL,
                      roundActions: fanRoundActions,
                      accentColor: themeManager.effectiveTint, reduceMotion: reduceMotion)
            .padding(.trailing, Self.chromeInset)
            .padding(.top, book.pageBoxChromeSafeTop + 8)
            .allowsHitTesting(chromeVisible)
            .opacity(chromeVisible ? 1 : 0)
    }

    /// Bottom chrome stack:
    /// - **Chrome up + speech:** colour bar (optional) + position card with mini player inside
    /// - **Chrome down + speech:** mini player alone (decoupled; seek card hidden)
    /// - **Chrome up, no speech:** position card only
    /// - **Chrome down, no speech:** empty
    ///
    /// Colour bar lives in this VStack (not a magic `+ 88` offset) so it always
    /// clears the card cleanly.
    @ViewBuilder
    private var bottomChromeLayer: some View {
        let speechActive = speech.isSessionActive
        VStack(spacing: 10) {
            if chromeVisible {
                highlightColorBar
                // Coupled: mini player rides inside the position card when speaking.
                positionCard(includeMiniPlayer: speechActive)
            } else if speechActive {
                // Decoupled: transport stays reachable while full chrome is hidden.
                standaloneMiniPlayer
            }
        }
        .padding(.horizontal, Self.chromeInset)
        .padding(.bottom, book.pageBoxChromeSafeBottom + Self.chromeInset)
        .allowsHitTesting(chromeVisible || speechActive)
    }

    @ViewBuilder
    private var highlightColorBar: some View {
        if let id = colorBarAnnotationID,
           let annotation = annotations.first(where: { $0.id == id })
        {
            ReaderHighlightColorBar(
                selected: annotation.color,
                onSelect: { applyHighlightColor($0, to: annotation) },
                onDismiss: { colorBarAnnotationID = nil }
            )
        }
    }

    /// Mini player in its own glass when chrome is dismissed mid-TTS.
    private var standaloneMiniPlayer: some View {
        speechMiniPlayer(tint: themeManager.effectiveTint)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func speechMiniPlayer(tint: SwiftUI.Color) -> some View {
        ReaderSpeechMiniPlayer(
            controller: speech,
            tint: tint,
            onStop: { stopReadingAloud() },
            onSkipBack: { handleSpeechSkipBack() },
            onSkipForward: { handleSpeechSkipForward() },
            onSeekHoldStart: { forward in handleSpeechSeekHoldStart(forward: forward) },
            onSeekHoldTick: { forward in handleSpeechSeekHoldTick(forward: forward) },
            onSeekHoldEnd: { handleSpeechSeekHoldEnd() },
            // Empty areas of the strip (caption, waveform, gutters) show chrome —
            // same idea as tapping the page when only the mini player is up.
            onBackgroundTap: { book.chromeHidden = false }
        )
    }

    /// Position card; when `includeMiniPlayer` the TTS strip sits above a
    /// hairline separator inside the same glass surface. While the EPUB is
    /// still opening (or before the first locator), show a glass skeleton so
    /// the bottom chrome occupies its final layout immediately.
    @ViewBuilder
    private func positionCard(includeMiniPlayer: Bool) -> some View {
        Group {
            if let summary = positionSummary {
                positionCardContent(summary: summary, includeMiniPlayer: includeMiniPlayer)
            } else {
                ReaderPositionCardSkeleton()
            }
        }
    }

    @ViewBuilder
    private func positionCardContent(
        summary: ReaderPositionSummary,
        includeMiniPlayer: Bool
    ) -> some View {
        let tint = themeManager.effectiveTint
        // Always use readingPosition for both page and pageCount so we never mix
        // visual swipe pages (e.g. 95) with Readium ~1 KB chapter positions (e.g. 10).
        // That mixed pair produced "Page 95 of 10" until the next swipe refreshed UI.
        let pos = book.readingPosition
        let pageReady = pos?.pageBarReady == true
        let pageCount = pageReady ? max(1, pos?.pageCount ?? 1) : 1
        let sliderEnabled = pageReady && pageCount > 1
        // Live page under the thumb while scrubbing; otherwise navigator page.
        let displayPage: Int = {
            guard pageReady else { return 1 }
            if isEditingSlider {
                return ReaderChapterScrub.page(sliderValue: sliderValue, pageCount: pageCount)
            }
            return min(pageCount, max(1, pos?.page ?? 1))
        }()
        // Chapter minutes left track the thumb while scrubbing.
        // Visual page units must never be fed to `minutes(forPositions:)` as if
        // they were ~1 KB Readium positions — scale via chapter position count.
        let chapterRemainingMinutes: Int? = {
            guard pageReady else { return nil }
            if isEditingSlider {
                guard let chapterPositions = book.currentChapterPositions,
                      !chapterPositions.isEmpty, pageCount > 0
                else { return nil }
                let remaining = ReaderPageMetrics.chapterRemainingPositions(
                    page: displayPage,
                    pageCount: pageCount,
                    chapterPositionCount: chapterPositions.count
                )
                return ReaderTimeEstimate.minutes(forPositions: remaining)
            }
            if let remaining = book.remainingPositions?.chapter {
                return ReaderTimeEstimate.minutes(forPositions: remaining)
            }
            return nil
        }()
        // Theme tint on page digit + "N min" when scrubbed away from origin.
        let scrubValuesEmphasized = ReaderChapterScrub.isDeviatedFromOrigin(
            sliderValue: sliderValue,
            origin: sliderScrubOrigin,
            pageCount: pageCount
        )
        // Until swipe-scale measure is ready: page=0 signals "Page …" (not 1 of 1).
        let cardPage = pageReady ? displayPage : 0
        let cardPageCount = pageReady ? pageCount : 0
        Group {
            if includeMiniPlayer {
                ReaderPositionCard(
                    page: cardPage,
                    pageCount: cardPageCount,
                    chapterRemainingMinutes: chapterRemainingMinutes,
                    workLine: summary.workLine,
                    tint: tint,
                    sliderValue: scrubBinding,
                    sliderEnabled: sliderEnabled,
                    scrubOrigin: sliderScrubOrigin,
                    scrubValuesEmphasized: scrubValuesEmphasized,
                    onEditingChanged: handleSliderEditingChanged
                ) {
                    speechMiniPlayer(tint: tint)
                }
            } else {
                ReaderPositionCard(
                    page: cardPage,
                    pageCount: cardPageCount,
                    chapterRemainingMinutes: chapterRemainingMinutes,
                    workLine: summary.workLine,
                    tint: tint,
                    sliderValue: scrubBinding,
                    sliderEnabled: sliderEnabled,
                    scrubOrigin: sliderScrubOrigin,
                    scrubValuesEmphasized: scrubValuesEmphasized,
                    onEditingChanged: handleSliderEditingChanged
                )
            }
        }
        // Selection ticks only while scrubbing (trigger is 0 when not editing).
        .sensoryFeedback(.selection, trigger: scrubPreviewPage(pageCount: pageCount))
    }

    /// Page under the thumb while scrubbing; stable `0` when not editing so
    /// sensory feedback only fires on real scrub steps.
    private func scrubPreviewPage(pageCount: Int) -> Int {
        guard isEditingSlider, pageCount > 0 else { return 0 }
        return ReaderChapterScrub.page(sliderValue: sliderValue, pageCount: pageCount)
    }

    /// The fan's labelled menu pills: Contents, Bookmarks & Highlights, Find in Work,
    /// Comments (AO3-backed works only — not in the reference design's four, but
    /// dropping it would lose an existing feature, which the brief forbids), and
    /// Themes & Settings.
    private var fanPills: [ReaderFanMenuPill] {
        var pills: [ReaderFanMenuPill] = [
            ReaderFanMenuPill(id: "contents", title: contentsPillTitle, systemImage: "list.bullet") {
                contentsSegment = .chapters
                router.panel = .readerChapters
            },
            ReaderFanMenuPill(id: "bookmarks", title: "Bookmarks & Highlights", systemImage: "bookmark") {
                contentsSegment = .bookmarks
                router.panel = .readerChapters
            },
            ReaderFanMenuPill(
                id: "find", title: "Find in Work", systemImage: "magnifyingglass",
                // Readium synthesises a content search service for EPUBs; if this
                // publication somehow has none, dim the control rather than open a
                // box that can never return anything.
                isEnabled: ReaderSearchModel.isSearchable(book.publication)
            ) {
                router.panel = .readerFind
            }
        ]
        if ao3WorkID != nil {
            pills.append(ReaderFanMenuPill(
                id: "comments", title: "Comments", systemImage: "bubble.left.and.bubble.right"
            ) {
                showingComments = true
            })
        }
        pills.append(ReaderFanMenuPill(id: "settings", title: "Themes & Settings", systemImage: "textformat.size") {
            router.panel = .readerDisplay
        })
        return pills
    }

    private var contentsPillTitle: String {
        guard let percent = book.totalProgression.map({ Int(($0 * 100).rounded()) }) else { return "Contents" }
        return "Contents · \(percent)%"
    }

    /// The work's page on AO3 — the `ShareLink` target in the fan's round row.
    private var shareURL: URL? {
        ao3WorkID.map(AO3AuthService.workURL)
    }

    /// The fan's round action row (after the native `ShareLink` slot): kudos is
    /// wired to the existing native write action; read aloud and in-book
    /// bookmarking are shown per the layout but disabled until their capabilities
    /// land (TASKS.md) rather than faked.
    private var fanRoundActions: [ReaderFanRoundAction] {
        var actions: [ReaderFanRoundAction] = []
        // Icons always use the reader theme tint; active/inactive is outline vs
        // filled SF Symbol (kudos heart, bookmark), not grey vs tint.
        let tint = themeManager.effectiveTint
        if let ao3WorkID {
            actions.append(ReaderFanRoundAction(
                id: "kudos",
                systemImage: kudosGiven ? "heart.fill" : "heart",
                tint: tint,
                accessibilityLabel: kudosGiven ? "Kudos given" : "Give kudos",
                isEnabled: !kudosWorking && !kudosGiven
            ) {
                giveKudos(workID: ao3WorkID)
            })
        }
        // Start when idle; when the mini player is up (playing *or* paused) this
        // is the same `stopReadingAloud()` the mini player's stop button uses —
        // not pause — so the strip dismisses instead of lingering muted.
        // `isSessionActive` (not `status != .stopped`): the raw comparison also
        // matched `.unavailable`, so a publication Readium can't speak got the
        // filled/emphasized "active" look and a "Stop reading aloud" a11y label
        // on a control that was simultaneously disabled below.
        let speechActive = speech.isSessionActive
        actions.append(ReaderFanRoundAction(
            id: "readAloud",
            // Active: filled waveform + theme capsule fill (same emphasized
            // treatment as rotation lock) so "speaking" is obvious at a glance.
            systemImage: speechActive ? "waveform.circle.fill" : "waveform",
            tint: tint,
            accessibilityLabel: speechActive ? "Stop reading aloud" : "Read aloud",
            // Needs extractable content; a publication Readium can't tokenise
            // gets a disabled control rather than silent no-op playback.
            isEnabled: speech.isAvailable,
            isEmphasized: speechActive
        ) {
            playReaderToggleHaptic()
            withAnimation(.snappy(duration: 0.35)) {
                toggleReadingAloud()
            }
        })
        let rotationLocked = orientationLock.isLocked
        actions.append(ReaderFanRoundAction(
            id: "rotationLock",
            // Open padlock while rotation is free, closed once pinned — the SF
            // Symbol for the open variant is `lock.open.rotation`, not
            // `lock.rotation.open`, which silently renders nothing. Pair with
            // `.contentTransition(.symbolEffect(.replace))` on the Image and
            // `withAnimation` here for the Control Center lock morph.
            // Locked also fills the capsule with theme tint + a white glyph so
            // the state is obvious (outline vs closed lock alone is too subtle).
            systemImage: rotationLocked ? "lock.rotation" : "lock.open.rotation",
            tint: tint,
            accessibilityLabel: rotationLocked ? "Unlock rotation" : "Lock rotation",
            isEmphasized: rotationLocked
        ) {
            playReaderToggleHaptic()
            withAnimation(.snappy(duration: 0.35)) {
                orientationLock.toggle(in: ReaderOrientationLock.activeScene)
            }
        })
        let isBookmarked = bookmarkAtCurrentPosition != nil
        actions.append(ReaderFanRoundAction(
            id: "bookmark",
            systemImage: isBookmarked ? "bookmark.fill" : "bookmark",
            tint: tint,
            accessibilityLabel: isBookmarked ? "Remove bookmark" : "Add bookmark",
            // Needs a locator to anchor to; disabled until the navigator reports one.
            isEnabled: currentReadingPosition != nil
        ) {
            playReaderToggleHaptic()
            toggleBookmarkAtCurrentPosition()
        })
        return actions
    }

    /// Light toggle tick for fan round actions (rotation lock, TTS, bookmark).
    private func playReaderToggleHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Stronger tick when a chapter skip / restart commits (Music-like boundary).
    private func playSpeechChapterHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Soft step feedback while hold-seeking within a chapter.
    private func playSpeechSeekTickHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: Loading + progress

    private func openBook() async {
        // Capture references (not the view struct) so the escaping callback is clean.
        let work = work
        let context = modelContext
        let router = router
        let progressPersistence = progressPersistence

        // Baseline + one session-open shelf stamp (Continue Reading). Mid-session
        // settles use the debounced path and do not rewrite lastReadDate.
        progressPersistence.seed(
            persistedLocatorString: work.readiumLocator.isEmpty ? nil : work.readiumLocator
        )
        work.markProgressModified(Date())
        try? context.save()

        progressPersistence.onDebouncedWrite = { locatorString in
            work.applyDebouncedReadiumLocator(locatorString)
            try? context.save()
            // Durable dirty flag only — does not schedule an immediate package
            // syncUp (that still waits for flush/close/background or launch).
            FolderSyncService.markDirty()
        }
        book.onLocatorChange = { locator in
            guard let string = locator.persistenceString else { return }
            // note() may call onDebouncedWrite immediately or schedule a trailing write.
            progressPersistence.note(
                locatorString: string,
                totalProgression: locator.locations.totalProgression
            )
        }
        // Finish a completed work only at the navigator's true end state — the
        // final resource visible with its trailing edge at 1.0 — never from a
        // progression threshold (A7-F1). WIPs stay manual, so an ongoing read
        // is never marked finished (and later freed) out from under the user.
        book.onReachedPublicationEnd = {
            // Keep locator + progressModifiedAt in sync for merge; full shelf stamp
            // only when we actually auto-finish (below).
            if let string = book.currentLocator?.persistenceString {
                work.applyDebouncedReadiumLocator(string)
                progressPersistence.markPersisted(
                    locatorString: string,
                    totalProgression: book.currentLocator?.locations.totalProgression
                )
                FolderSyncService.markDirty()
            }
            guard work.isComplete, !work.isFinished else {
                try? context.save()
                return
            }
            work.isFinished = true
            // Full stamp: Continue Reading + lastModifiedAt for folder-sync dirty.
            work.markProgressModified(Date())
            try? context.save()
        }
        book.onOpenExternalURL = { url in
            if openCommentsLinkIfMatching(url) { return }
            // AO3 links in the work (e.g. the preface's tag links) route to the matching
            // native screen where one exists; everything else opens the in-app web view.
            router.openAO3Link(url)
        }
        let initialLocator = Locator(persistenceString: work.readiumLocator)
        // No Readium progress yet but a legacy position exists → resume at that chapter.
        let fallbackSpineIndex = initialLocator == nil && work.lastSpineIndex > 0
            ? work.lastSpineIndex : nil
        let config = EPUBNavigatorViewController.Configuration(
            preferences: preferences,
            // Adds Highlight / Add Note to the system selection menu next to
            // Copy, Look Up and friends.
            editingActions: ReadiumBook.selectionEditingActions,
            fontFamilyDeclarations: fontFamilyDeclarations,
            readiumCSSRSProperties: ReadiumReaderStyleMapper.readingSystemProperties
        )
        await book.open(fileURL: work.fileURL, initialLocator: initialLocator,
                        fallbackSpineIndex: fallbackSpineIndex, config: config)
    }
}

/// Reader behaviour that isn't the view hierarchy itself: Apple-Music-style
/// speech chapter skip / hold-seek, the position card's label inputs, the
/// scrub slider's live seek, and kudos. Split out purely for navigability —
/// same file, so the `private` members above stay reachable and nothing
/// about access levels or behaviour changes.
extension ReadiumReaderView {

    // MARK: Contents sheet helpers

    /// Opens the note editor queued by Contents' **Add Note**, now that the
    /// panel sheet has finished dismissing. A no-op for every other way the
    /// panel closes, which is why it can hang off the shared `onDismiss`.
    private func presentPendingNoteEditor() {
        guard let pending = pendingNoteAfterPanelDismiss else { return }
        pendingNoteAfterPanelDismiss = nil
        editingNote = pending
    }

    /// First Readium locator of a chapter — the anchor for Contents' swipe
    /// actions, which act on the chapter's start rather than the live position.
    /// nil until `positionsByReadingOrder` has loaded, which is what gates those
    /// actions from appearing at all (see `ReaderContentsSheet`).
    private func chapterStartLocator(for section: ReaderSection) -> Locator? {
        guard book.positionsByReadingOrder.indices.contains(section.spineIndex) else { return nil }
        return book.positionsByReadingOrder[section.spineIndex].first
    }

    // MARK: Annotation lookups

    /// This work's live bookmarks / highlights / notes, in book order.
    private var annotations: [ReadingAnnotation] {
        allAnnotations.filter { $0.work?.id == work.id && !$0.isPendingDeletion }
    }

    private var bookmarkAnnotations: [ReadingAnnotation] {
        annotations.filter { $0.kind == .bookmark }
    }

    /// All in-book highlights (with or without a note). Bare marks used to be
    /// invisible here, which left no sheet-based path to delete them.
    private var noteAnnotations: [ReadingAnnotation] {
        annotations.filter { $0.kind == .highlight }
    }

    /// The Readium position (1-based, publication-wide) the reader is on.
    /// This is the page's identity, so bookmarking can toggle exactly rather
    /// than fuzzily matching progressions.
    private var currentReadingPosition: Int? {
        book.currentLocator?.locations.position
    }

    /// The bookmark on the current page, if one exists — drives the round
    /// button's filled/outline state and makes the tap a toggle.
    private var bookmarkAtCurrentPosition: ReadingAnnotation? {
        guard let position = currentReadingPosition else { return nil }
        return bookmarkAnnotations.first {
            Locator(persistenceString: $0.locatorString)?.locations.position == position
        }
    }

    // MARK: Contents / Display sheet

    private var readerSheetTitle: String {
        switch router.panel {
        case .readerChapters: "Contents"
        case .readerFind: "Find in Work"
        default: "Display & Themes"
        }
    }

    private var readerSheet: some View {
        NavigationStack {
            Group {
                if router.panel == .readerChapters {
                    ReaderContentsSheet(
                        segment: $contentsSegment,
                        sections: book.sections,
                        bookmarks: bookmarkAnnotations,
                        notes: noteAnnotations,
                        chapterStartPercent: { section in
                            guard let locator = chapterStartLocator(for: section),
                                  let progression = locator.locations.totalProgression
                            else { return nil }
                            return Int((progression * 100).rounded())
                        },
                        onSelectChapter: { section in
                            book.go(toSpineIndex: section.spineIndex)
                            router.panel = .none
                        },
                        onBookmarkChapter: { section in
                            guard let locator = chapterStartLocator(for: section) else { return }
                            addBookmark(at: locator)
                        },
                        onAddNoteToChapter: { section in
                            guard let locator = chapterStartLocator(for: section),
                                  let bookmark = addBookmark(at: locator)
                            else { return }
                            // Queue rather than present: the panel's `onDismiss`
                            // opens the editor once Contents is actually gone.
                            pendingNoteAfterPanelDismiss = bookmark
                            router.panel = .none
                        },
                        onSelectAnnotation: goToAnnotation,
                        onDeleteAnnotation: deleteAnnotation
                    )
                } else if router.panel == .readerFind {
                    ReaderSearchView(
                        model: searchModel,
                        publication: book.publication,
                        sections: book.sections,
                        // Matched by href against `book.sections`, the same basis
                        // `ReaderSearchGrouping` matches results against — not
                        // `readingPosition.chapter`, which is 1 + an index into
                        // `positionsByReadingOrder`. That array can have fewer
                        // entries than `book.sections` (any spine item with zero
                        // Readium positions is absent from it), so the two "chapter
                        // index" spaces can silently drift apart after such a gap.
                        // This was why "This Chapter" only pinned first sometimes.
                        currentSpineIndex: currentSpineIndex,
                        onSelect: { locator in
                            book.go(to: locator)
                            router.panel = .none
                        },
                        onBookmark: { locator in addBookmark(at: locator) }
                    )
                } else {
                    ReaderOptionsForm()
                }
            }
            .navigationTitle(readerSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { router.panel = .none }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Annotation rows and the segmented control tint from the theme, not the
        // raw accent, so Sepia keeps its warm brown.
        .tint(themeManager.effectiveTint)
        .preferredColorScheme(readerTheme.colorScheme)
    }
    private func handleSpeechSkipBack() {
        guard let pos = book.readingPosition else { return }
        switch ReaderSpeechSkip.backwardAction(
            page: pos.page,
            chapter: pos.chapter,
            chapterCount: pos.chapterCount
        ) {
        case .restartChapter:
            goToSpineChapterStart(pos.chapter, resumePlaying: speech.isPlaying)
            playSpeechChapterHaptic()
        case .previousChapter:
            goToSpineChapterStart(pos.chapter - 1, resumePlaying: speech.isPlaying)
            playSpeechChapterHaptic()
        case .none:
            break
        }
    }

    private func handleSpeechSkipForward() {
        guard let pos = book.readingPosition else { return }
        switch ReaderSpeechSkip.forwardAction(chapter: pos.chapter, chapterCount: pos.chapterCount) {
        case .nextChapter:
            goToSpineChapterStart(pos.chapter + 1, resumePlaying: speech.isPlaying)
            playSpeechChapterHaptic()
        case .none:
            break
        }
    }

    /// 1-based spine chapter → first Readium position; re-anchors TTS.
    private func goToSpineChapterStart(_ chapter1Based: Int, resumePlaying: Bool) {
        let index = chapter1Based - 1
        guard book.positionsByReadingOrder.indices.contains(index),
              let first = book.positionsByReadingOrder[index].first
        else { return }
        book.go(to: first)
        // Keep a paused session paused at the new chapter; only autoplay if we
        // were already speaking.
        speech.reanchor(to: first, resumePlaying: resumePlaying)
    }

    private func handleSpeechSeekHoldStart(forward: Bool) {
        speechSeekWasPlaying = speech.isPlaying
        speechSeekHolding = true
        if speech.isPlaying {
            speech.pause()
        }
        // First seek step is the hold control's immediate first tick.
    }

    private func handleSpeechSeekHoldTick(forward: Bool) {
        guard let positions = book.currentChapterPositions, positions.count > 1 else { return }
        // Never index the positions list with visual page-1 (mixed metrics).
        // Prefer the live locator's global position; else map visual→progression
        // the same way the chapter scrub slider does.
        let currentIdx: Int = {
            if let globalPos = book.currentLocator?.locations.position,
               let first = positions.first?.locations.position {
                return max(0, min(positions.count - 1, globalPos - first))
            }
            if let progression = book.currentLocator?.locations.progression, positions.count > 1 {
                let idx = Int((progression * Double(positions.count - 1)).rounded())
                return max(0, min(positions.count - 1, idx))
            }
            if let pos = book.readingPosition {
                return ReaderPageMetrics.positionIndex(
                    visualPage: pos.page,
                    visualPageCount: pos.pageCount,
                    positionCount: positions.count
                )
            }
            return 0
        }()
        let delta = forward ? 1 : -1
        guard let newIdx = ReaderSpeechSkip.seekIndex(
            current: currentIdx,
            count: positions.count,
            delta: delta
        ) else { return }
        let locator = positions[newIdx]
        book.go(to: locator)
        speech.noteSeekLocator(locator)
        playSpeechSeekTickHaptic()
    }

    private func handleSpeechSeekHoldEnd() {
        guard speechSeekHolding else { return }
        speechSeekHolding = false
        speech.reanchor(to: book.currentLocator, resumePlaying: speechSeekWasPlaying)
        speechSeekWasPlaying = false
    }

    /// The AO3 story chapter the reader is currently on, for the chapter-aware
    /// Comments entry and the position card's chapter line. `pos.chapter - 1` is
    /// the current spine index; the section list normalizes it past Preface/
    /// Summary/Afterword. nil (→ Comments opens on All) until a position and
    /// built sections both exist.
    private var currentAO3Chapter: Int? {
        guard let pos = book.readingPosition, !book.sections.isEmpty else { return nil }
        return book.sections.ao3StoryChapter(forSpineIndex: pos.chapter - 1)
    }

    /// The position card's label lines, built from `book.readingPosition` +
    /// `book.remainingPositions` — no new requests, no new persistence.
    private var positionSummary: ReaderPositionSummary? {
        guard let pos = book.readingPosition else { return nil }
        let remaining = book.remainingPositions
        return ReaderPositionSummary(
            page: pos.page, pageCount: pos.pageCount, percent: pos.percent,
            place: .resolve(chapter: pos.chapter, chapterCount: pos.chapterCount,
                            sections: book.sections,
                            postedChapterTotal: SavedWork.totalChapterCount(from: work.chapters)),
            remainingInChapter: remaining?.chapter, remainingInWork: remaining?.work
        )
    }

    /// Pushes the slider to the reader's live position while the user isn't
    /// dragging it, so it tracks normal reading without fighting the drag.
    /// While the page bar is not ready, leave the thumb alone — forcing 0 from
    /// the stub pageCount:1 readingPosition was a next/back snap on the slider.
    private func syncSliderFromPosition(_ pos: ReadiumBook.ReadingPosition?) {
        guard !isEditingSlider, let pos, pos.pageBarReady, pos.pageCount > 0 else { return }
        // A single-page chapter has nowhere left to go — page 1 of 1 is both the
        // start and the end, so the bar should read full, not empty.
        sliderValue = pos.pageCount > 1 ? Double(pos.page - 1) / Double(pos.pageCount - 1) : 1
    }

    /// Seeks the page under the thumb *while* dragging, so the text scrubs with
    /// the slider (Books-style) instead of only jumping on release. Rate-limited
    /// two ways — only when the rounded page actually changes, and at most once
    /// per `scrubSeekInterval` — because a fast drag across a long chapter would
    /// otherwise queue a `go(to:)` per intermediate page. `syncSliderFromPosition`
    /// stays suppressed while editing, so these seeks can't fight the thumb.
    private func handleScrubSeek() {
        guard isEditingSlider, !book.isLocatorIngestionBlocked, !isDismissingByDrag else { return }
        guard book.pageBarReady, book.visualPageCount != nil else { return }
        let pageCount = book.readingPosition?.pageCount ?? 0
        guard pageCount > 1 else { return }
        let page = ReaderChapterScrub.page(sliderValue: sliderValue, pageCount: pageCount)
        // Only when the rounded page actually changes — many slider samples map
        // to the same page. Backpressure past that is the seek's own job
        // (`scrubToProgressionInCurrentResource` coalesces to latest-wins), not
        // a fixed time gate here, which only ever added lag of its own.
        guard page != lastScrubSeekPage else { return }
        lastScrubSeekPage = page
        book.scrubToProgressionInCurrentResource(
            ReaderPageMetrics.progression(page: page, pageCount: pageCount)
        )
    }

    /// Write-through binding for the position card's slider: stores the thumb
    /// value, then live-seeks. Deliberately *not* an `.onChange(of: sliderValue)`
    /// on `body` — this view already carries enough modifiers that one more
    /// blew the SwiftUI type-checker's budget (see the `colorBarDismissToken`
    /// note for the same problem solved the same way).
    private var scrubBinding: Binding<Double> {
        Binding(
            get: { sliderValue },
            set: { newValue in
                sliderValue = newValue
                handleScrubSeek()
            }
        )
    }

    /// Live-seeks during the drag (`handleScrubSeek`) and commits the exact page
    /// on release — the release seek still runs unconditionally, since the last
    /// live one may have been rate-limited away short of where the thumb ended.
    /// On begin, freeze a scrub-origin tick so the user can return to cancel.
    private func handleSliderEditingChanged(_ editing: Bool) {
        if editing {
            isEditingSlider = true
            book.isScrubbing = true
            sliderScrubOrigin = sliderValue
            // Seed with where we already are, so the first tiny drag inside the
            // starting page doesn't fire a seek to the page we're on — which in
            // scrolled mode would snap the text to that page's top edge.
            lastScrubSeekPage = book.readingPosition?.page
            return
        }
        isEditingSlider = false
        book.isScrubbing = false
        sliderScrubOrigin = nil
        lastScrubSeekPage = nil
        // Ignore scrub commit while dismiss freeze / exit latch is up — a release
        // that races with swipe-down must not seek the navigator mid-exit.
        guard !book.isLocatorIngestionBlocked, !isDismissingByDrag else { return }
        let pageCount = book.readingPosition?.pageCount ?? 0
        guard pageCount > 0 else { return }
        let page = ReaderChapterScrub.page(sliderValue: sliderValue, pageCount: pageCount)
        // Swipe-scale seek once page bar is ready.
        if book.pageBarReady, book.visualPageCount != nil {
            book.goToProgressionInCurrentResource(
                ReaderPageMetrics.progression(page: page, pageCount: pageCount)
            )
            return
        }
        // Position-list fallback when visual metrics aren't available yet.
        guard let positions = book.currentChapterPositions, !positions.isEmpty else { return }
        let index = ReaderChapterScrub.positionIndex(
            sliderValue: sliderValue,
            pageCount: positions.count
        )
        book.go(to: positions[index])
    }

    private func giveKudos(workID: Int) {
        guard !kudosWorking, !kudosGiven else { return }
        kudosWorking = true
        Task {
            do {
                kudosBanner = try await auth.giveKudos(workID: workID)
                kudosGiven = true
            } catch {
                kudosBanner = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            kudosWorking = false
        }
    }

    private var kudosBannerPresented: Binding<Bool> {
        Binding(get: { kudosBanner != nil }, set: { if !$0 { kudosBanner = nil } })
    }
}

// MARK: - Theme mapping

extension ReaderTheme {
    /// The matching Readium navigator theme. Readium has no OLED case of its own —
    /// `.dark` gives the navigator's chrome (e.g. its own default selection color)
    /// the right dark-mode behavior, while `backgroundColor`/`textColor` above are
    /// passed through `EPUBPreferences` explicitly, so the true-black page and text
    /// colors are unaffected by this mapping.
    var readiumTheme: ReadiumNavigator.Theme {
        switch self {
        case .light: .light
        case .sepia: .sepia
        case .dark, .oled: .dark
        }
    }
}

// MARK: - Locator persistence (public-API only)

extension Locator {
    /// A JSON string suitable for storing in SwiftData. The toolkit's own
    /// `jsonString()` is internal, so round-trip through Foundation JSON using the
    /// public `jsonObject` / `JSONValue` accessors.
    var persistenceString: String? {
        let dict = jsonObject.mapValues(\.any)
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Rebuilds a `Locator` from `persistenceString`; nil if absent/invalid.
    init?(persistenceString: String) {
        guard !persistenceString.isEmpty,
              let data = persistenceString.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let json = JSONValue(any),
              let locator = try? Locator(json: json, warnings: nil)
        else { return nil }
        self = locator
    }
}


// MARK: - Visual page bridge (swipe-accurate bottom bar)

/// Receives `kudosVisualPage` messages from injected reflowable scripts and
/// updates `ReadiumBook` on the main actor for low-latency page labels/slider.
private final class VisualPageMessageBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "kudosVisualPage"
    weak var book: ReadiumBook?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName,
              let body = message.body as? [String: Any]
        else { return }
        let page = (body["page"] as? Int)
            ?? (body["page"] as? NSNumber)?.intValue
        let pageCount = (body["pageCount"] as? Int)
            ?? (body["pageCount"] as? NSNumber)?.intValue
        let fromUserScroll = (body["fromUserScroll"] as? Bool)
            ?? (body["fromUserScroll"] as? NSNumber)?.boolValue
            ?? false
        guard let page, let pageCount, fromUserScroll else { return }
        Task { @MainActor [weak book] in
            book?.applyVisualPageFromUserScroll(page: page, pageCount: pageCount)
        }
    }
}

#endif
