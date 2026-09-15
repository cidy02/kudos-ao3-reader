import Foundation
import Testing
@testable import Kudos

/// Artboard 1bw's two row subtitles. Both are the reason the board gives for the
/// screens existing — a collection's state has to be readable "before the tap,
/// not after" — so they are worth pinning.
@MainActor
struct WorkAssociationPickerTests {
    @Test func collectionStateNamesWhatSubmittingWillDo() {
        let moderated = AO3CollectionAccess(isOpen: true, isModerated: true)
        #expect(WorkCollectionsGiftsView.stateText(moderated)
            == "Moderated — a maintainer approves the work")

        let closed = AO3CollectionAccess(isOpen: false)
        #expect(WorkCollectionsGiftsView.stateText(closed) == "Closed to new works")

        let open = AO3CollectionAccess()
        #expect(WorkCollectionsGiftsView.stateText(open) == "Open")
    }

    /// Unrevealed and anonymous are additive, not a fourth state: a collection can
    /// be moderated *and* unrevealed, and hiding either would be the silence the
    /// board's footnote says neither state has.
    @Test func unrevealedAndAnonymousAppendRatherThanReplace() {
        let access = AO3CollectionAccess(
            isOpen: true, isModerated: true, isUnrevealed: true, isAnonymous: true
        )
        let text = WorkCollectionsGiftsView.stateText(access)
        #expect(text.hasPrefix("Moderated — a maintainer approves the work"))
        #expect(text.contains("Unrevealed until reveal"))
        #expect(text.contains("Anonymous"))
    }

    @Test func seriesDetailDropsWhatAO3DidNotSend() {
        // Neither figure present — no subtitle at all rather than "0 works".
        let bare = AO3SeriesMembership(seriesID: 1, title: "Water")
        #expect(WorkSeriesPickerView.detailText(bare) == nil)

        // Work count only, and not selected: no position line.
        let counted = AO3SeriesMembership(seriesID: 2, title: "Case Files", workCount: 5)
        #expect(WorkSeriesPickerView.detailText(counted) == "5 works")

        // Position shows only for a series this work is actually in.
        let unselected = AO3SeriesMembership(
            seriesID: 3, title: "Short Stays", position: 2, workCount: 3, isSelected: false
        )
        #expect(WorkSeriesPickerView.detailText(unselected) == "3 works")
    }

    @Test func seriesDetailReadsAsTheBoardWritesIt() {
        let membership = AO3SeriesMembership(
            seriesID: 4, title: "Water", position: 2, workCount: 3, isSelected: true
        )
        #expect(WorkSeriesPickerView.detailText(membership) == "3 works · this work is 2nd")
    }

    @Test func oneWorkIsSingular() {
        let membership = AO3SeriesMembership(seriesID: 5, title: "Solo", workCount: 1)
        #expect(WorkSeriesPickerView.detailText(membership) == "1 work")
    }
}
