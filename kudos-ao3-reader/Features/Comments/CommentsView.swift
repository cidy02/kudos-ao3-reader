import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Native AO3 comments for a work: all comments or per-chapter, threaded, with
/// reply/compose and the per-comment actions AO3 actually exposes. Pushed from
/// Work Detail and presented as a sheet from the reader's actions menu.
struct CommentsView: View {
    let workID: Int
    let workTitle: String
    /// Author names, for the byline badge on their own comments.
    var workAuthors: [String] = []

    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme

    @State private var model: CommentsModel
    @State private var showingChapterPicker = false
    @State private var pendingDelete: AO3Comment?
    @State private var actionBanner: String?
    @State private var contextLoadTask: Task<Void, Never>?

    init(workID: Int, workTitle: String, workAuthors: [String] = [], initialChapterPosition: Int? = nil) {
        self.workID = workID
        self.workTitle = workTitle
        self.workAuthors = workAuthors
        _model = State(initialValue: CommentsModel(
            workID: workID, workAuthors: workAuthors, initialChapterPosition: initialChapterPosition
        ))
    }

    var body: some View {
        List {
            controlsSection
            contentSections
            if case .loaded = model.phase, auth.isLoggedIn {
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
            // loadInitial sets scope/chapter itself and does the one load; skip the
            // redundant reload its programmatic changes would otherwise trigger.
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
        .onDisappear { contextLoadTask?.cancel() }
        .sheet(isPresented: composerBinding) {
            CommentComposerSheet(model: model)
        }
        .sheet(isPresented: $showingChapterPicker) {
            chapterPicker
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
    }

    // MARK: Controls

    private var controlsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(workTitle)
                    .font(.headline)
                    .lineLimit(2)

                scopePicker

                if model.scope == .byChapter {
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
                    .frame(minHeight: 44)
                    .accessibilityLabel("Browse comments by chapter")
                    .accessibilityValue(model.selectedChapter?.displayName ?? "No chapter selected")
                }

                HStack {
                    if let total = model.page?.totalComments {
                        Label("\(total.formatted()) comments", systemImage: "bubble.left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Comments")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Local rendering order — AO3 has no server-side comment sort.
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
                        HStack(spacing: 4) {
                            Text(model.newestFirst ? "Newest First" : "Oldest First")
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                    }
                    .accessibilityLabel("Sort comments")
                    .accessibilityValue(model.newestFirst ? "Newest First" : "Oldest First")
                }
            }
        }
        .cardRow()
    }

    private var scopePicker: some View {
        HStack(spacing: 0) {
            ForEach(CommentsModel.Scope.allCases) { scope in
                Button {
                    model.scope = scope
                } label: {
                    Text(scope.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(model.scope == scope ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 36)
                        .background {
                            if model.scope == scope {
                                Capsule().fill(Color.accentColor)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.scope == scope ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.quaternary, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comment scope")
    }

    // MARK: Content

    @ViewBuilder
    private var contentSections: some View {
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
            if model.displayRows.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Comments Yet",
                        systemImage: "bubble.left",
                        description: Text("Be the first to leave one.")
                    )
                }
                .cardRow()
            } else {
                ForEach(model.displayRows) { row in
                    CommentThreadRow(
                        row: row,
                        workAuthors: workAuthors,
                        showChapterBadge: model.scope == .all && row.depth == 0,
                        onReply: { model.startComposer(replyingTo: $0) },
                        onEdit: { model.startEditing($0) },
                        onDelete: { pendingDelete = $0 },
                        onCopyLink: { copyLink($0) },
                        onOpenURL: { router.open($0) }
                    )
                    .commentBubbleRow(depth: row.depth)
                }
                if let page = model.page, page.totalPages > 1 {
                    paginationSection(page)
                }
            }
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
        if case .loaded = model.phase, auth.isLoggedIn {
            Button {
                model.startComposer()
            } label: {
                Label("Write a comment", systemImage: "pencil")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isOffline)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(theme.appTheme.carouselCardSurface.ignoresSafeArea())
            .accessibilityLabel("Write a comment")
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

                Section {
                    Text(
                        "AO3 does not publish per-chapter totals, so Kudos does not "
                            + "fetch every chapter just to count them."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            let rowCount = CGFloat(model.chapters.count + 1)
            return [.height(190 + rowCount * 52)]
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

// MARK: - Composer

/// Reply / top-level comment sheet with draft preservation and the defensive
/// submission flow (single POST, verify-on-ambiguity — `CommentSubmissionGuard`).
struct CommentComposerSheet: View {
    @Bindable var model: CommentsModel

    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var draftSaveTask: Task<Void, Never>?

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
                    TextEditor(text: $model.composerText)
                        .frame(minHeight: 180, maxHeight: 260)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
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
