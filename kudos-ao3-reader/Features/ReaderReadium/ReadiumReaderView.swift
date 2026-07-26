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

/// Converts the app's point/em-based reader settings into Readium's percentage
/// and factor-based preferences. Keeping the calibration here makes the mapping
/// testable and prevents the SwiftUI view from accumulating magic numbers.
enum ReadiumReaderStyleMapper {
    /// Readium CSS starts from the browser's 16 px root size.
    private static let readiumBaseFontSize = 16.0

    static func preferences(
        style: ReaderTextStyle,
        theme: ReaderTheme,
        fontFamily: FontFamily?,
        readingMode: ReadingMode,
        columnCount: ColumnCount?
    ) -> EPUBPreferences {
        EPUBPreferences(
            backgroundColor: ReadiumNavigator.Color(hex: theme.backgroundHex),
            // Only set a column count in paged mode. Forcing `.one` in scroll mode makes
            // Readium lay the text out in screen-height columns (page breaks mid-text +
            // dead space top/bottom) instead of one continuous flow.
            columnCount: readingMode == .scroll ? nil : columnCount,
            fontFamily: fontFamily,
            // Legacy CSS emits the selected point size as px. Readium expects a
            // percentage of its 16 px root, so 18 pt becomes 112.5%.
            fontSize: max(0.1, style.fontSizePt / readiumBaseFontSize),
            // Legacy bold is 600. Readium multiplies this value by its 400
            // normal weight, so 1.5 produces the same result.
            fontWeight: style.bold ? 1.5 : nil,
            // Readium CSS divides this preference by two before emitting rem.
            // Compensate so the positive half of the app's em slider is exact.
            letterSpacing: max(0, style.letterSpacing * 2),
            lineHeight: style.lineHeight,
            // The navigator configuration uses a 1 px base gutter, turning
            // Readium's factor into the app's absolute point/px margin.
            pageMargins: max(0, style.margin),
            // The legacy reader always overrides the EPUB's base typography.
            // Advanced Readium settings require publisher styles to be off.
            publisherStyles: false,
            scroll: readingMode == .scroll,
            textAlign: style.justify ? .justify : nil,
            textColor: ReadiumNavigator.Color(hex: theme.textHex),
            theme: theme.readiumTheme,
            wordSpacing: max(0, style.wordSpacing)
        )
    }

    static var readingSystemProperties: CSSRSProperties {
        CSSRSProperties(pageGutter: CSSPxLength(1))
    }

    static func fontFamily(for option: ReaderFontOption) -> FontFamily? {
        if option.isCustom {
            // The selection id contains ":" and ".". Prefix it with a space-
            // containing family name so Readium quotes it in the CSS custom
            // property instead of emitting an invalid bare CSS identifier.
            return FontFamily(rawValue: "Kudos User Font \(option.id)")
        }
        return fontStack(in: option.cssFamily).first
    }

    /// Declares both imported files and the fallback stacks for the built-in
    /// choices. Readium otherwise emits only the first family name, losing the
    /// legacy reader's carefully chosen fallbacks.
    static func fontFamilyDeclarations(
        options: [ReaderFontOption]
    ) -> [AnyHTMLFontFamilyDeclaration] {
        options.compactMap { option in
            guard let family = fontFamily(for: option) else { return nil }
            let stack = fontStack(in: option.cssFamily)
            let alternates = stack.filter { $0 != family }
            let faces: [CSSFontFace] = if let file = option.customFileURL?.fileURL {
                // Readium serves imported files through a separate custom-scheme
                // host. Preloading that URL trips WebKit's cross-origin check;
                // allowing the @font-face rule to request it normally works.
                [CSSFontFace(file: file)]
            } else {
                []
            }
            return CSSFontFamilyDeclaration(
                fontFamily: family,
                alternates: alternates,
                fontFaces: faces
            ).eraseToAnyHTMLFontFamilyDeclaration()
        }
    }

