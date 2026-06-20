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
    /// Toggled by tapping the page; the view hides/shows its chrome on this.
    var chromeHidden = false

    /// Fires on every position change — used to persist reading progress.
    var onLocatorChange: ((Locator) -> Void)?
    /// Hands web links in EPUB content to the app's in-app Browse tab.
    var onOpenExternalURL: ((URL) -> Void)?

    /// Fraction through the whole publication (0...1), when known.
    var totalProgression: Double? { currentLocator?.locations.totalProgression }

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
        currentLocator = locator
        onLocatorChange?(locator)
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

    func makeUIViewController(context: Context) -> EPUBNavigatorViewController { controller }
    func updateUIViewController(_ controller: EPUBNavigatorViewController, context: Context) {}
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

    /// Maps the app's reader settings + theme onto Readium's preferences. Sizes are
    /// expressed relative to the legacy defaults: font size and margins as
    /// multipliers; spacing/line-height passed through (clamped non-negative).
    private var preferences: EPUBPreferences {
        let style = textStyle
        return EPUBPreferences(
            // .auto lets Readium show a two-page spread on wide screens (iPad) and a
            // single column when narrow; iPhone stays single-column like the legacy.
            columnCount: (twoPageEnabled && !isPhone) ? .auto : .one,
            fontFamily: readiumFontFamily,
            fontSize: max(0.5, style.fontSizePt / ReaderTextStyle.defaultFontSizePt),
            fontWeight: style.bold ? 1.75 : nil,        // ≈ 700 (Readium scales ×400)
            letterSpacing: max(0, style.letterSpacing),
            lineHeight: style.lineHeight,
            pageMargins: min(2.0, max(0.5, style.margin / ReaderTextStyle.defaultMargin)),
            // Readium honours line-height / letter- & word-spacing / justify only when
            // publisher styles are off; with them on it keeps the EPUB's own CSS and
            // silently drops those overrides. Turn them off when the user opts into
            // Customize so the advanced typography actually applies (matching the
            // preview); leave publisher styles on otherwise for comfortable defaults.
            publisherStyles: !style.customize,
            scroll: readingMode == .scroll,
            textAlign: style.justify ? .justify : nil,
            theme: readerTheme.readiumTheme,
            wordSpacing: max(0, style.wordSpacing)
        )
    }

    /// The selected font as a Readium `FontFamily`: nil = default (system), a custom
    /// font's id (declared via `fontFamilyDeclarations`), or a built-in's primary name.
    private var readiumFontFamily: FontFamily? {
        let option = ReaderFontOption.current(id: fontID, customFonts: customFonts)
        if option.id == "system" { return nil }
        if option.isCustom { return FontFamily(rawValue: option.id) }
        let primary = option.cssFamily.split(separator: ",").first.map(String.init) ?? option.cssFamily
        return FontFamily(rawValue: primary.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")))
    }

    /// `@font-face` declarations for the user's imported fonts, so the navigator can
    /// load and apply them. Built-in families need no declaration (the WebView has them).
    private var fontFamilyDeclarations: [AnyHTMLFontFamilyDeclaration] {
        customFonts.compactMap { font in
            guard let fileURL = font.fileURL.fileURL else { return nil }
            return CSSFontFamilyDeclaration(
                fontFamily: FontFamily(rawValue: font.selectionID),
                fontFaces: [CSSFontFace(file: fileURL)]
            ).eraseToAnyHTMLFontFamilyDeclaration()
        }
    }

    /// Re-submit preferences whenever any mapped setting changes (instant updates).
    private var preferencesToken: String {
        "\(readingMode.rawValue)|\(readerTheme.rawValue)|\(fontID)|\(twoPageEnabled)|\(textStyle.token)"
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
            .background(readerTheme.backgroundColor)
            .preferredColorScheme(readerTheme.colorScheme)
            .navigationTitle(work.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem {
                    Button { router.toggle(.readerChapters) } label: {
                        Label("Chapters", systemImage: "list.bullet")
                    }
                }
                ToolbarItem {
                    Button { router.toggle(.readerDisplay) } label: {
                        Label("Display Options", systemImage: "textformat.size")
                    }
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
            .edgeSwipeToGoBack { dismiss() }
            .task(id: work.id) { await openBook() }
            .onChange(of: preferencesToken) { _, _ in book.submit(preferences) }
            // The Display / Customize controls live in a sheet over the reader; a
            // behind-the-sheet onChange can be missed, so re-apply when it closes.
            .onChange(of: router.panel) { _, panel in
                if panel == .none { book.submit(preferences) }
            }
            .onDisappear {
                WorkLifecycle.freeEPUBIfFinished(work, in: modelContext)
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
                ReadiumNavigatorContainer(controller: navigator)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        if chromeVisible { bottomBar }
                    }
            }
        }
    }

    // MARK: Chrome

    /// iOS navigation is gesture-based (swipe / tap zones), so the bar shows only
    /// the position pill — no prev/next buttons.
    private var bottomBar: some View {
        progressPill
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var progressPill: some View {
        let percent = book.totalProgression.map { Int(($0 * 100).rounded()) }
        let chapter = book.currentLocator?.title ?? ""
        let label = [percent.map { "\($0)%" }, chapter.isEmpty ? nil : chapter]
            .compactMap { $0 }.joined(separator: " · ")
        return Text(label.isEmpty ? work.title : label)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .glassEffect(.regular, in: .capsule)
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
            // Finish a completed work once the user reaches the end (WIPs are manual).
            if let progress = locator.locations.totalProgression, progress >= 0.99,
               work.isComplete, !work.isFinished {
                work.isFinished = true
            }
            try? context.save()
        }
        book.onOpenExternalURL = { url in
            router.open(url)
        }
        let initialLocator = Locator(persistenceString: work.readiumLocator)
        // No Readium progress yet but a legacy position exists → resume at that chapter.
        let fallbackSpineIndex = initialLocator == nil && work.lastSpineIndex > 0
            ? work.lastSpineIndex : nil
        let config = EPUBNavigatorViewController.Configuration(
            preferences: preferences,
            fontFamilyDeclarations: fontFamilyDeclarations
        )
        await book.open(fileURL: work.fileURL, initialLocator: initialLocator,
                        fallbackSpineIndex: fallbackSpineIndex, config: config)
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
