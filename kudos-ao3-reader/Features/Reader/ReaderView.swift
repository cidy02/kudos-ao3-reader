import OSLog
import SwiftData
import SwiftUI

// The legacy WKWebView reader is the **macOS** reader implementation only — iOS uses
// the Readium navigator (see `BookReaderView`), so this whole file is excluded from
// iOS builds.
#if os(macOS)

/// A basic EPUB reader with selectable themes, fonts, and scrolled/paged layout
/// (including a two-page spread on wide windows). Display options live in a
/// hideable inspector sidebar.
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
    /// Native half of the intra-chapter position bridge: current/remembered
    /// fractions per chapter plus the SwiftData write debounce (A7-F2).
    @State private var progressBridge = ReaderProgressBridge()
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

    /// Window width at which a two-page spread becomes available.
    private let twoPageThreshold: CGFloat = 820

    private var chapterCount: Int {
        document?.spineURLs.count ?? 0
    }

    private var isWideEnough: Bool {
        availableWidth >= twoPageThreshold
    }

    /// Always true: this legacy reader only ever builds for macOS (iOS uses the
    /// Readium navigator), where there's no iPhone-width constraint to rule out.
    private var twoPageSpreadAvailable: Bool { true }

    private var columns: Int {
        (readingMode == .paged && twoPageEnabled && twoPageSpreadAvailable && isWideEnough) ? 2 : 1
    }

    /// The reader's effective theme — the app theme while the two are linked.
    private var theme: ReaderTheme {
        themeManager.readerTheme
    }

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

    /// Applies the current style/layout to the controller.
    private func configureController() {
        controller.configure(css: css, mode: readingMode, columns: columns, margin: resolvedMargin)
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
            .toolbar {
                ActionToolbar(items: [
                    AnyView(ToolbarIconButton(title: "Chapters", systemImage: "list.bullet") {
                        router.toggle(.readerChapters)
                    }),
                    AnyView(ToolbarIconButton(title: "Display Options", systemImage: "textformat.size") {
                        router.toggle(.readerDisplay)
                    }),
                    AnyView(
                        Menu {
                            if let id = WorkTags.ao3WorkID(from: work.sourceURL) {
                                AO3WorkActionsMenu(workID: id, actions: workActions,
                                                   workContext: .init(savedWork: work),
                                                   commentsInitialChapterPosition: currentAO3Chapter)
                            }
                        } label: {
                            Label("More actions", systemImage: "ellipsis")
                        }
                        .disabled(WorkTags.ao3WorkID(from: work.sourceURL) == nil)
                    )
                ])
            }
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
            .task(id: work.id) { await load() }
            .onAppear(perform: wireController)
            .onDisappear {
                // Flush the exact final position so resume lands precisely, even if
                // the last scroll's debounce window hadn't elapsed before we left.
                flushProgress()
                try? modelContext.save()
                WorkLifecycle.freeEPUBIfFinished(work, in: modelContext)
                // Breaks the controller ↔ view retain cycle (A7-F3) — safe if
                // this instance reappears later, since `wireController()`
                // re-populates every callback `teardown()` clears.
                controller.teardown()
                // Leaving the reader closes its panel so it doesn't linger as state.
                if router.panel == .readerChapters || router.panel == .readerDisplay {
                    router.panel = .none
                }
            }
            // `onDisappear` doesn't run when the whole app quits with the reader
            // open — flush on termination so that close path can't lose position.
            .onReceive(NotificationCenter.default.publisher(
                for: NSApplication.willTerminateNotification)) { _ in
                flushProgress()
                try? modelContext.save()
            }
            .onChange(of: currentIndex) { _, _ in
                if !isLoading { loadCurrentChapter() }
            }
            .onChange(of: renderToken) { _, _ in
                // Mode/style/theme reflow: persist the position first; the layout
                // script then re-derives the page / scroll offset from the same
                // fraction, so the reading spot survives the transition.
                flushProgress()
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

    /// The bottom chapter controls; this legacy reader's chrome stays docked
    /// (macOS-only — no immersive tap-to-hide mode here).
    private var bottomControls: some View {
        chapterControls
    }

    private var chapterControls: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 12) {
                navButton(systemName: "chevron.left", action: goPrevious, disabled: prevDisabled)
                positionPill
                navButton(systemName: "chevron.right", action: goNext, disabled: nextDisabled)
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
        Text(positionLabel)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 16)
            .frame(height: 44)
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

    private func jump(to index: Int) {
        landNextChapterOnLastPage = false
        if index == currentIndex {
            // Same chapter: an explicit re-pick means "back to the start", so
            // drop its remembered position before reloading.
            progressBridge.forget(spine: index)
            loadCurrentChapter()
        } else {
            currentIndex = index // triggers load via onChange
        }
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
        // Intra-chapter position stream (already stale-gated by the controller):
        // track it in memory on every report, write it through only on the
        // bridge's debounce so scrolling doesn't hammer SwiftData.
        controller.onProgressFraction = { fraction in
            progressBridge.recordProgress(fraction)
            persistProgressIfDue()
        }
        // A cross-chapter note link resolves against the loaded spine and jumps
        // there through the authoritative `currentIndex` path (A7-F5) — a raw
        // in-webview navigation would otherwise leave the pill/TOC/progress/
        // comments scope pointed at the chapter that was current before the tap.
        // The lookup is split from the jump so the controller can finalize
        // WebKit's navigation decision before this starts a new load.
        controller.recognizesSpineURL = { url in
            spineIndex(for: url) != nil
        }
        controller.onCrossSpineNavigation = { url in
            guard let index = spineIndex(for: url) else { return }
            landNextChapterOnLastPage = false
            currentIndex = index // triggers load via onChange
        }
    }

    /// The spine position `url` refers to, if any — normalized through
    /// `ReaderController.fileKey` so both sides of the comparison treat macOS's
    /// `/var` vs `/private/var` symlinking identically.
    private func spineIndex(for url: URL) -> Int? {
        guard let document else { return nil }
        let key = ReaderController.fileKey(url)
        return document.spineURLs.firstIndex { ReaderController.fileKey($0) == key }
    }

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
            // Seed the persisted intra-chapter position so reopening restores
            // the exact saved spot in the saved chapter.
            progressBridge.seed(spine: currentIndex, fraction: work.lastScrollFraction)
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

}