    private static func fontStack(in cssFamily: String) -> [FontFamily] {
        cssFamily
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            }
            .filter { !$0.isEmpty }
            .map(FontFamily.init(rawValue:))
    }
}

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
    /// Readium's static position list grouped by reading-order item (chapter).
    /// Drives the progress pill's "Ch. x/x · Pg. x/x" without any extra requests.
    private(set) var positionsByReadingOrder: [[Locator]] = []
    /// Toggled by tapping the page; the view hides/shows its chrome on this.
    var chromeHidden = false

    /// The body's rendered line height in points — font size × the line-height
    /// multiplier, mirrored from the view's `ReaderTextStyle` whenever
    /// preferences are submitted. `navigatorContentInset` uses it to end the
    /// paged page box on a whole line; it must track the *effective* style
    /// (`.resolved`), since the Customize toggle can override the multiplier.
    var renderedLineHeightPoints: Double =
        ReaderTextStyle.defaultFontSizePt * ReaderTextStyle.defaultLineHeight

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

    /// A compact reading position for the progress pill: overall percent plus the
    /// current chapter and the page within it. Pages are Readium "positions"
    /// (~1 KB of content each), so they stay stable across font-size changes.
    struct ReadingPosition: Equatable {
        let percent: Int
        let chapter: Int
        let chapterCount: Int
        let page: Int
        let pageCount: Int
    }

    var readingPosition: ReadingPosition? {
        guard let locator = currentLocator,
              let globalPos = locator.locations.position,
              !positionsByReadingOrder.isEmpty
        else { return nil }
        // Find the chapter whose global position range contains the current spot.
        guard let chapterIndex = positionsByReadingOrder.firstIndex(where: { chapter in
            guard let first = chapter.first?.locations.position,
                  let last = chapter.last?.locations.position else { return false }
            return globalPos >= first && globalPos <= last
        }) else { return nil }
        let chapterPositions = positionsByReadingOrder[chapterIndex]
        let pageCount = max(1, chapterPositions.count)
        let firstPos = chapterPositions.first?.locations.position ?? globalPos
        let page = min(pageCount, max(1, globalPos - firstPos + 1))
        let percent = Int(((locator.locations.totalProgression ?? 0) * 100).rounded())
        return ReadingPosition(percent: percent,
                               chapter: chapterIndex + 1, chapterCount: positionsByReadingOrder.count,
                               page: page, pageCount: pageCount)
    }

    /// The current chapter's Readium positions, in reading order — the slider's
    /// seek targets (`positionsByReadingOrder[chapterIndex]`).
    var currentChapterPositions: [Locator]? {
        guard let pos = readingPosition, positionsByReadingOrder.indices.contains(pos.chapter - 1)
        else { return nil }
        return positionsByReadingOrder[pos.chapter - 1]
    }

    /// Remaining Readium positions in the current chapter and across the whole
    /// publication — feeds `ReaderTimeEstimate` for the position card's time labels.
    var remainingPositions: (chapter: Int, work: Int)? {
        guard let pos = readingPosition, let globalPos = currentLocator?.locations.position else { return nil }
        let totalPositions = positionsByReadingOrder.reduce(0) { $0 + $1.count }
        return (chapter: max(0, pos.pageCount - pos.page), work: max(0, totalPositions - globalPos))
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
            readingOrder = publication.readingOrder
            toc = tocLinks.isEmpty ? readingOrder : tocLinks
            positionsByReadingOrder = await (try? publication.positionsByReadingOrder().get()) ?? []
            sections = Self.buildSections(toc: toc, readingOrder: readingOrder)
            phase = .ready
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
        currentLocator = locator
        onLocatorChange?(locator)
    }

    /// True-end completion check only. Readium updates `viewport` with
    /// `currentLocation`; we derive a boolean and only publish it when the
    /// end state flips so scrolled settles don't invalidate SwiftUI for free.
    /// Rising-edge only for `onReachedPublicationEnd`.
    func navigator(_: any ViewportObservingNavigator, viewportDidChange viewport: NavigatorViewport?) {
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
        let source = """
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
            source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false
        ))
    }

    /// Encodes a string as a JavaScript literal via JSON, so quotes, newlines and
    /// backslashes in the CSS can't break out of it.
    private static func javaScriptStringLiteral(_ value: String) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "\"\""
    }

    /// Trims Readium's default reflowable content insets (the navigator treats
    /// iPhone portrait as the `.regular` vertical size class and reserves 62 pt
    /// top and bottom, a large dead band) and — the part that matters in paged
    /// mode — sizes the page box so it ends exactly on a line boundary.
    ///
    /// In paged mode this inset is what sets the page box height
    /// (`bottomConstraint` in Readium's `EPUBReflowableSpreadView`), and the
    /// navigator runs full-screen under `.ignoresSafeArea()`. A *fixed* bottom
    /// inset therefore can't be right: whether the box happens to end mid-line
    /// depends on `(available height) mod (line height)`, so one constant slices
    /// the last line in half at some text sizes and leaves a dead band at others
    /// — and the reader changes line height every time they touch Text Size.
    ///
    /// So compute it instead: take the largest whole number of lines that fits
    /// above `minimumBottomInset`, and give the remainder back as the inset. The
    /// box then always ends on a line boundary (no sliced line at any text size)
    /// while the leftover stays under one line — the least dead space this layout
    /// can have, since paged fragmentation already moves a line that won't fit.
    ///
    /// Falls back to the plain minimum when the line height or view height isn't
    /// usable, which is never worse than the fixed-inset behaviour it replaces.
    ///
    /// Read the safe area from `window`, not the navigator's own view: that view
    /// ignores the safe area and so reports insets of zero.
    func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
        let view = (navigator as? UIViewController)?.view
        let safeTop = view?.window?.safeAreaInsets.top ?? 0
        return UIEdgeInsets(top: safeTop, left: 0,
                            bottom: snappedBottomInset(viewHeight: view?.bounds.height ?? 0,
                                                       safeTop: safeTop),
                            right: 0)
    }

    /// Clearance kept below the last line even after snapping, so text never sits
    /// flush against the screen edge / home indicator.
    static let minimumBottomInset: CGFloat = 8

    /// The remainder left over after fitting whole lines into the available
    /// height. Pure arithmetic, so `ReaderPageBoxTests` can pin the two rules
    /// that matter: the result is never below the minimum, and the height it
    /// leaves is always an exact multiple of the line height.
    nonisolated static func snappedBottomInset(
        viewHeight: CGFloat, safeTop: CGFloat, lineHeight: CGFloat,
        minimum: CGFloat = minimumBottomInset
    ) -> CGFloat {
        let available = viewHeight - safeTop - minimum
        guard lineHeight > 0, available > lineHeight else { return minimum }
        let remainder = available.truncatingRemainder(dividingBy: lineHeight)
        return minimum + remainder
    }

    private func snappedBottomInset(viewHeight: CGFloat, safeTop: CGFloat) -> CGFloat {
        Self.snappedBottomInset(viewHeight: viewHeight, safeTop: safeTop,
                                lineHeight: CGFloat(renderedLineHeightPoints))
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

/// Thin SwiftUI host for an already-built `EPUBNavigatorViewController`. Adds a
/// downward swipe gesture on top of Readium so the reader can be dismissed without
/// interfering with the navigator's built-in page turns.
struct ReadiumNavigatorContainer: UIViewControllerRepresentable {
    let controller: EPUBNavigatorViewController
    let readingMode: ReadingMode
    let onDismissDragChanged: (CGFloat) -> Void
    let onDismissDragEnded: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        context.coordinator.update(readingMode: readingMode,
                                   onDismissDragChanged: onDismissDragChanged,
                                   onDismissDragEnded: onDismissDragEnded)
        context.coordinator.install(on: controller)
        return controller
    }

    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {
        context.coordinator.update(readingMode: readingMode,
                                   onDismissDragChanged: onDismissDragChanged,
                                   onDismissDragEnded: onDismissDragEnded)
        context.coordinator.install(on: controller)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var readingMode: ReadingMode = .scroll
        private var onDismissDragChanged: (CGFloat) -> Void = { _ in }
        private var onDismissDragEnded: (Bool) -> Void = { _ in }
        private weak var installedView: UIView?
        private var dismissPan: UIPanGestureRecognizer?
        /// Latched once a drag is recognized as a downward dismiss, so minor sideways
        /// wobble mid-drag doesn't snap the sheet back to rest (the old jank source).
        private var dismissLatched = false

        func update(
            readingMode: ReadingMode,
            onDismissDragChanged: @escaping (CGFloat) -> Void,
            onDismissDragEnded: @escaping (Bool) -> Void
        ) {
            self.readingMode = readingMode
            self.onDismissDragChanged = onDismissDragChanged
            self.onDismissDragEnded = onDismissDragEnded
        }

        func install(on controller: EPUBNavigatorViewController) {
            guard let view = controller.view else { return }
            guard installedView !== view else { return }

            if let dismissPan {
                dismissPan.view?.removeGestureRecognizer(dismissPan)
            }

            let dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan))
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
            case .changed:
                if !dismissLatched {
                    // Latch as a dismiss once a clearly downward, vertical-dominant drag
                    // starts (and, in scroll mode, only from the top of the page).
                    let startsDismiss = translation.y > 12
                        && translation.y > abs(translation.x) * 1.1
                        && (readingMode != .scroll || isAtTop(in: view))
                    guard startsDismiss else { return }
                    dismissLatched = true
                }
                onDismissDragChanged(rubberBandedDistance(max(0, translation.y)))
            case .ended:
                guard dismissLatched else { onDismissDragEnded(false); return }
                let passesDistance = translation.y > 110
                let passesVelocity = translation.y > 40 && velocity.y > 900
                onDismissDragEnded(passesDistance || passesVelocity)
                dismissLatched = false
            case .cancelled, .failed:
                onDismissDragEnded(false)
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
            true
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

    @State private var book = ReadiumBook()
    /// Debounces SwiftData writes for the Readium locator stream (see
    /// `ReadiumProgressPersistence`). UI locator / progress pill stay live.
    @State private var progressPersistence = ReadiumProgressPersistence()
    /// Native comments sheet over the reader (only for AO3-backed works).
    @State private var showingComments = false

    private var ao3WorkID: Int? {
        work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)
    }
    @State private var dismissDragOffset: CGFloat = 0
    @State private var isDismissingByDrag = false

    // MARK: Chrome state

    @State private var fanMenuOpen = false
    /// Which tab the Contents sheet opens on — the fan's "Contents" and
    /// "Bookmarks & Notes" pills both route here, differing only in this.
    @State private var contentsSegment: ReaderContentsSegment = .chapters
    /// Chapter-relative seek fraction (0...1) shown by the position card's slider.
    /// Driven from `book.readingPosition` while not being dragged; only pushed to
    /// the navigator on editing-ended, so it never fights `locationDidChange`.
    @State private var sliderValue: Double = 0
    @State private var isEditingSlider = false
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
            get: { router.panel == .readerChapters || router.panel == .readerDisplay },
            set: { if !$0 { router.panel = .none } }
        )
    }

    var body: some View {
        content
            .modifier(ReaderInteractiveDismissStyle(offset: dismissDragOffset,
                                                    reduceMotion: reduceMotion))
            // Every floating chrome layer sits outside the dismiss-style transform (not
            // inside `content`) so it's immune to the swipe-to-dismiss pan's scale/
            // offset/clip — including its brief spring-back when an ordinary tap's
            // incidental finger movement crosses the pan's own latch threshold without
            // becoming a real dismiss. That spring-back is a legitimate, real animation
            // (not a no-op), so it can't be skipped; keeping the chrome out of the
            // transformed subtree means it never rides along with it, whatever the cause.
            //
            // Each layer sizes to its own content (no infinite-frame hit-test area), so
            // taps in the empty space between them still reach the page and toggle
            // chrome via Readium's own `didTapAt`, exactly as before.
            .overlay(alignment: .top) { topBarLayer }
            .overlay(alignment: .bottom) { positionCardLayer }
            // Between the other chrome and the fan: while the fan is open, the
            // first tap anywhere outside it closes it rather than reaching the
            // control behind, and the fan itself stays hit-testable above this.
            .overlay { fanDismissBackdropLayer }
            .overlay(alignment: .topTrailing) { fanMenuLayer }
            .background(readerTheme.backgroundColor)
            .preferredColorScheme(readerTheme.colorScheme)
            .navigationTitle(work.title)
            .navigationBarTitleDisplayMode(.inline)
            // The floating top bar replaces the system nav bar entirely.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: readerPanelBinding) { readerSheet }
            .commentsSheet(
                isPresented: $showingComments,
                workID: ao3WorkID ?? 0,
                context: .init(savedWork: work),
                initialChapterPosition: currentAO3Chapter
            )
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
            // Readium's WebView swallows the system edge-swipe; add our own.
            .edgeSwipeToGoBack { dismissReader() }
            .task(id: bookLoadToken) {
                // Seed the line height before the navigator exists: its first
                // content-inset query happens during setup, well before any
                // preference change would otherwise supply it.
                book.renderedLineHeightPoints = textStyle.fontSizePt * textStyle.lineHeight
                await openBook()
            }
            .onChange(of: preferencesToken) { _, _ in applyReaderPreferences() }
            // The Display / Customize controls live in a sheet over the reader; a
            // behind-the-sheet onChange can be missed, so re-apply when it closes.
            .onChange(of: router.panel) { _, panel in
                if panel == .none { applyReaderPreferences() }
            }
            .onChange(of: book.readingPosition) { _, newValue in
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
                // Flush the exact final position so resume lands precisely, even if the
                // last scroll's debounce window hadn't elapsed before we left.
                flushProgress(shelfStamp: true)
                WorkLifecycle.freeEPUBIfFinished(work, in: modelContext)
                try? modelContext.save()
                scheduleFolderSyncOnReaderClose()
                if router.panel == .readerChapters || router.panel == .readerDisplay {
                    router.panel = .none
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch book.phase {
        case .loading:
            ProgressView("Opening…")
        case let .failed(message):
            ContentUnavailableView("Couldn't open this EPUB", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .ready:
            if let navigator = book.navigator {
                ReadiumNavigatorContainer(
                    controller: navigator,
                    readingMode: readingMode,
                    onDismissDragChanged: handleDismissDragChanged,
                    onDismissDragEnded: handleDismissDragEnded
                )
                .ignoresSafeArea()
            }
        }
    }

    private func handleDismissDragChanged(_ offset: CGFloat) {
        guard !isDismissingByDrag else { return }
        dismissDragOffset = offset
    }

    private func handleDismissDragEnded(_ shouldDismiss: Bool) {
        guard !isDismissingByDrag else { return }
        if shouldDismiss {
            isDismissingByDrag = true
            flushProgress(shelfStamp: true)
            if reduceMotion {
                dismissReader()
                return
            }
            // Slide the page the rest of the way off, then pop without the navigation
            // stack's own animation (the view is already off-screen) for a seamless exit.
            withAnimation(.easeIn(duration: 0.22)) {
                dismissDragOffset = 1400
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 210_000_000)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dismissReader() }
            }
        } else if dismissDragOffset != 0 {
            // Spring back to rest tracking; a snappy, well-damped return (no overshoot).
            // The dismiss-pan recognizer doesn't cancel other touches, so it also sees
            // every ordinary tap-to-toggle-chrome — those never latch as a dismiss, so
            // `dismissDragOffset` is already 0 here. Skipping the no-op reset means an
            // ordinary tap never opens a spring-animation transaction that can bleed
            // into (and jitter) the chrome toggle's own animation for the same tap.
            withAnimation(.interpolatingSpring(stiffness: 340, damping: 32)) {
                dismissDragOffset = 0
            }
        }
    }

    /// Submits the mapped preferences and keeps the page-box line height in step,
    /// so `navigatorContentInset`'s whole-line snap follows every Text Size /
    /// line-spacing change instead of snapping against a stale value. Readium
    /// re-queries the inset from `applySettings()` on submit, so the two always
    /// land together. `textStyle` is already `.resolved`, so this is the height
    /// actually rendered rather than the raw stored setting.
    private func applyReaderPreferences() {
        book.renderedLineHeightPoints = textStyle.fontSizePt * textStyle.lineHeight
        book.submit(preferences)
    }

    private func dismissReader() {
        flushProgress(shelfStamp: true)
        dismiss()
    }

    /// Flush point (dismiss / background / disappear): always persist the latest
    /// locator when it differs from disk, and refresh Continue Reading order.
    /// Bypasses the debounce window — a flush must never be dropped.
    private func flushProgress(shelfStamp: Bool) {
        progressPersistence.cancelTrailingWrite()
        // Prefer the live navigator locator; fall back to the last noted string.
        if let live = book.currentLocator?.persistenceString {
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

    private var topBarLayer: some View {
        ReaderChromeTopBar(
            title: work.title, author: work.author,
            tint: themeManager.effectiveTint, titleHidden: fanMenuOpen,
            onClose: dismissReader
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
                      roundActions: fanRoundActions, reduceMotion: reduceMotion)
            .padding(.trailing, 12)
            .padding(.top, 8)
            .allowsHitTesting(chromeVisible)
            .opacity(chromeVisible ? 1 : 0)
            // Close the fan when the chrome itself hides (tap-to-hide) so it can't
            // reopen invisibly-but-tappable underneath the chrome's next show.
            .onChange(of: chromeVisible) { _, visible in if !visible { fanMenuOpen = false } }
    }

    private var positionCardLayer: some View {
        Group {
            if let summary = positionSummary {
                ReaderPositionCard(
                    pageLabel: summary.pageLabel,
                    chapterTimeLabel: summary.chapterTimeLabel,
                    workLine: summary.workLine,
                    tint: themeManager.effectiveTint,
                    sliderValue: $sliderValue,
                    sliderEnabled: (book.currentChapterPositions?.count ?? 0) > 1,
                    onEditingChanged: handleSliderEditingChanged
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 28)
        .allowsHitTesting(chromeVisible)
        .opacity(chromeVisible ? 1 : 0)
    }

    /// The fan's labelled menu pills: Contents, Bookmarks & Notes, Find in Work,
    /// Comments (AO3-backed works only — not in the reference design's four, but
    /// dropping it would lose an existing feature, which the brief forbids), and
    /// Themes & Settings.
    private var fanPills: [ReaderFanMenuPill] {
        var pills: [ReaderFanMenuPill] = [
            ReaderFanMenuPill(id: "contents", title: contentsPillTitle, systemImage: "list.bullet") {
                contentsSegment = .chapters
                router.panel = .readerChapters
            },
            ReaderFanMenuPill(id: "bookmarks", title: "Bookmarks & Notes", systemImage: "bookmark") {
                contentsSegment = .bookmarks
                router.panel = .readerChapters
            },
            // Find in Work: shown per the layout, disabled until the Readium
            // search integration lands (see TASKS.md) — no fake search box.
            ReaderFanMenuPill(id: "find", title: "Find in Work", systemImage: "magnifyingglass", isEnabled: false) {}
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
        if let ao3WorkID {
            actions.append(ReaderFanRoundAction(
                id: "kudos", systemImage: kudosGiven ? "heart.fill" : "heart",
                tint: kudosGiven ? .pink : .primary,
                accessibilityLabel: kudosGiven ? "Kudos given" : "Give kudos",
                isEnabled: !kudosWorking && !kudosGiven
            ) {
                giveKudos(workID: ao3WorkID)
            })
        }
        actions.append(ReaderFanRoundAction(
            id: "readAloud", systemImage: "waveform", tint: .primary,
            accessibilityLabel: "Read aloud", isEnabled: false
        ) {})
        actions.append(ReaderFanRoundAction(
            id: "bookmark", systemImage: "bookmark", tint: .primary,
            accessibilityLabel: "Add bookmark", isEnabled: false
        ) {})
        return actions
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
    private func syncSliderFromPosition(_ pos: ReadiumBook.ReadingPosition?) {
        guard !isEditingSlider, let pos else { return }
        sliderValue = pos.pageCount > 1 ? Double(pos.page - 1) / Double(pos.pageCount - 1) : 0
    }

    /// Only navigates when the drag ends — the slider drives itself freely while
    /// being dragged, and `syncSliderFromPosition` is suppressed meanwhile so the
    /// navigator's own `locationDidChange` can't snap the thumb back mid-drag.
    private func handleSliderEditingChanged(_ editing: Bool) {
        isEditingSlider = editing
        guard !editing, let positions = book.currentChapterPositions, !positions.isEmpty else { return }
        let index = min(positions.count - 1, max(0, Int((sliderValue * Double(positions.count - 1)).rounded())))
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

    // MARK: Contents / Display sheet

    private var readerSheet: some View {
        NavigationStack {
            Group {
                if router.panel == .readerChapters {
                    ReaderContentsSheet(segment: $contentsSegment, sections: book.sections) { section in
                        book.go(toSpineIndex: section.spineIndex)
                        router.panel = .none
                    }
                } else {
                    ReaderOptionsForm()
                }
            }
            .navigationTitle(router.panel == .readerChapters ? "Contents" : "Display & Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { router.panel = .none }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(readerTheme.colorScheme)
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
            fontFamilyDeclarations: fontFamilyDeclarations,
            readiumCSSRSProperties: ReadiumReaderStyleMapper.readingSystemProperties
        )
        await book.open(fileURL: work.fileURL, initialLocator: initialLocator,
                        fallbackSpineIndex: fallbackSpineIndex, config: config)
    }
}

private struct ReaderInteractiveDismissStyle: ViewModifier {
    typealias Body = AnyView

    let offset: CGFloat
    let reduceMotion: Bool

    func body(content: Self.Content) -> AnyView {
        let clampedOffset = max(0, offset)
        let progress = min(clampedOffset / 280, 1)
        // The page follows the finger down, shrinking and rounding into a card as it
        // goes (Apple Books). No per-frame drop shadow — that offscreen pass on the
        // full-screen web view was the source of the drag jank.
        return AnyView(content
            .scaleEffect(reduceMotion ? 1 : 1 - progress * 0.06, anchor: .center)
            .clipShape(RoundedRectangle(cornerRadius: reduceMotion ? 0 : progress * 20,
                                        style: .continuous))
            .offset(y: clampedOffset)
            .opacity(Double(1 - progress * 0.2)))
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
#endif
