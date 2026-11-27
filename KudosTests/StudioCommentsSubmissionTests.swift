import Foundation
import Testing
@testable import Kudos

@MainActor
private final class StudioCommentsTestGate {
    private var entered = false
    private var released = false
    private var onEnter: CheckedContinuation<Void, Never>?
    private var onRelease: CheckedContinuation<Void, Never>?

    func enterAndWait() async {
        entered = true
        onEnter?.resume()
        onEnter = nil
        if released { return }
        await withCheckedContinuation { continuation in
            onRelease = continuation
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            onEnter = continuation
        }
    }

    func release() {
        released = true
        onRelease?.resume()
        onRelease = nil
    }
}

/// Regression tests for Writing Studio Comments reply safety, concurrency
/// fencing, override reconciliation, and multi-page/filter presentation.
/// All writes are faked in memory; nothing contacts AO3.
@MainActor
struct StudioCommentsSubmissionTests {
    private final class BundleAnchor {}

    @MainActor
    private final class CallCounter {
        var posts = 0
        var verifies = 0
    }

    private static func page(_ name: String) throws -> AO3InboxPage {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        let html = try String(contentsOf: url, encoding: .utf8)
        return try AO3Client.parseInboxPage(html, page: 1)
    }

    private func item(_ id: Int, on page: AO3InboxPage) throws -> AO3InboxItem {
        try #require(page.items.first(where: { $0.id == id }))
    }

    private func makeModel(
        store: UnresolvedCommentSubmissionStore = UnresolvedCommentSubmissionStore()
    ) -> StudioCommentsModel {
        StudioCommentsModel(submission: CommentSubmissionGuard(store: store))
    }

    @Test func sharedStoreBlocksDoublePostAcrossRecreatedModelsAndAdoptRestoresState() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let target = try item(9001, on: page)
        let store = UnresolvedCommentSubmissionStore()
        let counter = CallCounter()

        let first = makeModel(store: store)
        first.setReply("Thank you.", for: target.id)
        let firstPosted = await first.postReply(
            to: target, identity: "tester", generation: 1
        ) { _, _, _, _ in
            counter.posts += 1
            throw URLError(.timedOut)
        }
        #expect(firstPosted == false)
        #expect(counter.posts == 1)

        // Simulates leaving Comments (recreating the model) or opening from Threads.
        let second = makeModel(store: store)
        second.setReply("Thank you.", for: target.id)
        second.adoptSubmission(for: target, identity: "tester")
        let adoptedAmbiguous = Self.isAmbiguous(second.submissionPhase)
        #expect(adoptedAmbiguous)
        #expect(second.pendingCommentID == 9001)
        #expect(second.statusCommentID == 9001)
        #expect(second.statusIsError)

        let reposted = await second.postReply(
            to: target, identity: "tester", generation: 1
        ) { _, _, _, _ in
            counter.posts += 1
        }
        #expect(reposted == false)
        #expect(counter.posts == 1)

        // Editing away clears the stale Check Again banner without unlocking the original text.
        second.setReply("Something completely different.", for: target.id)
        second.syncSubmissionForDraftEdit(item: target, identity: "tester")
        #expect(second.submissionPhase == .idle)
        #expect(second.statusMessage == nil)

