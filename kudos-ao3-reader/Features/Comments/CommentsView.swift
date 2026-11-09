import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A pushed (non-modal) Comments destination.
///
/// Value-based on purpose: a destination-based `NavigationLink { CommentsView(…) }`
/// puts the pushed view *outside* the enclosing stack's `NavigationPath`, so a later
/// `path.append` — an author byline push, say — discards Comments instead of stacking
/// on top of it. That surfaced two ways: Back from the pushed profile skipped Comments
/// entirely, and when the append also raced a dismissing composer sheet the push was
/// dropped with no profile at all. Routing through the path makes it a plain append.
/// See T-139 / `AO3AuthorNavigationModifier`.
nonisolated struct AO3CommentsRoute: Hashable {
    let workID: Int
    let context: AO3CommentsWorkContext
    var focusesChapter = false
    var composes = false
}

/// A local downloaded work plus the EPUB section a comment named. Kept separate
/// from `LocalWorkDestination`: ordinary reader entry resumes, while this route
/// deliberately starts at a specific story chapter without changing saved progress.
private struct CommentReaderDestination: Identifiable, Hashable {
    let work: SavedWork
    let spineIndex: Int
    var id: String { "\(work.id.uuidString):\(spineIndex)" }

    // `navigationDestination(item:)` needs Hashable; the id is the identity.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Ordinary sizes keep the floating pill in a bottom safe-area inset (or the system
/// bottom accessory beside the minimised tab when pushed on iOS). Accessibility
/// sizes pin the same control under the list so it cannot cover a row.
private struct CommentWriteBarPlacement<Bar: View>: ViewModifier {
    var isAccessoryActive: Bool
    var accessibilitySize: Bool
    @ViewBuilder var bar: () -> Bar

    func body(content: Content) -> some View {
        if accessibilitySize {
            VStack(spacing: 0) {
                content
                bar()
            }
        } else if !isAccessoryActive {
            content.safeAreaInset(edge: .bottom) { bar() }
        } else {
            content
        }
    }
}

/// Native AO3 comments for a work: all comments or per-chapter, threaded, with
/// reply/compose and the per-comment actions AO3 actually exposes. Pushed from
/// Work Detail and presented as a sheet from the reader's actions menu.
struct CommentsView: View {
    private struct PendingDelete {
        let comment: AO3Comment
        let generation: Int
    }

    let workID: Int
    let workContext: AO3CommentsWorkContext
    /// True when presented modally (a sheet/pop-up card) rather than pushed onto
    /// a `NavigationStack` — a push gets the system's automatic back button, but
    /// a sheet's own root `NavigationStack` has no way back without one, so this
    /// drives an explicit Close button (and, when `onRequestExpand` is set, an
    /// Expand button promoting the pop-up card to a full-screen presentation).
    var isModal = false
    /// Present when shown modally and expansion is available; promotes the sheet
    /// to a `fullScreenCover` (see `commentsSheet(...)` below) — for long threads
    /// or composing, where the pop-up card feels cramped.
    var onRequestExpand: (() -> Void)?
    /// Modal presenters use this to dismiss Comments before opening/moving the
    /// reader. A pushed Comments screen leaves it nil and pushes its own reader.
    var onOpenReaderChapter: ((SavedWork, Int) -> Void)?
    /// Inbox can retain canonical work metadata learned by this navigation, so
    /// returning to the feed corrects sibling badges and summary cards together.
    var onResolveWorkContext: ((AO3CommentsWorkContext) -> Void)?

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(PrivacyGate.self) private var gate
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var allWorks: [SavedWork]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var noteSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .footnote) private var writeCommentButtonSize: CGFloat = 14

    @State private var model: CommentsModel
    @State private var showingChapterPicker = false
    @State private var showingLogin = false
    @State private var pendingDelete: PendingDelete?
    @State private var actionBanner: String?
    /// Reveal for a work that isn't in the library: this screen only, never the app-wide reveal-all.
    @State private var revealedUnsavedWork = false
    @State private var contextLoadTask: Task<Void, Never>?
    /// The comment "Thread"/"Parent Thread" most recently scrolled to, briefly
    /// tinted so the jump is visible even when the target was already on-screen.
    @State private var highlightedCommentID: Int?
    @State private var swipeTracker = CommentSwipeTracker()
    @State private var highlightClearTask: Task<Void, Never>?
    /// Roots forced open by a "Thread"/"Parent Thread" jump, so a collapsed reply
    /// stack can't hide the comment being scrolled to.
    @State private var focusScrollTask: Task<Void, Never>?
    @State private var didApplyInitialFocus = false
    @State private var commentsWidth: CGFloat = 390
    /// The thread being pushed, if any. AO3 gives Thread / Parent Thread their own
    /// isolated-thread pages, so these navigate rather than scrolling in place.
    @State private var pushedThread: CommentThreadRoute?
    #if os(iOS)
    @State private var accessoryTab: AppTab?
    #endif
    @State private var readerSections: [ReaderSection]
    @State private var readerDestination: CommentReaderDestination?
    #if DEBUG
    @State private var didApplyDebugThreadRoute = false
    #endif

    init(
        workID: Int, context: AO3CommentsWorkContext, initialChapterPosition: Int? = nil,
        initialCommentID: Int? = nil, initialFocusesChapter: Bool = false,
        initialComposes: Bool = false,
        initialReplyCommentID: Int? = nil,
        requiredSessionGeneration: Int? = nil,
        isModal: Bool = false, onRequestExpand: (() -> Void)? = nil,
        readerSections: [ReaderSection] = [],
        onOpenReaderChapter: ((SavedWork, Int) -> Void)? = nil,
        onResolveWorkContext: ((AO3CommentsWorkContext) -> Void)? = nil
    ) {
        self.workID = workID
        self.workContext = context
        self.isModal = isModal
        self.onRequestExpand = onRequestExpand
        self.onOpenReaderChapter = onOpenReaderChapter
        self.onResolveWorkContext = onResolveWorkContext
        _readerSections = State(initialValue: readerSections)
        _model = State(initialValue: CommentsModel(
            workID: workID,
            workContext: context,
            requiredSessionGeneration: requiredSessionGeneration,
            initialChapterPosition: initialChapterPosition,
            initialCommentID: initialCommentID,
            initialFocusesChapter: initialFocusesChapter,
            initialComposes: initialComposes,
            initialReplyCommentID: initialReplyCommentID
        ))
    }

    private var authenticationKey: String {
        "\(auth.sessionGeneration)|\(auth.isLoggedIn)|\(auth.username ?? "")"
    }

    private var gutter: CGFloat { SubjectMetrics.accountGutter }

