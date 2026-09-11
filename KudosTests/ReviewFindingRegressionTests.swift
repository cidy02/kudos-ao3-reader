import Foundation
import Testing
@testable import Kudos

/// Findings from the branch review that were not in the backup layer. Each test
/// fails on the code as it was.
struct ReviewFindingRegressionTests {

    // MARK: Bulk edit must not send tag fields

    @Test func theBulkPostCarriesNoTagFieldAtAll() {
        var changes = AO3BulkEditChanges()
        changes.workIDs = [1, 2]
        changes.tagsToAdd.additionalTags = ["Fluff"]
        changes.tagsToAdd.fandoms = ["Naruto"]
        changes.rating = "11"

        let names = Set(changes.parameters(csrfToken: "t").map(\.0))
        // Every one of these replaces on AO3, so a bulk POST carrying an *addition*
        // wipes whatever each work already had.
        #expect(!names.contains(AO3WorkFormField.additionalTags))
        #expect(!names.contains(AO3WorkFormField.fandoms))
        #expect(!names.contains(AO3WorkFormField.relationships))
        #expect(!names.contains(AO3WorkFormField.characters))
        #expect(!names.contains(AO3WorkFormField.warnings))
        #expect(!names.contains(AO3WorkFormField.categories))
        // The uniform scalars still travel this way.
        #expect(names.contains(AO3WorkFormField.rating))
    }

    @Test func aTagsOnlyEditHasNothingUniformToPost() {
        var changes = AO3BulkEditChanges()
        changes.workIDs = [1]
        changes.tagsToAdd.additionalTags = ["Fluff"]

        #expect(changes.hasTagChanges)
        // Otherwise the run fires a POST carrying nothing but a CSRF token.
        #expect(!changes.hasUniformChanges)
    }

    @Test func addingATagMergesAgainstTheWorksOwnList() {
        var changes = AO3BulkEditChanges()
        changes.tagsToAdd.additionalTags = ["Fluff"]
        var current = AO3WorkTagSet()
        current.additionalTags = ["Slow Burn", "Hurt/Comfort"]

        let merged = changes.applying(to: current)
        // The whole finding in one line: the result keeps what was there.
        #expect(merged.additionalTags.contains("Slow Burn"))
        #expect(merged.additionalTags.contains("Hurt/Comfort"))
        #expect(merged.additionalTags.contains("Fluff"))
    }

    @Test func removalReachesTheMergeEvenThoughItNeverReachedTheRequest() {
        var changes = AO3BulkEditChanges()
        changes.tagsToRemove.additionalTags = ["Slow Burn"]
        var current = AO3WorkTagSet()
        current.additionalTags = ["Slow Burn", "Fluff"]

        let merged = changes.applying(to: current)
        #expect(!merged.additionalTags.contains("Slow Burn"))
        #expect(merged.additionalTags.contains("Fluff"))
    }

    // MARK: Clearing categories has to say so

    @Test func clearingEveryCategoryPostsAnEmptyValue() {
        var tags = AO3WorkTagSet()
        tags.categories = []
        let categoryPairs = tags.parameters().filter { $0.0 == AO3WorkFormField.categories }

        // Emitting nothing leaves AO3's existing categories in place, so "clear
        // them all" silently did nothing. Warnings already did this correctly.
        #expect(categoryPairs.count == 1)
        #expect(categoryPairs.first?.1 == "")
    }

    @Test func categoriesStillPostOneValueEachWhenSet() {
        var tags = AO3WorkTagSet()
        tags.categories = ["23", "22"]
        let values = tags.parameters()
            .filter { $0.0 == AO3WorkFormField.categories }
            .map(\.1)
        #expect(values == ["23", "22"])
    }

    // MARK: A family is a union

    @Test func siblingFandomsBecomeAnOrClauseRatherThanAnAnd() {
        var filters = AO3SearchFilters()
        filters.fandomUnion = ["Doctor Who (1963)", "Doctor Who (2005)"]

        let clause = filters.fandomUnionClause
        #expect(clause == "fandom: (\"Doctor Who (1963)\" OR \"Doctor Who (2005)\")")
        // And it reaches the query AO3 actually reads.
        #expect(filters.searchQuery.contains("OR"))
        // `fandom_names` stays empty: that field ANDs, which is the bug.
        #expect(filters.fandom.isEmpty)
    }

    @Test func oneFandomNeedsNoParenthesesAndNoOr() {
        var filters = AO3SearchFilters()
        filters.fandomUnion = ["Naruto"]
        #expect(filters.fandomUnionClause == "fandom: \"Naruto\"")
    }

    @Test func namesAreQuotedSoPunctuationDoesNotSplitIntoTerms() {
        var filters = AO3SearchFilters()
        // Real AO3 tags carry spaces, pipes and brackets.
        filters.fandomUnion = ["僕のヒーローアカデミア | Boku no Hero Academia"]
        let clause = try? #require(filters.fandomUnionClause)
        #expect(clause?.hasPrefix("fandom: \"") == true)
        #expect(clause?.hasSuffix("\"") == true)
    }

    @Test func anEmptyUnionProducesNoClause() {
        var filters = AO3SearchFilters()
        filters.fandomUnion = ["   ", ""]
        #expect(filters.fandomUnionClause == nil)
    }

    // MARK: A huge pasted number must not crash the slider

    @Test func anAbsurdTypedBoundDoesNotTrap() {
        // Survives digitsOnly and Int parsing; ×1.25 then exceeds Int.max.
        let ceiling = FilterRangeSlider.niceCeiling(8_000_000_000_000_000_000)
        #expect(ceiling > 0)
    }

    @Test func ordinaryBoundsStillRoundUpToANiceStep() {
        #expect(FilterRangeSlider.niceCeiling(80_000) == 100_000)
        #expect(FilterRangeSlider.niceCeiling(1) == 1_000)
    }
}
