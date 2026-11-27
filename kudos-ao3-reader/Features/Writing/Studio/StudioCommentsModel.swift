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

    /// AO3 rejects comments past 10,000 Unicode scalars (`String#length` in Ruby).
    static let characterLimit = 10_000

    static func remainingCharacters(for text: String) -> Int {
        characterLimit - text.unicodeScalars.count
    }

    /// Matches `CommentsModel`'s auth identity so unresolved submissions share one
    /// key space across Studio Comments and full threads, and offline-restored
    /// sessions without a real username stay session-local.
    static func submissionIdentity(
        username: String?,
        isLoggedIn: Bool,
        generation: Int
    ) -> String {
        let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed,
           !trimmed.isEmpty,
           trimmed.caseInsensitiveCompare("AO3 Account") != .orderedSame {
            return trimmed
        }
        return isLoggedIn ? CommentDraftIdentity.unnamedSession(generation) : ""
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
    private var accountEpoch = 0

    init(submission: CommentSubmissionGuard? = nil) {
        // Share the process-lifetime store with `CommentsModel` so an unresolved
        // reply stays blocked across section switches and full-thread navigation.
        self.submission = submission ?? CommentSubmissionGuard(store: .shared)
    }

    var submissionPhase: CommentSubmissionPhase { submission.phase }

    var pendingCommentID: Int? { submission.pendingKey?.context.parentCommentID }

    func resetForAccountChange() {
        accountEpoch &+= 1
        overrides = [:]
        replyDrafts = [:]
        statusMessage = nil
        statusCommentID = nil
        statusIsError = false
        postingID = nil
        markingReadID = nil
        submission.resetForAuthenticationChange()
    }

    /// Re-syncs the guard against the shared unresolved store when opening a
    /// comment thread, so an ambiguous reply recorded elsewhere or before a tab
    /// switch immediately surfaces its warning and "Check Again" action.
    func adoptSubmission(for item: AO3InboxItem, identity: String) {
        guard !submission.phase.isBusy,
              item.canReply,
              !item.isUnavailable,
              let workID = item.workID
        else { return }
        let key = submissionKey(workID: workID, commentID: item.id, identity: identity)
        submission.adopt(key)
        if case .ambiguous(let message) = submission.phase {
            setStatus(item.id, message, error: true)
        }
    }

    /// Keeps `.ambiguous` aligned with edits to the reply box: editing away from
    /// an unresolved draft hides its stale Check Again button without releasing
    /// the original block in the store; retyping the blocked draft surfaces it.
    func syncSubmissionForDraftEdit(item: AO3InboxItem, identity: String) {
        guard !submission.phase.isBusy,
              item.canReply,
              !item.isUnavailable,
              let workID = item.workID
        else { return }
        let wasAmbiguous: Bool
        switch submission.phase {
        case .ambiguous: wasAmbiguous = true
        case .idle: wasAmbiguous = false
        case .submitting, .verifying, .succeeded, .failed: return
        }
        let key = submissionKey(workID: workID, commentID: item.id, identity: identity)
        submission.adopt(key)
        if case .ambiguous(let message) = submission.phase {
            setStatus(item.id, message, error: true)
        } else if wasAmbiguous, statusCommentID == item.id, statusIsError {
            statusMessage = nil
            statusCommentID = nil
            statusIsError = false
        }
    }

    /// Drops optimistic flags once a fresh AO3 Inbox page confirms them, so a
    /// later Mark Unread in the full Inbox is not permanently masked here.
    func reconcile(with items: [AO3InboxItem]) {
        guard !overrides.isEmpty else { return }
        var next = overrides
        var changed = false
        for item in items {
            guard var flag = next[item.id] else { continue }
            if flag.read, !item.isUnread {
                flag.read = false
                changed = true
            }
            if flag.replied, item.isReplied {
                flag.replied = false
                changed = true
            }
            if !flag.read && !flag.replied {
                next.removeValue(forKey: item.id)
            } else {
                next[item.id] = flag
            }
        }
        if changed { overrides = next }
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
        guard item.canReply,
              !item.isUnavailable,
              let workID = item.workID,
              markingReadID != item.id
        else { return false }
        let body = replyText(for: item.id).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            setStatus(
                item.id,
                AO3WriteError.emptyComment.errorDescription ?? "Write a comment first.",
                error: true
            )
            return false
        }
        guard Self.remainingCharacters(for: body) >= 0 else {
            setStatus(item.id, "Replies on AO3 are limited to 10,000 characters.", error: true)
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
        let epoch = accountEpoch
        postingID = item.id
        defer {
            if accountEpoch == epoch, postingID == item.id { postingID = nil }
        }
        var hidden = false
        do {
            try await poster(item.id, body, generation) { hidden = $0 }
            guard accountEpoch == epoch, submission.pendingKey == key else { return false }
            acceptReply(item.id, submittedBody: body)
            return true
        } catch {
            guard accountEpoch == epoch, submission.pendingKey == key else { return false }
            return await handleReplyFailure(
                error,
                itemID: item.id,
                generation: generation,
                epoch: epoch,
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
        return await resolveAmbiguity(
            commentID: commentID, generation: generation, epoch: accountEpoch, verifier: verifier
        )
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
        guard item.isUnread,
              postingID != item.id,
              markingReadID == nil,
              !submission.phase.isBusy
        else { return false }
        guard let form, form.parameters(for: [item], action: .markRead) != nil else {
            setStatus(
                item.id,
                "Couldn't prepare AO3's Inbox action. Reload and try again.",
                error: true
            )
            return false
        }
        let epoch = accountEpoch
        markingReadID = item.id
        defer {
            if accountEpoch == epoch, markingReadID == item.id { markingReadID = nil }
        }
        do {
            _ = try await submit(.markRead, form, [item], referer)
            guard accountEpoch == epoch else { return false }
            noteRead(item.id)
            setStatus(item.id, AO3InboxBulkAction.markRead.successMessage, error: false)
            return true
        } catch {
            guard accountEpoch == epoch else { return false }
            setStatus(item.id, CommentsModel.message(for: error), error: true)
            return false
        }
    }

    private func handleReplyFailure(
        _ error: Error,
        itemID: Int,
        generation: Int,
        epoch: Int,
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
                commentID: itemID, generation: generation, epoch: epoch, verifier: verifier
            )
        }
        submission.fail(CommentsModel.message(for: error))
        setStatus(itemID, CommentsModel.message(for: error), error: true)
        return false
    }

    private func resolveAmbiguity(
        commentID: Int,
        generation: Int,
        epoch: Int,
        verifier: ReplyVerifier?
    ) async -> Bool {
        guard accountEpoch == epoch,
              let verifier,
              let pending = submission.pendingKey,
              pending.context.parentCommentID == commentID
        else { return false }
        let submittedAt = submission.pendingSubmittedAt
        let hidden = submission.pendingCommentMayBeHidden
        let body = pending.normalizedBody
        let context = pending.context
        submission.beginVerifying()
        setStatus(commentID, "Checking whether your reply went through…", error: false)
        let verdict: AO3AuthService.CommentVerification
        do {
            verdict = try await verifier(context, body, submittedAt, hidden, generation)
        } catch {
            guard accountEpoch == epoch, submission.pendingKey == pending else { return false }
            submission.markAmbiguous(CommentsModel.message(for: error), commentMayBeHidden: hidden)
            setStatus(commentID, CommentsModel.message(for: error), error: true)
            return false
        }
        guard accountEpoch == epoch, submission.pendingKey == pending else { return false }
        submission.resolveAmbiguity(verdict)
        if case .found = verdict {
            acceptReply(commentID, submittedBody: body)
            return true
        }
        if case .failed(let message) = submission.phase {
            setStatus(commentID, message, error: true)
        } else if case .ambiguous(let message) = submission.phase {
            setStatus(commentID, message, error: true)
        }
        return false
    }

    private func acceptReply(_ id: Int, submittedBody: String) {
        if submission.phase != .succeeded {
            submission.succeed()
        }
        noteReplied(id)
        if CommentSubmissionKey.normalize(replyText(for: id))
            == CommentSubmissionKey.normalize(submittedBody) {
            setReply("", for: id)
        }
        setStatus(id, "Reply posted.", error: false)
    }

    private func submissionKey(
        workID: Int,
        commentID: Int,
        identity: String
    ) -> CommentSubmissionKey {
        let context = AO3CommentContext(workID: workID, chapterID: nil, parentCommentID: commentID)
        let body = replyText(for: commentID).trimmingCharacters(in: .whitespacesAndNewlines)
        return CommentSubmissionKey(context: context, body: body, identity: identity)
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
