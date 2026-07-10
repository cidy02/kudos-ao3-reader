import OSLog
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// The legacy WKWebView reader is the **macOS** reader implementation only — iOS uses
// the Readium navigator (see `BookReaderView`), so this whole file is excluded from
// iOS builds.
#if os(macOS)

/// A basic EPUB reader with selectable themes, fonts, and scrolled/paged layout
/// (including a two-page spread on wide windows, except iPhone). Display options
/// live in a hideable inspector sidebar.
struct ReaderView: View {
    @Bindable var work: SavedWork

    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomFont.dateAdded) private var customFonts: [CustomFont]
    @AppStorage("readerFontID") private var fontID: String = "system"
    @AppStorage("readerMode") private var readingMode: ReadingMode = .scroll
    @AppStorage("readerTwoPage") private var twoPageEnabled = false

    // Apple Books–style custom typography. `customizeEnabled` gates the layout
    // options; bold/font always apply. See `ReaderTextStyle`.
    @AppStorage("readerCustomize") private var customizeEnabled = false
    @AppStorage("readerBoldText") private var boldText = false
    @AppStorage("readerFontPt") private var fontSizePt: Double = ReaderTextStyle.defaultFontSizePt
    @AppStorage("readerLineHeight") private var lineHeight: Double = ReaderTextStyle.defaultLineHeight
    @AppStorage("readerLetterSpacing") private var letterSpacing: Double = 0
    @AppStorage("readerWordSpacing") private var wordSpacing: Double = 0
    @AppStorage("readerMargin") private var pageMargin: Double = ReaderTextStyle.defaultMargin
    @AppStorage("readerJustify") private var justifyText = false

    @State private var controller = ReaderController()
    @State private var document: EPUBDocument?
    /// `document?.chapters` reconciled against the full spine into AO3-aware
    /// sections (Preface/Summary/Chapter/Afterword). Built once per `load()`
    /// alongside `document` rather than recomputed per access. See `ReaderSection`.
    @State private var sections: [ReaderSection] = []
    @State private var openError: String?
    @State private var readRoot: URL?
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var landNextChapterOnLastPage = false
    @State private var availableWidth: CGFloat = 0
    @State private var workActions = AO3WorkActionsModel()

    #if os(iOS)
    /// Whether the reader "chrome" (top bar + bottom chapter controls) is shown.
    /// Starts visible, then the reader becomes immersive: a tap toggles it and
    /// scrolling down hides it (Apple Books–style).
    @State private var chromeVisible = true
    #endif

    /// Window width at which a two-page spread becomes available.
    private let twoPageThreshold: CGFloat = 820

    private var chapterCount: Int {
        document?.spineURLs.count ?? 0
    }

    private var isWideEnough: Bool {
        availableWidth >= twoPageThreshold
    }

    /// Two-page spread is offered on iPad and macOS, but never on iPhone — its
    /// screen is too narrow for a useful spread. (iPad reports `os(iOS)` too, so this
    /// is a runtime idiom check, not a compile-time one.)
    private var twoPageSpreadAvailable: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom != .phone
        #else
        return true
        #endif
    }

    private var columns: Int {
        (readingMode == .paged && twoPageEnabled && twoPageSpreadAvailable && isWideEnough) ? 2 : 1
    }

    /// The reader's effective theme — the app theme while the two are linked.
    private var theme: ReaderTheme {
        themeManager.readerTheme
    }

    #if os(iOS)
    /// iPhone only (iPad reports `os(iOS)` too): drives the slimmed-down bottom bar.
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #endif

    private var currentFont: ReaderFontOption {
        ReaderFontOption.current(id: fontID, customFonts: customFonts)
    }

    /// The current custom typography settings, read live from `@AppStorage`.
    private var textStyle: ReaderTextStyle {
        ReaderTextStyle(
            customize: customizeEnabled, bold: boldText, fontSizePt: fontSizePt,
            lineHeight: lineHeight, letterSpacing: letterSpacing, wordSpacing: wordSpacing,
            margin: pageMargin, justify: justifyText
        )
    }

    private var css: String {
        ReaderStylesheet.css(theme: theme, font: currentFont, style: textStyle)
    }

    /// Horizontal page margin in px, shared by scrolled (CSS) and paged (column) modes.
    private var resolvedMargin: Int {
        Int(textStyle.resolved.margin)
    }

    /// Applies the current style/layout to the controller, including the device's
    /// fixed safe-area insets so the full-screen reader pads past the notch / home
    /// indicator (constant regardless of the chrome).
    private func configureController() {
        #if os(iOS)
        let insets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
        controller.configure(css: css, mode: readingMode, columns: columns, margin: resolvedMargin,
                             safeTop: Int(insets.top.rounded()), safeBottom: Int(insets.bottom.rounded()))
        #else
        controller.configure(css: css, mode: readingMode, columns: columns, margin: resolvedMargin)
        #endif
    }

    /// Changes to any of these require re-applying layout to the loaded page.
    private var renderToken: String {
        "\(theme.rawValue)|\(fontID)|\(readingMode.rawValue)|\(columns)|\(textStyle.token)"
    }

    /// The reader's chapters/display panels share the app-wide inspector (via
    /// `AppRouter.panel`) so only one inspector is ever open at a time.
    private var readerInspectorBinding: Binding<Bool> {
        Binding(
            get: { router.panel == .readerChapters || router.panel == .readerDisplay },
            set: { if !$0 { router.panel = .none } }
        )
    }

    var body: some View {
        Group {
            if isLoading {
                ReaderPageSkeleton()
            } else if document != nil, readRoot != nil, chapterCount > 0 {
                WebView(webView: controller.webView)
                    // Full-screen so toggling the chrome (status bar / home indicator /
                    // nav bar) never resizes the web view — that resize was what made
                    // paged padding shift and the page "bounce" on tap. The EPUB content
                    // pads itself past the unsafe areas via env(safe-area-inset-*).
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) { bottomControls }
                    .contentShape(Rectangle())
                    .modifier(PageSwipe(next: goNext, prev: goPrevious))
                    .focusable()
                    .focusEffectDisabled()
                    .onKeyPress(.leftArrow) { goPrevious(); return .handled }
                    .onKeyPress(.rightArrow) { goNext(); return .handled }
                    .onKeyPress(.space) { goNext(); return .handled }
            } else {
                ContentUnavailableView(
                    "Couldn't open this EPUB",
                    systemImage: "exclamationmark.triangle",
                    description: Text(openError ?? "The file may be missing or in an unsupported format.")
                )
            }
        }
        .background(theme.backgroundColor)
        .background { widthReader }
        // The reader's own theme drives its chrome/Liquid Glass appearance (and the
        // window while reading) — independent of the app theme when they're unlinked.
        .preferredColorScheme(theme.colorScheme)
        .ao3WorkActions(workActions, workID: WorkTags.ao3WorkID(from: work.sourceURL) ?? 0, auth: auth)
        .navigationTitle(work.title)
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                // One item holding a tight HStack so the icons cluster like the Library
                // toolbar (separate ToolbarItems get the system's wide spacing).
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 2) {
                        Button {
                            router.toggle(.readerChapters)
                        } label: {
                            Label("Chapters", systemImage: "list.bullet")
                        }
                        Button {
                            router.toggle(.readerDisplay)
                        } label: {
                            Label("Display Options", systemImage: "textformat.size")
                        }
                        Menu {
                            if let id = WorkTags.ao3WorkID(from: work.sourceURL) {
                                AO3WorkActionsMenu(workID: id, actions: workActions,
                                                   workContext: .init(savedWork: work),
                                                   commentsInitialChapterPosition: currentAO3Chapter)
                            }
                        } label: {
                            Label("More actions", systemImage: "ellipsis.circle")
                        }
                        .disabled(WorkTags.ao3WorkID(from: work.sourceURL) == nil)
                    }
                    .labelStyle(.iconOnly)
                }
            }
        #if os(iOS)
            // Chapters / Display open as clean half-height sheets that float over the
            // text instead of a side inspector that crowds the reading column.
            .sheet(isPresented: readerInspectorBinding) { readerSheet }
            // Immersive reading: no tab bar, and the top bar hides while reading and
            // reappears on tap. The status bar and home indicator follow the chrome.
            .toolbar(.hidden, for: .tabBar)
            .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
            .statusBarHidden(!chromeVisible)
            .persistentSystemOverlays(chromeVisible ? .automatic : .hidden)
            .animation(.easeInOut(duration: 0.25), value: chromeVisible)
            // The web view swallows the system edge swipe and immersive mode hides the
            // nav bar, so add our own left-edge swipe-to-go-back.
            .edgeSwipeToGoBack { dismiss() }
        #else
            .inspector(isPresented: readerInspectorBinding) {
                Group {
                    if router.panel == .readerChapters {
                        chaptersInspector
                    } else {
                        optionsSidebar
                    }
                }
                .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
            }
        #endif
            .task(id: work.id) { await load() }
            .onAppear(perform: wireController)
            .onDisappear {
                WorkLifecycle.freeEPUBIfFinished(work, in: modelContext)
                // Leaving the reader closes its panel so it doesn't linger as state.
                if router.panel == .readerChapters || router.panel == .readerDisplay {
                    router.panel = .none
                }
            }
            .onChange(of: currentIndex) { _, _ in
                if !isLoading { loadCurrentChapter() }
            }
            .onChange(of: renderToken) { _, _ in
                configureController()
            }
    }

    @Environment(\.modelContext) private var modelContext

    // MARK: Width measurement

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in
                availableWidth = width
            }
        }
    }

    // MARK: Chapter / page controls

    private var prevDisabled: Bool {
        readingMode == .paged ? (currentIndex == 0 && controller.page <= 1) : currentIndex == 0
    }

    private var nextDisabled: Bool {
        readingMode == .paged
            ? (currentIndex == chapterCount - 1 && controller.page >= controller.pageTotal)
            : currentIndex == chapterCount - 1
    }

    private var positionLabel: String {
        if readingMode == .paged {
            let chapterPart = currentSectionLabel.map { "Ch \($0)" } ?? "Ch \(currentIndex + 1)/\(chapterCount)"
            return "\(chapterPart) · Pg \(controller.page)/\(controller.pageTotal)"
        }
        return longFormPositionLabel
    }

    /// The AO3 story chapter currently being read, for the chapter-aware Comments
    /// button — `currentIndex` normalized past Preface/Summary/Afterword. nil
    /// (→ open comments on All) until sections are built.
    private var currentAO3Chapter: Int? {
        guard !sections.isEmpty else { return nil }
        return sections.ao3StoryChapter(forSpineIndex: currentIndex)
    }

    /// This position's normalized short label ("P"/"S"/"A"/"<i>/<total>"), or nil
    /// if sections haven't been built yet or this position is `.other` — callers
    /// fall back to the raw spine-position text.
    private var currentSectionLabel: String? {
        guard sections.indices.contains(currentIndex) else { return nil }
        let storyTotal = SavedWork.totalChapterCount(from: work.chapters) ?? sections.storyChapterCount
        let label = sections[currentIndex].pillLabel(storyChapterTotal: storyTotal)
        return label.isEmpty ? nil : label
    }

    /// Scroll mode's spoken-out label: the section's own name for front/back
    /// matter, "Chapter <i> of <total>" for a real story chapter — normalized
    /// against AO3 sections instead of a raw spine position (see `ReaderSection`).
    private var longFormPositionLabel: String {
        guard sections.indices.contains(currentIndex) else {
            return "Chapter \(currentIndex + 1) of \(chapterCount)"
        }
        let section = sections[currentIndex]
        switch section.kind {
        case .preface: return "Preface"
        case .summary: return "Summary"
        case .afterword: return "Afterword"
        case .chapter:
            let storyTotal = SavedWork.totalChapterCount(from: work.chapters) ?? sections.storyChapterCount
            return "Chapter \(section.storyChapterIndex ?? currentIndex + 1) of \(storyTotal)"
        case .other: return "Chapter \(currentIndex + 1) of \(chapterCount)"
        }
    }

    /// The bottom chapter controls. On iOS they're part of the reader chrome and
    /// only appear when it's revealed (tap); on macOS they stay docked.
    @ViewBuilder
    private var bottomControls: some View {
        #if os(iOS)
        if chromeVisible {
            chapterControls
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        #else
        chapterControls
        #endif
    }

    /// iPhone drops the prev/next buttons (navigate by swipe / Chapters list) and uses
    /// a slimmer pill; iPad and macOS keep the full set of controls.
    private var chapterControls: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 12) {
                #if os(iOS)
                if !isPhone { navButton(systemName: "chevron.left", action: goPrevious, disabled: prevDisabled) }
                #else
                navButton(systemName: "chevron.left", action: goPrevious, disabled: prevDisabled)
                #endif

                positionPill

                #if os(iOS)
                if !isPhone { navButton(systemName: "chevron.right", action: goNext, disabled: nextDisabled) }
                #else
                navButton(systemName: "chevron.right", action: goNext, disabled: nextDisabled)
                #endif
            }
        }
        .padding(.bottom, 12)
    }

    private func navButton(systemName: String, action: @escaping () -> Void, disabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(disabled)
    }

    private var positionPill: some View {
        // 25% smaller on iPhone, where it stands alone without flanking buttons.
        #if os(iOS)
        let compact = isPhone
        #else
        let compact = false
        #endif
        return Text(positionLabel)
            .font((compact ? Font.caption2 : Font.footnote).weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, compact ? 12 : 16)
            .frame(height: compact ? 33 : 44)
            .glassEffect(.regular, in: .capsule)
    }

    private func goPrevious() {
        if readingMode == .paged {
            controller.prevPage()
        } else if currentIndex > 0 {
            landNextChapterOnLastPage = false
            currentIndex -= 1
        }
    }

    private func goNext() {
        if readingMode == .paged {
            controller.nextPage()
        } else if currentIndex < chapterCount - 1 {
            currentIndex += 1
        }
    }

    // MARK: Chapters jump list

    /// The chapter jump list, shown in the same right inspector as the display
    /// options so the two panels share one consistent column. The section header
    /// labels the panel without touching the window title (which stays the work
    /// title), mirroring the "Theme"/"Font" headers in the options panel.
    private var chapterRows: some View {
        // .other sections have no navigable heading of their own (AO3/Calibre
        // never gave them one) and aren't part of the story — not shown here,
        // matching the reader index's documented Preface/Summary/Chapter/
        // Afterword-only contract. Still reachable by normal page-turning.
        ForEach(sections.filter { $0.kind != .other }) { section in
            let isCurrent = section.spineIndex == currentIndex
            Button {
                jump(to: section.spineIndex)
            } label: {
                HStack {
                    Text(section.title)
                        .lineLimit(2)
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    Spacer()
                    if isCurrent {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var chaptersInspector: some View {
        List {
            Section("Chapters") { chapterRows }
        }
    }

    #if os(iOS)
    /// Chapters / Display, presented as a clean half-height sheet over the text.
    /// Uses the system's opaque sheet background (not a translucent material) so the
    /// reader text never bleeds through and the segmented controls keep full contrast.
    private var readerSheet: some View {
        NavigationStack {
            Group {
                if router.panel == .readerChapters {
                    List { chapterRows }
                } else {
                    ReaderOptionsForm(twoPageAvailable: isWideEnough)
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
        .presentationContentInteraction(.scrolls)
        // The reader's settings sheet follows the reader theme (dark in Dark, etc.).
        .preferredColorScheme(theme.colorScheme)
    }
    #endif

    private func jump(to index: Int) {
        landNextChapterOnLastPage = false
        if index == currentIndex {
            loadCurrentChapter() // same chapter: reset to first page
        } else {
            currentIndex = index // triggers load via onChange
        }
        #if os(iOS)
        router.panel = .none // dismiss the chapters sheet after picking
        #endif
    }

    // MARK: Options sidebar

    /// The reader's display options, shown in the right inspector. Uses the same
    /// form as the Settings page so the controls stay identical everywhere.
    private var optionsSidebar: some View {
        ReaderOptionsForm(twoPageAvailable: isWideEnough)
    }

    // MARK: Loading

    private func wireController() {
        controller.onReachedEnd = {
            if currentIndex < chapterCount - 1 {
                landNextChapterOnLastPage = false
                currentIndex += 1
            } else {
                autoFinishIfComplete() // paged: past the last page of the last chapter
            }
        }
        controller.onReachedStart = {
            if currentIndex > 0 {
                landNextChapterOnLastPage = true
                currentIndex -= 1
            }
        }
        controller.onReachedScrollBottom = {
            if currentIndex == chapterCount - 1 {
                autoFinishIfComplete() // scrolled: bottom of the last chapter
            }
        }
        // AO3 links in the EPUB (e.g. the preface's tag links) route to the matching
        // native screen where one exists; everything else opens the AO3 web view.
        controller.onOpenExternalURL = { url in
            router.openAO3Link(url)
        }
        #if os(iOS)
        controller.onTap = { toggleChrome() }
        controller.onChromeHiddenChange = { hidden in chromeVisible = !hidden }
        #endif
    }

    #if os(iOS)
    /// Toggles the reader chrome and keeps the controller's scroll logic in sync.
    private func toggleChrome() {
        chromeVisible.toggle()
        controller.syncChromeHidden(!chromeVisible)
    }
    #endif

    /// Marks a completed work finished once the reader reaches its end. WIPs and
    /// works of unknown completeness are left for a manual "Mark as Finished", so
    /// an ongoing read isn't deleted out from under the user. The EPUB itself is
    /// freed on `.onDisappear` (if unprotected), not while the page is on screen.
    private func autoFinishIfComplete() {
        guard work.isComplete, !work.isFinished else { return }
        work.isFinished = true
        try? modelContext.save()
    }

    private func load() async {
        isLoading = true
        openError = nil
        let directory = Storage.readerDirectory(for: work.id)
        let fileURL = work.fileURL
        do {
            // Extracting + parsing the EPUB unzips the whole book to disk; run it off the
            // main actor so the loading skeleton stays live, then apply state on main.
            let parsed = try await Task.detached(priority: .userInitiated) {
                try EPUBDocument.open(epubURL: fileURL, into: directory)
            }.value
            document = parsed
            sections = ReaderSectionBuilder.build(
                tocEntries: parsed.chapters.map {
                    ReaderSectionBuilder.RawTOCEntry(title: $0.title, spineIndex: $0.spineIndex)
                },
                spineHrefs: parsed.spineURLs.map(\.absoluteString)
            )
            readRoot = directory
            currentIndex = min(max(work.lastSpineIndex, 0), parsed.spineURLs.count - 1)
            Log.epub.info("Opened EPUB: \(parsed.chapters.count) chapters")
        } catch {
            document = nil
            sections = []
            openError = (error as? EPUBError)?.errorDescription
            Log.epub.error("Couldn't open EPUB: \(error.localizedDescription, privacy: .public)")
        }
        configureController()
        isLoading = false
        loadCurrentChapter()
    }

    private func loadCurrentChapter() {
        guard let document, let readRoot, document.spineURLs.indices.contains(currentIndex) else { return }
        controller.load(
            document.spineURLs[currentIndex],
            readAccess: readRoot,
            landOnLast: landNextChapterOnLastPage
        )
        work.lastSpineIndex = currentIndex
        work.markProgressModified()
        landNextChapterOnLastPage = false
    }
}

/// A horizontal swipe gesture that turns pages (paged mode) or changes chapters
/// (scrolled mode). It fires only on a clearly horizontal swipe — `|dx| > |dy|` and
/// past a threshold — so vertical scrolling in scrolled mode is never hijacked.
private struct PageSwipe: ViewModifier {
    let next: () -> Void
    let prev: () -> Void

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    // Horizontal-dominant only, so a diagonal scroll doesn't page.
                    guard abs(dx) > abs(dy), abs(dx) > 44 else { return }
                    if dx < 0 { next() } else { prev() }
                }
        )
    }
}

#endif
