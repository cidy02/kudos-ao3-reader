import Foundation
import Testing
@testable import Kudos

/// Guards the comment parsers against AO3 markup drift, using a sanitized copy
/// of a live comments page (`Fixtures/ao3_comments_page.html`, captured
/// 2026-07-09 — see `docs/ai/COMMENTS_HANDOFF.md`).
@MainActor
struct AO3CommentsParseTests {
    final class BundleAnchor {}

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Comments page

    @Test func parsesThreadedComments() throws {
        let page = try AO3Client.parseCommentsPage(fixture("ao3_comments_page"), page: 1)

        // Two top-level comments; replies nest under their parents.
        #expect(page.comments.count == 2)
        let first = try #require(page.comments.first)
        #expect(first.id == 1001)
        #expect(first.isGuest)
        #expect(first.author == "StarrySky")
        #expect(first.userPath == nil)
        #expect(first.avatarURL == nil)
        #expect(first.bodyText == "That quiet thank you said everything.\n\nAbsolutely broke me.")
        #expect(first.chapterID == 9003)
        #expect(first.chapterLabel == "Chapter 3")
        #expect(first.postedText.contains("Jul 2026"))
        #expect(first.postedAt != nil)
        #expect(first.canReply)

        // Reply chain: 1001 ← 1002 ← 1003.
        #expect(first.replies.map(\.id) == [1002])
        let reply = try #require(first.replies.first)
        #expect(reply.author == "Calytrix")
        #expect(!reply.isGuest)
        #expect(reply.userPath == "/users/Calytrix/pseuds/Calytrix")
        #expect(reply.avatarURL?.absoluteString == "https://archiveofourown.org/icon.jpeg")
        #expect(reply.replies.map(\.id) == [1003])

        let second = try #require(page.comments.last)
        #expect(second.id == 1004)
        #expect(second.chapterLabel == "Chapter 4")
        #expect(second.replies.isEmpty)
    }

