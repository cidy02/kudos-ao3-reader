import Foundation
import Testing
@testable import Kudos

/// Writing Studio's Comments filters, grouping, and local reply / Mark Read state.
///
/// Rows come from inbox fixtures shaped like otwarchive master `452391b6`
/// (2026-11-01) `app/views/inbox/show.html.erb`: `span.replied` when
/// `inbox_comment.replied_to?`, and a Reply link only from
/// `can_reply_to_comment?`. Replying sets `replied_to` (`Comment#notify_parent_comment_owner`).
/// Mark Read (`InboxController#update`) sets `read` only. Posting and Mark Read
/// are faked here; nothing contacts AO3.
@MainActor
struct StudioCommentsTests {
    private final class BundleAnchor {}

    @MainActor
    private final class CallLog {
        var calls = 0
        var parentID: Int?
        var body: String?
        var verifyCalls = 0
        var action: AO3InboxBulkAction?
        var ids: [Int] = []
        var values: [String] = []
    }

    private static func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func page(_ name: String) throws -> AO3InboxPage {
        try AO3Client.parseInboxPage(try fixture(name), page: 1)
    }

    private func item(_ id: Int, on page: AO3InboxPage) throws -> AO3InboxItem {
        try #require(page.items.first(where: { $0.id == id }))
    }

    @Test func needsReplyOnTheManageFixture() throws {
        let page = try Self.page("ao3_inbox_manage")
        let model = StudioCommentsModel()

        let waiting = model.needsReplyCount(in: page.items)
        #expect(waiting == 1)
        let needsIDs = model.visibleComments(in: page.items).map(\.id)
        #expect(needsIDs == [9001])

        model.chip = .all
        let allIDs = model.visibleComments(in: page.items).map(\.id)
        #expect(allIDs == [9001, 9002])

        let groups = model.workGroups(in: page.items)
        #expect(groups.map(\.title) == ["My Great Fic"])
        #expect(groups.map { $0.comments.map(\.id) } == [[9001, 9002]])

        let tag = try item(9003, on: page)
        let tagIsWork = StudioCommentsBoard.isOnYourWork(tag)
        #expect(tagIsWork == false)
    }

