import Foundation
import SwiftUI
import Testing
@testable import Kudos

/// FID14 / Board 14 pure logic tests:
/// 1. Subtitle under title ("N fandoms · about N works · N downloaded")
/// 2. Letter grouping (Latin A-Z, digits/symbols/non-Latin → "#")
/// 3. Filter-state line and Reset behavior
struct FandomIndexTests {

    // MARK: - Subtitle under title (FandomSubtitle)

    @Test func subtitleWithAllThreeParts() {
        let text = FandomSubtitle.text(fandomsCount: 6, worksCount: 9_000, downloadedCount: 14)
        #expect(text == "6 fandoms · about 9k works · 14 downloaded")

        let text2 = FandomSubtitle.text(fandomsCount: 11, worksCount: 30_000, downloadedCount: 9)
        #expect(text2 == "11 fandoms · about 30k works · 9 downloaded")
    }

    @Test func rowSubtitleKeepsTheExactCount() {
        let text = FandomSubtitle.text(fandomsCount: 1, worksCount: 128_534, downloadedCount: 3, exactWorks: true)
        #expect(text == "128,534 works · 3 downloaded")
    }

    @Test func subtitleSingleFandomOmitsFandomCount() {
        let text = FandomSubtitle.text(fandomsCount: 1, worksCount: 1_100, downloadedCount: 2)
        #expect(text == "about 1.1k works · 2 downloaded")
    }

    @Test func subtitleZeroDownloadedOmitsDownloaded() {
        let text = FandomSubtitle.text(fandomsCount: 1, worksCount: 600, downloadedCount: 0)
        #expect(text == "about 600 works")

        let textNil = FandomSubtitle.text(fandomsCount: 1, worksCount: 600, downloadedCount: nil)
        #expect(textNil == "about 600 works")
    }

    @Test func subtitleSingleValuesSingularForm() {
        let text = FandomSubtitle.text(fandomsCount: 1, worksCount: 1, downloadedCount: 1)
        #expect(text == "about 1 work · 1 downloaded")
    }

    @Test func subtitleZeroOrNilWorksOmitsWorks() {
        let text = FandomSubtitle.text(fandomsCount: 5, worksCount: 0, downloadedCount: 3)
        #expect(text == "5 fandoms · 3 downloaded")

        let textNil = FandomSubtitle.text(fandomsCount: 5, worksCount: nil, downloadedCount: 3)
        #expect(textNil == "5 fandoms · 3 downloaded")
    }

    @Test func subtitleAllEmptyReturnsNil() {
        #expect(FandomSubtitle.text(fandomsCount: 1, worksCount: 0, downloadedCount: 0) == nil)
        #expect(FandomSubtitle.text(fandomsCount: nil, worksCount: nil, downloadedCount: nil) == nil)
    }

    @Test func subtitleLargeNumbersUseCompactNotation() {
        let text = FandomSubtitle.text(fandomsCount: 8_106, worksCount: 1_400_000, downloadedCount: 25)
        #expect(text == "8,106 fandoms · about 1.4m works · 25 downloaded")
    }

    // MARK: - Letter Grouping (FandomFamily.letterGroup)

    @Test func latinLettersGroupToUppercase() {
        #expect(FandomFamily.letterGroup(for: "Jane Eyre") == "J")
        #expect(FandomFamily.letterGroup(for: "Northanger Abbey") == "N")
        #expect(FandomFamily.letterGroup(for: "pride and prejudice") == "P")
        #expect(FandomFamily.letterGroup(for: "Sherlock Holmes") == "S")
        #expect(FandomFamily.letterGroup(for: "alice in wonderland") == "A")
        #expect(FandomFamily.letterGroup(for: "Zorro") == "Z")
    }

    @Test func leadingWhitespaceIsSkippedForLetterGrouping() {
        #expect(FandomFamily.letterGroup(for: "   Doctor Who") == "D")
        #expect(FandomFamily.letterGroup(for: "\tBleach") == "B")
    }

    @Test func digitsGroupToHash() {
        #expect(FandomFamily.letterGroup(for: "1984") == "#")
        #expect(FandomFamily.letterGroup(for: "2001: A Space Odyssey") == "#")
        #expect(FandomFamily.letterGroup(for: "007") == "#")
        #expect(FandomFamily.letterGroup(for: "9 to 5") == "#")
    }

    @Test func symbolsAndPunctuationGroupToHash() {
        #expect(FandomFamily.letterGroup(for: "$9.99") == "#")
        #expect(FandomFamily.letterGroup(for: "#1 Fan") == "#")
        #expect(FandomFamily.letterGroup(for: "!Kudos") == "#")
        #expect(FandomFamily.letterGroup(for: "- Dash") == "#")
        #expect(FandomFamily.letterGroup(for: "★ Star") == "#")
        #expect(FandomFamily.letterGroup(for: "@Username") == "#")
    }

