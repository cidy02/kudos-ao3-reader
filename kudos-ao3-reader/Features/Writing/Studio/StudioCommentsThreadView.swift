import SwiftUI

/// The opened comment: its text, a reply box, Post Reply, and Mark Read.
struct StudioCommentsThreadView: View {
    let commentID: Int
    var model: StudioCommentsModel

    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inbox
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Group {
            if let item = model.item(commentID, in: inbox.items) {
                thread(item)
            } else {
                ContentUnavailableView {
                    Label("Comment unavailable", systemImage: "bubble.left")
                } description: {
                    Text("This comment is no longer on the inbox page on screen.")
                }
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .subjectScreenSurface(.content, palette: theme.scopePalette)
        .navigationDestination(for: StudioCommentsFullThread.self) { route in
            StudioCommentsFullThreadScreen(route: route)
        }
    }

    private var title: String {
        let name = model.item(commentID, in: inbox.items)?.workTitle ?? ""
        return name.isEmpty ? "Comment" : name
    }

    private func thread(_ item: AO3InboxItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StudioCommentCard(item: item, showsWork: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(StudioCommentCard.summary(item))
                if item.canReply {
                    replyBox(item)
                }
                if showsMarkRead(item) || item.workID != nil {
                    actions(item)
                }
                if model.statusCommentID == item.id, let message = model.statusMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(model.statusIsError ? AnyShapeStyle(theme.appTheme.errorColor) : AnyShapeStyle(.secondaryInk))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.vertical, 12)
        }
    }

    private func replyBox(_ item: AO3InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your reply to \(item.commenterName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .accessibilityHidden(true)
            TextField(
                "Your reply to \(item.commenterName)",
                text: replyBinding(item.id),
                axis: .vertical
            )
            .lineLimit(3...8)
            .font(.body)
            .padding(10)
            .background(
                theme.appTheme.cardSurface,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .accessibilityLabel("Your reply to \(item.commenterName)")
            .disabled(isBusy(item))
            if !postingName.isEmpty {
                Text("Posts on AO3 as \(postingName)")
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            theme.appTheme.cardBackdrop,
            in: RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
        )
    }

    /// One row when both labels fit. The stack is the fallback so large text
    /// cannot clip "Post Reply" or "Mark Read" off the side of the screen.
    private func actions(_ item: AO3InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    markReadButton(item)
                    postButton(item)
                }
                VStack(alignment: .leading, spacing: 8) {
                    markReadButton(item)
                    postButton(item)
                }
            }
            if model.pendingCommentID == item.id, case .ambiguous = model.submissionPhase {
                Button("Check Again") { Task { await checkAgain(item) } }
                    .buttonStyle(.kudosSecondary)
                    .disabled(isBusy(item))
                    .accessibilityLabel("Check Again")
            }
            if let route = fullThread(item, opensReply: false, focusChapter: false) {
                NavigationLink(value: route) {
                    Text("Thread")
                        .font(.headline)
                        .foregroundStyle(theme.accentInk)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Opens the whole comment thread")
            }
        }
    }

    @ViewBuilder
    private func markReadButton(_ item: AO3InboxItem) -> some View {
        if showsMarkRead(item) {
            Button("Mark Read") { Task { await markRead(item) } }
                .buttonStyle(.kudosSecondary)
                .disabled(isBusy(item))
                .accessibilityLabel("Mark Read")
        }
    }

    @ViewBuilder
    private func postButton(_ item: AO3InboxItem) -> some View {
        if item.canReply {
            Button("Post Reply") { Task { await post(item) } }
                .buttonStyle(.kudosPrimary)
                .disabled(cannotPost(item))
                .accessibilityLabel("Post Reply")
        }
    }

    private func showsMarkRead(_ item: AO3InboxItem) -> Bool {
        guard item.isUnread, let form = inbox.bulkForm else { return false }
        return form.parameters(for: [item], action: .markRead) != nil
    }

    private func isBusy(_ item: AO3InboxItem) -> Bool {
        model.postingID == item.id
            || model.markingReadID == item.id
            || model.submissionPhase.isBusy
    }

    private func cannotPost(_ item: AO3InboxItem) -> Bool {
        let draft = model.replyText(for: item.id)
        let blank = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return isBusy(item) || blank
    }

    private func replyBinding(_ id: Int) -> Binding<String> {
        Binding(
            get: { model.replyText(for: id) },
            set: { model.setReply($0, for: id) }
        )
    }

    private var postingName: String {
        let preferred = auth.preferredPostingPseudName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let preferred, !preferred.isEmpty { return preferred }
        return auth.username ?? ""
    }

    private func post(_ item: AO3InboxItem) async {
        guard auth.isLoggedIn, let username = auth.username else { return }
        let generation = auth.sessionGeneration
        let posted = await model.postReply(
            to: item,
            identity: username,
            generation: generation,
            verifier: verifier(generation: generation),
            poster: { parentID, body, generation, onFormPrepared in
                _ = try await auth.postCommentReply(
                    parentCommentID: parentID,
                    content: body,
                    expectedGeneration: generation,
                    onFormPrepared: onFormPrepared
                )
            }
        )
        if posted { await inbox.refresh(auth: auth) }
    }

