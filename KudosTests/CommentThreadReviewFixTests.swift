import Foundation
import Testing
@testable import Kudos

/// Two defects an independent review (Codex, 2026-09-24) found in the 1f
/// threading rebuild: the "deeper replies" count and the collapse caret.
@MainActor
struct CommentThreadReviewFixTests {
    /// A chain of single replies `depth` levels below `root`, ending in `leaf`.
    private static func chain(depth: Int, leaf: AO3Comment) -> AO3Comment {
        var node = leaf
        for level in stride(from: depth - 1, through: 1, by: -1) {
            var parent = AO3Comment(id: 100 + level, author: "P\(level)", isGuest: false)
            parent.replies = [node]
            node = parent
        }
        return node
    }

    /// AO3 renders past its nesting limit as one "N more comments" placeholder.
    /// Dropped below depth 5, it stands for N replies — counting it as one made
    /// the list say "1 deeper reply" while the thread screen said 7.
    @Test func aCutoffPlaceholderPastTheCapCountsEveryCommentItStandsFor() throws {
        var cutoff = AO3Comment(id: 900, author: "", isGuest: false)
        cutoff.isThreadCutoff = true
        cutoff.cutoffCount = 7
        var root = AO3Comment(id: 1, author: "Root", isGuest: false)
        // Depths 1…5 inline, the placeholder at depth 6.
        root.replies = [Self.chain(depth: 6, leaf: cutoff)]

        let rows = CommentConversationBuilder.rows(
            roots: [root],
            repliesByRoot: [root.id: CommentThreadGeometry.flattenedReplies(from: root)],
            expandedRootIDs: [], visibleReplyCounts: [:],
            maxDepth: CommentThreadGeometry.maxInlineDepth
        )
        let last = try #require(rows.last)
        guard case let .continueThread(_, hidden) = last.item else {
            Issue.record("expected a trailing Continue thread row, got \(last.item)")
            return
        }
        #expect(hidden == 7)
    }

    /// The same placeholder inside the cap: "Show N" on the expander and on the
    /// collapse caret count what it stands for too, not one row.
    @Test func inlineCountsIncludeWhatACutoffPlaceholderStandsFor() throws {
        var cutoff = AO3Comment(id: 900, author: "", isGuest: false)
        cutoff.isThreadCutoff = true
        cutoff.cutoffCount = 7
        var root = AO3Comment(id: 1, author: "Root", isGuest: false)
        // 25 plain replies plus the placeholder: past the auto-expand limit.
        root.replies = (2 ... 26).map { AO3Comment(id: $0, author: "R\($0)", isGuest: false) } + [cutoff]
        let replies = [root.id: CommentThreadGeometry.flattenedReplies(from: root)]

        let folded = CommentConversationBuilder.rows(
            roots: [root], repliesByRoot: replies, expandedRootIDs: [], visibleReplyCounts: [:]
        )
        guard case let .expander(_, hidden, _) = try #require(folded.last).item else {
            Issue.record("expected a trailing expander row")
            return
        }
        #expect(hidden == 32)

        let collapsed = CommentConversationBuilder.rows(
            roots: [root], repliesByRoot: replies, expandedRootIDs: [], visibleReplyCounts: [:],
            collapsedRootIDs: [root.id]
        )
        #expect(collapsed.first?.collapse?.replyCount == 32)
    }

    /// Reopening a folded long thread must show its replies again. Collapsing
    /// drops the expanded state, so reopening used to bring back only the
    /// "Show N replies" row — with a "Hide" caret above it.
    @Test func reopeningAFoldedLongThreadShowsItsRepliesAgain() async {
        var root = AO3Comment(id: 1, author: "Root", isGuest: false)
        root.replies = (2 ... 26).map { AO3Comment(id: $0, author: "R\($0)", isGuest: false) }
        let page = AO3CommentsPage(comments: [root])
        let model = CommentsModel(
            workID: 95_002,
            workContext: AO3CommentsWorkContext(title: "Fixture", authors: ["Creator"]),
            initialFocusesChapter: false,
            initialComposes: false,
            pageLoader: { _, _, _, _ in page },
            chapterLoader: { _, _ in [] },
            pageCache: CommentsPageCache()
        )
        await model.loadInitial(auth: AO3AuthService(
            vault: MemoryAO3SessionVault(),
            validator: InboxTestSessionValidator(),
            loginPerformer: DynamicInboxTestLoginPerformer(),
            cookieManager: MockAO3CookieManager(),
            removalTracker: MemoryAO3SessionRemovalTracker()
        ))
        func replyPosts() -> Int {
            model.conversationRows.filter {
                if case let .post(_, _, depth, _) = $0.item { return depth > 0 }
                return false
            }.count
        }
        #expect(replyPosts() == 0)
        model.expandReplies(rootID: root.id)
        #expect(replyPosts() > 0)
        model.toggleCollapsed(rootID: root.id)
        #expect(replyPosts() == 0)
        model.toggleCollapsed(rootID: root.id)
        #expect(replyPosts() > 0)
    }
}
