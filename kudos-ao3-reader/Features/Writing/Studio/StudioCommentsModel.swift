import Foundation

/// Comments list state: which chip is on, and what a successful reply or Mark
/// Read changed before the inbox page reloads.
///
/// Reply posting goes through `CommentSubmissionGuard` and
/// `AO3AuthService.postCommentReply`. Mark Read submits the inbox page's own
/// bulk form (`performInboxBulkAction`), the same write the Inbox screen uses.
@MainActor
@Observable
final class StudioCommentsModel {
    typealias ReplyPoster = @MainActor (
        _ parentCommentID: Int,
        _ body: String,
        _ generation: Int,
        _ onFormPrepared: @escaping @MainActor (Bool) -> Void
    ) async throws -> Void

    typealias ReplyVerifier = @MainActor (
        _ context: AO3CommentContext,
        _ body: String,
        _ submittedAt: Date?,
        _ commentMayBeHidden: Bool,
        _ generation: Int
    ) async throws -> AO3AuthService.CommentVerification

    typealias MarkReadSubmitter = @MainActor (
        _ action: AO3InboxBulkAction,
        _ form: AO3InboxBulkForm,
        _ items: [AO3InboxItem],
        _ referer: URL
    ) async throws -> String

    private struct Override: Equatable {
        var replied = false
        var read = false
    }

    var chip: StudioCommentsChip = .needsReply
    private(set) var statusMessage: String?
    private(set) var statusCommentID: Int?
    private(set) var statusIsError = false
    private(set) var postingID: Int?
    private(set) var markingReadID: Int?
    let submission: CommentSubmissionGuard

    private var overrides: [Int: Override] = [:]
    private var replyDrafts: [Int: String] = [:]

    init(submission: CommentSubmissionGuard? = nil) {
        self.submission = submission ?? CommentSubmissionGuard() // made here, on the main actor, not in a default argument
    }

    var submissionPhase: CommentSubmissionPhase { submission.phase }

    var pendingCommentID: Int? { submission.pendingKey?.context.parentCommentID }

    func resetForAccountChange() {
        overrides = [:]
        replyDrafts = [:]
        statusMessage = nil
        statusCommentID = nil
        statusIsError = false
        postingID = nil
        markingReadID = nil
        submission.resetForAuthenticationChange()
    }

    func replyText(for id: Int) -> String {
        replyDrafts[id] ?? ""
    }

    func setReply(_ text: String, for id: Int) {
        var drafts = replyDrafts
        drafts[id] = text
        replyDrafts = drafts
    }

    func displayed(_ items: [AO3InboxItem]) -> [AO3InboxItem] {
        items.map(apply)
    }

    func item(_ id: Int, in items: [AO3InboxItem]) -> AO3InboxItem? {
        displayed(items).first(where: { $0.id == id })
    }

    func needsReplyCount(in items: [AO3InboxItem]) -> Int {
        StudioCommentsBoard.needsReplyCount(displayed(items))
    }

    func visibleComments(in items: [AO3InboxItem]) -> [AO3InboxItem] {
        StudioCommentsBoard.comments(displayed(items), chip: chip)
    }

    func workGroups(in items: [AO3InboxItem]) -> [StudioCommentWorkGroup] {
        let works = StudioCommentsBoard.comments(displayed(items), chip: .byWork)
        return StudioCommentsBoard.groups(works)
    }

    /// Posts `replyText` as a reply. True only when AO3 confirmed it, or a
    /// follow-up check found it. The comment then leaves Needs Reply.
    @discardableResult
    func postReply(
        to item: AO3InboxItem,
        identity: String,
        generation: Int,
        verifier: ReplyVerifier? = nil,
        poster: ReplyPoster
    ) async -> Bool {
        guard let workID = item.workID, markingReadID != item.id else { return false }
        let body = replyText(for: item.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            setStatus(
                item.id,
                AO3WriteError.emptyComment.errorDescription ?? "Write a comment first.",
                error: true
            )
            return false
        }
        let context = AO3CommentContext(
            workID: workID, chapterID: nil, parentCommentID: item.id
        )
        let key = CommentSubmissionKey(context: context, body: body, identity: identity)
        guard submission.begin(key) else {
            setStatus(item.id, blockedMessage(), error: phaseIsError)
            return false
        }
        postingID = item.id
        defer {
            if postingID == item.id { postingID = nil }
        }
        var hidden = false
        do {
            try await poster(item.id, body, generation) { hidden = $0 }
            acceptReply(item.id)
            return true
        } catch {
            return await handleReplyFailure(
                error,
                itemID: item.id,
                context: context,
                generation: generation,
                hidden: hidden,
                verifier: verifier
            )
        }
    }

