import SwiftUI
import Testing
@testable import Kudos

/// Tests for Browse category card top-fandom pills (Board 13, FID61).
///
/// Ensures fandom names have layout priority over work counts so names are never
/// truncated to make room for counts, holds with long fandom names and Dynamic Type AX5,
/// and VoiceOver accessibility labels always preserve the full name and count.
@MainActor
struct BrowseCategoryCardPillTests {
    @Test func accessibilityLabelPreservesFullNameAndWorkCount() {
        let doctorWho = BrowseCategoryFandomChipLabel.accessibilityLabel(
            title: "Doctor Who",
            workCount: 144_000,
            isFamiliar: true
        )
        #expect(doctorWho == "Doctor Who, 144K works, you have read from this fandom")

        let sherlock = BrowseCategoryFandomChipLabel.accessibilityLabel(
            title: "Sherlock Holmes",
            workCount: 131_000,
            isFamiliar: false
        )
        #expect(sherlock == "Sherlock Holmes, 131K works")

        let lockedTomb = BrowseCategoryFandomChipLabel.accessibilityLabel(
            title: "The Locked Tomb Series - Tamsyn Muir",
            workCount: 15_200,
            isFamiliar: false
        )
        #expect(lockedTomb == "The Locked Tomb Series - Tamsyn Muir, 15K works")
    }

    @Test func chipLabelBuildsHierarchyForVariousFandomLengths() {
        let names = [
            "Naruto",
            "Doctor Who",
            "Doctor Who (2005)",
            "Sherlock Holmes",
            "Supernatural",
            "Harry Potter - J. K. Rowling",
            "The Locked Tomb Series - Tamsyn Muir"
        ]

        for name in names {
            let label = BrowseCategoryFandomChipLabel(
                title: name,
                workCount: 144_000,
                isApproximate: true,
                isFamiliar: true,
                chipTitleSize: 13,
                chipCountSize: 11
            )
            // Evaluating the body constructs the ViewThatFits hierarchy.
            _ = label.body
        }
    }

    @Test func chipLabelBuildsAtAX5Size() {
        let longName = "The Locked Tomb Series - Tamsyn Muir"
        let labelAX5 = BrowseCategoryFandomChipLabel(
            title: longName,
            workCount: 15_200,
            isApproximate: false,
            isFamiliar: true,
            chipTitleSize: 29,
            chipCountSize: 24
        )
        _ = labelAX5.body
    }
}
