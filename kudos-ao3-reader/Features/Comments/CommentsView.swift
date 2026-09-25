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
    /// Inbox can retain canonical work metadata learned by this navigation, so
    /// returning to the feed corrects sibling badges and summary cards together.
    var onResolveWorkContext: ((AO3CommentsWorkContext) -> Void)?

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: CommentsModel
    @State private var showingChapterPicker = false
    @State private var showingLogin = false
    @State private var pendingDelete: PendingDelete?
    @State private var actionBanner: String?
    @State private var contextLoadTask: Task<Void, Never>?
    /// The comment "Thread"/"Parent Thread" most recently scrolled to, briefly
    /// tinted so the jump is visible even when the target was already on-screen.
    @State private var highlightedCommentID: Int?
    @State private var highlightClearTask: Task<Void, Never>?
    /// Roots forced open by a "Thread"/"Parent Thread" jump, so a collapsed reply
    /// stack can't hide the comment being scrolled to.
    @State private var focusScrollTask: Task<Void, Never>?
    @State private var didApplyInitialFocus = false
    @State private var commentsWidth: CGFloat = 390
    /// The thread being pushed, if any. AO3 gives Thread / Parent Thread their own
    /// isolated-thread pages, so these navigate rather than scrolling in place.
    @State private var pushedThread: CommentThreadRoute?

    init(
        workID: Int, context: AO3CommentsWorkContext, initialChapterPosition: Int? = nil,
        initialCommentID: Int? = nil, initialFocusesChapter: Bool = false,
        initialComposes: Bool = false,
        initialReplyCommentID: Int? = nil,
        requiredSessionGeneration: Int? = nil,
        isModal: Bool = false, onRequestExpand: (() -> Void)? = nil,
        onResolveWorkContext: ((AO3CommentsWorkContext) -> Void)? = nil
    ) {
        self.workID = workID
        self.workContext = context
        self.isModal = isModal
        self.onRequestExpand = onRequestExpand
        self.onResolveWorkContext = onResolveWorkContext
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
        if model.belongsToCurrentSession(auth: auth) {
            commentsBody
        } else {
            ProgressView()
                .task { dismiss() }
        }
    }

    private var commentsBody: some View {
        // Walked once here and handed down, rather than recomputed by the strip
        // and again by the section header: this whole body re-evaluates on every
        // swipe, which is the cost `conversationRows` exists to keep down.
        let figures = loadedFigures
        return ScrollViewReader { proxy in
            List {
                Section {
                    header.pageBodyRow(top: 18, gutter: 0)
                    if model.page != nil {
                        SubjectStatStrip(cells: signalCells(figures), palette: palette)
                            .pageBodyRow(top: 14, gutter: gutter)
                        if let note = signalScopeNote {
                            Text(note)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.secondary.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                                .pageBodyRow(top: 8, gutter: gutter + 4)
                        }
                    }
                    filterRail.pageBodyRow(top: 16, gutter: gutter)
                }
                contentSections(scrollProxy: proxy, figures: figures)
                if case .loaded = model.phase {
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
            // Rows need the container width to size their indent, but indent
            // feeds `listRowInsets` — which is resolved before a row lays out,
            // so a row can't measure itself in time. Measure once here.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { commentsWidth = $0 }
            .environment(\.commentsContentWidth, commentsWidth)
            // The screen states its own name in `header` now (spec 1f), so the bar
            // is emptied rather than titled. macOS has no such bar to empty — its
            // window still needs a title — hence the one platform fork.
            #if os(macOS)
            .navigationTitle("Comments")
            #endif
            .subjectScreenWash(palette: palette, washHeight: 480)
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
            // `subjectScreenWash` already hides the floating tab bar.
            .safeAreaInset(edge: .bottom) { writeCommentBar }
            .refreshable { await model.load(auth: auth, forceRefresh: true) }
            .task {
                await model.loadInitial(auth: auth)
                reportResolvedWorkContext()
                await applyInitialFocusIfNeeded(proxy: proxy)
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
                Text("This removes the comment on AO3. It can't be undone.")
            }
            .alert("AO3", isPresented: bannerBinding) {
                Button("OK") { actionBanner = nil }
            } message: {
                Text(actionBanner ?? "")
            }
            .toolbar {
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
            onRequestLogin: { showingLogin = true },
            onOpenAuthor: openAuthor
        )
    }

    // MARK: Header

    /// Spec 1f's page header: the chapter as kicker, the work at 32pt, the
    /// byline underneath. It replaces the Work-Detail-style overview card that
    /// used to open this screen — the rating/chapters figures it carried belong
    /// to the work's own page, and the artboard spends that space on figures
    /// about the *comments* instead (see `signalCells`).
    ///
    /// The byline goes through the trailing slot rather than the plain-string
    /// `subtitle`, for the same reason `WorkDetailIdentityHeader` does: it has to
    /// stay a real `AO3AuthorBylineView` so every co-author is still tappable
    /// through to their profile, and — because this screen can be modal — so the
    /// tap still routes through `openAuthor`'s dismiss-then-push queue.
    private var header: some View {
        SubjectHeaderBlock(
            kicker: headerKicker,
            title: model.workContext.title,
            palette: palette,
            gutter: gutter,
            hasTrailing: hasByline
        ) {
            AO3AuthorBylineView(
                names: model.workAuthors,
                identities: model.workAuthorIdentities,
                includesBy: false,
                font: .system(size: 15.5),
                expandsHitTarget: false,
                onOpenRoute: openAuthor
            )
        }
    }

    private var hasByline: Bool {
        !model.workAuthors.isEmpty || !model.workAuthorIdentities.isEmpty
    }

    /// What this screen is scoped to: the chapter when the reader has picked
    /// one, and the screen's own name when they are looking at the whole work.
    private var headerKicker: String {
        if model.scope == .byChapter, let chapter = model.selectedChapter {
            return "Chapter \(chapter.position)"
        }
        return "Comments"
    }

    // MARK: Signal strip

    /// The three figures the strip counts rather than reads off AO3.
    private struct LoadedFigures {
        var threads = 0
        var comments = 0
        var mine = 0
        var latest: Date?
    }

    /// One walk over the loaded page for all three.
    ///
    /// Deliberately a single pass: this is evaluated from `commentsBody`, which
    /// re-runs whenever the list does, and three separate `flattened` walks of
    /// the same tree is the kind of cost `conversationRows` was introduced to
    /// avoid. Bounded by one AO3 page of comments, not by the work.
    private var loadedFigures: LoadedFigures {
        var figures = LoadedFigures()
        for root in model.displayThreads {
            figures.threads += 1
            for comment in root.flattened {
                figures.comments += 1
                // AO3 renders an Edit action only on the signed-in account's own
                // comments, which is the same per-session signal
                // `FlattenedReply.parentIsViewer` takes — and unlike matching
                // the byline against `auth.username` it still holds for a comment
                // left under a non-default pseud.
                if comment.editPath != nil { figures.mine += 1 }
                if let posted = comment.postedAt, posted > (figures.latest ?? .distantPast) {
                    figures.latest = posted
                }
            }
        }
        return figures
    }

    /// Artboard 1f's COMMENTS / THREADS / YOURS / LATEST strip, minus any cell
    /// this screen cannot source.
    ///
    /// Only COMMENTS is AO3's own: `AO3CommentsPage.totalComments` is the
    /// work-level figure parsed off the page's stats line. AO3 publishes no
    /// thread count, no per-viewer count and no "last comment at", so the other
    /// three are counted from the page in front of the reader. `signalScopeNote`
    /// says so out loud whenever that is less than the whole work — a figure
    /// that looks authoritative and is not is the one failure this screen must
    /// not ship.
    private func signalCells(_ figures: LoadedFigures) -> [SubjectStatStrip.Cell] {
        var cells: [SubjectStatStrip.Cell] = []

        if let total = model.page?.totalComments {
            cells.append(SubjectStatStrip.Cell(
                value: total.formatted(),
                label: "Comments",
                accessibilityText: "\(total.formatted()) comments on AO3"
            ))
        }

        cells.append(SubjectStatStrip.Cell(
            value: figures.threads.formatted(),
            label: "Threads",
            accessibilityText: "\(figures.threads.formatted()) conversations loaded"
        ))

        // Dropped rather than printed as a permanent zero when signed out: AO3
        // emits no ownership signal at all for an anonymous reader, so the cell
        // could only ever say "none" and would be reporting the session, not the
        // comments.
        if auth.isLoggedIn {
            cells.append(SubjectStatStrip.Cell(
                value: figures.mine.formatted(),
                label: "Yours",
                isHighlighted: figures.mine > 0,
                accessibilityText: "\(figures.mine.formatted()) of the loaded comments are yours"
            ))
        }

        if let latest = figures.latest {
            cells.append(SubjectStatStrip.Cell(
                value: latest.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)),
                label: "Latest",
                accessibilityText: "Newest loaded comment "
                    + latest.formatted(.relative(presentation: .named))
            ))
        }

        return cells
    }

    /// Printed under the strip whenever the loaded page is not the whole work.
    private var signalScopeNote: String? {
        guard let page = model.page, page.totalPages > 1 else { return nil }
        return "Threads, yours and latest count this page. AO3 pages its comments, "
            + "and only the comment total is the whole work’s."
    }

    // MARK: Chapter + sort

    /// The artboard's two dropdown pills, under the signal strip.
    ///
    /// The All / By Chapter segmented picker is gone: it asked the same question
    /// the chapter control answers, and the sheet this pill opens already lists
    /// "All Comments" above the chapters. One control, both behaviours, and the
    /// pill itself states which one is in force.
    private var filterRail: some View {
        HStack(spacing: 7) {
            Button {
                showingChapterPicker = true
            } label: {
                SubjectChip(
                    text: chapterPillTitle,
                    style: .pill(isSelected: model.scope == .byChapter),
                    systemImage: "book",
                    trailingImage: "chevron.down",
                    palette: palette
                )
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .accessibilityLabel("Browse comments by chapter")
            .accessibilityValue(chapterPillTitle)

            sortPill

            Spacer(minLength: 0)
        }
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
                trailingImage: "chevron.down",
                palette: palette
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
                ForEach(0..<4, id: \.self) { _ in CommentSkeletonRow() }
            }
            .cardRow()
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
                        .buttonStyle(.borderedProminent)
                }
            }
            .cardRow()
        case .loaded:
            if model.isFromCache && model.isOffline {
                staleBanner
            }
            if model.displayThreads.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Comments Yet",
                        systemImage: "bubble.left",
                        description: Text("Be the first to leave one.")
                    )
                }
                .cardRow()
            } else {
                Section {
                    // The count is what is actually under the rule — every loaded
                    // comment, replies included — not the work's total, which the
                    // strip above already prints from AO3's own figure. Omitted
                    // entirely when there is nothing to head.
                    SectionRuleHeader(title: "Comments", count: figures.comments)
                        .pageBodyRow(top: 18, gutter: 0)
                }
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

    private var staleBanner: some View {
        Section {
            Label {
                let fetched = model.page?.fetchedAt
                    .formatted(.relative(presentation: .named)) ?? "earlier"
                Text("You're offline — showing comments from \(fetched). They may be out of date.")
            } icon: {
                Image(systemName: "wifi.exclamationmark")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .cardRow()
    }

    private func paginationSection(_ page: AO3CommentsPage) -> some View {
        Section {
            HStack {
                Button {
                    loadPage(model.currentPageNumber - 1)
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(model.currentPageNumber <= 1)
                // Matches the 44pt min-frame this file's other controls
                // reserve (HIG audit UI-3).
                .minimumHitTarget()

                Spacer()
                Text("Page \(model.currentPageNumber) of \(page.totalPages)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()

                Button {
                    loadPage(model.currentPageNumber + 1)
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.trailingIcon)
                }
                .disabled(model.currentPageNumber >= page.totalPages)
                .minimumHitTarget()
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
            // Spec 1f's centred 44pt pill, in the page's own accent rather than the
            // app tint — this is the one filled control on a washed screen, which
            // is exactly what `solidButton*` names. Still floating over the page
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
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(palette.solidButtonLabel)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Capsule().fill(palette.accent))
            }
            .buttonStyle(.plain)
            .disabled(model.isOffline)
            // `.plain` draws no disabled state of its own, unlike the
            // `.borderedProminent` this replaced — so the offline dimming is drawn
            // here rather than quietly lost with the button style.
            .opacity(model.isOffline ? 0.45 : 1)
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
    }

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
                                    .foregroundStyle(model.scope == .all ? Color.accentColor : .secondary)
                            }
                            if model.scope == .all {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .foregroundStyle(model.scope == .all ? Color.accentColor : .primary)
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
                                    .lineLimit(1)
                                Spacer()
                                if chapter == model.selectedChapter, model.scope == .byChapter {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .foregroundStyle(
                                chapter == model.selectedChapter && model.scope == .byChapter
                                    ? Color.accentColor : .primary
                            )
                        }
                    }
                } footer: {
                    // Quiet help text, not a warning panel: explains why there are
                    // no per-chapter counts without shouting about it.
                    Text("AO3 doesn't publish per-chapter totals, so Kudos doesn't fetch every chapter just to count them.")
                }
            }
            .appThemedScroll()
            .appThemedRows()
            // The chapter index used to be fetched only as a side effect of
            // switching scope to By Chapter. The pill that opens this sheet can
            // now be tapped while the scope is still All, so the sheet asks for
            // the index itself — `loadChaptersIfNeeded` is idempotent and returns
            // immediately once it holds one.
            .task { await model.loadChaptersIfNeeded(auth: auth) }
            .overlay {
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
                    } else {
                        ProgressView()
                    }
                }
            }
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

    @Environment(AppRouter.self) private var router

    #if !os(macOS)
    @State private var isFullScreen = false
    @State private var pendingExpand = false
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        // macOS has no fullScreenCover concept (sheets already resize to the
        // window); present as a plain sheet with no expand affordance.
        content.sheet(isPresented: $isPresented, onDismiss: {
            // Real completion signal for an author byline/reply-quote tap queued by
            // the presented CommentsView — see `requestAuthorProfileAfterDismiss`.
            router.openPendingAuthorProfileAfterDismiss()
        }) {
            NavigationStack {
                CommentsView(
                    workID: workID, context: context, initialChapterPosition: initialChapterPosition,
                    isModal: true
                )
            }
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
                        }
                    )
                }
            }
            .fullScreenCover(isPresented: $isFullScreen, onDismiss: {
                router.openPendingAuthorProfileAfterDismiss()
            }) {
                NavigationStack {
                    CommentsView(
                        workID: workID, context: context, initialChapterPosition: initialChapterPosition,
                        isModal: true
                    )
                }
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
}

