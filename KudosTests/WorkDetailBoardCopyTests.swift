import Foundation
import Testing
@testable import Kudos

/// Board-copy regression tests for the T-507 Work Detail detail sweep
/// (`iPhone-WorkDetail`, `WorkDetail-Proposed`, `WorkDetail-Proposed-Reading`,
/// and owner-locked T-511 Version E `WD-E-Mix` / `Work-Actions`).
/// Plain value checks only: no network, no AO3, no view host.
@MainActor
@Suite("Work Detail board copy (T-507)")
struct WorkDetailBoardCopyTests {
    @Test func seriesWordsLabelFormatsSingularAndCompactCounts() {
        #expect(WorkDetailDisclosure.seriesWordsLabel(1) == "1 word")
        let small = 850.compactCount.lowercased()
        #expect(WorkDetailDisclosure.seriesWordsLabel(850) == "\(small) words")
        let compact = 141_000.compactCount.lowercased()
        #expect(WorkDetailDisclosure.seriesWordsLabel(141_000) == "\(compact) words")
    }

    /// T-511: the collapsed digest is the title and the part, never a length.
    /// The board's words and completion stay on the expanded row.
    @Test func seriesDigestStaysAPartLineWhileTheExpandedRowCarriesLength() {
        #expect(
            WorkDetailDisclosure.seriesDigest(
                title: "The Coast Road", position: 2, partCount: 3
            ) == "The Coast Road · part 2 of 3"
        )
        #expect(
            WorkDetailDisclosure.seriesDigest(
                title: "The Coast Road", position: 2, partCount: nil
            ) == "The Coast Road · part 2"
        )
        #expect(
            WorkDetailDisclosure.seriesDigest(title: "The Coast Road", position: 0) == "The Coast Road"
        )
        let words = WorkDetailDisclosure.seriesWordsLabel(141_000)
        #expect(
            WorkDetailDisclosure.seriesSubtitle(
                position: 2, partCount: 3, wordCount: 141_000, isComplete: false
            ) == "Part 2 of 3 · \(words) · in progress"
        )
        #expect(!WorkDetailDisclosure.seriesDigest(title: "The Coast Road", position: 2).contains("word"))
    }

    @Test func seriesSubtitleMatchesBoardPartWordsAndCompletionFormat() {
        let compact = 141_000.compactCount.lowercased()
        #expect(
            WorkDetailDisclosure.seriesSubtitle(
                position: 2, partCount: 3, wordCount: 141_000, isComplete: false
            ) == "Part 2 of 3 · \(compact) words · in progress"
        )
        #expect(
            WorkDetailDisclosure.seriesSubtitle(
                position: 3, partCount: 3, wordCount: 141_000, isComplete: true
            ) == "Part 3 of 3 · \(compact) words · complete"
        )
        #expect(
            WorkDetailDisclosure.seriesSubtitle(
                position: 2, partCount: nil, wordCount: nil, isComplete: nil
            ) == "Part 2"
        )
        #expect(
            WorkDetailDisclosure.seriesSubtitle(
                position: 4, partCount: 3, wordCount: 0, isComplete: false
            ) == "Part 4 · in progress"
        )
        #expect(
            WorkDetailDisclosure.seriesSubtitle(
                position: 0, partCount: nil, wordCount: nil, isComplete: nil
            ) == nil
        )
    }

    @Test func menuMembershipDetailUsesTheExistingQueueAndCollectionLabels() {
        #expect(WorkDetailDisclosure.menuQueueDetail(count: 0) == nil)
        #expect(WorkDetailDisclosure.menuQueueDetail(count: -1) == nil)
        #expect(WorkDetailDisclosure.menuCollectionDetail(count: 0) == nil)
        #expect(
            WorkDetailDisclosure.menuQueueDetail(count: 3) == WorkDetailPresentation.queueLabel(count: 3)
        )
        #expect(
            WorkDetailDisclosure.menuCollectionDetail(count: 1)
                == WorkDetailPresentation.collectionLabel(count: 1)
        )
        #expect(WorkDetailPresentation.queueLabel(count: 3).contains("Queue"))
        #expect(WorkDetailPresentation.collectionLabel(count: 1).contains("Collection"))
    }

    @Test func commentsRowFormatsCountAndVoiceOverLabel() {
        #expect(WorkDetailCommentsRow.countText(nil) == nil)
        #expect(WorkDetailCommentsRow.countText(0) == 0.formatted())
        #expect(WorkDetailCommentsRow.countText(286) == 286.formatted())
        #expect(WorkDetailCommentsRow.countText(1_250) == 1_250.formatted())

        #expect(WorkDetailCommentsRow.accessibilityLabel(count: nil) == "Comments")
        #expect(WorkDetailCommentsRow.accessibilityLabel(count: 0) == "Comments, \(0.formatted())")
        #expect(WorkDetailCommentsRow.accessibilityLabel(count: 286) == "Comments, \(286.formatted())")
    }
}
