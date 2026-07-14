import OSLog
import SwiftData
import SwiftUI
#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import UIKit
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

    /// Trims Readium's default reflowable content insets. The navigator treats
    /// iPhone portrait as the `.regular` vertical size class and reserves 62 pt
    /// top and bottom, which left a large empty band beneath the last line in
    /// paged mode. Keep the top clear of the status bar / Dynamic Island, but let
    /// the text run close to the bottom edge.
    func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
        let safeTop = (navigator as? UIViewController)?.view.window?.safeAreaInsets.top ?? 0
        return UIEdgeInsets(top: safeTop, left: 0, bottom: 16, right: 0)
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
            // The pill sits outside the dismiss-style transform (not inside `content`)
            // so it's immune to the swipe-to-dismiss pan's scale/offset/clip — including
            // its brief spring-back when an ordinary tap's incidental finger movement
            // crosses the pan's own latch threshold without becoming a real dismiss.
            // That spring-back is a legitimate, real animation (not a no-op), so it
            // can't be skipped; keeping the pill out of the transformed subtree means
            // it never rides along with it, whatever the cause.
            .overlay(alignment: .bottom) { bottomBar }
            .background(readerTheme.backgroundColor)
            .preferredColorScheme(readerTheme.colorScheme)
            .navigationTitle(work.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // One item holding a tight HStack so the icons cluster like the
                // Library toolbar (separate ToolbarItems get the system's wide spacing).
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 2) {
                        if ao3WorkID != nil {
                            Button { showingComments = true } label: {
                                Label("Comments", systemImage: "bubble.left.and.bubble.right")
                            }
                        }
                        Button { router.toggle(.readerChapters) } label: {
                            Label("Chapters", systemImage: "list.bullet")
                        }
                        Button { router.toggle(.readerDisplay) } label: {
                            Label("Display Options", systemImage: "textformat.size")
                        }
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: readerPanelBinding) { readerSheet }
            .commentsSheet(
                isPresented: $showingComments,
                workID: ao3WorkID ?? 0,
                context: .init(savedWork: work),
                initialChapterPosition: currentAO3Chapter
            )
            // Immersive reading: hide the tab bar; the nav/status bars follow the chrome.
            .toolbar(.hidden, for: .tabBar)
            .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
            .statusBarHidden(!chromeVisible)
            .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
            .animation(.easeInOut(duration: 0.25), value: book.chromeHidden)
            // Readium's WebView swallows the system edge-swipe; add our own.
            .edgeSwipeToGoBack { dismissReader() }
            .task(id: bookLoadToken) { await openBook() }
            .onChange(of: preferencesToken) { _, _ in book.submit(preferences) }
            // The Display / Customize controls live in a sheet over the reader; a
            // behind-the-sheet onChange can be missed, so re-apply when it closes.
            .onChange(of: router.panel) { _, panel in
                if panel == .none { book.submit(preferences) }
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
            work.readiumLocator = toWrite
            if shelfStamp {
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

    /// iOS navigation is gesture-based (swipe / tap zones), so the bar shows only
    /// the position pill — no prev/next buttons.
    private var bottomBar: some View {
        // A full-bleed, non-interactive layer that bottom-aligns the pill against the
        // true screen edge (the overlay otherwise stops at the home-indicator safe
        // area). Hit testing is off so taps still reach the page to toggle chrome.
        //
        // Always present (not conditionally inserted via `if chromeVisible`) and
        // shown/hidden with a fixed offset + opacity rather than
        // `.transition(.move(edge:))`: that transition computes its off-screen
        // distance from this view's own resolved frame, which is ambiguous here — a
        // `.frame(maxHeight: .infinity)` inside a container whose nav bar/status bar
        // visibility is *also* animating at the same moment. SwiftUI can get that
        // computation wrong for the transition's first frame or two and then
        // visibly correct itself, which reads as the pill jumping up before sliding
        // down. A fixed offset has no such ambiguity.
        progressPill
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // Sit as close to the bottom edge as the Dynamic Island is to the top.
            .padding(.bottom, 11)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .offset(y: chromeVisible ? 0 : 120)
            .opacity(chromeVisible ? 1 : 0)
    }

    private var progressPill: some View {
        // Just the essentials: overall percent, chapter, and page within the chapter.
        let label = if let pos = book.readingPosition {
            "\(pos.percent)%  ·  \(sectionLabel(for: pos))  ·  Pg. \(pos.page)/\(pos.pageCount)"
        } else if let percent = book.totalProgression.map({ Int(($0 * 100).rounded()) }) {
            "\(percent)%"
        } else {
            ""
        }
        return Text(label)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .glassEffect(.regular, in: .capsule)
            .opacity(label.isEmpty ? 0 : 1)
    }

    /// The AO3 story chapter the reader is currently on, for the chapter-aware
    /// Comments button. `pos.chapter - 1` is the current spine index (same basis the
    /// pill uses); the section list normalizes it past Preface/Summary/Afterword.
    /// nil (→ open on All comments) until a position and built sections both exist.
    private var currentAO3Chapter: Int? {
        guard let pos = book.readingPosition, !book.sections.isEmpty else { return nil }
        return book.sections.ao3StoryChapter(forSpineIndex: pos.chapter - 1)
    }

    /// The pill's chapter segment, normalized against AO3 front/back matter
    /// (`ReaderSection`) instead of a raw spine position — "P"/"S"/"A", or
    /// "<index>/<total>" for a real story chapter, preferring AO3's own posted
    /// chapter total over one derived purely from the section list. Falls back to
    /// the raw "Ch. x/x" reading if sections haven't been built (shouldn't happen
    /// once `.ready`, but a locator can theoretically outrace it).
    private func sectionLabel(for pos: ReadiumBook.ReadingPosition) -> String {
        guard book.sections.indices.contains(pos.chapter - 1) else {
            return "Ch. \(pos.chapter)/\(pos.chapterCount)"
        }
        let storyTotal = SavedWork.totalChapterCount(from: work.chapters) ?? book.sections.storyChapterCount
        let label = book.sections[pos.chapter - 1].pillLabel(storyChapterTotal: storyTotal)
        return label.isEmpty ? "Ch. \(pos.chapter)/\(pos.chapterCount)" : label
    }

    // MARK: Chapters / Display sheet

    private var readerSheet: some View {
        NavigationStack {
            Group {
                if router.panel == .readerChapters {
                    List { chapterRows }
                } else {
                    ReaderOptionsForm()
                }
            }
            .navigationTitle(router.panel == .readerChapters ? "Chapters" : "Display & Themes")
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

    private var chapterRows: some View {
        // .other sections have no navigable heading of their own (AO3/Calibre
        // never gave them one) and aren't part of the story — not shown here,
        // matching the reader index's documented Preface/Summary/Chapter/
        // Afterword-only contract. Still reachable by normal page-turning.
        ForEach(book.sections.filter { $0.kind != .other }) { section in
            Button {
                book.go(toSpineIndex: section.spineIndex)
                router.panel = .none
            } label: {
                Text(section.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .buttonStyle(.plain)
        }
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
            // Flush position first so the finished mark and final locator land together.
            if let string = book.currentLocator?.persistenceString {
                work.readiumLocator = string
                progressPersistence.markPersisted(
                    locatorString: string,
                    totalProgression: book.currentLocator?.locations.totalProgression
                )
            }
            guard work.isComplete, !work.isFinished else {
                try? context.save()
                return
            }
            work.isFinished = true
            work.markModified(Date())
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
