import Foundation
import Testing
@testable import Kudos

/// Artboard 1s stages changes and submits them together. What counts as a change
/// is the whole risk: too eager and the toolbar claims work that is not there;
/// too lax and an edit is silently dropped.
struct AO3CollectionItemStagingTests {
    private func item(
        id: Int = 1,
        creator: AO3CollectionItemApproval = .unreviewed,
        moderator: AO3CollectionItemApproval = .unreviewed,
        unrevealed: Bool = false,
        anonymous: Bool = false
    ) -> AO3CollectionItem {
        AO3CollectionItem(
            id: id,
            collectionSlug: "tidewrack",
            collectionTitle: "Tidewrack",
            workTitle: "The Weight of Water",
            creatorApproval: creator,
            moderatorApproval: moderator,
            isUnrevealed: unrevealed,
            isAnonymous: anonymous,
            userApprovalField: "u",
            collectionApprovalField: "c",
            unrevealedField: "un",
            anonymousField: "an",
            removeField: "rm"
        )
    }

    // MARK: What counts as a change

    @Test func nothingStagedIsNothingPending() {
        let staging = AO3CollectionItemStaging()
        #expect(staging.pendingCount(for: [item()]) == 0)
    }

    @Test func settingAValueBackToWhereItStartedIsNotAChange() {
        let row = item(creator: .unreviewed)
        var staging = AO3CollectionItemStaging()
        staging.setCreatorApproval(.approved, for: row)
        #expect(staging.pendingCount(for: [row]) == 1)

        // Tapping it back is not work. Submitting it would write a value AO3
        // already holds while the toolbar counted it.
        staging.setCreatorApproval(.unreviewed, for: row)
        #expect(staging.pendingCount(for: [row]) == 0)
        #expect(staging.hasChanges(for: row) == false)
    }

    @Test func aRealChangeOnAnyOfTheFourCounts() {
        let row = item()
        for stage in [
            { (s: inout AO3CollectionItemStaging) in s.setCreatorApproval(.approved, for: row) },
            { (s: inout AO3CollectionItemStaging) in s.setModeratorApproval(.rejected, for: row) },
            { (s: inout AO3CollectionItemStaging) in s.setUnrevealed(true, for: row) },
            { (s: inout AO3CollectionItemStaging) in s.setAnonymous(true, for: row) }
        ] {
            var staging = AO3CollectionItemStaging()
            stage(&staging)
            #expect(staging.pendingCount(for: [row]) == 1)
        }
    }

    // MARK: Rows show what is staged

    @Test func aRowDrawsTheStagedValueRatherThanAO3s() {
        let row = item(creator: .unreviewed, unrevealed: false)
        var staging = AO3CollectionItemStaging()
        staging.setCreatorApproval(.approved, for: row)
        staging.setUnrevealed(true, for: row)

        #expect(staging.creatorApproval(for: row) == .approved)
        #expect(staging.isUnrevealed(for: row) == true)
        // Untouched settings still read from AO3.
        #expect(staging.moderatorApproval(for: row) == .unreviewed)
        #expect(staging.isAnonymous(for: row) == false)
    }

    // MARK: Removal

    @Test func removalIsExclusiveAndReplacesAnythingElseStaged() {
        let row = item()
        var staging = AO3CollectionItemStaging()
        staging.setCreatorApproval(.approved, for: row)
        staging.setRemoved(true, for: row)

        let drafts = staging.pendingDrafts(for: [row])
        #expect(drafts.count == 1)
        #expect(drafts.first?.remove == true)
        // Asking AO3 to approve something and delete it in the same POST is not a
        // request worth sending.
        #expect(drafts.first?.creatorApproval == nil)
    }

    @Test func unremovingLeavesNothingPending() {
        let row = item()
        var staging = AO3CollectionItemStaging()
        staging.setRemoved(true, for: row)
        staging.setRemoved(false, for: row)
        #expect(staging.pendingCount(for: [row]) == 0)
    }

    // MARK: Hygiene

    @Test func draftsForItemsNoLongerOnThePageAreDropped() {
        let stale = item(id: 99)
        var staging = AO3CollectionItemStaging()
        staging.setCreatorApproval(.approved, for: stale)

        // The tab changed under it. Posting a draft for a row nobody can see would
        // be a change the reader cannot check.
        #expect(staging.pendingDrafts(for: [item(id: 1)]).isEmpty)
    }

    @Test func draftsComeBackInAStableOrder() {
        let rows = [item(id: 3), item(id: 1), item(id: 2)]
        var staging = AO3CollectionItemStaging()
        for row in rows { staging.setAnonymous(true, for: row) }
        // A dictionary has no order; the POST should not vary between runs.
        #expect(staging.pendingDrafts(for: rows).map(\.itemID) == [1, 2, 3])
    }

    @Test func discardingClearsEverything() {
        let rows = [item(id: 1), item(id: 2)]
        var staging = AO3CollectionItemStaging()
        for row in rows { staging.setUnrevealed(true, for: row) }
        staging.clearAll()
        #expect(staging.pendingCount(for: rows) == 0)
    }
}
