import OSLog
import SwiftData
import SwiftUI
#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import UIKit
import WebKit
#endif

/// `ReadiumBook` — owns the Readium navigator for one work — and the WKWebView
/// message bridge it feeds.
///
/// Split out of `ReadiumReaderView.swift`, which had reached 2500 non-comment
/// lines against SwiftLint's 1400-line *error* limit and so made
/// `Scripts/verify.sh` unpassable for every branch cut from this stack.
/// Pure code movement — no behavior change.
///
/// `VisualPageMessageBridge` moved here rather than staying behind because it is
/// `private` and `ReadiumBook` is its only consumer; keeping the two together
/// preserves that narrow visibility instead of widening it.
///
/// Two members did have to widen: `clearVisualPageMetrics()` and
/// `schedulePageBarRemeasure()` were `fileprivate` and are called by
/// `ReadiumReaderView`, which now lives elsewhere. `publishPageBar` and
/// `applyVisualPageFromUserScroll` stayed `fileprivate`, since their only callers
/// are in this file — which is exactly why the message bridge came along.

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
    /// True once the first spread has delivered a location — used to keep the
    /// page skeleton over the navigator so Readium's built-in activity spinner
    /// never shows between "opening" and readable text.
    private(set) var hasPresentedFirstPage = false
    /// Bumped on every `open` so a stale first-page safety timeout from a prior
    /// open (font reload / re-open) cannot lift the skeleton early.
    private var firstPagePresentationGeneration = 0
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
    ///
    /// Starts **hidden**: a work opens straight into the page, the way a book does,
    /// and one tap brings the bars back. Nothing resets this per open, so it also
    /// persists for as long as the book object lives.
    var chromeHidden = true

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
    func clearVisualPageMetrics() {
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
        ReaderWebIsolation.installReadiumStoreIsolation()
        ReaderWebIsolation.onReadiumOpenExternalURL = { [weak self] url in
            _ = self?.routeWebURLToBrowse(url)
        }
        phase = .loading
        hasPresentedFirstPage = false
        firstPagePresentationGeneration += 1
        let presentationGeneration = firstPagePresentationGeneration
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
            // Belt-and-braces. Spreads are wrapped when they assign
            // `navigationDelegate` (ReaderWebIsolation setter hook);
            // this only refreshes the Browse callback on views already
            // in the tree. A preloaded spread is guarded before load.
            if let view = navigator.view {
                ReaderWebIsolation.installNavigationGuards(
                    in: view,
                    origin: .readiumScheme,
                    onOpenExternalURL: ReaderWebIsolation.onReadiumOpenExternalURL
                )
            }
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
            // Do **not** set `hasPresentedFirstPage` here — seeding is not a rendered
            // spread. Readium still shows its centered activity indicator until the
            // first WebView spread loads; the view keeps the skeleton over the
            // navigator until `locationDidChange` (or the safety timeout below).
            if let initial {
                currentLocator = initial
            }
            phase = .ready
            // Single owner of open pageCount: delayed WKWebView measures.
            schedulePageBarRemeasure()
            scheduleFirstPagePresentationTimeout(generation: presentationGeneration)
            Log.epub.info("Opened EPUB (Readium): \(self.toc.count) TOC entries")
        } catch {
            // Nothing to wait for — drop the skeleton so the failure UI can show.
            hasPresentedFirstPage = true
            phase = .failed(error.localizedDescription)
            Log.epub.error("Couldn't open EPUB (Readium): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// If Readium never delivers `locationDidChange` (corrupt resource, stuck
    /// load), still lift the skeleton so the user isn't trapped on a wireframe.
    private func scheduleFirstPagePresentationTimeout(generation: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            guard self.firstPagePresentationGeneration == generation else { return }
            guard !self.hasPresentedFirstPage else { return }
            self.hasPresentedFirstPage = true
        }
    }

    private func markFirstPagePresentedIfNeeded() {
        guard !hasPresentedFirstPage else { return }
        hasPresentedFirstPage = true
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
    /// Internal (not `private`) so `ReadiumReaderTests` can exercise the nested-TOC
    /// flattening (A7-F8) directly with synthetic fixtures.
    static func buildSections(
        toc: [ReadiumShared.Link],
        readingOrder: [ReadiumShared.Link]
    ) -> [ReaderSection] {
        let spineHrefs = readingOrder.map(\.href)
        let spineKeys = spineHrefs.map(ReaderSectionBuilder.hrefKey)
        // Outermost-entry-wins on a duplicate spine target. A grouping node with no
        // page of its own (a "Part One" heading whose href is just its first
        // chapter's file) is an ordinary EPUB2 NCX shape, and flattening now emits
        // both it and that child. `ReaderSectionBuilder.build` resolves duplicates
        // last-write-wins, so without this the child would overwrite its parent and
        // silently rename that spine item — a behavior change beyond A7-F8's scope,
        // and one that can shift story-chapter numbering when the two titles
        // classify differently (e.g. an "Afterword" parent losing to a chapter
        // child). Dropping the deeper duplicate keeps exactly the title that won
        // before flattening, so this wave only *adds* the previously-missing
        // children. `build`'s own last-wins contract is shared with the macOS
        // pipeline and is deliberately left alone.
        var claimedSpineIndices: Set<Int> = []
        let rawTOC: [ReaderSectionBuilder.RawTOCEntry] = flattenTOC(toc).compactMap { link in
            let key = ReaderSectionBuilder.hrefKey(link.href)
            guard let spineIndex = spineKeys.firstIndex(of: key),
                  claimedSpineIndices.insert(spineIndex).inserted
            else { return nil }
            return ReaderSectionBuilder.RawTOCEntry(
                title: link.title ?? "Section \(spineIndex + 1)",
                spineIndex: spineIndex
            )
        }
        return ReaderSectionBuilder.build(tocEntries: rawTOC, spineHrefs: spineHrefs)
    }

    /// Readium models a hierarchical TOC (EPUB2 NCX / EPUB3 nav Part→Chapter
    /// nesting) via `Link.children`; flatten depth-first in document order so a
    /// chapter nested under a Part heading still gets its own navigable
    /// `RawTOCEntry` instead of silently disappearing (A7-F8 — the chapter sheet
    /// only ever iterated the top-level array, so a nested chapter's spine item
    /// fell back to `.other` and was hidden from the index). Duplicate spine
    /// targets this introduces are resolved by the caller — see the
    /// outermost-wins note in `buildSections`.
    private static func flattenTOC(_ links: [ReadiumShared.Link]) -> [ReadiumShared.Link] {
        links.flatMap { [$0] + flattenTOC($0.children) }
    }

    // MARK: EPUBNavigatorDelegate

    func navigator(_: Navigator, locationDidChange locator: Locator) {
        // Belt-and-braces sweep after a page settles. Creation-time wrap
        // is the setter hook in ReaderWebIsolation.
        if let view = navigator?.view {
            ReaderWebIsolation.installNavigationGuards(
                in: view,
                origin: .readiumScheme,
                onOpenExternalURL: ReaderWebIsolation.onReadiumOpenExternalURL
            )
        }
        // Freeze `setContentOffset` / hide-under-snapshot can emit spurious
        // location settles. Ignoring them keeps `currentLocator` (and flush)
        // at the pre-gesture reading position. Exit latch keeps the gate up
        // through successful dismiss teardown so a late settle cannot corrupt
        // the flushed resume point.
        guard !isLocatorIngestionBlocked else { return }
        // First post-open settle: the spread has painted enough for Readium to
        // report a location — lift the skeleton that was covering its spinner.
        markFirstPagePresentedIfNeeded()
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
    func schedulePageBarRemeasure() {
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
            lineHeight: CGFloat(renderedLineHeightPoints),
            // The live horizontal gutter, so bottom breathing room tracks the
            // margin the reader is actually rendering with (Customize → Margins).
            sideMargin: CGFloat(renderedPageMarginPoints),
            // Read from the same defaults key the reader's `@AppStorage("readerMode")`
            // uses rather than mirrored onto this object, so the two cannot drift.
            snapsToLineGrid: UserDefaults.standard.string(forKey: "readerMode")
                == ReadingMode.paged.rawValue
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
        sideMargin: CGFloat = CGFloat(ReaderTextStyle.defaultMargin),
        minimumEdge: CGFloat = minimumBottomInset,
        snapsToLineGrid: Bool = true
    ) -> (top: CGFloat, bottom: CGFloat) {
        // The bottom is capped at the *side* margin, so the page has the same
        // breathing room under the last line as it does beside every line.
        //
        // It used to be `max(minimumEdge, safeBottom)` plus the line remainder —
        // on a home-indicator phone that is 34pt of safe area plus up to a full
        // line, so the text stopped 60pt+ above the edge while the sides sat at
        // ~20pt. It read as a large empty band (owner-reported). Text under the
        // home indicator is fine — it is a thin translucent bar, not a bezel, and
        // this is what Books does — so the safe area is a *ceiling* here, not a
        // floor.
        let bottom = max(minimumEdge, min(safeBottom, sideMargin))
        let top = max(0, safeTop)
        let availableForText = viewHeight - top - bottom
        // Scrolled mode has no page box to fit lines into — text runs continuously,
        // so there is no fold for a half line to peek at and nothing to snap to.
        // Snapping there was pure waste: it padded the bottom by up to a full line
        // for a constraint that does not exist, which is the dead space the owner
        // reported (Books, scrolling, has exactly its margins and nothing more).
        guard snapsToLineGrid, lineHeight > 0, availableForText > lineHeight else {
            return (top, bottom)
        }
        // Whole-line snapping still matters in paged mode (no half line peeking at
        // the fold), and the leftover has to live at one end or the other: the band
        // is a whole number of lines, so `top + bottom` is fixed for a given view
        // height and line height. Moving it to the top was tried and rejected — it
        // just relocated the dead space to between the island and the first line,
        // where it is *more* obvious. So it stays at the bottom, and the win comes
        // from the floor underneath it dropping from `max(8, safeBottom)` (34pt on a
        // home-indicator phone) to the side margin (~20pt).
        //
        // Removing the leftover altogether means making the band divide evenly by
        // nudging the *line height* a fraction of a percent instead of padding the
        // box — invisible to a reader, but it moves page counts and time estimates,
        // so it is its own change rather than a tweak here.
        let remainder = availableForText.truncatingRemainder(dividingBy: lineHeight)
        return (top, bottom + remainder)
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
            sideMargin: minimum,
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
