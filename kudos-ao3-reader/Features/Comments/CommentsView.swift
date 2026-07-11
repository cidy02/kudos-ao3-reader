import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Native AO3 comments for a work: all comments or per-chapter, threaded, with
/// reply/compose and the per-comment actions AO3 actually exposes. Pushed from
/// Work Detail and presented as a sheet from the reader's actions menu.
struct CommentsView: View {
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

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var model: CommentsModel
    @State private var showingChapterPicker = false
    @State private var showingLogin = false
    @State private var pendingDelete: AO3Comment?
    @State private var actionBanner: String?
    @State private var contextLoadTask: Task<Void, Never>?
    /// The comment "Thread"/"Parent Thread" most recently scrolled to, briefly
    /// tinted so the jump is visible even when the target was already on-screen.
    @State private var highlightedCommentID: Int?
    @State private var highlightClearTask: Task<Void, Never>?
    /// Roots forced open by a "Thread"/"Parent Thread" jump, so a collapsed reply
    /// stack can't hide the comment being scrolled to.
    @State private var forceExpandedRootIDs: Set<Int> = []
    @State private var focusScrollTask: Task<Void, Never>?

    init(
        workID: Int, context: AO3CommentsWorkContext, initialChapterPosition: Int? = nil,
        isModal: Bool = false, onRequestExpand: (() -> Void)? = nil
    ) {
        self.workID = workID
        self.workContext = context
        self.isModal = isModal
        self.onRequestExpand = onRequestExpand
        _model = State(initialValue: CommentsModel(
            workID: workID, workAuthors: context.authors, initialChapterPosition: initialChapterPosition
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                infoSection
                scopeSection
                chapterSection
                sortSection
                contentSections(scrollProxy: proxy)
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
            .navigationTitle("Comments")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .hidesFloatingTabBar()
            .safeAreaInset(edge: .bottom) { writeCommentBar }
            .refreshable { await model.load(auth: auth, forceRefresh: true) }
            .task { await model.loadInitial(auth: auth) }
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
                contextLoadTask = Task { await model.load(auth: auth) }
            }
            .onDisappear {
                contextLoadTask?.cancel()
                highlightClearTask?.cancel()
                focusScrollTask?.cancel()
            }
            .sheet(isPresented: composerBinding) {
                CommentComposerSheet(model: model)
            }
            .sheet(isPresented: $showingChapterPicker) {
                chapterPicker
            }
            .sheet(isPresented: $showingLogin) {
                AO3LoginView()
            }
            .alert("Delete this comment?", isPresented: deleteBinding, presenting: pendingDelete) { comment in
                Button("Delete", role: .destructive) { delete(comment) }
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

    /// Scrolls to and briefly highlights `commentID` within the currently-loaded
    /// list ("Thread"/"Parent Thread" — the native equivalent of AO3's own
    /// isolated-thread page, no extra request since the target is always already
    /// on this same fetched page). Nested replies live inside the root List row,
    /// so we first scroll to the owning root (materializes the tall cell) and
    /// then to the nested `.id`.
    private func focusThread(_ commentID: Int, proxy: ScrollViewProxy) {
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
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(commentID, anchor: .center)
            }
            return
        }

        // The target is a nested reply inside `rootID`'s row. Expand that root if
        // it's collapsed (its nested `.id` wouldn't exist in the view tree at all)
        // and scroll the row in first. `scrollTo` silently no-ops on an id that
        // isn't laid out yet, so the nested id needs a layout pass before we can
        // address it — hence the yield rather than a second call in this same pass.
        forceExpandedRootIDs.insert(rootID)
        proxy.scrollTo(rootID, anchor: .center)
        focusScrollTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(commentID, anchor: .center)
            }
        }
    }

    private func threadHandlers(scrollProxy: ScrollViewProxy) -> CommentThreadHandlers {
        CommentThreadHandlers(
            onReply: { model.startComposer(replyingTo: $0) },
            onEdit: { model.startEditing($0) },
            onDelete: { pendingDelete = $0 },
            onCopyLink: { copyLink($0) },
            onFocusThread: { focusThread($0, proxy: scrollProxy) },
            onRequestLogin: { showingLogin = true },
            onOpenAuthor: openAuthor
        )
    }

    // MARK: Info card

    /// Reuses Work Detail's own overview-card pattern (title/author/fandom/stats
    /// row via `WorkStatLabel`) rather than inventing a second one. No cover
    /// thumbnail — most AO3 works don't have one, and Work Detail's card omits
    /// it too. Comment count joins rating/chapters once the page has loaded.
    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(workContext.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !workContext.authors.isEmpty {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "person")
                            .foregroundStyle(.secondary)
                        AO3AuthorBylineView(
                            names: workContext.authors,
                            identities: workContext.authorIdentities,
                            includesBy: false,
                            font: .subheadline,
                            onOpenRoute: openAuthor
                        )
                    }
                }

                if !workContext.fandoms.isEmpty {
                    Label(workContext.fandoms.joined(separator: ", "), systemImage: "books.vertical")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                FlowLayout(spacing: 10, rowSpacing: 6) {
                    if !workContext.rating.isEmpty {
                        WorkStatLabel(text: workContext.rating, symbol: "checkmark.shield")
                    }
                    if !workContext.chapters.isEmpty {
                        WorkStatLabel(text: workContext.chapters, symbol: "book")
                    }
                    if let total = model.page?.totalComments {
                        WorkStatLabel(text: total.formatted(), symbol: "bubble.left")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .cardRow()
    }

    // MARK: Scope

    /// All/By Chapter. Its own card, separate from the info card above and the
    /// chapter selector below, matching the mockup's distinct control cards.
    private var scopeSection: some View {
        Section {
            // The native segmented style — matches Reader Settings' own
            // Scrolled/Paged control exactly, rather than a bespoke capsule.
            Picker("Scope", selection: $model.scope) {
                ForEach(CommentsModel.Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Comment scope")
        }
        .cardRow()
    }

    // MARK: Sort

    /// Local-only order menu (AO3 has no server sort). A quiet utility row, not
    /// a card — it floats directly on the backdrop, right above the comments it
    /// orders, rather than sharing a card with Scope (which answers a different
    /// question: "which comments am I viewing").
    private var sortSection: some View {
        Section {
            HStack(spacing: 4) {
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
                    HStack(spacing: 3) {
                        Text(model.newestFirst ? "Newest First" : "Oldest First")
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .accessibilityLabel("Sort comments")
                .accessibilityValue(model.newestFirst ? "Newest First" : "Oldest First")
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .tint(.secondary)
        }
        // Aligned with card CONTENT (not card edges) — the same inset `.cardRow()`
        // gives the text inside the cards above/below — so this reads as part of
        // the same column rather than a stray indent.
        .listRowInsets(EdgeInsets(
            top: 2,
            leading: CardListMetrics.sideMargin + CardListMetrics.innerHorizontal,
            bottom: 10,
            trailing: CardListMetrics.sideMargin + CardListMetrics.innerHorizontal
        ))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: Chapter selector

    /// Its own card, not glued onto the info card — matches the mockup, and
    /// reads more clearly as "which comments am I viewing" rather than as
    /// metadata about the work.
    @ViewBuilder
    private var chapterSection: some View {
        if model.scope == .byChapter {
            Section {
                Button {
                    showingChapterPicker = true
                } label: {
                    HStack {
                        Label(model.selectedChapter?.displayName ?? "Choose a chapter",
                              systemImage: "book")
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Browse comments by chapter")
                .accessibilityValue(model.selectedChapter?.displayName ?? "No chapter selected")
            }
            .cardRow()
        }
    }

    // MARK: Content

    @ViewBuilder
    private func contentSections(scrollProxy: ScrollViewProxy) -> some View {
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
                    Button("Try Again") { Task { await model.load(auth: auth, forceRefresh: true) } }
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
                ForEach(model.displayThreads) { comment in
                    CommentThreadRow(
                        comment: comment,
                        workAuthors: workContext.authors,
                        showChapterBadge: model.scope == .all,
                        startsExpanded: forceExpandedRootIDs.contains(comment.id)
                    )
                    .id(comment.id)
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
        if isModal { dismiss() }
        router.openAuthorProfile(route)
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
            // Floats over the page backdrop — no opaque slab. The safe-area inset
            // (plus the list's trailing spacer) keeps content from ever sitting
            // underneath it; the soft shadow does the lifting. Shown whether or
            // not the user is signed in: logged out, it opens the AO3 login sheet
            // instead of composing — it must never be a dead end.
            Button {
                if auth.isLoggedIn {
                    model.startComposer()
                } else {
                    showingLogin = true
                }
            } label: {
                Label(
                    auth.isLoggedIn ? "Write a comment" : "Log in to comment",
                    systemImage: auth.isLoggedIn ? "pencil" : "person.crop.circle.badge.questionmark"
                )
                .font(.headline)
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(model.isOffline)
            // Match the theme's card-shadow language: Dark/OLED are shadow-free
            // (the red capsule already pops there, and a shadow can't read against
            // a near-black or true-black backdrop anyway); Light/Sepia get the
            // soft lift.
            .shadow(
                color: theme.appTheme == .dark || theme.appTheme == .oled
                    ? .clear : .black.opacity(0.2),
                radius: 10, y: 3
            )
            // The pill hugs its own label instead of stretching edge to edge —
            // full-width left the capsule's rounded ends reading as dead space
            // around a short, centered label. Centering happens here, on the
            // frame around the (compact) button, not inside the label.
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .accessibilityLabel(auth.isLoggedIn ? "Write a comment" : "Log in to comment")
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
                            model.selectedChapter = chapter
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
            .overlay {
                if model.chapters.isEmpty {
                    if model.chaptersFailed {
                        ContentUnavailableView(
                            "Couldn't Load Chapters",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Check your connection and try again.")
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

    private func delete(_ comment: AO3Comment) {
        Task {
            do {
                actionBanner = try await auth.deleteComment(commentID: comment.id)
                await model.load(auth: auth, forceRefresh: true)
            } catch {
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

    #if !os(macOS)
    @State private var isFullScreen = false
    @State private var pendingExpand = false
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        // macOS has no fullScreenCover concept (sheets already resize to the
        // window); present as a plain sheet with no expand affordance.
        content.sheet(isPresented: $isPresented) {
            NavigationStack {
                CommentsView(
                    workID: workID, context: context, initialChapterPosition: initialChapterPosition,
                    isModal: true
                )
            }
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
            .fullScreenCover(isPresented: $isFullScreen) {
                NavigationStack {
                    CommentsView(
                        workID: workID, context: context, initialChapterPosition: initialChapterPosition,
                        isModal: true
                    )
                }
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

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var draftSaveTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool

    private var isReply: Bool { model.composerParent != nil }
    private var isEdit: Bool { model.composerEditTarget != nil }

    private var composerTitle: String {
        if isEdit { return "Edit Comment" }
        return isReply ? "Reply" : "New Comment"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let parent = model.composerParent {
                        parentQuote(parent)
                    }
                    // An unmistakably-editable field: card surface (not a murky
                    // gray slab), a hairline that brightens with focus, a legible
                    // placeholder, and the cursor ready on open.
                    TextEditor(text: $model.composerText)
                        .frame(minHeight: 180, maxHeight: 260)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            theme.appTheme.cardSurface,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    editorFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.12),
                                    lineWidth: editorFocused ? 1.5 : 1
                                )
                        }
                        .overlay(alignment: .topLeading) {
                            if model.composerText.isEmpty {
                                Text(isReply ? "Write your reply…" : "Share your thoughts…")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                        .focused($editorFocused)
                        .disabled(model.submissionGuard.phase.isBusy)
                        .accessibilityLabel(isEdit ? "Edit comment text" : "Comment text")

                    if !isReply, !isEdit, model.scope == .byChapter {
                        // Honesty note: AO3's work-level comment form is the only
                        // one Kudos posts to; AO3 files it under the newest chapter.
                        Text("New comments post to the whole work — AO3 shows them on its latest chapter.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    statusBanner
                }
                .padding(16)
            }
            .appThemedScroll()
            .navigationTitle(composerTitle)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.submissionGuard.phase.isBusy)
    }

    private var canPost: Bool {
        !model.submissionGuard.phase.isBusy
            && !model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && auth.isLoggedIn
    }

    private func parentQuote(_ parent: AO3Comment) -> some View {
        HStack(alignment: .top, spacing: 9) {
            CommentAvatar(comment: parent, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(replyContext(for: parent))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(parent.bodyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func replyContext(for parent: AO3Comment) -> String {
        if let chapter = parent.chapterLabel, !chapter.isEmpty {
            return "Replying to \(parent.author) · \(chapter)"
        }
        return "Replying to \(parent.author)"
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
