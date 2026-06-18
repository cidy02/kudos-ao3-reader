import SwiftUI
import SwiftData
#if os(iOS)
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

    /// Fraction through the whole publication (0...1), when known.
    var totalProgression: Double? { currentLocator?.locations.totalProgression }

    /// Opens the work's EPUB and builds the navigator at `initialLocator` with the
    /// given starting preferences. The file already lives in the app sandbox, so
    /// (unlike the POC) it's opened in place — no copy.
    func open(fileURL: URL, initialLocator: Locator?, preferences: EPUBPreferences) async {
        phase = .loading
        do {
            let publication = try await ReadiumPublicationLoader.openEPUB(at: fileURL)
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocator,
                config: .init(preferences: preferences)
            )
            navigator.delegate = self
            let tocLinks = (try? await publication.tableOfContents().get()) ?? []
            self.navigator = navigator
            toc = tocLinks.isEmpty ? publication.readingOrder : tocLinks
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
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

    func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
        chromeHidden.toggle()
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

    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("readerFontPt") private var fontSizePt: Double = ReaderTextStyle.defaultFontSizePt
    @AppStorage("readerTwoPage") private var twoPageEnabled = false

    @State private var book = ReadiumBook()

    /// Reader chrome (bars) visibility — driven by tapping the page.
    private var chromeVisible: Bool { !book.chromeHidden }

    /// The reader's effective theme (app theme while linked).
    private var readerTheme: ReaderTheme { themeManager.readerTheme }

    /// Maps the app's reader settings + theme onto Readium's preferences. Font
    /// size is a multiplier (legacy points ÷ default); margins are a constant for
    /// now (the slider is wired in a follow-up).
    private var preferences: EPUBPreferences {
        EPUBPreferences(
            columnCount: twoPageEnabled ? .two : .auto,
            fontSize: max(0.5, fontSizePt / ReaderTextStyle.defaultFontSizePt),
            pageMargins: 1.4,
            scroll: readingMode == .scroll,
            theme: readerTheme.readiumTheme
        )
    }

    /// Re-submit preferences whenever any mapped setting changes.
    private var preferencesToken: String {
        "\(readingMode.rawValue)|\(readerTheme.rawValue)|\(fontSizePt)|\(twoPageEnabled)"
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

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 12) {
                navButton("chevron.left") { book.goBackward() }
                progressPill
                navButton("chevron.right") { book.goForward() }
            }
        }
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func navButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
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
        book.onLocatorChange = { locator in
            work.readiumLocator = locator.persistenceString ?? work.readiumLocator
            // Finish a completed work once the user reaches the end (WIPs are manual).
            if let progress = locator.locations.totalProgression, progress >= 0.99,
               work.isComplete, !work.isFinished {
                work.isFinished = true
            }
            try? context.save()
        }
        let initialLocator = Locator(persistenceString: work.readiumLocator)
        await book.open(fileURL: work.fileURL, initialLocator: initialLocator, preferences: preferences)
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