    private func checkAgain(_ item: AO3InboxItem) async {
        guard auth.isLoggedIn else { return }
        let generation = auth.sessionGeneration
        let posted = await model.reverify(
            commentID: item.id,
            generation: generation,
            verifier: verifier(generation: generation)
        )
        if posted { await inbox.refresh(auth: auth) }
    }

    private func markRead(_ item: AO3InboxItem) async {
        guard let form = inbox.bulkForm else { return }
        let changed = await model.markRead(
            item, form: form, referer: form.actionURL
        ) { action, form, items, referer in
            try await auth.performInboxBulkAction(
                action, form: form, items: items, referer: referer
            )
        }
        if changed { await inbox.refresh(auth: auth) }
    }

    private func verifier(generation: Int) -> StudioCommentsModel.ReplyVerifier {
        { context, body, submittedAt, hidden, _ in
            try await auth.verifyCommentPosted(
                context: context,
                body: body,
                submittedAt: submittedAt,
                commentMayBeHidden: hidden,
                expectedGeneration: generation
            )
        }
    }

    private func fullThread(
        _ item: AO3InboxItem, opensReply: Bool, focusChapter: Bool
    ) -> StudioCommentsFullThread? {
        guard let workID = item.workID else { return nil }
        return StudioCommentsFullThread(
            workID: workID,
            context: AO3CommentsWorkContext(title: item.workTitle, authors: []),
            commentID: item.id,
            chapterPosition: item.chapterPosition,
            focusChapter: focusChapter,
            opensReply: opensReply,
            sessionGeneration: auth.sessionGeneration
        )
    }
}

/// A comment thread pushed from the studio, using the app's comments screen.
struct StudioCommentsFullThread: Hashable, Sendable {
    let workID: Int
    let context: AO3CommentsWorkContext
    let commentID: Int
    let chapterPosition: Int?
    let focusChapter: Bool
    let opensReply: Bool
    let sessionGeneration: Int
}

private struct StudioCommentsFullThreadScreen: View {
    let route: StudioCommentsFullThread

    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inbox

    var body: some View {
        CommentsView(
            workID: route.workID,
            context: route.context,
            initialChapterPosition: route.focusChapter ? route.chapterPosition : nil,
            initialCommentID: route.commentID,
            initialFocusesChapter: route.focusChapter,
            initialReplyCommentID: route.opensReply ? route.commentID : nil,
            requiredSessionGeneration: route.sessionGeneration,
            onResolveWorkContext: { context in
                inbox.cacheWorkContext(
                    context,
                    for: route.workID,
                    sessionGeneration: route.sessionGeneration,
                    auth: auth
                )
            }
        )
    }
}

/// The app's existing Inbox, for everything this section does not list.
struct StudioCommentsInboxPage: View {
    var workContext: (AO3InboxItem) -> AO3CommentsWorkContext

    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inbox
    @Environment(AppRouter.self) private var router
    @State private var thread: StudioCommentsFullThread?

    var body: some View {
        AccountInboxScreen(
            model: inbox,
            onOpen: { open($0, reply: false, chapter: false) },
            onReply: { open($0, reply: true, chapter: false) },
            onOpenChapter: { open($0, reply: false, chapter: true) },
            workContext: workContext,
            metadataTaskID: metadataTaskID,
            onEnrichVisible: { await enrich() }
        )
        .navigationDestination(item: $thread) { route in
            StudioCommentsFullThreadScreen(route: route)
        }
        .onAppear { inbox.activate(auth: auth) }
    }

    private var metadataTaskID: String {
        let ids = inbox.items.compactMap(\.workID).map(String.init).joined(separator: ",")
        return "\(auth.sessionGeneration)|\(inbox.metadataRevision)|\(ids)"
    }

    private func open(_ item: AO3InboxItem, reply: Bool, chapter: Bool) {
        // Tag and admin comments have no work. AO3's comment page is the thread.
        guard let workID = item.workID else {
            router.open(AO3Client.commentThreadURL(commentID: item.id))
            return
        }
        thread = StudioCommentsFullThread(
            workID: workID,
            context: workContext(item),
            commentID: item.id,
            chapterPosition: item.chapterPosition,
            focusChapter: chapter,
            opensReply: reply,
            sessionGeneration: auth.sessionGeneration
        )
    }

    private func enrich() async {
        guard case .loaded = inbox.phase else { return }
        var seeds: [Int: AO3CommentsWorkContext] = [:]
        for item in inbox.items {
            guard let workID = item.workID else { continue }
            seeds[workID] = workContext(item)
        }
        await inbox.enrichVisibleWorkContexts(
            workIDs: inbox.items.compactMap(\.workID),
            seededContexts: seeds,
            auth: auth
        )
    }
}
