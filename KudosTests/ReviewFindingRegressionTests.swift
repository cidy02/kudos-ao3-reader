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

    // MARK: A family union is real now, and a fallback must still not be faked

    @Test func aFamilyTotalIsCachedOnlyBecauseTheSearchIsARealUnion() {
        // This pinned `false` while a family search sent `fandom_names`, which ANDs:
        // caching that intersection replaced an honest tilde with a figure wrong in
        // the same direction every time. The search is a real union now
        // (`filter_ids:(A OR B)`, measured against live AO3 — see AO3FandomUnion), so
        // the flag is true and the rule it guards moved into the load path: a page
        // that could not resolve every sibling's id falls back to the join and does
        // not cache its total at all.
        #expect(FandomWorksView.exactCountIsTrustworthy == true)
    }

    @Test func aUnionMissingOneSiblingIsNotAUnion() {
        // The fallback's trigger: one unresolvable id means no clause, which is what
        // makes the page keep the tilde rather than show a smaller answer as the
        // family's total.
        #expect(AO3FandomUnion.queryClause(filterIDs: []) == nil)
        #expect(AO3FandomUnion.filterID(fromTagWorksPage: "<html><body>no feed link</body></html>",
                                        tagName: "Anything") == nil)
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