extension View {
    /// Presents the native AO3 comments screen as an expandable pop-up card. See
    /// `CommentsSheetModifier`.
    func commentsSheet(
        isPresented: Binding<Bool>, workID: Int, context: AO3CommentsWorkContext,
        initialChapterPosition: Int? = nil
    ) -> some View {
        modifier(CommentsSheetModifier(
            isPresented: isPresented, workID: workID, context: context,
            initialChapterPosition: initialChapterPosition
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
    @State private var draftSaveTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool
    /// The field's live selection, handed to `CommentMarkup` so a format button
    /// wraps what the reader highlighted instead of appending at the end.
    @State private var selection: TextSelection?
    @State private var showingFormattingTray = false

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
                        Text("New comments post to the whole work — AO3 shows them on its latest chapter.")
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
                    Button("Cancel") {
                        model.saveDraft()
                        dismiss()
                    }
                    .disabled(model.submissionGuard.phase.isBusy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await model.submit(auth: auth) }
                    } label: {
                        if model.submissionGuard.phase.isBusy {
                            ProgressView()
                        } else {
                            Text(isEdit ? "Save" : (isReply ? "Post Reply" : "Post"))
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canPost)
                }
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
        // `subjectWash`, not `subjectScreenWash`: the latter also empties the
        // navigation bar, which is where Cancel and Post live on this sheet.
        // Applied under the presentation modifiers so those stay outermost.
        .subjectWash(palette, height: 320)
        // Two numbers, not two layouts (spec 1be): `.medium` is the artboard's
        // 462pt of sheet, and the system re-lays it out at the shorter height on
        // its own once the keyboard is up. A literal `.height(462)` would be one
        // device's number pinned to every screen size.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.submissionGuard.phase.isBusy)
    }

    /// The field, taking every point the sheet has left between the quoted
    /// parent and the identity line. No card and no focus hairline, unlike the
    /// pre-redesign composer: the sheet *is* the field here, so a bordered box
    /// inside it was a second frame around the same thing.
    private var editor: some View {
        TextEditor(text: $model.composerText, selection: $selection)
            .font(.system(size: 15))
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
                        .font(.system(size: 15))
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
        HStack(spacing: 10) {
            Text(auth.username.map { "as \($0)" } ?? "Not signed in")
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Text("\(remainingCharacters.formatted()) left")
                .foregroundStyle(remainingCharacters < 0 ? Color.red : Color.secondary)
        }
        .font(.system(size: 11.5))
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
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.appTheme.glassFill(0.09))
        .overlay(alignment: .leading) {
            // The rail, in the page's own accent — the same colour the thread
            // this reply hangs off is drawn in, so the quote reads as lifted out
            // of it rather than pasted in.
            Rectangle()
                .fill(palette.accent)
                .frame(width: 2)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    /// "{author} · {chapter}" in the page accent — the parent's own byline. The
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(parent.author)'s profile")
                if !chapterSuffix.isEmpty {
                    Text(chapterSuffix)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text(parent.author + chapterSuffix)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
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
                .buttonStyle(.bordered)
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

/// Wireframe for a loading comment card.
struct CommentSkeletonRow: View {
    var body: some View {
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
        .padding(.vertical, 4)
        .skeletonShimmer()
        .accessibilityHidden(true)
    }
}