        // Retyping the unresolved text brings back the blocked state immediately.
        second.setReply("Thank you.", for: target.id)
        second.syncSubmissionForDraftEdit(item: target, identity: "tester")
        let restoredAmbiguous = Self.isAmbiguous(second.submissionPhase)
        #expect(restoredAmbiguous)
        #expect(second.pendingCommentID == 9001)
    }

    @Test func reverifyResolvesUnknownErrorFoundAndAbsentWithoutWipingEditedDraft() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let target = try item(9001, on: page)
        let model = makeModel()
        let counter = CallCounter()

        model.setReply("Thank you.", for: target.id)
        let initial = await model.postReply(
            to: target, identity: "tester", generation: 1
        ) { _, _, _, _ in
            counter.posts += 1
            throw AO3WriteError.unconfirmed
        }
        #expect(initial == false)
        #expect(Self.isAmbiguous(model.submissionPhase))

        let stillUnknown = await model.reverify(commentID: target.id, generation: 1) { _, _, _, _, _ in
            counter.verifies += 1
            return .unknown
        }
        #expect(stillUnknown == false)
        #expect(counter.verifies == 1)
        #expect(Self.isAmbiguous(model.submissionPhase))
        #expect(model.replyText(for: target.id) == "Thank you.")

        let errored = await model.reverify(commentID: target.id, generation: 1) { _, _, _, _, _ in
            counter.verifies += 1
            throw URLError(.notConnectedToInternet)
        }
        #expect(errored == false)
        #expect(counter.verifies == 2)
        #expect(Self.isAmbiguous(model.submissionPhase))
        #expect(model.replyText(for: target.id) == "Thank you.")

        // If the draft changed while the earlier pending key is still being verified,
        // confirming the earlier reply must not wipe the newer draft text.
        model.setReply("Fresh follow-up draft.", for: target.id)
        let found = await model.reverify(commentID: target.id, generation: 1) { _, body, _, _, _ in
            counter.verifies += 1
            #expect(body == "Thank you.")
            return .found
        }
        #expect(found)
        #expect(counter.verifies == 3)
        #expect(model.needsReplyCount(in: page.items) == 0)
        #expect(model.replyText(for: target.id) == "Fresh follow-up draft.")

        // Separate model: `.absent` releases the block for an explicit retry.
        let retryModel = makeModel()
        retryModel.setReply("Second attempt.", for: target.id)
        let timedOut = await retryModel.postReply(
            to: target, identity: "tester", generation: 1
        ) { _, _, _, _ in
            counter.posts += 1
            throw URLError(.timedOut)
        }
        #expect(timedOut == false)
        let absent = await retryModel.reverify(commentID: target.id, generation: 1) { _, _, _, _, _ in
            .absent
        }
        #expect(absent == false)
        let isFailed = Self.isFailed(retryModel.submissionPhase)
        #expect(isFailed)
        #expect(retryModel.replyText(for: target.id) == "Second attempt.")
    }

    @Test func concurrentDoubleTapPostsOnce() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let target = try item(9001, on: page)
        let model = makeModel()
        let counter = CallCounter()
        let gate = StudioCommentsTestGate()
        model.setReply("Thank you.", for: target.id)

        let firstTask = Task { @MainActor in
            await model.postReply(to: target, identity: "tester", generation: 1) { _, _, _, _ in
                counter.posts += 1
                await gate.enterAndWait()
            }
        }
        await gate.waitUntilEntered()

        let secondResult = await model.postReply(
            to: target, identity: "tester", generation: 1
        ) { _, _, _, _ in
            counter.posts += 1
        }
        #expect(secondResult == false)
        #expect(counter.posts == 1)

        gate.release()
        let firstResult = await firstTask.value
        #expect(firstResult)
        #expect(counter.posts == 1)
    }

    @Test func accountChangeMidFlightMakesPostReplyInert() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let target = try item(9001, on: page)

        // 1. Success landing after account switch must not mark the new account replied.
        let model = makeModel()
        let successGate = StudioCommentsTestGate()
        model.setReply("Thank you.", for: target.id)
        let successTask = Task { @MainActor in
            await model.postReply(to: target, identity: "alice", generation: 1) { _, _, _, _ in
                await successGate.enterAndWait()
            }
        }
        await successGate.waitUntilEntered()
        model.resetForAccountChange()
        successGate.release()
        let successOutcome = await successTask.value
        #expect(successOutcome == false)
        #expect(model.needsReplyCount(in: page.items) == 1)
        #expect(model.statusMessage == nil)
        #expect(model.submissionPhase == .idle)

        // 2. CancellationError landing after account switch must not fail or banner the new account.
        let errorModel = makeModel()
        let errorGate = StudioCommentsTestGate()
        errorModel.setReply("Thank you.", for: target.id)
        let errorTask = Task { @MainActor in
            await errorModel.postReply(to: target, identity: "alice", generation: 1) { _, _, _, _ in
                await errorGate.enterAndWait()
                throw CancellationError()
            }
        }
        await errorGate.waitUntilEntered()
        errorModel.resetForAccountChange()
        errorGate.release()
        let errorOutcome = await errorTask.value
        #expect(errorOutcome == false)
        #expect(errorModel.statusMessage == nil)
        #expect(errorModel.submissionPhase == .idle)
    }

    @Test func accountChangeMidFlightMakesReverifyAndMarkReadInert() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let target = try item(9001, on: page)
        let form = try #require(page.bulkForm)

        // 1. Reverify throwing CancellationError after account change must not mutate state.
        let model = makeModel()
        model.setReply("Thank you.", for: target.id)
        let timedOut = await model.postReply(to: target, identity: "alice", generation: 1) { _, _, _, _ in
            throw URLError(.timedOut)
        }
        #expect(timedOut == false)

        let verifyGate = StudioCommentsTestGate()
        let verifyTask = Task { @MainActor in
            await model.reverify(commentID: target.id, generation: 1) { _, _, _, _, _ in
                await verifyGate.enterAndWait()
                throw CancellationError()
            }
        }
        await verifyGate.waitUntilEntered()
        model.resetForAccountChange()
        verifyGate.release()
        let verifyOutcome = await verifyTask.value
        #expect(verifyOutcome == false)
        #expect(model.statusMessage == nil)
        #expect(model.submissionPhase == .idle)

        // 2. Mark Read completing after account change must not mark the new account read.
        let readModel = makeModel()
        let readGate = StudioCommentsTestGate()
        let readTask = Task { @MainActor in
            await readModel.markRead(target, form: form, referer: form.actionURL) { _, _, _, _ in
                await readGate.enterAndWait()
                return AO3InboxBulkAction.markRead.successMessage
            }
        }
        await readGate.waitUntilEntered()
        readModel.resetForAccountChange()
        readGate.release()
        let readOutcome = await readTask.value
        #expect(readOutcome == false)
        let shown = try #require(readModel.item(9001, in: page.items))
        #expect(shown.isUnread)
        #expect(readModel.statusMessage == nil)
    }

    @Test func postReplyRefusesUnreplyableUnavailableAndOverLimitReplies() async throws {
        let page = try Self.page("ao3_inbox_studio_comments")
        let frozen = try item(9104, on: page)
        let replyable = try item(9101, on: page)
        let model = makeModel()
        let counter = CallCounter()

        model.setReply("Trying to reply to frozen comment.", for: frozen.id)
        let frozenPosted = await model.postReply(
            to: frozen, identity: "tester", generation: 1
        ) { _, _, _, _ in
            counter.posts += 1
        }
        #expect(frozenPosted == false)
        #expect(counter.posts == 0)

        var unavailable = replyable
        unavailable.isUnavailable = true
        model.setReply("Trying to reply to tombstone.", for: unavailable.id)
        let unavailablePosted = await model.postReply(
            to: unavailable, identity: "tester", generation: 1
        ) { _, _, _, _ in
            counter.posts += 1
        }
        #expect(unavailablePosted == false)
        #expect(counter.posts == 0)

        // Family emoji is 1 Character but 7 Unicode scalars — Ruby counts scalars.
        let overLimit = String(repeating: "👨‍👩‍👧‍👦", count: 1_500)
        #expect(overLimit.count < StudioCommentsModel.characterLimit)
        #expect(StudioCommentsModel.remainingCharacters(for: overLimit) < 0)
        model.setReply(overLimit, for: replyable.id)
        let overLimitPosted = await model.postReply(
            to: replyable, identity: "tester", generation: 1
        ) { _, _, _, _ in
            counter.posts += 1
        }
        #expect(overLimitPosted == false)
        #expect(counter.posts == 0)
        #expect(model.statusIsError)
        #expect(model.replyText(for: replyable.id) == overLimit)
    }

    @Test func reconcileClearsConfirmedMarkReadSoLaterMarkUnreadShows() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let target = try item(9001, on: page)
        let form = try #require(page.bulkForm)
        let model = makeModel()

        let changed = await model.markRead(
            target, form: form, referer: form.actionURL
        ) { _, _, _, _ in
            AO3InboxBulkAction.markRead.successMessage
        }
        #expect(changed)
        let optimistic = try #require(model.item(9001, in: page.items))
        #expect(optimistic.isUnread == false)

        // Fresh server page confirms 9001 is now read -> optimistic override clears.
        var confirmedRead = target
        confirmedRead.isUnread = false
        model.reconcile(with: [confirmedRead])

        // Later the user marks 9001 Unread in the full Inbox -> Studio reflects it.
        let reloadedUnread = try #require(model.item(9001, in: page.items))
        #expect(reloadedUnread.isUnread)
    }

    @Test func multiPageCopyFilterNoticeAndOfflineIdentity() throws {
        #expect(
            StudioCommentsBoard.emptyMessage(chip: .needsReply, totalPages: 1)
                == "No comments waiting for a reply."
        )
        #expect(
            StudioCommentsBoard.emptyMessage(chip: .needsReply, totalPages: 3)
                == "No comments waiting for a reply on this page."
        )
        #expect(
            StudioCommentsBoard.emptyMessage(chip: .all, totalPages: 1)
                == "No comments on your works."
        )
        #expect(
            StudioCommentsBoard.emptyMessage(chip: .all, totalPages: 3)
                == "No comments on your works on this page."
        )
        #expect(StudioCommentsBoard.pageNote(currentPage: 1, totalPages: 1) == nil)
        #expect(
            StudioCommentsBoard.pageNote(currentPage: 2, totalPages: 5)
                == "Page 2 of 5 · counts are for this page"
        )

        let manage = try Self.page("ao3_inbox_manage")
        let manageValues = try #require(manage.filterForm).selectedValues
        #expect(
            StudioCommentsBoard.activeInboxFilterNotice(in: manageValues)
                == "AO3 Inbox is filtered to Unread."
        )
        #expect(
            StudioCommentsBoard.activeInboxFilterNotice(in: AO3InboxPill.replied.values)
                == "AO3 Inbox is filtered to Replied."
        )
        #expect(StudioCommentsBoard.activeInboxFilterNotice(in: AO3InboxPill.all.values) == nil)
        #expect(
            StudioCommentsBoard.activeInboxFilterNotice(in: [
                AO3InboxPill.readField: "true", AO3InboxPill.repliedField: "all"
            ]) == "AO3 Inbox filters are active."
        )

        let offline = StudioCommentsModel.submissionIdentity(
            username: "AO3 Account", isLoggedIn: true, generation: 7
        )
        #expect(offline == CommentDraftIdentity.unnamedSession(7))
        let named = StudioCommentsModel.submissionIdentity(
            username: "tester", isLoggedIn: true, generation: 7
        )
        #expect(named == "tester")
    }

    private static func isAmbiguous(_ phase: CommentSubmissionPhase) -> Bool {
        if case .ambiguous = phase { return true }
        return false
    }

    private static func isFailed(_ phase: CommentSubmissionPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }
}
