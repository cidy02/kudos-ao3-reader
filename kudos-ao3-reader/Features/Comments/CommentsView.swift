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

    @State private var model: CommentsModel
    @State private var showingChapterPicker = false
    @State private var pendingDelete: AO3Comment?
    @State private var actionBanner: String?

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
            Task {
                model.resetForContextChange()
                if scope == .byChapter {
                    await model.loadChaptersIfNeeded(auth: auth)
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
            model.resetForContextChange()
            Task { await model.load(auth: auth) }
        }
        .onChange(of: model.newestFirst) { _, _ in
            Task { await model.load(auth: auth) }
        }
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

                Picker("Scope", selection: $model.scope) {
                    ForEach(CommentsModel.Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

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
                }

                HStack {
                    // Local rendering order — AO3 has no server-side comment sort.
                    Picker("Order", selection: $model.newestFirst) {
                        Text("Oldest First").tag(false)
                        Text("Newest First").tag(true)
                    }
                    .pickerStyle(.menu)
                    .font(.subheadline)
                    Spacer()
                    if let total = model.page?.totalComments {
                        Label("\(total.formatted())", systemImage: "bubble.left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardRow()
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
            if model.displayComments.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Comments Yet",
                        systemImage: "bubble.left",
                        description: Text("Be the first to leave one.")
                    )
                }
                .cardRow()
            } else {
                ForEach(model.displayComments) { comment in
                    Section {
                        CommentThreadCell(
                            comment: comment,
                            depth: 0,
                            workAuthors: workAuthors,
                            showChapterBadge: model.scope == .all,
                            onReply: { model.startComposer(replyingTo: $0) },
                            onEdit: { model.startEditing($0) },
                            onDelete: { pendingDelete = $0 },
                            onCopyLink: { copyLink($0) },
                            onOpenThread: { openThread($0) },
                            onReportAbuse: { reportAbuse($0) }
                        )
                    }
                    .cardRow()
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
                Text("You're offline — showing comments from \(model.page?.fetchedAt.formatted(.relative(presentation: .named)) ?? "earlier"). They may be out of date.")
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
                    Task { await model.loadPage(model.currentPageNumber - 1, auth: auth) }
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
                    Task { await model.loadPage(model.currentPageNumber + 1, auth: auth) }
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

    // MARK: Write bar

    @ViewBuilder
    private var writeCommentBar: some View {
        if case .loaded = model.phase {
            Button {
                model.startComposer()
            } label: {
                Label(
                    auth.isLoggedIn ? "Write a comment" : "Log in to AO3 to comment",
                    systemImage: auth.isLoggedIn ? "pencil" : "person.crop.circle.badge.questionmark"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!auth.isLoggedIn || model.isOffline)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
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
            List(model.chapters) { chapter in
                Button {
                    model.selectedChapter = chapter
                    showingChapterPicker = false
                } label: {
                    HStack {
                        Label(chapter.displayName, systemImage: "book")
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Spacer()
                        if chapter == model.selectedChapter {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
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
            .navigationTitle("Browse by Chapter")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    private func openThread(_ comment: AO3Comment) {
        if let url = comment.threadURL { router.open(url) }
    }

    private func reportAbuse(_ comment: AO3Comment) {
        // AO3's abuse form; the comment link identifies what's being reported.
        copyLink(comment)
        if let url = URL(string: "https://archiveofourown.org/abuse_reports/new") {
            router.open(url)
        }
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

// MARK: - Thread cell

/// One top-level comment with its reply tree. Indentation is capped so deep
/// threads stay readable on phone widths.
struct CommentThreadCell: View {
    let comment: AO3Comment
    let depth: Int
    let workAuthors: [String]
    let showChapterBadge: Bool
    let onReply: (AO3Comment) -> Void
    let onEdit: (AO3Comment) -> Void
    let onDelete: (AO3Comment) -> Void
    let onCopyLink: (AO3Comment) -> Void
    let onOpenThread: (AO3Comment) -> Void
    let onReportAbuse: (AO3Comment) -> Void

    @Environment(AO3AuthService.self) private var auth

    private var isByWorkAuthor: Bool {
        workAuthors.contains { $0.caseInsensitiveCompare(comment.author) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            byline
            if !comment.bodyText.isEmpty {
                Text(comment.bodyText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions

            if !comment.replies.isEmpty {
                ForEach(comment.replies) { reply in
                    CommentThreadCell(
                        comment: reply,
                        depth: depth + 1,
                        workAuthors: workAuthors,
                        showChapterBadge: false,
                        onReply: onReply,
                        onEdit: onEdit,
                        onDelete: onDelete,
                        onCopyLink: onCopyLink,
                        onOpenThread: onOpenThread,
                        onReportAbuse: onReportAbuse
                    )
                    .padding(.leading, depth < 3 ? 14 : 0)
                    .overlay(alignment: .leading) {
                        if depth < 3 {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(.quaternary)
                                .frame(width: 2)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private var byline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(comment.author)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            if isByWorkAuthor {
                Text("Author")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            } else if comment.isGuest {
                Text("Guest")
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if showChapterBadge, let chapter = comment.chapterLabel {
                Text(chapter)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 14) {
            if !comment.postedText.isEmpty {
                Text(comment.postedText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if comment.canReply && auth.isLoggedIn {
                Button { onReply(comment) } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
            Menu {
                if comment.canReply && auth.isLoggedIn {
                    Button { onReply(comment) } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                }
                if comment.editPath != nil {
                    Button { onEdit(comment) } label: {
                        Label("Edit Comment", systemImage: "pencil")
                    }
                }
                Button { onCopyLink(comment) } label: {
                    Label("Copy Link", systemImage: "link")
                }
                Button { onOpenThread(comment) } label: {
                    Label("Open Thread on AO3", systemImage: "safari")
                }
                Button { onReportAbuse(comment) } label: {
                    Label("Report Abuse", systemImage: "flag")
                }
                if comment.deletePath != nil {
                    Button(role: .destructive) { onDelete(comment) } label: {
                        Label("Delete Comment", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Composer

/// Reply / top-level comment sheet with draft preservation and the defensive
/// submission flow (single POST, verify-on-ambiguity — `CommentSubmissionGuard`).
struct CommentComposerSheet: View {
    @Bindable var model: CommentsModel

    @Environment(AO3AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    private var isReply: Bool { model.composerParent != nil }
    private var isEdit: Bool { model.composerEditTarget != nil }

    private var composerTitle: String {
        if isEdit { return "Edit Comment" }
        return isReply ? "Reply to Comment" : "New Comment"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let parent = model.composerParent {
                        parentQuote(parent)
                    }
                    TextEditor(text: $model.composerText)
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                        .disabled(model.submissionGuard.phase.isBusy)

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
                // Draft-as-you-type: nothing typed is lost to a dismissal or crash.
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Replying to \(parent.author)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(parent.bodyText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
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
