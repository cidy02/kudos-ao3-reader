import Foundation
import Testing
@testable import Kudos

/// 1cd (C2-1, C2-3, C2-7): what the moderation screen says and posts.
struct CollectionModerationCopyTests {

    @Test func declineConfirmationNamesTheParticipant() {
        #expect(CollectionModerationCopy.declineTitle(participant: "WriterName (alice)")
            == "Decline WriterName (alice)?")
    }

    @Test func recentlyDecidedStartsOnApproved() {
        #expect(AO3CollectionItemsView.startingTab(slug: "fest", initialTab: .approved) == .approved)
        #expect(AO3CollectionItemsView.startingTab(slug: "fest", initialTab: nil) == .unreviewed)
    }

    @Test func reviewTallyLabelsAPagedQueueAsThisPage() {
        #expect(CollectionModerationCopy.reviewTally(count: 4, page: 1, totalPages: 1) == "4 works awaiting review")
        #expect(CollectionModerationCopy.reviewTally(count: 1, page: 1, totalPages: 1) == "1 work awaiting review")
        #expect(CollectionModerationCopy.reviewTally(count: 20, page: 2, totalPages: 3)
            == "20 works awaiting review on this page · page 2 of 3")
    }

    @Test func anEmptiedPageMovesToTheNearestPageAO3StillHas() {
        // Later items move up, so a middle page survives; the last page does not.
        #expect(CollectionModerationCopy.pageAfterEmptying(page: 2, totalPages: 3) == 2)
        #expect(CollectionModerationCopy.pageAfterEmptying(page: 3, totalPages: 3) == 2)
        #expect(CollectionModerationCopy.pageAfterEmptying(page: 1, totalPages: 1) == 1)
    }

    @Test func bylineAddsTheSubmissionDateOnlyWhenAO3PrintedOne() {
        #expect(CollectionModerationCopy.byline(creator: "kestrelmoon", dateText: "03 Nov 2026")
            == "kestrelmoon · submitted 03 Nov 2026")
        #expect(CollectionModerationCopy.byline(creator: "kestrelmoon", dateText: "  ") == "kestrelmoon")
    }

    /// otwarchive Q6: the item form permits approval/unrevealed/anonymous/remove
    /// and nothing else, so a rejection is the approval status alone.
    @Test func aRejectionPostsOnlyTheApprovalField() {
        let draft = AO3CollectionItemDraft(itemID: 7, moderatorApproval: .rejected)
        let params = AO3Client.collectionItemParameters(draft, csrf: "t", methodOverride: "patch")
        #expect(params.map(\.0) == ["authenticity_token", "_method", "collection_items[7][collection_approval_status]"])
        #expect(params.last?.1 == "rejected")
    }

    /// The review queue's own pager, which the screen now keeps.
    @Test func theReviewQueueKeepsAO3sPageCount() throws {
        let html = """
        <html><body>
        <form action="/collections/fest/items/update_multiple" method="post">
          <input type="hidden" name="authenticity_token" value="csrf-item">
          <input type="hidden" name="_method" value="patch">
          <ul class="index group">
            <li class="collection item picture blurb group">
              <div class="header module">
                <h4 class="heading" id="collection_item_42"><a href="/works/99">Queued Work</a></h4>
                <h5 class="heading">Creator Pseud (Member)</h5>
              </div>
              <ul class="actions"><li class="collection status">
                <select name="collection_items[42][collection_approval_status]">
                  <option value="unreviewed" selected></option><option value="approved">Approved</option>
                  <option value="rejected">Rejected</option>
                </select></li></ul>
            </li>
          </ul>
        </form>
        <ol class="pagination actions"><li><span class="current">2</span></li>
          <li><a href="/collections/fest/items?page=3">3</a></li></ol>
        </body></html>
        """
        let page = try AO3Client.parseCollectionItemsPage(html, slug: "fest", tab: .unreviewed, page: 2)
        #expect(page.currentPage == 2)
        #expect(page.totalPages == 3)
    }
}