    @Test func parsesPaginationAndTotals() throws {
        let page = try AO3Client.parseCommentsPage(fixture("ao3_comments_page"), page: 1)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 3)
        #expect(page.totalComments == 47)
    }

    /// Edit/Delete come straight from AO3's per-session markup — present on the
    /// session's own comment, absent everywhere else. The UI is gated on these.
    @Test func exposesOnlyActionsAO3Rendered() throws {
        let page = try AO3Client.parseCommentsPage(fixture("ao3_comments_page"), page: 1)
        let guest = try #require(page.comments.first)
        #expect(guest.editPath == nil)
        #expect(guest.deletePath == nil)

        let own = try #require(guest.replies.first)
        #expect(own.editPath == "/comments/1002/edit")
        #expect(own.deletePath == "/comments/1002")
        #expect(own.threadActionURL?.absoluteString == "https://archiveofourown.org/comments/1002")
        #expect(own.parentThreadURL?.absoluteString == "https://archiveofourown.org/comments/1001")
        // Drives native "Parent Thread" focus (scroll-to, not an AO3 web page).
        #expect(own.parentCommentID == 1001)
        #expect(guest.parentCommentID == nil)
    }

    @Test func topLevelCommentWithNoRepliesStaysLeaf() throws {
        let page = try AO3Client.parseCommentsPage(fixture("ao3_comments_page"), page: 1)
        let replyLess = try #require(page.comments.last)
        #expect(replyLess.replies.isEmpty)
    }

    @Test func topLevelCommentWithMultipleDirectRepliesKeepsSiblings() {
        var root = AO3Comment(id: 1, author: "Root", isGuest: false)
        root.replies = [
            AO3Comment(id: 2, author: "First", isGuest: false),
            AO3Comment(id: 3, author: "Second", isGuest: false),
        ]

        // displayThreads preserves the full sibling reply tree under the root.
        let displayed = CommentsModel.orderedDisplayThreads(from: [root], newestFirst: false)
        #expect(displayed.map(\.id) == [1])
        #expect(displayed[0].replies.map(\.id) == [2, 3])
        #expect(displayed[0].replies.allSatisfy { $0.replies.isEmpty })
        #expect(displayed[0].flattened.map(\.id) == [1, 2, 3])
    }

    @Test func replyToReplyNestsUnderImmediateParent() throws {
        let page = try AO3Client.parseCommentsPage(fixture("ao3_comments_page"), page: 1)
        let displayed = CommentsModel.orderedDisplayThreads(
            from: page.comments, newestFirst: false
        )
        let root = try #require(displayed.first)
        let reply = try #require(root.replies.first)
        let replyToReply = try #require(reply.replies.first)

        #expect(root.replies.map(\.id) == [1002])
        #expect(reply.replies.map(\.id) == [1003])
        #expect(replyToReply.replies.isEmpty)
        #expect(root.flattened.map(\.id) == [1001, 1002, 1003])
    }

    @Test func supportsAtLeastFourNestingLevels() {
        var level4 = AO3Comment(id: 5, author: "L4", isGuest: false)
        var level3 = AO3Comment(id: 4, author: "L3", isGuest: false)
        level3.replies = [level4]
        var level2 = AO3Comment(id: 3, author: "L2", isGuest: false)
        level2.replies = [level3]
        var level1 = AO3Comment(id: 2, author: "L1", isGuest: false)
        level1.replies = [level2]
        var root = AO3Comment(id: 1, author: "Root", isGuest: false)
        root.replies = [level1]

        let displayed = CommentsModel.orderedDisplayThreads(from: [root], newestFirst: false)
        #expect(displayed[0].flattened.map(\.id) == [1, 2, 3, 4, 5])
        #expect(displayed[0].replies.map(\.id) == [2])
        #expect(displayed[0].replies[0].replies.map(\.id) == [3])
        #expect(displayed[0].replies[0].replies[0].replies.map(\.id) == [4])
        #expect(displayed[0].replies[0].replies[0].replies[0].replies.map(\.id) == [5])
    }

    @Test func multipleBranchesAtDifferentDepthsPreserveOrder() {
        var grandchild = AO3Comment(id: 3, author: "Grandchild", isGuest: false)
        grandchild.replies = [AO3Comment(id: 4, author: "Great-grandchild", isGuest: false)]
        var firstReply = AO3Comment(id: 2, author: "First reply", isGuest: false)
        firstReply.replies = [grandchild]
        let secondReply = AO3Comment(id: 5, author: "Second reply", isGuest: false)
        var root = AO3Comment(id: 1, author: "Root", isGuest: false)
        root.replies = [firstReply, secondReply]

        let displayed = CommentsModel.orderedDisplayThreads(from: [root], newestFirst: false)
        #expect(displayed[0].replies.map(\.id) == [2, 5])
        #expect(displayed[0].replies[0].replies.map(\.id) == [3])
        #expect(displayed[0].replies[0].replies[0].replies.map(\.id) == [4])
        #expect(displayed[0].flattened.map(\.id) == [1, 2, 3, 4, 5])
    }

    @Test func twoLevelCardsAndSharedSpineColumn() {
        // Card shells stop at depth 1 (root + direct-reply cards); deeper
        // nodes share the same avatar-column center for the spine.
        #expect(CommentThreadGeometry.maximumCardDepth == 1)
        #expect(CommentThreadGeometry.avatarSize == 40)
        #expect(CommentThreadGeometry.avatarColumnWidth == 40)
        let center = CommentThreadGeometry.avatarColumnWidth / 2
        for depth in 0...6 {
            #expect(CommentThreadGeometry.avatarCenterX(forDepth: depth) == center)
        }
        #expect(CommentThreadGeometry.autoExpandedMaxDirectReplies == 8)
        #expect(CommentThreadGeometry.postSpacing > 0)
        #expect(CommentThreadGeometry.spineWidth == 2)
    }

    @Test func displayThreadsPreservesReplyTreesAndNewestFirstRootOrder() {
        var firstRoot = AO3Comment(id: 1, author: "A", isGuest: false)
        firstRoot.replies = [AO3Comment(id: 10, author: "Reply", isGuest: false)]
        let secondRoot = AO3Comment(id: 2, author: "B", isGuest: false)
        let roots = [firstRoot, secondRoot]

        let oldestFirst = CommentsModel.orderedDisplayThreads(from: roots, newestFirst: false)
        #expect(oldestFirst.map(\.id) == [1, 2])
        #expect(oldestFirst[0].replies.map(\.id) == [10])

        let newestFirst = CommentsModel.orderedDisplayThreads(from: roots, newestFirst: true)
        #expect(newestFirst.map(\.id) == [2, 1])
        // Newest-first only reorders roots — reply trees stay under the same root.
        #expect(newestFirst[1].replies.map(\.id) == [10])
        #expect(newestFirst[0].replies.isEmpty)
    }

    @Test func largeDisplayThreadProjectionKeepsStableUniqueIDs() {
        let comments = (0..<500).map { rootIndex in
            var root = AO3Comment(id: rootIndex * 10, author: "Root", isGuest: false)
            root.replies = (1...4).map { replyIndex in
                AO3Comment(
                    id: rootIndex * 10 + replyIndex,
                    author: "Reply",
                    isGuest: false
                )
            }
            return root
        }

        let displayed = CommentsModel.orderedDisplayThreads(from: comments, newestFirst: false)
        #expect(displayed.count == 500)
        #expect(displayed.reduce(0) { $0 + $1.descendantCount } == 2_500)
        let allIDs = displayed.flatMap { $0.flattened.map(\.id) }
        #expect(allIDs.count == 2_500)
        #expect(Set(allIDs).count == 2_500)

        let newestFirst = CommentsModel.orderedDisplayThreads(from: comments, newestFirst: true)
        #expect(newestFirst.first?.id == comments.last?.id)
        #expect(newestFirst.last?.id == comments.first?.id)
        #expect(newestFirst.first?.replies.map(\.id) == comments.last?.replies.map(\.id))
    }

    @Test func rootIDContainingFindsNestedDescendant() {
        var child = AO3Comment(id: 20, author: "Child", isGuest: false)
        child.replies = [AO3Comment(id: 30, author: "Grandchild", isGuest: false)]
        var root = AO3Comment(id: 10, author: "Root", isGuest: false)
        root.replies = [child]
        let other = AO3Comment(id: 40, author: "Other", isGuest: false)

        let threads = CommentsModel.orderedDisplayThreads(
            from: [root, other], newestFirst: false
        )
        #expect(threads.map(\.id) == [10, 40])
        #expect(CommentsModel.rootID(containing: 10, in: threads) == 10)
        #expect(CommentsModel.rootID(containing: 20, in: threads) == 10)
        #expect(CommentsModel.rootID(containing: 30, in: threads) == 10)
        #expect(CommentsModel.rootID(containing: 40, in: threads) == 40)
        #expect(CommentsModel.rootID(containing: 999, in: threads) == nil)
    }

    @Test func autoCollapseThresholdIsPositive() {
        #expect(CommentThreadGeometry.autoExpandedMaxDirectReplies > 0)
        #expect(CommentThreadGeometry.autoExpandedMaxDirectReplies == 8)
    }

    @Test func missingCommentsRegionParsesAsEmpty() throws {
        let page = try AO3Client.parseCommentsPage("<html><body>No comments UI.</body></html>", page: 2)
        #expect(page.comments.isEmpty)
        #expect(page.currentPage == 2)
        #expect(page.totalPages == 2)
    }

    // MARK: Comment timestamps

    @Test func parsesAO3CommentTimestampWithNamedZoneAndOffset() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let expected = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 8, hour: 14, minute: 38
        )))

        #expect(AO3CommentTimestamp.parse("Wed 08 Jul 2026 02:38PM UTC") == expected)
        #expect(AO3CommentTimestamp.parse("Wed 08 Jul 2026 10:38AM -0400") == expected)
    }

    @Test func formatsRecentYesterdayAndOlderTimestampsInLocalZone() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let locale = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 10, hour: 23
        )))
        let recent = try #require(calendar.date(byAdding: .hour, value: -2, to: now))
        let yesterday = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 9, hour: 21, minute: 30
        )))
        let older = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 7, hour: 14, minute: 26
        )))

        #expect(AO3CommentTimestamp.displayText(
            rawText: "", date: recent, relativeTo: now,
            calendar: calendar, timeZone: zone, locale: locale
        ) == "2 hours ago")
        #expect(AO3CommentTimestamp.displayText(
            rawText: "", date: yesterday, relativeTo: now,
            calendar: calendar, timeZone: zone, locale: locale
        ) == "Yesterday at 9:30 PM EDT")
        #expect(AO3CommentTimestamp.displayText(
            rawText: "", date: older, relativeTo: now,
            calendar: calendar, timeZone: zone, locale: locale
        ) == "7/7/2026 at 2:26 PM EDT")
    }

    @Test func under24HoursWinsAcrossLocalMidnightAndInvalidTextFallsBack() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let locale = Locale(identifier: "en_US")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 10, hour: 0, minute: 30
        )))
        let previousLocalDay = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 9, hour: 23, minute: 30
        )))

        #expect(AO3CommentTimestamp.displayText(
            rawText: "", date: previousLocalDay, relativeTo: now,
            calendar: calendar, timeZone: zone, locale: locale
        ) == "1 hour ago")
        #expect(AO3CommentTimestamp.displayText(
            rawText: "AO3 changed this timestamp", date: nil, relativeTo: now,
            calendar: calendar, timeZone: zone, locale: locale
        ) == "AO3 changed this timestamp")
    }

    // MARK: Chapter index (/navigate)

    static let navigateHTML = """
    <html><body>
    <ol class="chapter index group" role="navigation">
      <li><a href="/works/424242/chapters/9001">1. The Fallen Star</a> <span class="datetime">(2026-07-01)</span></li>
      <li><a href="/works/424242/chapters/9003">2. Chapter 2</a> <span class="datetime">(2026-07-03)</span></li>
      <li><a href="/works/424242/chapters/9010">3. Rain on the Pavement</a> <span class="datetime">(2026-07-05)</span></li>
    </ol>
    </body></html>
    """

    @Test func parsesChapterIndex() throws {
        let chapters = try AO3Client.parseChapterIndex(Self.navigateHTML)
        #expect(chapters.map(\.id) == [9001, 9003, 9010])
        #expect(chapters.map(\.position) == [1, 2, 3])
        #expect(chapters[0].title == "The Fallen Star")
        #expect(chapters[0].displayName == "Chapter 1 · The Fallen Star")
        // AO3's default "Chapter N" title doesn't repeat in the display name.
        #expect(chapters[1].displayName == "Chapter 2")
        #expect(chapters[2].dateText == "2026-07-05")
    }

    // MARK: URL builders

    @Test func buildsCommentsURLs() {
        #expect(
            AO3Client.commentsPageURL(workID: 42).absoluteString
                == "https://archiveofourown.org/works/42?show_comments=true&view_adult=true&view_full_work=true"
        )
        #expect(
            AO3Client.commentsPageURL(workID: 42, page: 3).absoluteString
                == "https://archiveofourown.org/works/42?show_comments=true&view_adult=true&view_full_work=true&page=3"
        )
        // Chapter-scoped pages never need (or want) the full-work render.
        #expect(
            AO3Client.commentsPageURL(workID: 42, chapterID: 7, page: 2).absoluteString
                == "https://archiveofourown.org/works/42/chapters/7?show_comments=true&view_adult=true&page=2"
        )
        #expect(
            AO3Client.chapterIndexURL(workID: 42).absoluteString
                == "https://archiveofourown.org/works/42/navigate"
        )
    }

    // MARK: Post-verification matcher

    private func pageWith(_ comments: [AO3Comment]) -> AO3CommentsPage {
        AO3CommentsPage(comments: comments)
    }

    @Test func verificationMatcherFindsTopLevelComment() {
        var mine = AO3Comment(id: 2, author: "Reader", isGuest: false)
        mine.bodyText = "Loved  this   chapter!"
        let page = pageWith([mine])

        #expect(AO3AuthService.containsComment(
            in: page, author: "reader", normalizedBody: "Loved this chapter!", parentID: nil
        ))
        #expect(!AO3AuthService.containsComment(
            in: page, author: "reader", normalizedBody: "Different text", parentID: nil
        ))
        #expect(!AO3AuthService.containsComment(
            in: page, author: "SomeoneElse", normalizedBody: "Loved this chapter!", parentID: nil
        ))
    }

    @Test func verificationMatcherRequiresTheRightParentForReplies() {
        var reply = AO3Comment(id: 9, author: "Reader", isGuest: false)
        reply.bodyText = "Yes, exactly!"
        var parent = AO3Comment(id: 5, author: "Other", isGuest: false)
        parent.replies = [reply]
        var unrelated = AO3Comment(id: 6, author: "Other", isGuest: false)
        unrelated.bodyText = "Yes, exactly!"
        let page = pageWith([parent, unrelated])

        #expect(AO3AuthService.containsComment(
            in: page, author: "Reader", normalizedBody: "Yes, exactly!", parentID: 5
        ))
        // The same text under a different parent (or at top level) is not proof.
        #expect(!AO3AuthService.containsComment(
            in: page, author: "Reader", normalizedBody: "Yes, exactly!", parentID: 6
        ))
    }
}