// MARK: Intra-chapter position persistence

private extension ReaderView {
    func loadCurrentChapter() {
        guard let document, let readRoot, document.spineURLs.indices.contains(currentIndex) else { return }
        // Revisits restore the chapter's remembered position; first visits (and
        // explicit same-chapter re-picks) start at the top. Backward paging
        // (`landOnLast`) keeps its last-page landing for spatial continuity.
        let restore = progressBridge.beginChapter(spine: currentIndex)
        controller.load(
            document.spineURLs[currentIndex],
            readAccess: readRoot,
            landOnLast: landNextChapterOnLastPage,
            restoreFraction: restore > 0 ? restore : nil
        )
        // Chapter transitions persist the position pair together, so the saved
        // spine + fraction always describe the same chapter.
        work.lastSpineIndex = currentIndex
        work.lastScrollFraction = restore
        work.markProgressModified()
        progressBridge.markPersisted(restore)
        landNextChapterOnLastPage = false
    }

    /// Ordinary streamed update: writes only when the bridge's debounce allows,
    /// keeping SwiftData writes rare while the user scrolls.
    func persistProgressIfDue() {
        guard let fraction = progressBridge.fractionForDebouncedWrite() else { return }
        work.lastScrollFraction = fraction
        work.markProgressModified()
        progressBridge.markPersisted(fraction)
    }

    /// Flush point (dismissal, mode/layout transition, app termination): always
    /// writes the latest position, bypassing the debounce window.
    func flushProgress() {
        guard let fraction = progressBridge.fractionForFlush() else { return }
        work.lastScrollFraction = fraction
        work.markProgressModified()
        progressBridge.markPersisted(fraction)
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
