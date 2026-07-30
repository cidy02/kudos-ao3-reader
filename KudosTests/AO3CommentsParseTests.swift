import Foundation
import SwiftUI
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

    @Test func parsesCanonicalWorkAuthorsForRoleBadges() throws {
        let page = try AO3Client.parseCommentsPage(fixture("ao3_comments_page"), page: 1)
        #expect(page.workAuthors == ["Calytrix", "Second Pseud"])
        #expect(page.workAuthorIdentities.map(\.username) == ["Calytrix", "CoAuthor"])
        #expect(AO3CommentParticipantRole.resolve(
            name: "A Different Posting Pseud",
            isGuest: false,
            commenterUsername: "CoAuthor",
            currentUsername: "viewer",
            workAuthors: page.workAuthors,
            workAuthorUsernames: page.workAuthorIdentities.compactMap(\.username)
        ) == .author)
    }

    @Test func ownAccountRoleOverridesWorkAuthorAndUsesUsernameNotPseud() {
        #expect(AO3CommentParticipantRole.resolve(
            name: "My Posting Pseud",
            isGuest: false,
            commenterUsername: "AccountName",
            currentUsername: "accountname",
            workAuthors: ["My Posting Pseud"]
        ) == .me)
        #expect(AO3CommentParticipantRole.resolve(
            name: "My Posting Pseud",
            isGuest: false,
            commenterUsername: "DifferentAccount",
            currentUsername: "AccountName",
            workAuthors: ["My Posting Pseud"],
            workAuthorUsernames: ["ActualCreator"]
        ) == .user)
        #expect(AO3CommentParticipantRole.resolve(
            name: "My Posting Pseud",
            isGuest: true,
            workAuthors: ["My Posting Pseud"]
        ) == .guest)
    }

    @Test func workMetadataBuildsAndNonDestructivelyEnrichesCommentsContext() throws {
        let creator = try #require(AO3AuthorIdentity(
            displayName: "Posting Pseud",
            href: "/users/CreatorAccount/pseuds/Posting%20Pseud"
        ))
        let metadata = AO3WorkMetadata(
            id: 42,
            title: "Canonical Title",
            authors: ["Posting Pseud"],
            authorIdentities: [creator],
            rating: "Teen And Up Audiences",
            fandoms: ["Example Fandom"],
            chapters: "3/5"
        )
        let sparse = AO3CommentsWorkContext(title: "Inbox Title", authors: [])
        let enriched = sparse.merging(AO3CommentsWorkContext(metadata: metadata))

        #expect(enriched.title == "Canonical Title")
        #expect(enriched.authors == ["Posting Pseud"])
        #expect(enriched.authorIdentities == [creator])
        #expect(enriched.fandoms == ["Example Fandom"])
        #expect(enriched.rating == "Teen And Up Audiences")
        #expect(enriched.chapters == "3/5")
        #expect(!enriched.needsSummaryEnrichment)

        let sparseResponse = AO3CommentsWorkContext(
            title: "", authors: [], fandoms: [], rating: "", chapters: ""
        )
        #expect(enriched.merging(sparseResponse) == enriched)

        let anonymous = AO3CommentsWorkContext(
            title: "Anonymous Work",
            authors: [],
            authorIdentities: [.nonNavigable("Anonymous", kind: .anonymous)],
            fandoms: ["Example Fandom"],
            rating: "Not Rated",
            chapters: "1/1"
        )
        #expect(!anonymous.needsSummaryEnrichment)
    }

    @Test func parsesExplicitAnonymousCreatorWithoutTrustingGuestDisplayText() throws {
        let page = try AO3Client.parseCommentsPage("""
        <div id="comments_placeholder"><ol class="thread">
          <li class="comment group" id="comment_7001">
            <h4 class="heading byline">Anonymous Creator
              <span class="posted datetime">12 Jul 2026</span>
            </h4>
            <blockquote class="userstuff"><p>Creator reply</p></blockquote>
          </li>
          <li class="comment group" id="comment_7002">
            <h4 class="heading byline"><span>Anonymous Creator</span>
              <span class="role"> (Guest)</span>
            </h4>
            <blockquote class="userstuff"><p>Guest reply</p></blockquote>
          </li>
        </ol></div>
        """, page: 1)
        #expect(page.comments[0].isAnonymousCreator)
        #expect(!page.comments[0].isGuest)
        #expect(page.comments[1].isGuest)
        #expect(!page.comments[1].isAnonymousCreator)
    }

    @Test func standaloneThreadResolvesInboxParentOrSelfAndExactChapter() throws {
        // `/comments/<id>` renders its thread directly under #main — there is no
        // work-page `#comments_placeholder` wrapper.
        let replyPage = try AO3Client.parseStandaloneCommentThread("""
        <html><body><main id="main">
          <h3 class="heading">Comment on <a href="/works/424242">A Work</a></h3>
          <ol class="thread">
            <li class="comment group" id="comment_1002">
              <h4 class="heading byline"><a href="/users/R/pseuds/R">R</a></h4>
              <blockquote class="userstuff"><p>A reply</p></blockquote>
              <ul class="actions" id="navigation_for_comment_1002">
                <li><a href="/comments/1001">Parent Thread</a></li>
                <li><a href="/comments/1002">Thread</a></li>
              </ul>
            </li>
          </ol>
        </main></body></html>
        """)
        let rootPage = try AO3Client.parseStandaloneCommentThread("""
        <html><body><main id="main">
          <h3 class="heading">Comment on <a href="/works/424242">A Work</a></h3>
          <ol class="thread">
            <li class="comment group" id="comment_1001">
              <h4 class="heading byline">
                <span>Guest Root</span><span class="role"> (Guest)</span>
                <span class="parent">on <a href="/works/424242/chapters/9003">Chapter 3</a></span>
              </h4>
              <blockquote class="userstuff"><p>Root</p></blockquote>
              <ul class="actions"><li><a href="/comments/1001">Thread</a></li></ul>
            </li>
            <li><ol class="thread">
              <li class="comment group" id="comment_1002">
                <h4 class="heading byline"><a href="/users/R/pseuds/R">R</a></h4>
                <blockquote class="userstuff"><p>A reply</p></blockquote>
              </li>
            </ol></li>
          </ol>
        </main></body></html>
        """)
        #expect(CommentsModel.focusedRootID(
            notificationCommentID: 1001, in: rootPage
        ) == 1001)
        #expect(CommentsModel.focusedRootID(
            notificationCommentID: 1002, in: replyPage
        ) == 1001)
        #expect(CommentsModel.focusedRootID(
            notificationCommentID: 999_999, in: replyPage
        ) == nil)

        let chapter = try #require(CommentsModel.chapterRef(in: rootPage))
        #expect(chapter.id == 9003)
        #expect(chapter.position == 3)

        var chapterPage = AO3CommentsPage(
            comments: [AO3Comment(id: 5000, author: "Other", isGuest: false)],
            currentPage: 1,
            totalPages: 4,
            totalComments: 30
        )
        chapterPage = CommentsModel.chapterPage(
            chapterPage, including: rootPage, focusedRootID: 1001
        )
        #expect(chapterPage.comments.map(\.id) == [1001, 5000])
        #expect(chapterPage.totalPages == 4)
        #expect(chapterPage.totalComments == 30)

        let withoutDuplicate = CommentsModel.chapterPage(
            chapterPage, including: rootPage, focusedRootID: 1001
        )
        #expect(withoutDuplicate.comments.map(\.id) == [1001, 5000])
    }

    @Test func standaloneThreadParserFailsClosedWithoutAThread() {
        #expect(throws: AO3Error.self) {
            _ = try AO3Client.parseStandaloneCommentThread("<html><body>Unavailable</body></html>")
        }
    }

    /// Edit/Delete come straight from AO3's per-session markup — Edit only on
    /// the session's own comment, Delete also on others' comments on the
    /// session user's own works (work-owner moderation right). The UI is gated
    /// on these. Per otwarchive's `comments_helper.rb#can_edit_comment?`, AO3
    /// renders Edit only while the own comment has *zero replies* and isn't
    /// frozen — a replied-to comment loses Edit permanently, so "Delete shows
    /// but Edit doesn't" on the same comment is AO3 behavior the app must
    /// mirror, not a parsing bug. The fixture's own-comment action list mirrors
    /// markup captured live 2026-07-16: Edit/Delete as `data-remote` links
    /// (`/comments/<id>/edit`, `/comments/delete_comment?id=<id>`) plus a
    /// Freeze-Thread `button_to` form the parser must skip (it only reads
    /// anchors).
    @Test func exposesOnlyActionsAO3Rendered() throws {
        let page = try AO3Client.parseCommentsPage(fixture("ao3_comments_page"), page: 1)
        let guest = try #require(page.comments.first)
        #expect(guest.editPath == nil)
        #expect(guest.deletePath == nil)
        #expect(guest.canReply)

        let own = try #require(guest.replies.first)
        #expect(own.editPath == "/comments/1002/edit")
        #expect(own.deletePath == "/comments/delete_comment?id=1002")
        #expect(own.canReply)
        #expect(own.threadActionURL?.absoluteString == "https://archiveofourown.org/comments/1002")
        #expect(own.parentThreadURL?.absoluteString == "https://archiveofourown.org/comments/1001")
        // Drives native "Parent Thread" focus (scroll-to, not an AO3 web page).
        #expect(own.parentCommentID == 1001)
        #expect(guest.parentCommentID == nil)
    }

    @Test func replyActionDetectedFromAddCommentReplyHref() throws {
        // Full-work pages can vary label whitespace; the add_comment_reply path
        // is the durable signal that AO3 offered a Reply action.
        let html = """
        <div id="comments_placeholder">
          <ol class="thread">
            <li class="comment group" id="comment_42" role="article">
              <h4 class="heading byline"><a href="/users/A/pseuds/A">A</a></h4>
              <blockquote class="userstuff"><p>Hi</p></blockquote>
              <ul class="actions" id="navigation_for_comment_42">
                <li><a data-remote="true" href="/comments/add_comment_reply?chapter_id=9&amp;id=42&amp;view_full_work=true">  Reply  </a></li>
                <li><a href="/comments/42">Thread</a></li>
              </ul>
            </li>
          </ol>
        </div>
        """
        let page = try AO3Client.parseCommentsPage(html, page: 1)
        let comment = try #require(page.comments.first)
        #expect(comment.canReply)
        #expect(comment.threadPath == "/comments/42")
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

    /// Depth has to be *visible*. The previous card-based layout computed a
    /// `depth` for every reply and then never used it for layout, so a
    /// reply-to-a-reply rendered identically to a direct reply. Indent and rail
    /// colour are now the only things carrying that information.
    /// The indent depends on the container width and the text size, so a test has
    /// to pin both. 390pt is the canonical iPhone width the simulator gate uses.
    private func indent(
        _ depth: Int,
        width: CGFloat = 390,
        typeSize: DynamicTypeSize = .large
    ) -> CGFloat {
        CommentThreadGeometry.indent(
            forDepth: depth, availableWidth: width, typeSize: typeSize
        )
    }

    /// Width the indent may never eat into, for the pinned defaults above.
    private var indentBudget: CGFloat {
        390 - CommentThreadGeometry.sideMargin * 2
            - CommentThreadGeometry.minimumContentWidth(for: .large)
    }

    @Test func nestingDepthIsVisuallyDistinct() {
        // Indent grows per level...
        #expect(indent(0) == 0)
        #expect(indent(1) > indent(0))
        #expect(indent(2) > indent(1))

        // ...and then holds. AO3 does not cap reply nesting, so a deep chain would
        // otherwise indent itself off-screen — this must hold for absurd depths.
        #expect(indent(400) == indent(CommentThreadGeometry.threadsMaxIndentedDepth))

        // The content column survives that cap at any depth. Only the leading edge
        // is indented — cards sit beside each other rather than inside each other,
        // so nothing comes off the trailing edge to compound it.
        let content = 390 - CommentThreadGeometry.sideMargin * 2 - indent(400)
        #expect(content >= CommentThreadGeometry.minimumContentWidth(for: .large))

        // Adjacent levels must never share a rail colour, at any depth — that
        // colour is the only cue distinguishing two neighbouring levels once the
        // indent has been clamped.
        for depth in 0 ..< 40 {
            #expect(
                CommentThreadGeometry.railColor(forDepth: depth)
                    != CommentThreadGeometry.railColor(forDepth: depth + 1)
            )
        }
    }

    /// The connector drops from the parent's avatar centre and has to run *forward*
    /// into the reply's card. If the indent were ever narrower than that column, the
    /// elbow would double back on itself to reach the card it points at — which is
    /// exactly what a 30pt step did, and why this one is 48.
    @Test func indentClearsTheColumnTheConnectorDropsFrom() {
        let trunkOffsetInCard = CommentThreadGeometry.cardPadding
            + CommentThreadGeometry.avatarSize(forDepth: 0) / 2
        #expect(CommentThreadGeometry.threadsIndentStep > trunkOffsetInCard)

        // Restated end to end: a reply's leading edge sits right of its parent's
        // trunk at every level the indent actually steps.
        for depth in 1 ... CommentThreadGeometry.threadsMaxIndentedDepth {
            let trunk = indent(depth - 1) + CommentThreadGeometry.cardPadding
                + CommentThreadGeometry.avatarSize(forDepth: depth - 1) / 2
            #expect(indent(depth) > trunk)
        }
    }

    /// A thread line has to reach a reply whose parent is *not* the row directly
    /// above — separated from it by an earlier sibling's whole subtree. Every row
    /// in between has to be told to keep that ancestor's line running, or the line
    /// stops at the first nested card and the later sibling reads as unparented.
    ///
    /// Depth-first row order for root(A) with replies B and D, where B has a child
    /// C, is A, B, C, D — so D's connector has to survive two intervening rows.
    @Test func aLaterSiblingsLineIsCarriedPastTheSubtreeBetween() {
        let grandchild = AO3Comment(id: 3, author: "C", isGuest: false)
        var firstReply = AO3Comment(id: 2, author: "B", isGuest: false)
        firstReply.replies = [grandchild]
        let secondReply = AO3Comment(id: 4, author: "D", isGuest: false)
        var root = AO3Comment(id: 1, author: "A", isGuest: false)
        root.replies = [firstReply, secondReply]

        let rows = CommentConversationBuilder.rows(
            roots: [root],
            repliesByRoot: [root.id: CommentThreadGeometry.flattenedReplies(from: root)],
            expandedRootIDs: [],
            visibleReplyCounts: [:]
        )

        #expect(rows.map(\.depth) == [0, 1, 2, 1])
        #expect(rows.map(\.item.id) == ["post-1", "post-2", "post-3", "post-4"])

        // B has a peer still to come, so its own row runs the line past its card
        // rather than ending at it; D is last, so its row ends the line there.
        #expect(rows[1].isLastSibling == false)
        #expect(rows[3].isLastSibling == true)

        // C is the only row deep enough to need an *ancestor* line, and it must
        // request one for level 0 — that is the segment that carries the root's
        // line down past B's subtree to reach D.
        #expect(rows[2].ancestorLines == [true])
        #expect(rows[0].ancestorLines.isEmpty)
        #expect(rows[1].ancestorLines.isEmpty)
        #expect(rows[3].ancestorLines.isEmpty)

        // `nextDepth` drives where each enclosing card closes; a row's own card
        // closes exactly when nothing deeper follows it.
        #expect(rows.map(\.nextDepth) == [1, 2, 1, nil])

        // D is the one reply no connector reaches — C sits between it and its
        // parent — so it is the one row that names its parent in text. B and C
        // both follow their own parent directly, and a root has no parent.
        #expect(rows.map(\.showsParentAttribution) == [false, false, false, true])
    }

    /// A root with few *direct* replies but a deep subtree under them is the case
    /// the concept's own mock gets wrong: it gates "Continue thread" on
    /// `kids.length > 2`, so two replies carrying eight grandchildren show no
    /// affordance and the grandchildren vanish. The count has to be descendants.
    @Test func boundedListCountsDescendantsNotDirectChildren() {
        // Two direct replies; the first carries a chain of three more.
        var deep = AO3Comment(id: 5, author: "E", isGuest: false)
        for id in [4, 3] {
            var parent = AO3Comment(id: id, author: "N\(id)", isGuest: false)
            parent.replies = [deep]
            deep = parent
        }
        var firstReply = AO3Comment(id: 2, author: "B", isGuest: false)
        firstReply.replies = [deep]
        let secondReply = AO3Comment(id: 6, author: "F", isGuest: false)
        var root = AO3Comment(id: 1, author: "A", isGuest: false)
        root.replies = [firstReply, secondReply]

        let replies = CommentThreadGeometry.flattenedReplies(from: root)
        #expect(replies.count == 5)
        #expect(root.replies.count == 2)

        let items = CommentConversationBuilder.boundedItems(root: root, replies: replies)

        // Root + both direct replies + the continue row. Nothing deeper is drawn.
        #expect(items.count == 4)
        #expect(items.compactMap(\.actionableComment).map(\.id) == [1, 2, 6])

        guard case let .continueThread(rootID, hiddenCount) = items[3] else {
            Issue.record("expected a Continue thread row, got \(items[3])")
            return
        }
        #expect(rootID == 1)
        // Five descendants, two shown — three hidden. Counting direct children
        // would have given zero and dropped the row entirely.
        #expect(hiddenCount == 3)
    }

    /// Only a root that has replies gets a caret, and it must report every
    /// descendant it would reveal — "Show 2" on a thread that opens to five rows
    /// is a promise the reader catches being broken.
    @Test func onlyRootsWithRepliesOfferCollapse() {
        var reply = AO3Comment(id: 2, author: "B", isGuest: false)
        reply.replies = [AO3Comment(id: 3, author: "C", isGuest: false)]
        var root = AO3Comment(id: 1, author: "A", isGuest: false)
        root.replies = [reply]
        let childless = AO3Comment(id: 4, author: "D", isGuest: false)

        let repliesByRoot = [
            root.id: CommentThreadGeometry.flattenedReplies(from: root),
            childless.id: CommentThreadGeometry.flattenedReplies(from: childless),
        ]
        let rows = CommentConversationBuilder.rows(
            roots: [root, childless],
            repliesByRoot: repliesByRoot,
            expandedRootIDs: [], visibleReplyCounts: [:]
        )

        #expect(rows[0].collapse == CommentCollapseState(isCollapsed: false, replyCount: 2))
        // Replies never carry their own caret, and a childless root has nothing
        // to fold.
        #expect(rows.dropFirst().allSatisfy { $0.collapse == nil })

        // Folded, the conversation is one row — and the caret says what it hides.
        let collapsed = CommentConversationBuilder.rows(
            roots: [root], repliesByRoot: repliesByRoot,
            expandedRootIDs: [], visibleReplyCounts: [:], collapsedRootIDs: [root.id]
        )
        #expect(collapsed.count == 1)
        #expect(collapsed[0].collapse?.label == "Show 2")
    }

    /// A negative depth can only come from a bug upstream, but it must not crash
    /// the palette lookup or produce a negative indent.
    @Test func negativeDepthIsClamped() {
        #expect(indent(-3) == 0)
        #expect(CommentThreadGeometry.railColor(forDepth: -3) == CommentThreadGeometry.railColor(forDepth: 0))
    }

    @Test func commentBodyStaysClampedToFiveLines() {
        #expect(CommentThreadGeometry.collapsedBodyLineLimit == 5)
    }

    /// Expanding renders every descendant, so the collapse threshold must count
    /// them all — a single direct reply carrying a long chain still collapses.
    @Test func collapseThresholdCountsEveryReplyNotJustDirectChildren() {
        var chain = AO3Comment(id: 100, author: "Deep", isGuest: false)
        for id in stride(from: 99, through: 90, by: -1) {
            var parent = AO3Comment(id: id, author: "N", isGuest: false)
            parent.replies = [chain]
            chain = parent
        }
        var root = AO3Comment(id: 1, author: "Root", isGuest: false)
        root.replies = [chain]

        // Only one direct child, but eleven replies actually render.
        #expect(root.replies.count == 1)
        let flat = CommentThreadGeometry.flattenedReplies(from: root)
        #expect(flat.count == 11)
        #expect(flat.count > CommentThreadGeometry.autoExpandedMaxReplies)
        #expect(CommentThreadGeometry.autoExpandedMaxReplies == 8)
    }

    /// AO3 doesn't cap nesting depth: the traversals must not recurse per level.
    @Test func deepReplyChainsFlattenWithoutRecursion() {
        var node = AO3Comment(id: 2000, author: "Deep", isGuest: false)
        for id in stride(from: 1999, through: 1, by: -1) {
            var parent = AO3Comment(id: id, author: "N", isGuest: false)
            parent.replies = [node]
            node = parent
        }

        #expect(node.flattened.count == 2000)
        #expect(node.descendantCount == 2000)
        #expect(node.contains(commentID: 2000))
        #expect(!node.contains(commentID: 2001))

        let flat = CommentThreadGeometry.flattenedReplies(from: node)
        #expect(flat.count == 1999)
        #expect(flat.last?.depth == 1999)
    }

    @Test func flattenedRepliesAreOneCardPerReplyDepthFirst() {
        var grandchild = AO3Comment(id: 3, author: "G", isGuest: false)
        grandchild.replies = [AO3Comment(id: 4, author: "GG", isGuest: false)]
        var first = AO3Comment(id: 2, author: "R1", isGuest: false)
        first.replies = [grandchild]
        let second = AO3Comment(id: 5, author: "R2", isGuest: false)
        var root = AO3Comment(id: 1, author: "Root", isGuest: false)
        root.replies = [first, second]

        let flat = CommentThreadGeometry.flattenedReplies(from: root)
        #expect(flat.map(\.id) == [2, 3, 4, 5])
        #expect(flat.map(\.depth) == [1, 2, 3, 1])
        // Root itself is not a nested reply card.
        #expect(!flat.contains { $0.id == 1 })
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

    /// A deleted comment whose replies survive renders as a placeholder `li` with
    /// the comment id but no byline/body/actions (observed live 2026-07-10 on a
    /// heavily-commented work). It must parse as a tombstone that KEEPS its
    /// replies — returning nil would graft them onto the preceding sibling.
    @Test func deletedCommentParsesAsTombstoneAndKeepsItsReplies() throws {
        let html = """
        <html><body><div id="comments_placeholder"><ol class="thread">
          <li class="comment group odd" id="comment_1">
            <h4 class="heading byline"><a href="/users/First/pseuds/First">First</a></h4>
            <blockquote class="userstuff"><p>Still here.</p></blockquote>
          </li>
          <li class="comment group even" id="comment_2">
            <p>
              (Previous comment deleted.)
            </p>
          </li>
          <li>
            <ol class="thread">
              <li class="comment group odd" id="comment_3">
                <h4 class="heading byline"><a href="/users/Reply/pseuds/Reply">Reply</a></h4>
                <blockquote class="userstuff"><p>Replying to the deleted one.</p></blockquote>
              </li>
            </ol>
          </li>
        </ol></div></body></html>
        """
        let page = try AO3Client.parseCommentsPage(html, page: 1)
        #expect(page.comments.map(\.id) == [1, 2])

        let tombstone = try #require(page.comments.last)
        #expect(tombstone.isDeleted)
        #expect(tombstone.author.isEmpty)
        #expect(tombstone.bodyText == "(Previous comment deleted.)")
        #expect(!tombstone.canReply)
        #expect(tombstone.editPath == nil && tombstone.deletePath == nil)
        // The surviving reply hangs under the tombstone, not under comment 1.
        #expect(tombstone.replies.map(\.id) == [3])
        #expect(page.comments.first?.replies.isEmpty == true)
    }

    /// CAA-7: past depth 5 with more than one child, otwarchive stops
    /// rendering the subtree and substitutes a single id-less
    /// `<li class="comment"><p>(<a href="/comments/<id>">N more comments in
    /// this thread</a>)</p></li>`. Two independent cutoffs on one page must
    /// each parse as their own distinct, stable, non-`isDeleted` node with
    /// their count/link preserved — not collide onto the shared "(This
    /// comment couldn't be read.)" tombstone identity the generic id-less
    /// fallback previously gave every such node.
    @Test func deepThreadCutoffsParseAsDistinctNonCollidingNodes() throws {
        let html = """
        <html><body><div id="comments_placeholder"><ol class="thread">
          <li class="comment" id="comment_1">
            <h4 class="heading byline"><a href="/users/First/pseuds/First">First</a></h4>
            <blockquote class="userstuff"><p>Root one.</p></blockquote>
          </li>
          <li>
            <ol class="thread">
              <li class="comment" id="comment_2">
                <h4 class="heading byline"><a href="/users/Second/pseuds/Second">Second</a></h4>
                <blockquote class="userstuff"><p>Reply one.</p></blockquote>
              </li>
              <li>
                <ol class="thread">
                  <li class="comment">
                    <p>(<a href="/comments/9001">3 more comments in this thread</a>)</p>
                  </li>
                </ol>
              </li>
            </ol>
          </li>
          <li class="comment" id="comment_3">
            <h4 class="heading byline"><a href="/users/Third/pseuds/Third">Third</a></h4>
            <blockquote class="userstuff"><p>Root two.</p></blockquote>
          </li>
          <li>
            <ol class="thread">
              <li class="comment" id="comment_4">
                <h4 class="heading byline"><a href="/users/Fourth/pseuds/Fourth">Fourth</a></h4>
                <blockquote class="userstuff"><p>Reply two.</p></blockquote>
              </li>
              <li>
                <ol class="thread">
                  <li class="comment">
                    <p>(<a href="/comments/9002">7 more comments in this thread</a>)</p>
                  </li>
                </ol>
              </li>
            </ol>
          </li>
        </ol></div></body></html>
        """
        let page = try AO3Client.parseCommentsPage(html, page: 1)
        #expect(page.comments.map(\.id) == [1, 3])

        let replyOne = try #require(page.comments.first?.replies.first)
        let cutoffA = try #require(replyOne.replies.first)
        let replyTwo = try #require(page.comments.last?.replies.first)
        let cutoffB = try #require(replyTwo.replies.first)

        // Distinct, stable, always-negative identity — never the shared
        // empty-id hash both would have collided onto before this fix.
        #expect(cutoffA.id != cutoffB.id)
        #expect(cutoffA.id < 0 && cutoffB.id < 0)

        // Neither is misclassified as a deleted-comment tombstone.
        #expect(!cutoffA.isDeleted && !cutoffB.isDeleted)
        #expect(cutoffA.isThreadCutoff && cutoffB.isThreadCutoff)

        // Count and continuation link survive instead of being discarded.
        #expect(cutoffA.cutoffCount == 3)
        #expect(cutoffB.cutoffCount == 7)
        #expect(cutoffA.cutoffThreadPath == "/comments/9001")
        #expect(cutoffB.cutoffThreadPath == "/comments/9002")
        #expect(cutoffA.cutoffThreadURL?.absoluteString == "https://archiveofourown.org/comments/9001")
        #expect(cutoffB.cutoffThreadURL?.absoluteString == "https://archiveofourown.org/comments/9002")

        // A cutoff has no replies of its own — AO3 collapsed the rest.
        #expect(cutoffA.replies.isEmpty && cutoffB.replies.isEmpty)

        // Stable across re-parses of the same page (not process-random).
        let reparsed = try AO3Client.parseCommentsPage(html, page: 1)
        let reparsedCutoffA = try #require(reparsed.comments.first?.replies.first?.replies.first)
        #expect(reparsedCutoffA.id == cutoffA.id)
    }

    // MARK: Avatars

    /// AO3 serves its own logo (`/images/skins/iconsets/...`) as the icon for any
    /// account without an uploaded one. Presenting that as a user's profile picture
    /// would be using AO3's trademark, so it must resolve to nil and fall back to
    /// the app's generic placeholder. Real icons come from Rails ActiveStorage.
    @Test func ao3sOwnDefaultIconIsNeverUsedAsAnAvatar() {
        let defaultIcon = "/images/skins/iconsets/default/icon_user.png"
        #expect(AO3Comment.avatarURL(forIconSource: defaultIcon) == nil)
        // Also when AO3 renders it absolute rather than root-relative.
        #expect(AO3Comment.avatarURL(
            forIconSource: "https://archiveofourown.org" + defaultIcon
        ) == nil)
        // Any other bundled skin asset is AO3 artwork too, whatever the iconset.
        #expect(AO3Comment.avatarURL(
            forIconSource: "/images/skins/iconsets/night/icon_user.png"
        ) == nil)
        #expect(AO3Comment.avatarURL(forIconSource: nil) == nil)
        #expect(AO3Comment.avatarURL(forIconSource: "") == nil)

        // A real uploaded icon survives untouched.
        let uploaded = "https://archiveofourown.org/rails/active_storage/representations/proxy/abc/IMG_5719.JPG"
        #expect(AO3Comment.avatarURL(forIconSource: uploaded)?.absoluteString == uploaded)
        // An icon served off-site is not AO3 artwork either.
        let offsite = "https://s3.amazonaws.com/otw-ao3-icons/user/1.png"
        #expect(AO3Comment.avatarURL(forIconSource: offsite)?.absoluteString == offsite)
        // A lookalike host must not be mistaken for AO3.
        let lookalike = "https://notarchiveofourown.org/images/skins/iconsets/default/icon_user.png"
        #expect(AO3Comment.avatarURL(forIconSource: lookalike)?.absoluteString == lookalike)
    }

    /// End-to-end: the default icon is dropped while a sibling's real icon is kept.
    @Test func parsingDropsDefaultIconButKeepsUploadedOne() throws {
        let uploaded = "https://archiveofourown.org/rails/active_storage/proxy/abc/IMG_5719.JPG"
        let html = """
        <html><body><div id="comments_placeholder"><ol class="thread">
          <li class="comment" id="comment_1">
            <h4 class="heading byline"><a href="/users/Nia/pseuds/Nia">Nia</a></h4>
            <div class="icon"><img alt="" class="icon" src="/images/skins/iconsets/default/icon_user.png" /></div>
            <blockquote class="userstuff"><p>No icon uploaded.</p></blockquote>
          </li>
          <li class="comment" id="comment_2">
            <h4 class="heading byline"><a href="/users/Ben/pseuds/Ben">Ben</a></h4>
            <div class="icon"><img alt="" class="icon" src="\(uploaded)" /></div>
            <blockquote class="userstuff"><p>Has an icon.</p></blockquote>
          </li>
        </ol></div></body></html>
        """
        let page = try AO3Client.parseCommentsPage(html, page: 1)
        #expect(page.comments.count == 2)
        #expect(page.comments[0].author == "Nia")
        #expect(page.comments[0].avatarURL == nil)
        #expect(page.comments[1].author == "Ben")
        #expect(page.comments[1].avatarURL?.absoluteString == uploaded)
    }

    @Test func recognizedEmptyCommentsPageParsesAsEmpty() throws {
        let page = try AO3Client.parseCommentsPage(fixture("ao3_comments_empty"), page: 1)
        #expect(page.comments.isEmpty)
        #expect(page.totalComments == 0)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 1)
    }

    @Test func missingCommentsRegionThrowsParse() {
        #expect(throws: AO3Error.self) {
            try AO3Client.parseCommentsPage("<html><body>No comments UI.</body></html>", page: 2)
        }
    }

    @Test func placeholderWithoutTopThreadThrowsParse() {
        #expect(throws: AO3Error.self) {
            try AO3Client.parseCommentsPage(
                "<html><body><div id='comments_placeholder'></div></body></html>", page: 1
            )
        }
    }

    @Test func nestedThreadFragmentDoesNotCountAsTheTopThread() {
        #expect(throws: AO3Error.self) {
            try AO3Client.parseCommentsPage("""
            <html><body><div id="comments_placeholder"><div>
              <ol class="thread"><li class="comment" id="comment_1"></li></ol>
            </div></div></body></html>
            """, page: 1)
        }
    }

    @Test func unexpectedRowDoesNotCountAsAnEmptyTopThread() {
        #expect(throws: AO3Error.self) {
            try AO3Client.parseCommentsPage("""
            <html><body><div id="comments_placeholder">
              <ol class="thread"><li class="notice">Comments unavailable.</li></ol>
            </div></body></html>
            """, page: 1)
        }
    }

    @Test func loginPageIsAuthenticationRequiredNotEmpty() throws {
        do {
            _ = try AO3Client.parseCommentsPage(fixture("ao3_logged_out"), page: 1)
            Issue.record("expected the AO3 login page to require authentication")
        } catch AO3Error.authenticationRequired {
            // Expected: a restricted-work login bounce is not an empty thread.
        } catch {
            Issue.record("expected authenticationRequired, got \(error)")
        }
    }

    @Test func maintenancePageThrowsParse() {
        #expect(throws: AO3Error.self) {
            try AO3Client.parseCommentsPage("""
            <html><body><h1>Archive Down for Maintenance</h1></body></html>
            """, page: 1)
        }
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
        // Date only past yesterday: an archive comment's minute and zone are
        // noise, and the recent cases above still carry a time.
        ) == "Jul 7, 2026")
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

    @Test func emptyChapterIndexIsRecognized() throws {
        let chapters = try AO3Client.parseChapterIndex(
            "<html><body><ol class='chapter index group'></ol></body></html>"
        )
        #expect(chapters.isEmpty)
    }

    @Test func missingChapterIndexThrowsParse() {
        #expect(throws: AO3Error.self) {
            try AO3Client.parseChapterIndex("<html><body>No chapter index.</body></html>")
        }
    }

    @Test func chapterIndexLoginPageRequiresAuthentication() throws {
        do {
            _ = try AO3Client.parseChapterIndex(fixture("ao3_logged_out"))
            Issue.record("expected the AO3 login page to require authentication")
        } catch AO3Error.authenticationRequired {
            // Expected.
        } catch {
            Issue.record("expected authenticationRequired, got \(error)")
        }
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
        mine.userPath = "/users/reader/pseuds/Reader"
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
        reply.userPath = "/users/reader/pseuds/Reader"
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

    @Test func verificationUsesCanonicalUsernameNotDisplayedPseud() {
        var mine = AO3Comment(id: 2, author: "NightPseud", isGuest: false)
        mine.userPath = "/users/Reader/pseuds/NightPseud"
        mine.bodyText = "Made it!"
        #expect(AO3AuthService.commentVerification(
            in: pageWith([mine]), username: "reader", submittedBody: "Made it!",
            parentID: nil
        ) == .found)

        mine.userPath = "/users/SomeoneElse/pseuds/NightPseud"
        #expect(AO3AuthService.commentVerification(
            in: pageWith([mine]), username: "reader", submittedBody: "Made it!",
            parentID: nil
        ) == .absent)
    }

    @Test func anonymousCreatorMatchIsUnknown() {
        var anonymous = AO3Comment(id: 2, author: "Anonymous Creator", isGuest: false)
        anonymous.isAnonymousCreator = true
        anonymous.bodyText = "Made it!"
        #expect(AO3AuthService.commentVerification(
            in: pageWith([anonymous]), username: "reader", submittedBody: "Made it!",
            parentID: nil
        ) == .unknown)
    }

    @Test func transformedRichBodyMissesStayUnknownButPlainHeartCanMatch() {
        var mine = AO3Comment(id: 2, author: "Reader", isGuest: false)
        mine.userPath = "/users/reader/pseuds/Reader"
        mine.bodyText = "hello"
        #expect(AO3AuthService.commentVerification(
            in: pageWith([mine]), username: "reader", submittedBody: "<em>hello</em>",
            parentID: nil
        ) == .unknown)

        mine.bodyText = "Tom & Jerry"
        #expect(AO3AuthService.commentVerification(
            in: pageWith([mine]), username: "reader", submittedBody: "Tom &amp; Jerry",
            parentID: nil
        ) == .unknown)

        mine.bodyText = "Loved it <3"
        #expect(AO3AuthService.commentVerification(
            in: pageWith([mine]), username: "reader", submittedBody: "Loved it <3",
            parentID: nil
        ) == .found)
    }

    @Test func moderatedTopLevelMissIsUnknownButAVisibleMatchStillWins() {
        #expect(AO3AuthService.commentVerification(
            in: pageWith([]), username: "reader", submittedBody: "Made it!",
            parentID: nil, commentMayBeHidden: true
        ) == .unknown)

        var mine = AO3Comment(id: 2, author: "Reader", isGuest: false)
        mine.userPath = "/users/reader/pseuds/Reader"
        mine.bodyText = "Made it!"
        #expect(AO3AuthService.commentVerification(
            in: pageWith([mine]), username: "reader", submittedBody: "Made it!",
            parentID: nil, commentMayBeHidden: true
        ) == .found)
    }

    @Test func moderatedReplyMissIsUnknownButAVisibleMatchStillWins() {
        var parent = AO3Comment(id: 5, author: "Other", isGuest: false)
        #expect(AO3AuthService.commentVerification(
            in: pageWith([parent]), username: "reader", submittedBody: "Made it!",
            parentID: 5, commentMayBeHidden: true
        ) == .unknown)

        var mine = AO3Comment(id: 9, author: "Reader", isGuest: false)
        mine.userPath = "/users/reader/pseuds/Reader"
        mine.bodyText = "Made it!"
        parent.replies = [mine]
        #expect(AO3AuthService.commentVerification(
            in: pageWith([parent]), username: "reader", submittedBody: "Made it!",
            parentID: 5, commentMayBeHidden: true
        ) == .found)
    }

    @Test func matchingReplyCannotVerifyAMissingTopLevelComment() {
        var reply = AO3Comment(id: 9, author: "Reader", isGuest: false)
        reply.userPath = "/users/reader/pseuds/Reader"
        reply.bodyText = "Made it!"
        var parent = AO3Comment(id: 5, author: "Other", isGuest: false)
        parent.replies = [reply]

        #expect(AO3AuthService.commentVerification(
            in: pageWith([parent]), username: "reader", submittedBody: "Made it!",
            parentID: nil
        ) == .absent)
    }

    // MARK: T91-RF1 — exact reply verification endpoint

    /// A reply's verification plan must always be the exact parent thread,
    /// never a work-comments page number — regardless of which page the
    /// parent happens to be modeled/rendered on.
    @Test func replyVerificationPlanIsAlwaysTheStandaloneParentThread() {
        // Parent modeled as living on work-comments page 5: the plan must
        // still resolve to the standalone thread, not a page guess.
        let onPageFive = AO3CommentContext(workID: 42, chapterID: nil, parentCommentID: 555)
        #expect(
            AO3AuthService.verificationPlan(for: onPageFive)
                == .standaloneThread(parentCommentID: 555)
        )

        // Chapter-scoped replies are no exception — the parent thread endpoint
        // doesn't take a chapter or page parameter at all.
        let chapterScoped = AO3CommentContext(workID: 42, chapterID: 7, parentCommentID: 9)
        #expect(
            AO3AuthService.verificationPlan(for: chapterScoped)
                == .standaloneThread(parentCommentID: 9)
        )
    }

    @Test func topLevelVerificationPlanIsWorkComments() {
        let topLevel = AO3CommentContext(workID: 42, chapterID: nil, parentCommentID: nil)
        #expect(AO3AuthService.verificationPlan(for: topLevel) == .workComments(workID: 42))
    }

    /// Regression for the exact repro in the finding: a reply's parent thread
    /// lives on work-comments page 5 and would be absent from page 1. Proves
    /// (via the plan) that verification never consults a work-comments page
    /// for a reply, so this scenario cannot false-negative into `.absent`.
    @Test func pageOneLackingTheReplyCannotBeConsultedForAReplyVerification() {
        let context = AO3CommentContext(workID: 42, chapterID: nil, parentCommentID: 555)
        guard case .standaloneThread = AO3AuthService.verificationPlan(for: context) else {
            Issue.record("reply verification must never plan a work-comments page fetch")
            return
        }
    }

    /// The standalone thread response — one root comment (the parent) with its
    /// direct replies — must find a reply actually present there, exactly the
    /// shape `AO3Client.commentThreadPage`/`parseStandaloneCommentThread` return.
    @Test func standaloneThreadContainingTheReplyIsFound() {
        var reply = AO3Comment(id: 1000, author: "Reader", isGuest: false)
        reply.userPath = "/users/reader/pseuds/Reader"
        reply.bodyText = "Made it!"
        var parent = AO3Comment(id: 555, author: "Other", isGuest: false)
        parent.replies = [reply]
        let standaloneThreadPage = AO3CommentsPage(comments: [parent], currentPage: 1, totalPages: 1)

        #expect(AO3AuthService.containsComment(
            in: standaloneThreadPage, author: "Reader", normalizedBody: "Made it!", parentID: 555
        ))
    }

    // MARK: T91-RF1 — timing evidence

    @Test func timingToleranceAcceptsAGenuineMatchDespiteClockSkew() throws {
        var reply = AO3Comment(id: 1000, author: "Reader", isGuest: false)
        reply.userPath = "/users/reader/pseuds/Reader"
        reply.bodyText = "Made it!"
        reply.postedAt = try #require(
            AO3CommentTimestamp.parse("Mon 13 Jul 2026 12:00PM UTC")
        )
        var parent = AO3Comment(id: 555, author: "Other", isGuest: false)
        parent.replies = [reply]
        let page = pageWith([parent])

        // The POST attempt started a couple of minutes "after" the (minute-
        // granularity, clock-skewed) posted time AO3 reports — must still match.
        let submittedAt = reply.postedAt!.addingTimeInterval(120)
        #expect(AO3AuthService.containsComment(
            in: page, author: "Reader", normalizedBody: "Made it!", parentID: 555,
            postedAfter: submittedAt
        ))
    }

    @Test func timingDisagreementStaysUnknown() throws {
        var oldReply = AO3Comment(id: 1000, author: "Reader", isGuest: false)
        oldReply.userPath = "/users/reader/pseuds/Reader"
        oldReply.bodyText = "Made it!"
        oldReply.postedAt = try #require(
            AO3CommentTimestamp.parse("Mon 01 Jun 2026 12:00PM UTC")
        )
        var parent = AO3Comment(id: 555, author: "Other", isGuest: false)
        parent.replies = [oldReply]
        let page = pageWith([parent])

        // This attempt started weeks after that old reply — an identical
        // author/parent/body match that old cannot be proof THIS one landed.
        let submittedAt = Date(timeIntervalSince1970: 1_784_000_000) // 2026-07-13ish
        #expect(AO3AuthService.commentVerification(
            in: page, username: "Reader", submittedBody: "Made it!", parentID: 555,
            postedAfter: submittedAt
        ) == .unknown)
    }

    @Test func timingCheckIsSkippedWhenPostedAtDidNotParse() {
        var reply = AO3Comment(id: 1000, author: "Reader", isGuest: false)
        reply.userPath = "/users/reader/pseuds/Reader"
        reply.bodyText = "Made it!"
        reply.postedAt = nil // unparseable timestamp on this comment
        var parent = AO3Comment(id: 555, author: "Other", isGuest: false)
        parent.replies = [reply]
        let page = pageWith([parent])

        #expect(AO3AuthService.containsComment(
            in: page, author: "Reader", normalizedBody: "Made it!", parentID: 555,
            postedAfter: Date()
        ))
    }
}
