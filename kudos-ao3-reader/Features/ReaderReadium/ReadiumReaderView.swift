import OSLog
import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
import ReadiumShared
import ReadiumNavigator
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
            let faces: [CSSFontFace]
            if let file = option.customFileURL?.fileURL {
                // Readium serves imported files through a separate custom-scheme
                // host. Preloading that URL trips WebKit's cross-origin check;
                // allowing the @font-face rule to request it normally works.
                faces = [CSSFontFace(file: file)]
            } else {
                faces = []
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

enum ReaderPageTurnDirection: Equatable {
    case forward, backward

    var horizontalSign: CGFloat {
        switch self {
        case .forward: 1
        case .backward: -1
        }
    }
}

struct ReaderPageTurnEvent: Equatable {
    let sequence: Int
    let direction: ReaderPageTurnDirection
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
    private(set) var currentLocator: Locator?
    private(set) var navigator: EPUBNavigatorViewController?
    private(set) var pageTurnEvent: ReaderPageTurnEvent?
    /// Readium's static position list grouped by reading-order item (chapter).
    /// Drives the progress pill's "Ch. x/x · Pg. x/x" without any extra requests.
    private(set) var positionsByReadingOrder: [[Locator]] = []
    /// Toggled by tapping the page; the view hides/shows its chrome on this.
    var chromeHidden = false

    /// Fires on every position change — used to persist reading progress.
    var onLocatorChange: ((Locator) -> Void)?
    /// Hands web links in EPUB content to the app's in-app Browse tab.
    var onOpenExternalURL: ((URL) -> Void)?

    private var pageTurnSequence = 0

    /// Fraction through the whole publication (0...1), when known.
    var totalProgression: Double? { currentLocator?.locations.totalProgression }

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
            let tocLinks = (try? await publication.tableOfContents().get()) ?? []
            self.navigator = navigator
            toc = tocLinks.isEmpty ? publication.readingOrder : tocLinks
            positionsByReadingOrder = (try? await publication.positionsByReadingOrder().get()) ?? []
            phase = .ready
            Log.epub.info("Opened EPUB (Readium): \(self.toc.count) TOC entries")
        } catch {
            phase = .failed(error.localizedDescription)
            Log.epub.error("Couldn't open EPUB (Readium): \(error.localizedDescription, privacy: .public)")
        }
    }

    func submit(_ preferences: EPUBPreferences) { navigator?.submitPreferences(preferences) }
    func goForward() { Task { @MainActor in await navigator?.goForward() } }
    func goBackward() { Task { @MainActor in await navigator?.goBackward() } }
    func go(to link: ReadiumShared.Link) { Task { @MainActor in await navigator?.go(to: link) } }

    // MARK: EPUBNavigatorDelegate

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        if let direction = pageTurnDirection(from: currentLocator, to: locator) {
            pageTurnSequence += 1
            pageTurnEvent = ReaderPageTurnEvent(sequence: pageTurnSequence, direction: direction)
        }
        currentLocator = locator
        onLocatorChange?(locator)
    }

    private func pageTurnDirection(from oldLocator: Locator?, to newLocator: Locator) -> ReaderPageTurnDirection? {
        guard let oldLocator else { return nil }

        if let oldPosition = oldLocator.locations.position,
           let newPosition = newLocator.locations.position,
           oldPosition != newPosition {
            return newPosition > oldPosition ? .forward : .backward
        }

        let oldProgression = oldLocator.locations.totalProgression ?? oldLocator.locations.progression
        let newProgression = newLocator.locations.totalProgression ?? newLocator.locations.progression
        guard let oldProgression, let newProgression,
              abs(newProgression - oldProgression) > 0.0001 else { return nil }
        return newProgression > oldProgression ? .forward : .backward
    }

    // The only delegate method without a default implementation.
    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        phase = .failed(error.localizedDescription)
    }

    /// Readium's default implementation opens every external URL in the system
    /// browser. Keep HTTP(S) links inside Kudos, matching the legacy reader, while
    /// preserving the system behavior for schemes such as `mailto:`.
    func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
        if !routeWebURLToBrowse(url) {
            UIApplication.shared.open(url)
        }
    }

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
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

/// Thin SwiftUI host for an already-built `EPUBNavigatorViewController`.
struct ReadiumNavigatorContainer: UIViewControllerRepresentable {
    let controller: EPUBNavigatorViewController
    let readingMode: ReadingMode
    let onDismissDragChanged: (CGFloat) -> Void
    let onDismissDragEnded: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

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

        @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            let velocity = gesture.velocity(in: view)

