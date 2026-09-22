import Foundation
import Testing
@testable import Kudos

/// The two collection-items pages do not share a default tab. These tests pin
/// the URL AO3 actually filters on, not the tab value we started from.
struct AO3CollectionItemsScopeTests {
    @Test func collectionDefaultOmitsStatusAndAccountAwaitingCollectionDoesNot() {
        let collection = AO3CollectionURL.items(slug: "fest", tab: .unreviewed, page: 1)
        #expect(collection.query == nil)
        #expect(collection.path == "/collections/fest/items")

        let account = AO3CollectionURL.userItems(username: "ada", tab: .unreviewed, page: 1)
        #expect(account?.path == "/users/ada/collection_items")
        #expect(account?.absoluteString.contains("status=unreviewed_by_collection") == true)
        #expect(
            account?.path.hasSuffix("/\(AO3MoreOnAO3Route.collectionItems)") == true
        )
    }

    @Test func accountAwaitingYouOmitsStatusAndCollectionAwaitingYouDoesNot() {
        let account = AO3CollectionURL.userItems(username: "ada", tab: .invited, page: 1)
        #expect(account?.query == nil)
        #expect(account?.path == "/users/ada/collection_items")

        let collection = AO3CollectionURL.items(slug: "fest", tab: .invited, page: 1)
        #expect(collection.absoluteString.contains("status=unreviewed_by_user"))
    }

    @Test func accountPageTwoKeepsTheTabAndThePage() {
        let awaiting = AO3CollectionURL.userItems(username: "ada", tab: .unreviewed, page: 2)
        #expect(awaiting?.absoluteString.contains("status=unreviewed_by_collection") == true)
        #expect(awaiting?.absoluteString.contains("page=2") == true)

        let yours = AO3CollectionURL.userItems(username: "ada", tab: .invited, page: 2)
        #expect(yours?.absoluteString.contains("status=") == false)
        #expect(yours?.absoluteString.contains("page=2") == true)
    }

    @Test func userItemsRejectsABlankOrSlashedLogin() {
        #expect(AO3CollectionURL.userItems(username: " ", tab: .approved, page: 1) == nil)
        #expect(AO3CollectionURL.userItems(username: "a/b", tab: .approved, page: 1) == nil)
        #expect(AO3CollectionURL.userItemsUpdateMultiple(username: "ada")?.path
            == "/users/ada/collection_items/update_multiple")
    }

    @Test func aDisabledCreatorApprovalIsNotWhatGetsPosted() {
        var item = sampleItem()
        item.creatorApprovalIsEditable = false
        let draft = AO3CollectionItemDraft(
            itemID: item.id,
            creatorApproval: .approved,
            moderatorApproval: .rejected,
            isUnrevealed: true,
            isAnonymous: nil,
            remove: false
        )
        let stored = AO3CollectionItemSubmission.draftAO3WillStore(draft, item: item)
        #expect(AO3CollectionItemSubmission.isSubmittable(stored))
        let names = AO3Client.collectionItemParameters(stored, csrf: "t", methodOverride: "patch")
            .map(\.0)
        #expect(!names.contains("collection_items[7][user_approval_status]"))
        #expect(names.contains("collection_items[7][collection_approval_status]"))
        #expect(names.contains("collection_items[7][unrevealed]"))
    }

    @Test func accountPageDropsMaintainerFieldsAndKeepsCreatorApprovalAndRemoval() {
        var item = sampleItem()
        item.moderatorApprovalIsEditable = false
        item.unrevealedIsEditable = false
        item.anonymousIsEditable = false
        let draft = AO3CollectionItemDraft(
            itemID: item.id,
            creatorApproval: .approved,
            moderatorApproval: .rejected,
            isUnrevealed: true,
            isAnonymous: true,
            remove: true
        )
        let stored = AO3CollectionItemSubmission.draftAO3WillStore(draft, item: item)
        #expect(stored.remove)
        #expect(stored.creatorApproval == .approved)
        #expect(stored.moderatorApproval == nil)
        #expect(stored.isUnrevealed == nil)
        #expect(stored.isAnonymous == nil)
        let names = AO3Client.collectionItemParameters(stored, csrf: "t", methodOverride: nil)
            .map(\.0)
        #expect(names.contains("collection_items[7][user_approval_status]"))
        #expect(names.contains("collection_items[7][remove]"))
        #expect(!names.contains("collection_items[7][collection_approval_status]"))
        #expect(!names.contains("collection_items[7][unrevealed]"))
        #expect(!names.contains("collection_items[7][anonymous]"))
    }

    @Test func aCreatorOnlyEditOnALockedCreatorControlIsNotSubmittable() {
        var item = sampleItem()
        item.creatorApprovalIsEditable = false
        let draft = AO3CollectionItemDraft(itemID: item.id, creatorApproval: .rejected)
        let stored = AO3CollectionItemSubmission.draftAO3WillStore(draft, item: item)
        #expect(!AO3CollectionItemSubmission.isSubmittable(stored))
    }

    @Test func decisionPhraseCountsWaitingRowsAndDoesNotInventZero() {
        var waiting = sampleItem()
        waiting.creatorApproval = .unreviewed
        waiting.moderatorApproval = .approved
        var settled = sampleItem()
        settled.id = 8
        settled.creatorApproval = .approved
        settled.moderatorApproval = .approved
        #expect(AO3CollectionItemSubmission.decisionsNeeded([waiting, settled]) == 1)
        #expect(AO3CollectionItemSubmission.decisionPhrase(for: 0) == nil)
        #expect(AO3CollectionItemSubmission.decisionPhrase(for: 1) == "1 needs a decision")
        #expect(AO3CollectionItemSubmission.decisionPhrase(for: 3) == "3 need a decision")
    }

    @Test func cardEyebrowAndMetaUseOnlyBlurbFacts() {
        #expect(AO3CollectionCardCopy.eyebrow(
            viewerIsOwner: true, maintainerNames: ["Ada"], byline: "Ada"
        ) == "You moderate")
        #expect(AO3CollectionCardCopy.eyebrow(
            viewerIsOwner: false, maintainerNames: ["Ada", "Bea"], byline: ""
        ) == "Ada")
        #expect(AO3CollectionCardCopy.eyebrow(
            viewerIsOwner: false, maintainerNames: [], byline: " kept "
        ) == "kept")

        let facts = AO3CollectionCardCopy.metaFacts(
            worksCount: 12,
            bookmarksCount: nil,
            isModerated: true,
            isClosed: false,
            isUnrevealed: false,
            challengeName: nil
        )
        #expect(facts == ["12 works", "Moderated"])
        #expect(facts.allSatisfy { !$0.localizedCaseInsensitiveContains("await") })
        #expect(facts.allSatisfy { !$0.localizedCaseInsensitiveContains("your work") })
    }

    private func sampleItem() -> AO3CollectionItem {
        AO3CollectionItem(
            id: 7,
            collectionSlug: "fest",
            collectionTitle: "Fest",
            workTitle: "Queued",
            userApprovalField: "collection_items[7][user_approval_status]",
            collectionApprovalField: "collection_items[7][collection_approval_status]",
            unrevealedField: "collection_items[7][unrevealed]",
            anonymousField: "collection_items[7][anonymous]",
            removeField: "collection_items[7][remove]"
        )
    }
}