    @Test func nonLatinScriptsGroupToHash() {
        #expect(FandomFamily.letterGroup(for: "進撃の巨人") == "#")
        #expect(FandomFamily.letterGroup(for: "僕のヒーローアカデミア") == "#")
        #expect(FandomFamily.letterGroup(for: "文豪ストレイドッグス") == "#")
        #expect(FandomFamily.letterGroup(for: "魔道祖师") == "#")
    }

    @Test func emptyAndWhitespaceStringsGroupToHash() {
        #expect(FandomFamily.letterGroup(for: "") == "#")
        #expect(FandomFamily.letterGroup(for: "   ") == "#")
        #expect(FandomFamily.letterGroup(for: "\n\t") == "#")
    }

    // MARK: - Filter-state line and Reset (FandomFilterState)

    @Test func defaultStateMatchesBoardExpectations() {
        let text = FandomFilterState.text(
            groupsVariants: true,
            sort: .alphabetical,
            options: FandomListFilterOptions()
        )
        #expect(text == "Grouped by family")
        #expect(!FandomFilterState.hasDiffFromDefaults(
            groupsVariants: true,
            sort: .alphabetical,
            options: FandomListFilterOptions()
        ))
    }

    @Test func boardFilterStateWithMinimumWorks() {
        var options = FandomListFilterOptions()
        options.minimumWorks = .fifty
        let text = FandomFilterState.text(
            groupsVariants: true,
            sort: .alphabetical,
            options: options
        )
        #expect(text == "Grouped by family · at least 50 works")
        #expect(FandomFilterState.hasDiffFromDefaults(
            groupsVariants: true,
            sort: .alphabetical,
            options: options
        ))
    }

    @Test func filterStateWithSortChange() {
        let text = FandomFilterState.text(
            groupsVariants: true,
            sort: .familyTotal,
            options: FandomListFilterOptions()
        )
        #expect(text == "Grouped by family · most works")
        #expect(FandomFilterState.hasDiffFromDefaults(
            groupsVariants: true,
            sort: .familyTotal,
            options: FandomListFilterOptions()
        ))
    }

    @Test func filterStateWhenUngrouped() {
        let text = FandomFilterState.text(
            groupsVariants: false,
            sort: .alphabetical,
            options: FandomListFilterOptions()
        )
        #expect(text == "Ungrouped")
        #expect(FandomFilterState.hasDiffFromDefaults(
            groupsVariants: false,
            sort: .alphabetical,
            options: FandomListFilterOptions()
        ))
    }

    @Test func filterStateWithMultipleActiveFilters() {
        var options = FandomListFilterOptions()
        options.minimumWorks = .ten
        options.hideRPF = true
        options.favouritedOnly = true

        let text = FandomFilterState.text(
            groupsVariants: false,
            sort: .familyTotal,
            options: options
        )
        #expect(text == "Ungrouped · most works · at least 10 works · no RPF · favourited only")
        #expect(FandomFilterState.hasDiffFromDefaults(
            groupsVariants: false,
            sort: .familyTotal,
            options: options
        ))
    }

    @Test func resetRestoresDefaults() {
        // Given modified settings:
        var options = FandomListFilterOptions()
        options.minimumWorks = .fifty
        options.hideRPF = true
        var groupsVariants = false
        var sort: FandomFamilySort = .familyTotal

        #expect(FandomFilterState.hasDiffFromDefaults(
            groupsVariants: groupsVariants,
            sort: sort,
            options: options
        ))

        // When reset:
        options = FandomListFilterOptions()
        groupsVariants = true
        sort = .alphabetical

        // Then:
        #expect(!FandomFilterState.hasDiffFromDefaults(
            groupsVariants: groupsVariants,
            sort: sort,
            options: options
        ))
        #expect(FandomFilterState.text(
            groupsVariants: groupsVariants,
            sort: sort,
            options: options
        ) == "Grouped by family")
    }

    // MARK: - Board 14 index gutter clearance & header colour (FID47)

    @Test @MainActor func fandomRowsClearSectionIndexAndHeaderUsesPrimaryInk() {
        #expect(FandomFamilyBlock.leadingInset == 16)
        #expect(FandomFamilyBlock.trailingInset >= 30)
        #expect(FandomLetterHeader.rowInsets.leading == FandomFamilyBlock.leadingInset)
        #expect(FandomLetterHeader.rowInsets.trailing == FandomFamilyBlock.trailingInset)
        #expect(FandomLetterHeader.titleColor == Color.primary)
    }
}
