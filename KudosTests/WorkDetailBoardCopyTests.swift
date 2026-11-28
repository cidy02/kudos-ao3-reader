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
    @Test func seriesWordsLabelFormatsSingularSmallAndCompactCounts() {
        #expect(WorkDetailDisclosure.seriesWordsLabel(1) == "1 word")
        #expect(WorkDetailDisclosure.seriesWordsLabel(850) == "850 words")
        let compact = 141_000.compactCount.lowercased()
        #expect(WorkDetailDisclosure.seriesWordsLabel(141_000) == "\(compact) words")
    }

    @Test func seriesDigestIncludesWordsOnlyWhenKnown() {
        let compact = 141_000.compactCount.lowercased()
        #expect(
            WorkDetailDisclosure.seriesDigest(
                title: "The Coast Road", position: 2, partCount: 3, wordCount: 141_000
            ) == "The Coast Road · part 2 of 3 · \(compact) words"
        )
        #expect(
            WorkDetailDisclosure.seriesDigest(
                title: "The Coast Road", position: 2, partCount: 3, wordCount: nil
            ) == "The Coast Road · part 2 of 3"
        )
        #expect(
            WorkDetailDisclosure.seriesDigest(
                title: "The Coast Road", position: 2, partCount: nil, wordCount: 0
            ) == "The Coast Road · part 2"
        )
        #expect(
            WorkDetailDisclosure.seriesDigest(
                title: "The Coast Road", position: 0, partCount: nil, wordCount: 141_000
            ) == "The Coast Road · \(compact) words"
        )
        #expect(
            WorkDetailDisclosure.seriesDigest(
                title: "The Coast Road", position: 0, partCount: nil, wordCount: nil
            ) == "The Coast Road"
        )
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

    @Test func menuMembershipDetailMatchesWorkActionsBoard() {
        #expect(WorkDetailDisclosure.menuMembershipDetail(count: 0) == nil)
        #expect(WorkDetailDisclosure.menuMembershipDetail(count: -1) == nil)
        #expect(WorkDetailDisclosure.menuMembershipDetail(count: 1) == "In 1")
        #expect(WorkDetailDisclosure.menuMembershipDetail(count: 3) == "In 3")
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