            switch gesture.state {
            case .changed:
                guard translation.y > 0,
                      translation.y > abs(translation.x) * 1.1,
                      readingMode != .scroll || isAtTop(in: view)
                else {
                    onDismissDragChanged(0)
                    return
                }
                onDismissDragChanged(rubberBandedDistance(translation.y))
            case .ended:
                let verticalDominates = translation.y > 0
                    && translation.y > abs(translation.x) * 1.2
                let passesDistance = translation.y > 120
                let passesVelocity = translation.y > 44 && velocity.y > 1_100
                onDismissDragEnded(verticalDominates && (passesDistance || passesVelocity))
            case .cancelled, .failed:
                onDismissDragEnded(false)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let velocity = pan.velocity(in: view)
            let translation = pan.translation(in: view)
            let downwardIntent = velocity.y > 0 || translation.y > 0
            let verticalVelocity = abs(velocity.y) > abs(velocity.x) * 1.25
            let verticalTranslation = translation.y > abs(translation.x) * 1.25
            guard downwardIntent, verticalVelocity || verticalTranslation else { return false }
            return readingMode != .scroll || isAtTop(in: view)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        private func rubberBandedDistance(_ distance: CGFloat) -> CGFloat {
            guard distance > 160 else { return distance }
            return min(320, 160 + (distance - 160) * 0.35)
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
    @State private var dismissDragOffset: CGFloat = 0
    @State private var isDismissingByDrag = false
    @State private var pageTurnDirection: ReaderPageTurnDirection?
    @State private var pageTurnProgress: CGFloat = 1
    @State private var pageTurnResetTask: Task<Void, Never>?
    @State private var suppressNextPageTurn = false

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

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
    private var chromeVisible: Bool { !book.chromeHidden }

    /// The reader's effective theme (app theme while linked).
    private var readerTheme: ReaderTheme { themeManager.readerTheme }

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
            .modifier(ReaderPageTurnStyle(direction: pageTurnDirection,
                                          progress: pageTurnProgress,
                                          reduceMotion: reduceMotion,
                                          theme: readerTheme))
            .modifier(ReaderInteractiveDismissStyle(offset: dismissDragOffset,
                                                    reduceMotion: reduceMotion))
            .background(readerTheme.backgroundColor)
            .preferredColorScheme(readerTheme.colorScheme)
            .navigationTitle(work.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // One item holding a tight HStack so the icons cluster like the
                // Library toolbar (separate ToolbarItems get the system's wide spacing).
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 2) {
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
            .onChange(of: book.pageTurnEvent) { _, event in
                handlePageTurnEvent(event)
            }
            // The Display / Customize controls live in a sheet over the reader; a
            // behind-the-sheet onChange can be missed, so re-apply when it closes.
            .onChange(of: router.panel) { _, panel in
                if panel == .none { book.submit(preferences) }
            }
            .onDisappear {
                pageTurnResetTask?.cancel()
                // Flush the exact final position so resume lands precisely, even if the
                // last scroll didn't emit a locator change before we left.
                persistCurrentProgress()
                WorkLifecycle.freeEPUBIfFinished(work, in: modelContext)
                try? modelContext.save()
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
                    .overlay(alignment: .bottom) {
                        if chromeVisible { bottomBar }
                    }
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
            persistCurrentProgress()
            withAnimation(reduceMotion ? .easeOut(duration: 0.05) : .easeOut(duration: 0.16)) {
                dismissDragOffset = max(dismissDragOffset, 180)
            }
            Task { @MainActor in
                if !reduceMotion {
                    try? await Task.sleep(nanoseconds: 90_000_000)
                }
                dismissReader()
            }
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                dismissDragOffset = 0
            }
        }
    }

    private func dismissReader() {
        persistCurrentProgress()
        dismiss()
    }

    private func persistCurrentProgress() {
        if let saved = book.currentLocator?.persistenceString {
            work.readiumLocator = saved
            work.lastReadDate = Date()
            try? modelContext.save()
        }
    }

    private func handlePageTurnEvent(_ event: ReaderPageTurnEvent?) {
        guard let event else { return }
        if suppressNextPageTurn {
            suppressNextPageTurn = false
            return
        }
        guard readingMode == .paged else { return }
        animatePageTurn(event.direction)
    }

    private func animatePageTurn(_ direction: ReaderPageTurnDirection) {
        pageTurnResetTask?.cancel()
        var immediate = Transaction()
        immediate.animation = nil
        withTransaction(immediate) {
            pageTurnDirection = direction
            pageTurnProgress = 0
        }
        withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.32)) {
            pageTurnProgress = 1
        }