    /// Checks an ambiguous reply again. True when the reply is found on AO3.
    @discardableResult
    func reverify(
        commentID: Int,
        generation: Int,
        verifier: @escaping ReplyVerifier
    ) async -> Bool {
        guard pendingCommentID == commentID, case .ambiguous = submission.phase else {
            return false
        }
        return await resolveAmbiguity(commentID: commentID, generation: generation, verifier: verifier)
    }

    /// Submits AO3's Mark Read for one row. True when the write succeeds.
    /// Read and replied are separate inbox flags, so the row stays in Needs Reply.
    @discardableResult
    func markRead(
        _ item: AO3InboxItem,
        form: AO3InboxBulkForm?,
        referer: URL,
        submit: MarkReadSubmitter
    ) async -> Bool {
        guard item.isUnread, postingID != item.id, markingReadID == nil else { return false }
        guard let form, form.parameters(for: [item], action: .markRead) != nil else {
            setStatus(
                item.id,
                "Couldn't prepare AO3's Inbox action. Reload and try again.",
                error: true
            )
            return false
        }
        markingReadID = item.id
        defer {
            if markingReadID == item.id { markingReadID = nil }
        }
        do {
            _ = try await submit(.markRead, form, [item], referer)
            noteRead(item.id)
            setStatus(item.id, AO3InboxBulkAction.markRead.successMessage, error: false)
            return true
        } catch {
            setStatus(item.id, CommentsModel.message(for: error), error: true)
            return false
        }
    }

    private func handleReplyFailure(
        _ error: Error,
        itemID: Int,
        context: AO3CommentContext,
        generation: Int,
        hidden: Bool,
        verifier: ReplyVerifier?
    ) async -> Bool {
        if CommentsModel.isAmbiguousSubmitError(error) {
            submission.markAmbiguous(
                CommentsModel.ambiguousSubmitMessage(for: error),
                commentMayBeHidden: hidden
            )
            setStatus(itemID, CommentsModel.ambiguousSubmitMessage(for: error), error: true)
            guard verifier != nil else { return false }
            return await resolveAmbiguity(
                commentID: itemID, generation: generation, verifier: verifier
            )
        }
        submission.fail(CommentsModel.message(for: error))
        setStatus(itemID, CommentsModel.message(for: error), error: true)
        return false
    }

    private func resolveAmbiguity(
        commentID: Int,
        generation: Int,
        verifier: ReplyVerifier?
    ) async -> Bool {
        guard let verifier, let pending = submission.pendingKey,
              pending.context.parentCommentID == commentID
        else { return false }
        let submittedAt = submission.pendingSubmittedAt
        let hidden = submission.pendingCommentMayBeHidden
        let body = pending.normalizedBody
        let context = pending.context
        submission.beginVerifying()
        let verdict: AO3AuthService.CommentVerification
        do {
            verdict = try await verifier(context, body, submittedAt, hidden, generation)
        } catch {
            submission.markAmbiguous(CommentsModel.message(for: error), commentMayBeHidden: hidden)
            setStatus(commentID, CommentsModel.message(for: error), error: true)
            return false
        }
        guard submission.pendingKey == pending else { return false }
        submission.resolveAmbiguity(verdict)
        if case .found = verdict {
            acceptReply(commentID)
            return true
        }
        if case .failed(let message) = submission.phase {
            setStatus(commentID, message, error: true)
        } else if case .ambiguous(let message) = submission.phase {
            setStatus(commentID, message, error: true)
        }
        return false
    }

    private func acceptReply(_ id: Int) {
        submission.succeed()
        noteReplied(id)
        setReply("", for: id)
        setStatus(id, "Reply posted.", error: false)
    }

    private func noteReplied(_ id: Int) {
        var next = overrides
        var flag = next[id] ?? Override()
        flag.replied = true
        flag.read = true
        next[id] = flag
        overrides = next
    }

    private func noteRead(_ id: Int) {
        var next = overrides
        var flag = next[id] ?? Override()
        flag.read = true
        next[id] = flag
        overrides = next
    }

    private func apply(_ item: AO3InboxItem) -> AO3InboxItem {
        guard let flag = overrides[item.id] else { return item }
        var copy = item
        if flag.replied {
            copy.isReplied = true
            copy.isUnread = false
        }
        if flag.read { copy.isUnread = false }
        return copy
    }

    private func setStatus(_ id: Int, _ message: String, error: Bool) {
        statusCommentID = id
        statusMessage = message
        statusIsError = error
    }

    private var phaseIsError: Bool {
        switch submission.phase {
        case .ambiguous, .failed: true
        case .idle, .submitting, .verifying, .succeeded: false
        }
    }

    private func blockedMessage() -> String {
        switch submission.phase {
        case .idle: "Couldn't post that reply."
        case .submitting, .verifying: "Posting your reply…"
        case .succeeded: "Reply posted."
        case .ambiguous(let message), .failed(let message): message
        }
    }
}