    @Test func needsReplyAndByWorkAcrossWorks() throws {
        let page = try Self.page("ao3_inbox_studio_comments")
        #expect(page.items.map(\.id) == [9101, 9102, 9103, 9104, 9105])

        let model = StudioCommentsModel()
        let waiting = model.needsReplyCount(in: page.items)
        #expect(waiting == 2)
        let needsIDs = model.visibleComments(in: page.items).map(\.id)
        #expect(needsIDs == [9101, 9103])

        let tide = try item(9101, on: page)
        #expect(tide.commenterName == "Ines")
        #expect(tide.workTitle == "What the Tide Keeps")
        #expect(tide.chapterIndicatorTitle == "Chapter 3")
        #expect(tide.excerpt == "The tide took the last line.")
        #expect(tide.isUnread)
        #expect(tide.canReply)
        let tideReplied = tide.isReplied
        #expect(tideReplied == false)

        let answered = try item(9102, on: page)
        #expect(answered.isReplied)
        let answeredNeeds = StudioCommentsBoard.needsReply(answered)
        #expect(answeredNeeds == false)

        // Unread, but the template omitted Reply because `can_reply_to_comment?`
        // is false. That is not the same flag as `replied_to?`.
        let keeper = try item(9104, on: page)
        #expect(keeper.isUnread)
        let keeperCanReply = keeper.canReply
        #expect(keeperCanReply == false)
        let keeperReplied = keeper.isReplied
        #expect(keeperReplied == false)
        let keeperNeeds = StudioCommentsBoard.needsReply(keeper)
        #expect(keeperNeeds == false)

        let tag = try item(9105, on: page)
        #expect(tag.workID == nil)

        let groups = model.workGroups(in: page.items)
        #expect(groups.map(\.title) == [
            "What the Tide Keeps",
            "Lantern Season",
            "Keeper of the Northern Light"
        ])
        #expect(groups.map(\.comments.count) == [2, 1, 1])
        #expect(groups.map { $0.comments.map(\.id) } == [[9101, 9102], [9103], [9104]])
    }

    @Test func postedReplyLeavesNeedsReplyAndBlocksADuplicate() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let item = try item(9001, on: page)
        let model = StudioCommentsModel()
        let log = CallLog()
        model.setReply("Thank you.", for: item.id)

        let posted = await model.postReply(
            to: item, identity: "tester", generation: 1
        ) { parentID, body, _, _ in
            log.calls += 1
            log.parentID = parentID
            log.body = body
        }

        #expect(posted)
        #expect(log.calls == 1)
        #expect(log.parentID == 9001)
        #expect(log.body == "Thank you.")
        let waiting = model.needsReplyCount(in: page.items)
        #expect(waiting == 0)
        let shown = try #require(model.item(9001, in: page.items))
        #expect(shown.isReplied)
        let stillUnread = shown.isUnread
        #expect(stillUnread == false)
        let draft = model.replyText(for: 9001)
        #expect(draft.isEmpty)
        #expect(model.submissionPhase == .succeeded)

        model.setReply("Thank you.", for: 9001)
        let duplicate = await model.postReply(
            to: item, identity: "tester", generation: 1
        ) { _, _, _, _ in
            log.calls += 1
        }
        #expect(duplicate == false)
        #expect(log.calls == 1)

        model.resetForAccountChange()
        let afterSwitch = model.needsReplyCount(in: page.items)
        #expect(afterSwitch == 1)
        let cleared = model.replyText(for: 9001)
        #expect(cleared.isEmpty)
    }

    @Test func rejectedReplyStaysAndCanBeRetried() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let item = try item(9001, on: page)
        let model = StudioCommentsModel()
        let log = CallLog()
        model.setReply("Thank you.", for: item.id)

        let posted = await model.postReply(
            to: item, identity: "tester", generation: 1
        ) { _, _, _, _ in
            log.calls += 1
            throw AO3WriteError.rejected("AO3 declined the reply.")
        }

        #expect(posted == false)
        #expect(log.calls == 1)
        let waiting = model.needsReplyCount(in: page.items)
        #expect(waiting == 1)
        #expect(model.statusMessage == "AO3 declined the reply.")
        #expect(model.statusIsError)

        let retried = await model.postReply(
            to: item, identity: "tester", generation: 1
        ) { _, _, _, _ in
            log.calls += 1
        }
        #expect(retried)
        #expect(log.calls == 2)
        let after = model.needsReplyCount(in: page.items)
        #expect(after == 0)
    }

    @Test func blankReplyDoesNotPost() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let item = try item(9001, on: page)
        let model = StudioCommentsModel()
        let log = CallLog()
        model.setReply("   ", for: item.id)

        let posted = await model.postReply(
            to: item, identity: "tester", generation: 1
        ) { _, _, _, _ in
            log.calls += 1
        }

        #expect(posted == false)
        #expect(log.calls == 0)
        #expect(model.statusMessage == "Write a comment first.")
        let waiting = model.needsReplyCount(in: page.items)
        #expect(waiting == 1)
    }

    @Test func timedOutReplyStaysAndBlocksASecondPost() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let item = try item(9001, on: page)
        let model = StudioCommentsModel()
        let log = CallLog()
        model.setReply("Thank you.", for: item.id)

        let posted = await model.postReply(
            to: item, identity: "tester", generation: 1
        ) { _, _, _, _ in
            log.calls += 1
            throw URLError(.timedOut)
        }

        #expect(posted == false)
        #expect(log.calls == 1)
        let waiting = model.needsReplyCount(in: page.items)
        #expect(waiting == 1)
        let ambiguous = Self.isAmbiguous(model.submissionPhase)
        #expect(ambiguous)
        let shown = try #require(model.item(9001, in: page.items))
        let replied = shown.isReplied
        #expect(replied == false)

        let again = await model.postReply(
            to: item, identity: "tester", generation: 1
        ) { _, _, _, _ in
            log.calls += 1
        }
        #expect(again == false)
        #expect(log.calls == 1)
    }

    @Test func foundReplyLeavesNeedsReply() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let item = try item(9001, on: page)
        let model = StudioCommentsModel()
        let log = CallLog()
        model.setReply("Thank you.", for: item.id)

        let posted = await model.postReply(
            to: item,
            identity: "tester",
            generation: 1,
            verifier: { _, _, _, _, _ in
                log.verifyCalls += 1
                return .found
            }
        ) { _, _, _, _ in
            log.calls += 1
            throw URLError(.timedOut)
        }

        #expect(posted)
        #expect(log.calls == 1)
        #expect(log.verifyCalls == 1)
        let waiting = model.needsReplyCount(in: page.items)
        #expect(waiting == 0)
        let shown = try #require(model.item(9001, in: page.items))
        #expect(shown.isReplied)
        let stillUnread = shown.isUnread
        #expect(stillUnread == false)
        #expect(model.submissionPhase == .succeeded)
    }

    @Test func unknownVerificationStaysInNeedsReply() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let item = try item(9001, on: page)
        let model = StudioCommentsModel()
        let log = CallLog()
        model.setReply("Thank you.", for: item.id)

        let posted = await model.postReply(
            to: item,
            identity: "tester",
            generation: 1,
            verifier: { _, _, _, _, _ in
                log.verifyCalls += 1
                return .unknown
            }
        ) { _, _, _, _ in
            log.calls += 1
            throw URLError(.timedOut)
        }

        #expect(posted == false)
        #expect(log.calls == 1)
        #expect(log.verifyCalls == 1)
        let waiting = model.needsReplyCount(in: page.items)
        #expect(waiting == 1)
        let ambiguous = Self.isAmbiguous(model.submissionPhase)
        #expect(ambiguous)
        let shown = try #require(model.item(9001, in: page.items))
        let replied = shown.isReplied
        #expect(replied == false)
    }

    @Test func absentVerificationCanBeRetried() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let item = try item(9001, on: page)
        let model = StudioCommentsModel()
        let log = CallLog()
        model.setReply("Thank you.", for: item.id)

        let posted = await model.postReply(
            to: item,
            identity: "tester",
            generation: 1,
            verifier: { _, _, _, _, _ in .absent }
        ) { _, _, _, _ in
            log.calls += 1
            throw URLError(.timedOut)
        }

        #expect(posted == false)
        #expect(log.calls == 1)
        let waiting = model.needsReplyCount(in: page.items)
        #expect(waiting == 1)
        let failed = Self.isFailed(model.submissionPhase)
        #expect(failed)

        let retried = await model.postReply(
            to: item, identity: "tester", generation: 1
        ) { _, _, _, _ in
            log.calls += 1
        }
        #expect(retried)
        #expect(log.calls == 2)
    }

    @Test func markReadClearsUnreadAndStaysInNeedsReply() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let item = try item(9001, on: page)
        let form = try #require(page.bulkForm)
        let model = StudioCommentsModel()
        let log = CallLog()

        let changed = await model.markRead(
            item, form: form, referer: form.actionURL
        ) { action, _, items, _ in
            log.calls += 1
            log.action = action
            log.ids = items.map(\.id)
            log.values = items.compactMap(\.bulkSelectionField?.value)
            return AO3InboxBulkAction.markRead.successMessage
        }

        #expect(changed)
        #expect(log.calls == 1)
        #expect(log.action == .markRead)
        #expect(log.ids == [9001])
        #expect(log.values == ["501"])
        let shown = try #require(model.item(9001, in: page.items))
        let stillUnread = shown.isUnread
        #expect(stillUnread == false)
        let replied = shown.isReplied
        #expect(replied == false)
        let waiting = model.needsReplyCount(in: page.items)
        #expect(waiting == 1)
        #expect(model.statusMessage == AO3InboxBulkAction.markRead.successMessage)
        let statusIsError = model.statusIsError
        #expect(statusIsError == false)
    }

    @Test func markReadWithoutAFormDoesNotSubmit() async throws {
        let page = try Self.page("ao3_inbox_manage")
        let item = try item(9001, on: page)
        let form = try #require(page.bulkForm)
        let model = StudioCommentsModel()
        let log = CallLog()

        let changed = await model.markRead(
            item, form: nil, referer: form.actionURL
        ) { _, _, _, _ in
            log.calls += 1
            return ""
        }

        #expect(changed == false)
        #expect(log.calls == 0)
        let shown = try #require(model.item(9001, in: page.items))
        #expect(shown.isUnread)
        #expect(model.statusIsError)
        #expect(model.statusMessage == "Couldn't prepare AO3's Inbox action. Reload and try again.")
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