        let delay: UInt64 = reduceMotion ? 180_000_000 : 340_000_000
        pageTurnResetTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                pageTurnDirection = nil
                pageTurnProgress = 1
            }
        }
    }

    // MARK: Chrome

    /// iOS navigation is gesture-based (swipe / tap zones), so the bar shows only
    /// the position pill — no prev/next buttons.
    private var bottomBar: some View {
        // A full-bleed, non-interactive layer that bottom-aligns the pill against the
        // true screen edge (the overlay otherwise stops at the home-indicator safe
        // area). Hit testing is off so taps still reach the page to toggle chrome.
        progressPill
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // Sit as close to the bottom edge as the Dynamic Island is to the top.
            .padding(.bottom, 11)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var progressPill: some View {
        // Just the essentials: overall percent, chapter, and page within the chapter.
        let label: String
        if let pos = book.readingPosition {
            label = "\(pos.percent)%  ·  Ch. \(pos.chapter)/\(pos.chapterCount)  ·  Pg. \(pos.page)/\(pos.pageCount)"
        } else if let percent = book.totalProgression.map({ Int(($0 * 100).rounded()) }) {
            label = "\(percent)%"
        } else {
            label = ""
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

    @ViewBuilder
    private var chapterRows: some View {
        ForEach(Array(book.toc.enumerated()), id: \.offset) { _, link in
            Button {
                suppressNextPageTurn = true
                book.go(to: link)
                router.panel = .none
            } label: {
                Text(link.title ?? link.href)
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
        book.onLocatorChange = { locator in
            work.readiumLocator = locator.persistenceString ?? work.readiumLocator
            work.lastReadDate = Date()   // drives the Library's Continue Reading shelf
            // Finish a completed work once the user reaches the end (WIPs are manual).
            if let progress = locator.locations.totalProgression, progress >= 0.99,
               work.isComplete, !work.isFinished {
                work.isFinished = true
            }
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
        return AnyView(content
            .offset(y: clampedOffset)
            .scaleEffect(reduceMotion ? 1 : 1 - progress * 0.035)
            .opacity(Double(1 - progress * 0.16))
            .shadow(color: .black.opacity(Double(reduceMotion ? 0 : 0.18 * progress)),
                    radius: 22 * progress, x: 0, y: -2 * progress))
    }
}

private struct ReaderPageTurnStyle: ViewModifier {
    typealias Body = AnyView

    let direction: ReaderPageTurnDirection?
    let progress: CGFloat
    let reduceMotion: Bool
    let theme: ReaderTheme

    func body(content: Self.Content) -> AnyView {
        let clampedProgress = min(max(progress, 0), 1)
        let isActive = direction != nil && clampedProgress < 1
        let sign = direction?.horizontalSign ?? 0
        let travel: CGFloat = reduceMotion ? 8 : 42

        return AnyView(content
            .scaleEffect(isActive && !reduceMotion ? 0.985 + 0.015 * clampedProgress : 1)
            .offset(x: isActive ? sign * travel * (1 - clampedProgress) : 0)
            .opacity(Double(isActive && reduceMotion ? 0.9 + 0.1 * clampedProgress : 1))
            .shadow(color: .black.opacity(Double(isActive && !reduceMotion ? 0.16 * (1 - clampedProgress) : 0)),
                    radius: isActive && !reduceMotion ? 20 * (1 - clampedProgress) : 0,
                    x: isActive ? -sign * 6 * (1 - clampedProgress) : 0,
                    y: isActive ? 2 * (1 - clampedProgress) : 0)
            .overlay {
                if let direction, isActive && !reduceMotion {
                    ReaderPageTurnStackOverlay(direction: direction,
                                               progress: clampedProgress,
                                               theme: theme)
                }
            })
    }
}

private struct ReaderPageTurnStackOverlay: View {
    let direction: ReaderPageTurnDirection
    let progress: CGFloat
    let theme: ReaderTheme

    var body: some View {
        GeometryReader { proxy in
            let width = min(max(proxy.size.width * 0.12, 28), 84)
            HStack(spacing: 0) {
                if direction == .forward { Spacer(minLength: 0) }
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.backgroundColor)
                    .frame(width: width)
                    .shadow(color: .black.opacity(Double(0.12 * (1 - progress))),
                            radius: 16 * (1 - progress),
                            x: direction == .forward ? -6 : 6,
                            y: 0)
                    .opacity(Double(0.24 * (1 - progress)))
                    .offset(x: direction == .forward ? -18 * progress : 18 * progress)
                if direction == .backward { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Theme mapping

extension ReaderTheme {
    /// The matching Readium navigator theme.
    var readiumTheme: ReadiumNavigator.Theme {
        switch self {
        case .light: .light
        case .sepia: .sepia
        case .dark: .dark
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
