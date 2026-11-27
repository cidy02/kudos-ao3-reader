import SwiftUI

/// The opened comment: its text, a reply box, Post Reply, and Mark Read.
struct StudioCommentsThreadView: View {
    let commentID: Int
    var model: StudioCommentsModel

    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inbox
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        .task(id: adoptKey) {
            if let item = model.item(commentID, in: inbox.items) {
                model.adoptSubmission(for: item, identity: submissionIdentity)
            }
        }
    }

    private var adoptKey: String {
        "\(commentID)|\(auth.sessionGeneration)|\(auth.username ?? "")"
    }

    private var submissionIdentity: String {
        StudioCommentsModel.submissionIdentity(
            username: auth.username,
            isLoggedIn: auth.isLoggedIn,
            generation: auth.sessionGeneration
        )
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
                    let style = model.statusIsError
                        ? AnyShapeStyle(theme.appTheme.errorColor)
                        : AnyShapeStyle(.secondaryInk)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(style)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.vertical, 12)
        }
    }

    private func replyBox(_ item: AO3InboxItem) -> some View {
        let trimmed = model.replyText(for: item.id).trimmingCharacters(in: .whitespacesAndNewlines)
        let remaining = StudioCommentsModel.remainingCharacters(for: trimmed)
        let fieldShape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your reply to \(item.commenterName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                TextField(
                    "Your reply to \(item.commenterName)",
                    text: replyBinding(item),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(3...8)
                .font(.subheadline)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(theme.appTheme.cardSurface, in: fieldShape)
                .overlay(fieldShape.strokeBorder(theme.appTheme.glassStroke(0.13), lineWidth: 0.5))
                .accessibilityLabel("Your reply to \(item.commenterName)")
                .disabled(isBusy(item))
            }
            if remaining < 0 {
                let over = (-remaining).formatted()
                Text("\(over) characters over AO3's 10,000-character limit.")
                    .font(.caption)
                    .foregroundStyle(theme.appTheme.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            replyFooter(item)
        }
        .padding(10)
        .subjectPanel(cornerRadius: 12)
    }

    private func replyFooter(_ item: AO3InboxItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                postingAsLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                postButton(item)
            }
            VStack(alignment: .leading, spacing: 8) {
                postingAsLabel
                postButton(item)
            }
        }
    }

    @ViewBuilder
    private var postingAsLabel: some View {
        if !postingName.isEmpty {
            Text("Posts on AO3 as \(postingName)")
                .font(.caption)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One row when labels fit; stacks at large text sizes so controls never clip.
    private func actions(_ item: AO3InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            markReadButton(item)
            if model.pendingCommentID == item.id, case .ambiguous = model.submissionPhase {
                Button("Check Again") { startCheckAgain(item) }
                    .buttonStyle(.kudosSecondary)
                    .disabled(isBusy(item))
                    .accessibilityLabel("Check Again")
            }
            if let route = fullThread(item, opensReply: false, focusChapter: false) {
                NavigationLink(value: route) {
                    Text("Thread")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.accentInk)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Thread")
                .accessibilityHint("Opens the whole comment thread")
            }
        }
    }

    @ViewBuilder
    private func markReadButton(_ item: AO3InboxItem) -> some View {
        if showsMarkRead(item) {
            Button("Mark Read") { startMarkRead(item) }
                .buttonStyle(.kudosSecondary)
                .disabled(isBusy(item))
                .accessibilityLabel("Mark Read")
        }
    }

    @ViewBuilder
    private func postButton(_ item: AO3InboxItem) -> some View {
        if item.canReply {
            let disabled = cannotPost(item)
            let shape = SubjectMetrics.controlShape(dynamicTypeSize)
            Button {
                startPost(item)
            } label: {
                Text("Post Reply")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ThemeManager.label(on: theme.effectiveTint))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(minHeight: 34)
                    .background(theme.effectiveTint, in: shape)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .opacity(disabled ? 0.45 : 1)
            .disabled(disabled)
            .minimumHitTarget()
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
            || inbox.isPerformingBulkAction
    }

    private func cannotPost(_ item: AO3InboxItem) -> Bool {
        let trimmed = model.replyText(for: item.id).trimmingCharacters(in: .whitespacesAndNewlines)
        let overLimit = StudioCommentsModel.remainingCharacters(for: trimmed) < 0
        return !auth.isLoggedIn || isBusy(item) || trimmed.isEmpty || overLimit
    }

    private func replyBinding(_ item: AO3InboxItem) -> Binding<String> {
        let model = model
        let identity = submissionIdentity
        return Binding(
            get: { model.replyText(for: item.id) },
            set: { text in
                model.setReply(text, for: item.id)
                model.syncSubmissionForDraftEdit(item: item, identity: identity)
            }
        )
    }

    private var postingName: String {
        let preferred = auth.preferredPostingPseudName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let preferred, !preferred.isEmpty { return preferred }
        guard let username = auth.username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty,
              username.caseInsensitiveCompare("AO3 Account") != .orderedSame
        else { return "" }
        return username
    }

    private func startPost(_ item: AO3InboxItem) {
        guard auth.isLoggedIn else { return }
        let auth = auth
        let inbox = inbox
        let model = model
        let generation = auth.sessionGeneration
        let username = auth.username
        let identity = submissionIdentity
        let cacheScope = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        Task {
            await Self.performPost(
                item: item,
                identity: identity,
                username: username,
                cacheScope: cacheScope,
                generation: generation,
                auth: auth,
                inbox: inbox,
                model: model
            )
        }
    }

    private func startCheckAgain(_ item: AO3InboxItem) {
        guard auth.isLoggedIn else { return }
        let auth = auth
        let inbox = inbox
        let model = model
        let generation = auth.sessionGeneration
        let username = auth.username
        let cacheScope = AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        Task {
            await Self.performCheckAgain(
                item: item,
                username: username,
                cacheScope: cacheScope,
                generation: generation,
                auth: auth,
                inbox: inbox,
                model: model
            )
        }
    }

    struct MarkReadRequest {
        let item: AO3InboxItem
        let form: AO3InboxBulkForm
        let username: String?
        let cacheScope: String
        let generation: Int
    }

    private func startMarkRead(_ item: AO3InboxItem) {
        guard auth.isLoggedIn, !inbox.isPerformingBulkAction, let form = inbox.bulkForm else { return }
        let auth = auth
        let inbox = inbox
        let model = model
        let request = MarkReadRequest(
            item: item,
            form: form,
            username: auth.username,
            cacheScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth),
            generation: auth.sessionGeneration
        )
        Task {
            await Self.performMarkRead(request, auth: auth, inbox: inbox, model: model)
        }
    }

    private static func performPost(
        item: AO3InboxItem,
        identity: String,
        username: String?,
        cacheScope: String,
        generation: Int,
        auth: AO3AuthService,
        inbox: AO3InboxModel,
        model: StudioCommentsModel
    ) async {
        guard auth.isLoggedIn, auth.sessionGeneration == generation else { return }
        let posted = await model.postReply(
            to: item,
            identity: identity,
            generation: generation,
            verifier: makeVerifier(auth: auth, generation: generation),
            poster: { parentID, body, expectedGeneration, onFormPrepared in
                _ = try await auth.postCommentReply(
                    parentCommentID: parentID,
                    content: body,
                    expectedGeneration: expectedGeneration,
                    onFormPrepared: onFormPrepared
                )
            }
        )
        if posted {
            await refreshInboxAfterWrite(
                auth: auth,
                inbox: inbox,
                username: username,
                cacheScope: cacheScope,
                generation: generation
            )
        }
    }

    private static func performCheckAgain(
        item: AO3InboxItem,
        username: String?,
        cacheScope: String,
        generation: Int,
        auth: AO3AuthService,
        inbox: AO3InboxModel,
        model: StudioCommentsModel
    ) async {
        guard auth.isLoggedIn, auth.sessionGeneration == generation else { return }
        let posted = await model.reverify(
            commentID: item.id,
            generation: generation,
            verifier: makeVerifier(auth: auth, generation: generation)
        )
        if posted {
            await refreshInboxAfterWrite(
                auth: auth,
                inbox: inbox,
                username: username,
                cacheScope: cacheScope,
                generation: generation
            )
        }
    }

    static func performMarkRead(
        _ request: MarkReadRequest,
        auth: AO3AuthService,
        inbox: AO3InboxModel,
        model: StudioCommentsModel
    ) async {
        guard auth.isLoggedIn,
              auth.sessionGeneration == request.generation,
              !inbox.isPerformingBulkAction
        else { return }
        let changed = await model.markRead(
            request.item, form: request.form, referer: request.form.actionURL
        ) { action, form, items, referer in
            try auth.requireSessionGeneration(request.generation)
            return try await auth.performInboxBulkAction(
                action, form: form, items: items, referer: referer
            )
        }
        if changed {
            await refreshInboxAfterWrite(
                auth: auth,
                inbox: inbox,
                username: request.username,
                cacheScope: request.cacheScope,
                generation: request.generation
            )
        }
    }

    private static func refreshInboxAfterWrite(
        auth: AO3AuthService,
        inbox: AO3InboxModel,
        username: String?,
        cacheScope: String,
        generation: Int
    ) async {
        guard auth.isLoggedIn, auth.sessionGeneration == generation else { return }
        if let username, !username.isEmpty {
            await AO3AuthorProfileFetcher.invalidateInbox(
                username: username,
                cacheScope: cacheScope,
                isCurrent: { auth.isLoggedIn && auth.sessionGeneration == generation }
            )
        }
        guard auth.isLoggedIn, auth.sessionGeneration == generation else { return }
        await inbox.refresh(auth: auth)
    }

    private static func makeVerifier(
        auth: AO3AuthService,
        generation: Int
    ) -> StudioCommentsModel.ReplyVerifier {
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
        let context = inbox.workContext(for: workID)
            ?? AO3CommentsWorkContext(title: item.workTitle, authors: [])
        return StudioCommentsFullThread(
            workID: workID,
            context: context,
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