    /// The page hue, derived exactly the way Work Detail derives its own, so a
    /// work and its comments wash in one colour rather than two near-misses.
    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(
                fandoms: model.workContext.fandoms,
                title: model.workContext.title
            )
        )
    }

    var body: some View {
        Group {
            if model.belongsToCurrentSession(auth: auth) {
                commentsBody
            } else {
                ProgressView().accentFill()
                    .task { dismiss() }
            }
        }
        .screenTint(palette)
    }

    private var commentsBody: some View {
        // Walked once here and handed down, rather than recomputed by the strip
        // and again by the section header: this whole body re-evaluates on every
        // swipe, which is the cost `conversationRows` exists to keep down.
        let figures = loadedFigures
        return ScrollViewReader { proxy in
            List {
                Section {
                    compactWorkRow.pageBodyRow(top: 14, gutter: gutter)
                    if model.page != nil {
                        metaLine(figures).pageBodyRow(top: 10, gutter: gutter)
                    }
                    filterRail.pageBodyRow(top: 10, gutter: gutter)
                    headerDivider.pageBodyRow(top: 14, gutter: gutter)
                }
                contentSections(scrollProxy: proxy, figures: figures)
                if case .loaded = model.phase {
                    // Board 21 draws no paragraph under the meta line: the scope note
                    // is a footnote under the list instead (same words, same condition).
                    if let note = signalScopeNote {
                        Text(note)
                            .font(.system(size: noteSize))
                            .foregroundStyle(Color.secondary.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .pageBodyRow(top: 12, gutter: gutter + 4)
                    }
                    // The safe-area inset reserves the floating CTA's footprint; this
                    // final breathing room also lets the last long comment scroll fully
                    // clear of glass/tab/home-indicator overlays.
                    Color.clear
                        .frame(height: 64)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityHidden(true)
                }
            }
            .cardList()
            .coordinateSpace(.named(CommentThreadGeometry.listSpace))
            .environment(swipeTracker)
            // Rows need the container width to size their indent, but indent
            // feeds `listRowInsets` — which is resolved before a row lays out,
            // so a row can't measure itself in time. Measure once here.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { commentsWidth = $0 }
            .environment(\.commentsContentWidth, commentsWidth)
            .subjectScreenWash(title: "Comments", palette: palette, role: .content)
            .navigationDestination(item: $pushedThread) { route in
                CommentThreadScreen(
                    rootID: route.commentID,
                    model: model,
                    handlers: threadHandlers(scrollProxy: proxy),
                    // A "Parent Thread" pointing above the pushed subtree pops back
                    // here; the list is the only place that can resolve it.
                    onFocusOutsideSubtree: { scrollToComment($0, proxy: proxy) }
                )
            }
            .navigationDestination(for: AO3WorkSummary.self) { summary in
                WorkDetailView(remote: summary)
            }
            .navigationDestination(item: $readerDestination) { destination in
                BookReaderView(
                    work: destination.work,
                    initialSpineIndex: destination.spineIndex
                )
            }
            // At accessibility sizes the inset did not keep the list clear of the
            // pill, and the pill covered "All comments". The bar then sits under
            // the list, full width, on its own ground. Pushed at standard sizes on iOS,
            // Comments uses the system bottom accessory beside the minimised tab (T-482).
            .modifier(
                CommentWriteBarPlacement(
                    isAccessoryActive: usesTabViewBottomAccessory,
                    accessibilitySize: dynamicTypeSize.isAccessibilitySize
                ) {
                    writeCommentBar
                }
            )
            #if os(iOS)
            .tabViewBottomAccessory {
                if usesTabViewBottomAccessory, case .loaded = model.phase {
                    commentAccessoryBar
                }
            }
            .onAppear {
                // The tab this screen lives in; the selection can change before the composer loads.
                if accessoryTab == nil { accessoryTab = router.selection }
                router.commentAccessoryTab = commentAccessoryActive ? accessoryTab : nil
            }
            .onChange(of: commentAccessoryActive) { _, active in
                router.commentAccessoryTab = active ? accessoryTab : nil
            }
            #endif
            .refreshable { await model.load(auth: auth, forceRefresh: true) }
            .task(id: readableWork?.id) { await loadReaderSectionsIfNeeded() }
            .task {
                await model.loadInitial(auth: auth)
                reportResolvedWorkContext()
                await applyInitialFocusIfNeeded(proxy: proxy)
                #if DEBUG
                if !didApplyDebugThreadRoute, let rootID = DebugLaunchRoute.threadRootID(in: model) {
                    didApplyDebugThreadRoute = true
                    openThread(rootID)
                }
                if DebugLaunchRoute.takeSheet("chapterpicker") {
                    model.scope = .byChapter
                    showingChapterPicker = true
                }
                #endif
            }
            .onChange(of: model.workContext) { _, context in
                if !context.authors.isEmpty || !context.authorIdentities.isEmpty {
                    reportResolvedWorkContext()
                }
            }
            .onChange(of: authenticationKey) { _, _ in
                guard model.belongsToCurrentSession(auth: auth) else {
                    dismiss()
                    return
                }
                contextLoadTask?.cancel()
                pendingDelete = nil
                actionBanner = nil
                model.syncAuthenticationContext(auth: auth)
                contextLoadTask = Task {
                    // Let any scope/chapter reset observers replace this task first,
                    // so an account switch still issues only one comments request.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    await model.load(auth: auth, forceRefresh: true)
                }
            }
            .onChange(of: model.scope) { _, scope in
                // loadInitial sets scope/chapter itself and does the one load; skip
                // the redundant reload its programmatic changes would otherwise trigger.
                guard !model.isApplyingInitialContext else { return }
                contextLoadTask?.cancel()
                contextLoadTask = Task {
                    model.resetForContextChange()
                    if scope == .byChapter {
                        await model.loadChaptersIfNeeded(auth: auth)
                        guard !Task.isCancelled else { return }
                        if model.chaptersFailed {
                            // The chapter index genuinely failed to load (offline/
                            // timeout) — don't silently fall through to a whole-work
                            // fetch while the UI still reads "By Chapter" with no
                            // per-comment chapter badges to show it's mislabeled.
                            // Surface the real failure via the chapter picker's own
                            // error state instead.
                            showingChapterPicker = true
                            return
                        }
                        if model.selectedChapter == nil, let first = model.chapters.first {
                            // Assigning the chapter triggers the selectedChapter
                            // onChange, which loads — don't also load here (double GET).
                            model.selectedChapter = first
                            return
                        }
                    }
                    await model.load(auth: auth)
                }
            }
            .onChange(of: model.selectedChapter) { _, _ in
                guard !model.isApplyingInitialContext else { return }
                contextLoadTask?.cancel()
                model.resetForContextChange()
                contextLoadTask = Task { await model.load(auth: auth) }
            }
            .onChange(of: model.newestFirst) { _, _ in
                contextLoadTask?.cancel()
                // Reset first: the currently-cached page belongs to the OLD order's
                // target page, not the new one — showing it (even briefly, reversed)
                // would render the wrong page's content under the new sort label.
                model.resetForContextChange()
                contextLoadTask = Task { await model.load(auth: auth) }
            }
            .onDisappear {
                contextLoadTask?.cancel()
                highlightClearTask?.cancel()
                focusScrollTask?.cancel()
                router.commentAccessoryTab = nil
            }
            .sheet(isPresented: composerBinding, onDismiss: {
                // When this CommentsView is itself modal, the outer sheet/full-screen
                // presenter (`CommentsSheetModifier`) is the one that fires a queued
                // parent-author push — consuming it here too would land it while that
                // outer presentation is still mid-dismiss (silently buried, see
                // `openParentAuthor`). Non-modal (pushed) CommentsView has no outer
                // sheet, so the composer's own dismiss is the real completion signal.
                if !isModal {
                    router.openPendingAuthorProfileAfterDismiss()
                }
            }) {
                CommentComposerSheet(
                    model: model, isModal: isModal,
                    dismissCommentsView: isModal ? dismiss : nil
                )
            }
            .onChange(of: model.composerContext != nil) { _, presented in
                // Same rising-edge strand clear as `CommentsSheetModifier`, for the
                // one queuing path that modifier can't cover: a *pushed* (non-modal)
                // CommentsView opens no outer sheet, so nothing else would clear a
                // route stranded before the composer's reply-quote byline is tapped.
                // Queuing only happens on the way out, so this cannot race the drain.
                if presented { router.cancelPendingAuthorProfileAfterDismiss() }
            }
            .sheet(isPresented: $showingChapterPicker) {
                chapterPicker
            }
            .sheet(isPresented: $showingLogin) {
                AO3LoginView()
            }
            .alert("Delete this comment?", isPresented: deleteBinding, presenting: pendingDelete) { pending in
                Button("Delete", role: .destructive) { delete(pending) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes the comment on AO3. It cannot be undone.")
            }
            .alert("AO3", isPresented: bannerBinding) {
                Button("OK") { actionBanner = nil }
            } message: {
                Text(actionBanner ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    WorkListMoreMenu {
                        Button {
                            Task { await model.load(auth: auth, forceRefresh: true) }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        if let workURL {
                            ShareLink(item: workURL) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            Link(destination: workURL) {
                                Label("Open on AO3", systemImage: "safari")
                            }
                        }
                    }
                }
                // Only when presented modally: a push already gets the system's
                // automatic back button, and a fully-expanded presentation (reached
                // via onRequestExpand) has nowhere further to expand to.
                if isModal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                    if let onRequestExpand {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                onRequestExpand()
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                            }
                            .accessibilityLabel("Expand to full screen")
                        }
                    }
                }
            }
        }
    }

    private var workURL: URL? {
        URL(string: "https://archiveofourown.org/works/\(model.workID)")
    }

    /// The exact local copy represented by this Comments screen, when it is still
    /// readable. This is the same file-existence gate used by every reader entry.
    private var readableWork: SavedWork? {
        allWorks.first { work in
            (work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)) == workID
                && WorkReaderPreparation.hasReadableEPUB(for: work)
        }
    }

    private func chapterSpineIndex(for comment: AO3Comment) -> Int? {
        guard readableWork != nil, let chapter = comment.storyChapterPosition else { return nil }
        return readerSections.spineIndex(forStoryChapter: chapter)
    }

    private func openReader(atChapterFor comment: AO3Comment) {
        guard let work = readableWork,
              let spineIndex = chapterSpineIndex(for: comment)
        else { return }
        if let onOpenReaderChapter {
            onOpenReaderChapter(work, spineIndex)
        } else {
            readerDestination = CommentReaderDestination(work: work, spineIndex: spineIndex)
        }
    }

    /// Outside an already-open reader, derive the chapter map from the installed
    /// EPUB only. Reader callers pass their already-built sections and skip this.
    private func loadReaderSectionsIfNeeded() async {
        guard readerSections.isEmpty, let work = readableWork else { return }
        let fileURL = work.fileURL
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("comment-chapters-\(UUID().uuidString)", isDirectory: true)
        let sections: [ReaderSection]? = try? await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let document = try EPUBDocument.open(epubURL: fileURL, into: directory)
            return ReaderSectionBuilder.build(
                tocEntries: document.chapters.map {
                    ReaderSectionBuilder.RawTOCEntry(title: $0.title, spineIndex: $0.spineIndex)
                },
                spineHrefs: document.spineURLs.map(\.absoluteString)
            )
        }.value
        guard readableWork?.id == work.id, let sections else { return }
        readerSections = sections
    }

    private func reportResolvedWorkContext() {
        guard !model.workAuthors.isEmpty || !model.workAuthorIdentities.isEmpty else { return }
        onResolveWorkContext?(model.workContext)
    }

    /// Pushes AO3's own isolated-thread page for `commentID`.
    ///
    /// This used to scroll to the comment in place and call that "the native
    /// equivalent" of AO3's thread page. It isn't: AO3 navigates, and a comment
    /// carries a real `threadPath` to navigate *to*. Matching that is also what
    /// lets the list stay shallow — deep chains have somewhere to go.
    private func openThread(_ commentID: Int) {
        pushedThread = CommentThreadRoute(commentID: commentID)
    }

    /// Scrolls to and briefly highlights `commentID` in this list. Still used for
    /// the Inbox deep link, which lands on a comment *in context* — pushing a
    /// thread screen over a list the reader hasn't seen yet would bury it.
    ///
    /// Every comment is its own List row, so the target is directly addressable —
    /// but a *collapsed* thread doesn't render its replies at all, so a reply still
    /// needs its root expanded and a layout pass before `scrollTo` can resolve it.
    private func scrollToComment(_ commentID: Int, proxy: ScrollViewProxy) {
        highlightedCommentID = commentID
        highlightClearTask?.cancel()
        highlightClearTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            highlightedCommentID = nil
        }

        focusScrollTask?.cancel()
        guard let rootID = model.rootID(containing: commentID), rootID != commentID else {
            // A root comment owns its own List row — address it directly.
            withAnimationUnlessReduced(.easeInOut(duration: 0.3), reduceMotion: reduceMotion) {
                proxy.scrollTo(commentID, anchor: .center)
            }
            return
        }

        // The target is a reply under `rootID`. Expand that thread if it's
        // collapsed (its row wouldn't be in the view tree at all) and scroll the
        // root in first. `scrollTo` silently no-ops on an id that isn't laid out
        // yet, so the newly inserted reply rows need a layout pass before we can
        // address one — hence the yield rather than a second call in this pass.
        model.forceExpand(rootID: rootID)
        proxy.scrollTo(rootID, anchor: .center)
        focusScrollTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            withAnimationUnlessReduced(.easeInOut(duration: 0.3), reduceMotion: reduceMotion) {
                proxy.scrollTo(commentID, anchor: .center)
            }
        }
    }

    /// The focused Inbox response changes the List from skeletons to a real
    /// thread in the same update. Wait one short layout pass before scrolling so
    /// `ScrollViewReader` can resolve the newly inserted root id reliably.
    private func applyInitialFocusIfNeeded(proxy: ScrollViewProxy) async {
        guard !didApplyInitialFocus, let commentID = model.initialFocusCommentID else { return }
        didApplyInitialFocus = true
        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        scrollToComment(commentID, proxy: proxy)
    }

    private func threadHandlers(scrollProxy: ScrollViewProxy) -> CommentThreadHandlers {
        CommentThreadHandlers(
            onReply: { model.startComposer(replyingTo: $0, auth: auth) },
            onEdit: { model.startEditing($0, auth: auth) },
            onDelete: { comment in
                guard let current = model.deletableComment(comment, auth: auth) else { return }
                pendingDelete = PendingDelete(
                    comment: current,
                    generation: auth.sessionGeneration
                )
            },
            onCopyLink: { copyLink($0) },
            onFocusThread: { openThread($0) },
            chapterSpineIndex: { chapterSpineIndex(for: $0) },
            onGoToChapter: { openReader(atChapterFor: $0) },
            onRequestLogin: { showingLogin = true },
            onOpenAuthor: openAuthor
        )
    }

    // MARK: Header

    private var workSummary: AO3WorkSummary {
        AO3WorkSummary(
            id: workID,
            title: model.workContext.title,
            authors: model.workAuthors,
            authorIdentities: model.workAuthorIdentities,
            fandoms: model.workContext.fandoms,
            rating: model.workContext.rating,
            warnings: [],
            categories: [],
            dateUpdated: "",
            tags: [],
            summary: "",
            language: "",
            chapters: model.workContext.chapters
        )
    }

    private var isMatureConcealed: Bool {
        guard hideMature else { return false }
        if let matching = allWorks.first(where: { $0.ao3WorkID == workID }) {
            return gate.isConcealed(matching, enabled: hideMature)
        }
        return CommentsHeaderLayout.isWorkConcealed(
            rating: model.workContext.rating,
            hideMature: hideMature,
            isRevealed: gate.revealAll || revealedUnsavedWork
        )
    }

    private func revealMatureWork() {
        if let matching = allWorks.first(where: { $0.ao3WorkID == workID }) {
            gate.reveal(matching)
        } else {
            revealedUnsavedWork = true
        }
    }

    @ViewBuilder
    private var compactWorkRow: some View {
        if isMatureConcealed {
            compactWorkRowContent(concealed: true)
                .environment(\.ao3AuthorNavigationEnabled, false)
                .blur(radius: 6)
                .overlay {
                    MatureRevealCapsule()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    revealMatureWork()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Hidden mature work")
                .accessibilityHint("Activate to reveal.")
        } else {
            compactWorkRowContent(concealed: false)
                .contentShape(Rectangle())
                .cardNavigation(to: workSummary, accessibilityLabel: workRowAccessibilityLabel)
        }
    }

    private func compactWorkRowContent(concealed: Bool) -> some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            CompactWorkCover(
                title: model.workContext.title,
                fandoms: model.workContext.fandoms,
                showsInitial: !concealed
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(model.workContext.title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                workSubtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, dynamicTypeSize.isAccessibilitySize ? 4 : 0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var workSubtitle: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                if hasByline {
                    AO3AuthorBylineView(
                        names: model.workAuthors,
                        identities: model.workAuthorIdentities,
                        includesBy: false,
                        font: .subheadline,
                        compact: true,
                        expandsHitTarget: false,
                        onOpenRoute: openAuthor
                    )
                }
                if let selectedChapterFact {
                    Text(selectedChapterFact)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if hasByline {
                    AO3AuthorBylineView(
                        names: model.workAuthors,
                        identities: model.workAuthorIdentities,
                        includesBy: false,
                        font: .subheadline,
                        compact: true,
                        expandsHitTarget: false,
                        onOpenRoute: openAuthor
                    )
                }
                if hasByline, selectedChapterFact != nil {
                    Text("·")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let selectedChapterFact {
                    Text(selectedChapterFact)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var workRowAccessibilityLabel: String {
        var label = model.workContext.title
        if hasByline {
            let names = model.workAuthors.isEmpty
                ? model.workAuthorIdentities.map(\.displayName)
                : model.workAuthors
            label += " by \(names.joined(separator: ", "))"
        }
        if let chapterFact = selectedChapterFact {
            label += ", \(chapterFact)"
        }
        return label
    }

    private var hasByline: Bool {
        !model.workAuthors.isEmpty || !model.workAuthorIdentities.isEmpty
    }

    private var totalChapters: Int? {
        CommentsHeaderLayout.totalChaptersCount(
            chapters: model.chapters,
            chaptersLoaded: model.chaptersLoaded,
            rawChapters: model.workContext.chapters
        )
    }

    private var selectedChapterFact: String? {
        CommentsHeaderLayout.chapterSubtitle(
            scope: model.scope,
            selectedChapter: model.selectedChapter,
            totalChapters: totalChapters
        )
    }

    // MARK: Signal line & figures

    /// The three figures counted from loaded comment threads.
    private struct LoadedFigures {
        var threads = 0
        var comments = 0
        var mine = 0
        var latest: Date?
    }

    /// One walk over the loaded page for all three.
    private var loadedFigures: LoadedFigures {
        var figures = LoadedFigures()
        for root in model.displayThreads {
            figures.threads += 1
            for comment in root.flattened {
                figures.comments += 1
                if comment.editPath != nil { figures.mine += 1 }
                if let posted = comment.postedAt, posted > (figures.latest ?? .distantPast) {
                    figures.latest = posted
                }
            }
        }
        return figures
    }

    private func metaLine(_ figures: LoadedFigures) -> some View {
        let totalComments = model.page?.totalComments ?? figures.comments
        // The rows' own short age, so "latest" never disagrees with the newest row (Foundation's
        // relative format rounded 3.6 months up to "4mo" while the row said "3mo").
        let latestRelative = figures.latest.map { date -> String in
            let age = AO3CommentTimestamp.shortAge(seconds: Date().timeIntervalSince(date))
            return age == "now" ? "just now" : "\(age) ago"
        }
        let data = CommentsHeaderLayout.metaLineData(
            totalComments: totalComments,
            threads: figures.threads,
            mine: figures.mine,
            isLoggedIn: auth.isLoggedIn,
            latestRelativeText: latestRelative
        )
        return HStack(spacing: 0) {
            metaLineText(data)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(data.accessibilityLabel)
    }

    private func metaLineText(_ data: CommentsHeaderLayout.MetaLineData) -> Text {
        var text = Text(data.commentsText)
            .fontWeight(.semibold)
            .foregroundStyle(Color.primary)

        text = text + Text(" · ") + Text(data.threadsText)

        if let yoursText = data.yoursText {
            if data.isYoursHighlighted {
                text = text + Text(" · ") + Text(yoursText)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.accentInk)
            } else {
                text = text + Text(" · ") + Text(yoursText)
            }
        }

        if let latestText = data.latestText {
            text = text + Text(" · ") + Text(latestText)
        }

        return text
    }

    private var headerDivider: some View {
        // In a VStack: a Divider follows its parent stack's axis, and the row lays out horizontally.
        VStack(spacing: 0) { Divider() }
            .opacity(0.6)
            .accessibilityHidden(true)
    }

    /// Printed under the strip whenever the loaded page is not the whole work.
    private var signalScopeNote: String? {
        guard let page = model.page, page.totalPages > 1 else { return nil }
        return "Threads, Yours and Latest count only this page. The comment total covers the whole work."
    }

    // MARK: Chapter + sort

    /// The artboard's two dropdown pills, under the signal strip.
    ///
    /// The All / By Chapter segmented picker is gone: it asked the same question
    /// the chapter control answers, and the sheet this pill opens already lists
    /// "All Comments" above the chapters. One control, both behaviours, and the
    /// pill itself states which one is in force.
    @ViewBuilder private var filterRail: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Side by side the two were cut to "All…" and "…" at the accessibility sizes (seen
            // on the simulator at AX5): one under the other, each with the row to itself.
            VStack(alignment: .leading, spacing: 7) {
                chapterPill
                sortPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 7) {
                chapterPill
                sortPill
                Spacer(minLength: 0)
            }
        }
    }

    private var chapterPill: some View {
            Button {
                showingChapterPicker = true
            } label: {
                SubjectChip(
                    text: chapterPillTitle,
                    style: .pill(isSelected: model.scope == .byChapter),
                    systemImage: "book",
                    trailingImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Browse comments by chapter")
            .accessibilityValue(chapterPillTitle)
    }

    /// Local-only order menu — AO3 has no server sort, so this reorders what the
    /// model fetches rather than asking for a different ordering.
    private var sortPill: some View {
        Menu {
            Button {
                model.newestFirst = false
            } label: {
                if !model.newestFirst {
                    Label("Oldest First", systemImage: "checkmark")
                } else {
                    Text("Oldest First")
                }
            }
            Button {
                model.newestFirst = true
            } label: {
                if model.newestFirst {
                    Label("Newest First", systemImage: "checkmark")
                } else {
                    Text("Newest First")
                }
            }
        } label: {
            SubjectChip(
                text: model.newestFirst ? "Newest" : "Oldest",
                style: .pill(isSelected: false),
                systemImage: "arrow.up.arrow.down",
                trailingImage: "chevron.down"
            )
        }
        .buttonStyle(.plain)
        // Sibling controls elsewhere in this file reserve a 44pt hit target; a
        // 30pt pill falls short of it on its own (HIG audit UI-3).
        .minimumHitTarget()
        .accessibilityLabel("Sort comments")
        .accessibilityValue(model.newestFirst ? "Newest First" : "Oldest First")
    }

    /// Short by design — the spec's own "Chapter 4", not `displayName`'s
    /// "Chapter 4 · A Very Long Chapter Title", which in a pill can only truncate.
    private var chapterPillTitle: String {
        guard model.scope == .byChapter else { return "All comments" }
        guard let chapter = model.selectedChapter else { return "By chapter" }
        return "Chapter \(chapter.position)"
    }

    // MARK: Content

    @ViewBuilder
    private func contentSections(
        scrollProxy: ScrollViewProxy, figures: LoadedFigures
    ) -> some View {
        switch model.phase {
        case .idle, .loading:
            Section {
                ForEach(0..<4, id: \.self) { _ in
                    CommentSkeletonRow()
                        .listRowInsets(EdgeInsets(
                            top: CommentThreadGeometry.rowTopPadding,
                            leading: CommentThreadGeometry.sideMargin,
                            bottom: 0,
                            trailing: CommentThreadGeometry.sideMargin
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        case let .failed(message):
            Section {
                ContentUnavailableView {
                    Label("Couldn't Load Comments", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        Task {
                            await model.retryInitialLoad(auth: auth)
                            await applyInitialFocusIfNeeded(proxy: scrollProxy)
                        }
                    }
                    .buttonStyle(.kudosPrimary)
                }
            }
            .cardRow()
        case .loaded:
            if let notice = model.keptCopyNotice {
                staleBanner(notice)
            }
            if model.displayThreads.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Comments Yet",
                        systemImage: "bubble.left",
                        description: Text("You can be the first to comment on this work.")
                    )
                }
                .cardRow()
            } else {
                // No "Comments N" rule here: board 21 has none, and the meta line
                // above already states the count (AO3's own total for the work).
                // One flat, lazy ForEach over rows the model already resolved —
                // no nested ForEach and no per-pass allocation, so a swipe
                // re-evaluating this body stays cheap.
                ForEach(model.conversationRows) { row in
                    CommentConversationRow(
                        item: row.item,
                        workAuthors: model.workAuthors,
                        workAuthorIdentities: model.workAuthorIdentities,
                        showChapterBadge: model.scope == .all,
                        startsConversation: row.startsConversation,
                        depth: row.depth,
                        isLastSibling: row.isLastSibling,
                        ancestorLines: row.ancestorLines,
                        nextDepth: row.nextDepth,
                        showsParentAttribution: row.showsParentAttribution,
                        collapse: row.collapse,
                        ancestorIDs: row.ancestorIDs,
                        onExpand: { model.expandReplies(rootID: row.rootID) },
                        onContinueThread: { openThread(row.rootID) },
                        onToggleCollapse: { model.toggleCollapsed(rootID: row.rootID) }
                    )
                    .commentSwipeActions(comment: row.item.actionableComment)
                }
                .environment(\.commentHighlightID, highlightedCommentID)
                .environment(\.commentThreadHandlers, threadHandlers(scrollProxy: scrollProxy))
                if let page = model.page, page.totalPages > 1 {
                    paginationSection(page)
                }
            }
        }
    }

    private func openAuthor(_ route: AO3AuthorRoute) {
        if isModal {
            // Queue the push and let the comments sheet finish dismissing; the
            // presenting `CommentsSheetModifier`'s onDismiss fires it once the
            // dismiss animation actually completes (real completion signal, not
            // a guessed duration).
            //
            // The queue itself is the re-entrancy guard: a second tap while the
            // first is still mid-dismiss is refused here (first tap wins) rather
            // than landing the same profile on the stack twice. It lives on the
            // router, not in local @State, so it also catches a second tap coming
            // from the composer's reply-quote byline — a different View struct
            // that cannot see this one's state — and it cannot latch, since the
            // router clears it when the push is consumed.
            guard router.requestAuthorProfileAfterDismiss(route) else { return }
            dismiss()
        } else {
            router.openAuthorProfile(route)
        }
    }

    private func staleBanner(_ notice: String) -> some View {
        Section {
            Label {
                Text(notice)
            } icon: {
                Image(systemName: model.isOffline ? "wifi.exclamationmark" : "exclamationmark.triangle")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .cardRow()
    }

    private func paginationSection(_ page: AO3CommentsPage) -> some View {
        let previous = Button {
            loadPage(model.currentPageNumber - 1)
        } label: {
            Label("Previous", systemImage: "chevron.left")
        }
        .disabled(model.currentPageNumber <= 1)
        // Matches the 44pt min-frame this file's other controls
        // reserve (HIG audit UI-3).
        .minimumHitTarget()
        let position = Text("Page \(model.currentPageNumber) of \(page.totalPages)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        let next = Button {
            loadPage(model.currentPageNumber + 1)
        } label: {
            Label("Next", systemImage: "chevron.right")
                .labelStyle(.trailingIcon)
        }
        .disabled(model.currentPageNumber >= page.totalPages)
        .minimumHitTarget()
        return Section {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    // In one row the buttons broke mid-word ("P / revi- / ous", "Ne / xt") at the
                    // accessibility sizes, and side by side "Previous" still did at the largest:
                    // the page, then each button on a line of its own, at its own edge.
                    VStack(spacing: 8) {
                        position
                        previous.frame(maxWidth: .infinity, alignment: .leading)
                        next.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    HStack {
                        previous
                        Spacer()
                        position
                        Spacer()
                        next
                    }
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .cardRow()
    }

    private func loadPage(_ number: Int) {
        contextLoadTask?.cancel()
        contextLoadTask = Task { await model.loadPage(number, auth: auth) }
    }

    // MARK: Write bar

    @ViewBuilder
    private var writeCommentBar: some View {
        if case .loaded = model.phase {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleWriteCommentBar
            } else {
                floatingWriteCommentBar
            }
        }
    }

    /// Full-width, on the page's raised surface, with the label free to wrap.
    /// Stays put under the list (not a scroll-away control, and not an overlay).
    private var accessibleWriteCommentBar: some View {
        let title = auth.isLoggedIn ? "Write a comment" : "Log in to comment"
        return Button {
            if auth.isLoggedIn {
                model.startComposer(auth: auth)
            } else {
                showingLogin = true
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: auth.isLoggedIn
                    ? "pencil" : "person.crop.circle.badge.questionmark")
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: writeCommentButtonSize, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(theme.onEffectiveTint)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .fill(theme.effectiveTint)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.isOffline)
        .opacity(model.isOffline ? 0.45 : 1)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(theme.appTheme.cardSurface.ignoresSafeArea(edges: .bottom))
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var floatingWriteCommentBar: some View {
        // Spec 1f's centred 44pt pill, in the app colour — a control is never the
        // page's subject colour, even on a washed screen. Still floating over the page
        // backdrop with no opaque slab behind it: the safe-area inset (plus the
        // list's trailing spacer) keeps content from sitting underneath, and
        // the artboard's scrim would put the slab back. Shown whether or not
        // the reader is signed in — logged out it opens the AO3 login sheet
        // instead of composing, so it is never a dead end.
        let title = auth.isLoggedIn ? "Write a comment" : "Log in to comment"
        Button {
                if auth.isLoggedIn {
                    model.startComposer(auth: auth)
                } else {
                    showingLogin = true
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: auth.isLoggedIn
                        ? "pencil" : "person.crop.circle.badge.questionmark")
                        .font(.system(size: 14, weight: .semibold))
                    Text(title)
                        .font(.system(size: writeCommentButtonSize, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .buttonStyle(.kudosPrimary)
            .disabled(model.isOffline)
            // Match the theme's card-shadow language: Dark/OLED are shadow-free
            // (the accent capsule already pops there, and a shadow can't read
            // against a near-black or true-black backdrop anyway); Light/Sepia get
            // the soft lift.
            .shadow(
                color: theme.appTheme.isDarkFamily ? .clear : .black.opacity(0.2),
                radius: 10, y: 3
            )
            // The pill hugs its own label instead of stretching edge to edge —
            // full-width left the capsule's rounded ends reading as dead space
            // around a short, centered label. Centering happens here, on the
            // frame around the (compact) button, not inside the label.
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            // Sit tight to the home-indicator safe area — only a hair of top
            // padding so the pill doesn't collide with the last comment.
            .padding(.top, 2)
            .padding(.bottom, 0)
            .accessibilityLabel(title)
    }

    private var usesTabViewBottomAccessory: Bool {
        #if os(iOS)
        CommentsWriteBarPlacementPolicy.usesBottomAccessory(
            isModal: isModal,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        #else
        false
        #endif
    }

    private var commentAccessoryActive: Bool {
        guard usesTabViewBottomAccessory else { return false }
        if case .loaded = model.phase { return true }
        return false
    }

    #if os(iOS)
    /// Board 21: the comment bar alongside the minimised tab on iOS.
    private var commentAccessoryBar: some View {
        let title = auth.isLoggedIn ? "Comment on the work…" : "Log in to comment"
        return Button {
            if auth.isLoggedIn {
                model.startComposer(auth: auth)
            } else {
                showingLogin = true
            }
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(theme.effectiveTint))
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(model.isOffline)
        .opacity(model.isOffline ? 0.45 : 1)
        .accessibilityLabel(title)
    }
    #endif

    // MARK: Sheets + bindings

    private var composerBinding: Binding<Bool> {
        Binding(
            get: { model.composerContext != nil },
            set: { shown in
                if !shown {
                    model.saveDraft()
                    model.closeComposer()
                }
            }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var bannerBinding: Binding<Bool> {
        Binding(get: { actionBanner != nil }, set: { if !$0 { actionBanner = nil } })
    }

    private var chapterPicker: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        model.scope = .all
                        showingChapterPicker = false
                    } label: {
                        HStack {
                            Label("All Comments", systemImage: "bubble.left")
                            Spacer()
                            if let total = model.page?.totalComments {
                                Text(total.formatted())
                                    .foregroundStyle(
                                        model.scope == .all ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
                                    )
                            }
                            if model.scope == .all {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .foregroundStyle(model.scope == .all ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    }

                    if model.chapters.isEmpty {
                        if model.chaptersFailed {
                            ContentUnavailableView(
                                "Couldn't Load Chapters",
                                systemImage: "exclamationmark.triangle",
                                description: Text(
                                    model.chaptersFailureMessage
                                        ?? "Check your connection and try again."
                                )
                            )
                        } else if model.chaptersLoaded {
                            Text("No chapters available.")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView().accentFill()
                                .accessibilityLabel("Loading chapters")
                        }
                    }

                    ForEach(model.chapters) { chapter in
                        Button {
                            // Chapter first, scope second. Both changes fire their
                            // own `onChange`, and each of those cancels the task the
                            // other started — so whichever order SwiftUI delivers
                            // them in, exactly one load survives. Setting scope
                            // first would instead let its handler run with no
                            // chapter chosen, which is the branch that assigns one
                            // itself and reloads a second time.
                            model.selectedChapter = chapter
                            model.scope = .byChapter
                            showingChapterPicker = false
                        } label: {
                            HStack {
                                Label(chapter.displayName, systemImage: "book")
                                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                Spacer()
                                if chapter == model.selectedChapter, model.scope == .byChapter {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .foregroundStyle(
                                chapter == model.selectedChapter && model.scope == .byChapter
                                    ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)
                            )
                        }
                    }
                } footer: {
                    // Quiet help text, not a warning panel: explains why there are
                    // no per-chapter counts without shouting about it.
                    Text("AO3 doesn't show comment totals for each chapter. Choose a chapter to see its comments.")
                }
                .appThemedRows()
            }
            .appThemedScroll()
            // The chapter index used to be fetched only as a side effect of
            // switching scope to By Chapter. The pill that opens this sheet can
            // now be tapped while the scope is still All, so the sheet asks for
            // the index itself — `loadChaptersIfNeeded` is idempotent and returns
            // immediately once it holds one.
            .task { await model.loadChaptersIfNeeded(auth: auth) }
            .navigationTitle("Browse Comments by Chapter")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        }
        .presentationDetents(chapterPickerDetents)
        .presentationDragIndicator(.visible)
    }

    private var chapterPickerDetents: Set<PresentationDetent> {
        if model.chapters.count <= 3 {
            // Title + rows + footer note: fitted so a one-chapter work gets a
            // compact sheet instead of a mostly-empty half screen.
            let rowCount = CGFloat(model.chapters.count + 1)
            return [.height(150 + rowCount * 52)]
        }
        return [.medium, .large]
    }

    // MARK: Actions

    private func delete(_ pending: PendingDelete) {
        let expectedGeneration = pending.generation
        guard auth.sessionGeneration == expectedGeneration else { return }
        Task {
            do {
                let message = try await auth.deleteComment(
                    commentID: pending.comment.id,
                    expectedGeneration: expectedGeneration
                )
                guard auth.sessionGeneration == expectedGeneration else { return }
                actionBanner = message
                await model.load(
                    auth: auth,
                    forceRefresh: true,
                    expectedGeneration: expectedGeneration
                )
            } catch {
                guard auth.sessionGeneration == expectedGeneration else { return }
                actionBanner = CommentsModel.message(for: error)
            }
        }
    }

    private func copyLink(_ comment: AO3Comment) {
        guard let url = comment.threadURL else { return }
        #if os(iOS)
        UIPasteboard.general.url = url
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        #endif
        actionBanner = "Link copied."
    }

}

/// A trailing-icon label layout for the pagination "Next" button.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
}

// MARK: - Sheet presentation with expand-to-full-screen

/// Presents `CommentsView` as a pop-up card with an "expand" affordance that
/// promotes it to a `fullScreenCover` — for long threads or composing, where the
/// sheet feels cramped. Reused by every call site that shows Comments modally
/// (the actions menu, both readers, and the Library/Search context menus) so
/// the sheet→full-screen handoff is written once.
private struct CommentsSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let workID: Int
    let context: AO3CommentsWorkContext
    var initialChapterPosition: Int?
    var readerSections: [ReaderSection] = []
    var onOpenReaderChapter: ((Int) -> Void)?
    /// The reader keeps the page undimmed under this sheet. Every other caller
    /// leaves the system scrim, so a comments sheet over the library still dims.
    var undimmed = false

    @Environment(AppRouter.self) private var router
    @State private var pendingReaderDestination: CommentReaderDestination?
    @State private var readerDestination: CommentReaderDestination?

    #if !os(macOS)
    @State private var isFullScreen = false
    @State private var pendingExpand = false
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        // macOS has no fullScreenCover concept (sheets already resize to the
        // window); present as a plain sheet with no expand affordance.
        content.sheet(isPresented: $isPresented, onDismiss: {
            finishReaderOpenIfNeeded()
            // Real completion signal for an author byline/reply-quote tap queued by
            // the presented CommentsView — see `requestAuthorProfileAfterDismiss`.
            router.openPendingAuthorProfileAfterDismiss()
        }) {
            NavigationStack {
                CommentsView(
                    workID: workID, context: context, initialChapterPosition: initialChapterPosition,
                    isModal: true, readerSections: readerSections,
                    onOpenReaderChapter: requestReaderOpen
                )
            }
        }
        .navigationDestination(item: $readerDestination) { destination in
            BookReaderView(work: destination.work, initialSpineIndex: destination.spineIndex)
        }
        .onChange(of: isPresented) { _, presented in
            // Rising edge only: a route can only ever be queued on the way *out* of a
            // presentation, so clearing as one opens cannot race the drain above — it
            // just guarantees a route stranded by some future unhooked presenter can't
            // survive to push a profile the user never asked for.
            if presented { router.cancelPendingAuthorProfileAfterDismiss() }
        }
        #else
        content
            // The full-screen presentation only starts once the sheet has fully
            // dismissed (onDismiss) — flipping both bindings in the same pass
            // races the two presentations and can drop the fullScreenCover.
            .sheet(isPresented: $isPresented, onDismiss: {
                if pendingExpand {
                    pendingExpand = false
                    isFullScreen = true
                }
                finishReaderOpenIfNeeded()
                // Real completion signal for an author byline/reply-quote tap queued
                // by the presented CommentsView — see `requestAuthorProfileAfterDismiss`.
                // No-ops during an expand handoff (nothing queued in that flow).
                router.openPendingAuthorProfileAfterDismiss()
            }) {
                NavigationStack {
                    CommentsView(
                        workID: workID, context: context, initialChapterPosition: initialChapterPosition,
                        isModal: true,
                        onRequestExpand: {
                            pendingExpand = true
                            isPresented = false
                        },
                        readerSections: readerSections,
                        onOpenReaderChapter: requestReaderOpen
                    )
                }
                .presentationBackgroundInteraction(undimmed ? .enabled(upThrough: .large) : .automatic)
            }
            .fullScreenCover(isPresented: $isFullScreen, onDismiss: {
                finishReaderOpenIfNeeded()
                router.openPendingAuthorProfileAfterDismiss()
            }) {
                NavigationStack {
                    CommentsView(
                        workID: workID, context: context, initialChapterPosition: initialChapterPosition,
                        isModal: true, readerSections: readerSections,
                        onOpenReaderChapter: requestReaderOpen
                    )
                }
            }
            .navigationDestination(item: $readerDestination) { destination in
                BookReaderView(work: destination.work, initialSpineIndex: destination.spineIndex)
            }
            .onChange(of: isPresented) { _, presented in
                // Rising edge only: a route can only ever be queued on the way *out* of
                // a presentation, so clearing as one opens cannot race either drain
                // above — it just guarantees a route stranded by some future unhooked
                // presenter can't survive to push a profile the user never asked for.
                // (The expand handoff re-enters through this same sheet binding, and
                // queues nothing of its own, so it is unaffected.)
                if presented { router.cancelPendingAuthorProfileAfterDismiss() }
            }
        #endif
    }

    private func requestReaderOpen(_ work: SavedWork, _ spineIndex: Int) {
        pendingReaderDestination = CommentReaderDestination(work: work, spineIndex: spineIndex)
        #if os(macOS)
        isPresented = false
        #else
        if isFullScreen {
            isFullScreen = false
        } else {
            isPresented = false
        }
        #endif
    }

    private func finishReaderOpenIfNeeded() {
        guard let destination = pendingReaderDestination else { return }
        pendingReaderDestination = nil
        if let onOpenReaderChapter {
            onOpenReaderChapter(destination.spineIndex)
        } else {
            readerDestination = destination
        }
    }
}

extension View {
    /// Presents the native AO3 comments screen as an expandable pop-up card. See
    /// `CommentsSheetModifier`.
    func commentsSheet(
        isPresented: Binding<Bool>, workID: Int, context: AO3CommentsWorkContext,
        initialChapterPosition: Int? = nil,
        undimmed: Bool = false,
        readerSections: [ReaderSection] = [],
        onOpenReaderChapter: ((Int) -> Void)? = nil
    ) -> some View {
        modifier(CommentsSheetModifier(
            isPresented: isPresented, workID: workID, context: context,
            initialChapterPosition: initialChapterPosition,
            readerSections: readerSections,
            onOpenReaderChapter: onOpenReaderChapter,
            undimmed: undimmed
        ))
    }
}

// MARK: - Composer

/// Reply / top-level comment sheet with draft preservation and the defensive
/// submission flow (single POST, verify-on-ambiguity — `CommentSubmissionGuard`).
struct CommentComposerSheet: View {
    @Bindable var model: CommentsModel
    /// Whether the presenting `CommentsView` is itself modal — when true, opening
    /// the parent-quote author must dismiss that outer sheet too, or the profile
    /// push lands silently behind it.
    var isModal = false
    /// The outer `CommentsView`'s own dismiss action, captured by its caller
    /// before this sheet's `\.dismiss` environment value shadows it.
    var dismissCommentsView: DismissAction?

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var editorTextSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var identitySize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .footnote) private var quoteBodySize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .caption) private var quoteAuthorSize: CGFloat = 11
    @State private var draftSaveTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool
    /// The field's live selection, handed to `CommentMarkup` so a format button
    /// wraps what the reader highlighted instead of appending at the end.
    @State private var selection: TextSelection?
    @State private var showingFormattingTray = false
    @State private var detent: PresentationDetent = .medium

    private var isReply: Bool { model.composerParent != nil }
    private var isEdit: Bool { model.composerEditTarget != nil }

    /// AO3's comment field is 10,000 characters and rejects the whole POST past
    /// it, which is why the budget is a real gate here and not just a readout —
    /// a request that can only come back as an error is not worth spending.
    private static let characterLimit = 10_000

    /// Counted in code points, as AO3 counts: its `validates_length_of` measures
    /// Ruby's `String#length`. Counting `Character`s instead let a comment with a
    /// few family or flag emoji (one `Character`, several code points each) read
    /// "5 left" and then be refused by AO3 (1ba.2).
    static func remainingCharacters(for text: String) -> Int {
        characterLimit - text.unicodeScalars.count
    }

    /// Board 22's header ↗ button: medium goes to large, large returns to medium.
    static func toggledDetent(_ current: PresentationDetent) -> PresentationDetent {
        current == .large ? .medium : .large
    }

    /// 1ba: Cancel and Post sit in the sheet header. A reply uses that same
    /// Post — the board does not say "Post Reply". An edit stays Save.
    static func confirmationAction(isEdit: Bool, isReply: Bool) -> String {
        if isEdit { return "Save" }
        if isReply { return "Post" }
        return "Post"
    }

    private var remainingCharacters: Int {
        Self.remainingCharacters(for: model.composerText)
    }

    /// Spec 1ba's header title. "Reply to <name>" rather than a bare "Reply":
    /// the sheet is a medium detent over a thread, and which comment is being
    /// answered is the thing the reader most needs restated.
    private var composerTitle: String {
        if isEdit { return "Edit comment" }
        guard let parent = model.composerParent else { return "New comment" }
        return "Reply to \(parent.author)"
    }

    /// The same hue the list behind this sheet washes in — taken from the
    /// model's own work context so the rail on the quoted parent is the colour
    /// of the thread it came out of.
    private var palette: SubjectPalette {
        theme.appTheme.subjectPalette(
            hue: CoverArt.workHue(
                fandoms: model.workContext.fandoms,
                title: model.workContext.title
            )
        )
    }

    var body: some View {
        NavigationStack {
            // A plain VStack, not a ScrollView: the artboard's field takes every
            // point the sheet has left over, and a scroll view would let it
            // collapse to its content instead. What scrolls is the field.
            VStack(spacing: 0) {
                if let parent = model.composerParent {
                    parentQuote(parent)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }

                editor

                VStack(alignment: .leading, spacing: 8) {
                    if !isReply, !isEdit, model.scope == .byChapter {
                        // Honesty note: AO3's work-level comment form is the only
                        // one Kudos posts to; AO3 files it under the newest chapter.
                        Text("New comments post to the whole work. AO3 shows them on its latest chapter.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    statusBanner

                    identityRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .navigationTitle(composerTitle)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            // Pinned to the sheet's bottom edge and, because a bottom safe-area
            // inset rides the keyboard, directly above the keys — which is all
            // artboard 1be asks for beyond 1ba.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CommentFormatBar(text: $model.composerText, selection: $selection) {
                    showingFormattingTray = true
                }
            }
            #if DEBUG
            .task { if DebugLaunchRoute.takeSheet("formattingtray") { showingFormattingTray = true } }
            #endif
            .sheet(isPresented: $showingFormattingTray, onDismiss: {
                // Put the cursor back. Closing the tray onto a sheet with no
                // keyboard, after picking a tag that just moved the caret, is
                // otherwise a dead stop.
                editorFocused = true
            }) {
                CommentFormattingTray(text: $model.composerText, selection: $selection)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        model.saveDraft()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                    .disabled(model.submissionGuard.phase.isBusy)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { detent = Self.toggledDetent(detent) }
                    } label: {
                        Image(systemName: detent == .large
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(detent == .large ? "Collapse" : "Expand")
                }
                ToolbarItem(placement: .confirmationAction) {
                    postButton
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .onChange(of: model.composerText) { _, _ in
                // An edit away from a blocked submission's exact text must
                // stop showing that block as if it applied to what's on
                // screen now — cheap (in-memory dictionary lookup), so unlike
                // the draft save below this runs on every keystroke, not
                // debounced.
                model.syncSubmissionGuardToComposerText()
                // Preserve draft-as-you-type without synchronously rewriting the
                // UserDefaults dictionary on every keystroke.
                draftSaveTask?.cancel()
                draftSaveTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    model.saveDraft()
                }
            }
            .onDisappear {
                draftSaveTask?.cancel()
                model.saveDraft()
            }
            .onAppear {
                // Cursor ready on open — the field reads as editable immediately.
                editorFocused = true
            }
        }
        // Sheet surface, not `subjectScreenWash` (which applies the pushed-page chrome).
        // Applied under the presentation modifiers so those stay outermost.
        .appScreenSurface(.grouped)
        // Two numbers, not two layouts (spec 1be): `.medium` is the artboard's
        // 462pt of sheet, and the system re-lays it out at the shorter height on
        // its own once the keyboard is up. A literal `.height(462)` would be one
        // device's number pinned to every screen size.
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.submissionGuard.phase.isBusy)
            .screenTint(palette)
    }

    /// Filled accent capsule when enabled. Disabled, a pale tint with the theme's
    /// text colour on an undimmed style (as `FilterResultsBar`), so it reads in every theme.
    @ViewBuilder
    private var postButton: some View {
        let enabled = canPost
        let button = Button {
            Task { await model.submit(auth: auth) }
        } label: {
            if model.submissionGuard.phase.isBusy {
                ProgressView().accentFill()
            } else {
                // One line in the toolbar: the disabled capsule had broken "Post" into "Po / st".
                Text(Self.confirmationAction(isEdit: isEdit, isReply: isReply))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .disabled(!enabled)
        if enabled {
            button.buttonStyle(.kudosPrimary)
        } else {
            button
                .buttonStyle(UndimmedButtonStyle())
                .font(.headline)
                .foregroundStyle(theme.appTheme.textColor)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(theme.effectiveTint.opacity(0.15), in: Capsule())
        }
    }

    /// The field, taking every point the sheet has left between the quoted
    /// parent and the identity line. No card and no focus hairline, unlike the
    /// pre-redesign composer: the sheet *is* the field here, so a bordered box
    /// inside it was a second frame around the same thing.
    private var editor: some View {
        TextEditor(text: $model.composerText, selection: $selection)
            .font(.system(size: editorTextSize))
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                if model.composerText.isEmpty {
                    // Offset past `TextEditor`'s own internal text inset, so the
                    // placeholder sits exactly where the first character will.
                    Text(isReply ? "Write your reply…" : "Share your thoughts…")
                        .font(.system(size: editorTextSize))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 17)
                        .padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }
            .focused($editorFocused)
            .disabled(model.submissionGuard.phase.isBusy)
            .accessibilityLabel(isEdit ? "Edit comment text" : "Comment text")
    }

    /// Who this posts as, and how much of AO3's field is left (spec 1ba).
    private var identityRow: some View {
        let identity = Text(auth.username.map { "as \($0)" } ?? "Not signed in")
            .lineLimit(1)
            .truncationMode(.middle)
        let remaining = Text("\(remainingCharacters.formatted()) left")
            .foregroundStyle(remainingCharacters < 0 ? Color.red : Color.secondary)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Side by side the name was cut from the middle ("as AO…eader") at the
                // accessibility sizes: each on a line of its own.
                VStack(alignment: .leading, spacing: 2) {
                    identity
                    remaining
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    identity
                    Spacer(minLength: 0)
                    remaining
                }
            }
        }
        .font(.system(size: identitySize))
        .monospacedDigit()
        .foregroundStyle(Color.secondary)
        .accessibilityElement(children: .combine)
    }

    private var canPost: Bool {
        !model.submissionGuard.phase.isBusy
            && !model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && remainingCharacters >= 0
            && auth.isLoggedIn
    }

    /// The comment being answered, kept above the field — the reason 1ba is a
    /// medium detent rather than a full sheet.
    ///
    /// No avatar, unlike the pre-redesign quote: the artboard gives this block
    /// one accent line and three of body, and at the medium detent a 32pt avatar
    /// came out of the parent's own words. The name is still a button to the same
    /// profile route through the same `openParentAuthor`, so the destination
    /// keeps its way in — only the second tap target for it is gone.
    private func parentQuote(_ parent: AO3Comment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            replyContextLabel(for: parent)
            Text(parent.bodyText)
                .font(.system(size: quoteBodySize))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.appTheme.glassFill(0.06))
        .overlay(alignment: .leading) {
            // The rail, in the page's own accent — the same colour the thread
            // this reply hangs off is drawn in, so the quote reads as lifted out
            // of it rather than pasted in.
            Rectangle()
                .fill(palette.accent)
                .frame(width: 2)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
    }

    /// "{author} · {chapter}" in the app colour (the author is a link) — the parent's own byline. The
    /// "Replying to" half of it moved into the sheet title (spec 1ba), so
    /// repeating it here would say the same thing twice in 40 points of sheet.
    @ViewBuilder
    private func replyContextLabel(for parent: AO3Comment) -> some View {
        let chapterSuffix: String = {
            if let chapter = parent.chapterLabel, !chapter.isEmpty {
                return " · \(chapter)"
            }
            return ""
        }()
        if let route = parent.profileRoute {
            HStack(spacing: 0) {
                Button {
                    openParentAuthor(route)
                } label: {
                    Text(parent.author)
                        .font(.system(size: quoteAuthorSize, weight: .semibold))
                        .foregroundStyle(theme.accentInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(parent.author)'s profile")
                if !chapterSuffix.isEmpty {
                    Text(chapterSuffix)
                        .font(.system(size: quoteAuthorSize, weight: .semibold))
                        .foregroundStyle(theme.accentInk)
                }
            }
        } else {
            Text(parent.author + chapterSuffix)
                .font(.system(size: quoteAuthorSize, weight: .semibold))
                .foregroundStyle(theme.accentInk)
        }
    }

    private func openParentAuthor(_ route: AO3AuthorRoute) {
        // Queue the push, then dismiss the composer — and, when Comments itself is
        // presented modally, the whole modal chain — before it fires. Pushing before
        // the sheets finish tearing down would leave the profile pushed onto the tab
        // stack silently behind a still-open Comments sheet; the actual completion
        // signal is whichever presenter's `onDismiss` fires last (the outer
        // `CommentsSheetModifier` when modal, this sheet's own `onDismiss` otherwise
        // — see their `openPendingAuthorProfileAfterDismiss()` calls), not a guessed
        // duration (same scar tissue as nested login sheets).
        //
        // Queuing doubles as the re-entrancy guard (first tap wins) — see `openAuthor`.
        guard router.requestAuthorProfileAfterDismiss(route) else { return }
        dismiss()
        dismissCommentsView?()
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch model.submissionGuard.phase {
        case .verifying:
            Label("We're checking whether this posted before trying again…",
                  systemImage: "clock.arrow.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .ambiguous(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                // Re-posting stays blocked until a check definitively answers —
                // this re-runs the verification fetch, never the POST.
                Button {
                    Task { await model.reverify(auth: auth) }
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.kudosSecondary)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
        case .succeeded:
            Label("Posted.", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.green)
        case .idle, .submitting:
            EmptyView()
        }
    }
}

// MARK: - Skeleton

/// Wireframe for a loading root comment, in 1f's shape: an avatar column and
/// a content column on the page, no card — so the list does not change
/// vocabulary the moment the real rows arrive.
struct CommentSkeletonRow: View {
    var body: some View {
        let avatar = CommentThreadGeometry.avatarSize(forDepth: 0)
        HStack(alignment: .top, spacing: 11) {
            SkeletonBlock(height: avatar, width: avatar, cornerRadius: avatar / 2)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SkeletonBlock(height: 12, width: 110)
                    Spacer()
                    SkeletonBlock(height: 10, width: 60)
                }
                SkeletonTextLine()
                SkeletonTextLine()
                SkeletonTextLine(width: 140)
            }
        }
        .padding(.bottom, CommentThreadGeometry.conversationGap)
        .skeletonShimmer()
        .accessibilityHidden(true)
    }
}
