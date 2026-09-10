import Testing
@testable import Kudos

/// Sibling-family grouping: cluster on the parsed title, never key identity on it.
struct FandomFamilyTests {

    // MARK: - Grouping

    @Test func distinctTitlesStayUngrouped() {
        let families = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Naruto (Anime & Manga)", workCount: 1),
            AO3Fandom(name: "Bleach (Anime & Manga)", workCount: 1),
        ])
        #expect(families.count == 2)
        #expect(Set(families.map(\.parsedTitle)) == ["Naruto", "Bleach"])
    }

    @Test func twoTagsWithTheSameParsedTitleGroupAndKeepOriginals() {
        let fandoms = [
            AO3Fandom(name: "Doctor Who (1963)", workCount: 4_000),
            AO3Fandom(name: "Doctor Who (2005)", workCount: 12_000),
        ]
        let families = FandomFamily.grouped(fandoms: fandoms)
        #expect(families.count == 1)
        let family = families[0]
        #expect(family.parsedTitle == "Doctor Who")
        #expect(family.memberCount == 2)
        #expect(Set(family.includedFilterNames) == Set(fandoms.map(\.name)))
        #expect(family.members.map(\.displayName.original) == family.includedFilterNames)
        #expect(family.members.contains { $0.qualifierDisplay == "1963" })
        #expect(family.members.contains { $0.qualifierDisplay == "2005" })
    }

    @Test func familyIdIsNotTheParsedTitle() {
        let family = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Doctor Who (1963)", workCount: 1),
            AO3Fandom(name: "Doctor Who (2005)", workCount: 2),
        ])[0]
        #expect(family.id != family.parsedTitle)
        #expect(family.id != "Doctor Who")
        #expect(family.id.contains(FandomFamily.idSeparator))
    }

    @Test func twoGroupsWithTheSameTitleAndDifferentMembersHaveDifferentIds() {
        let sixties = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Doctor Who (1963)", workCount: 1),
            AO3Fandom(name: "Doctor Who (2005)", workCount: 2),
        ])[0]
        let movie = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Doctor Who (1996)", workCount: 3),
        ])[0]
        #expect(sixties.parsedTitle == movie.parsedTitle)
        #expect(sixties.id != movie.id)
        #expect(movie.id == FandomFamily.id(originalNames: ["Doctor Who (1996)"]))
    }

    @Test func groupingPerCategoryDoesNotMergeUnrelatedLists() {
        // Same parsed title in two category inputs must not share an id or a
        // grouping bucket — the clustering dictionary lives inside one call.
        let movies = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "IT (Movies)", workCount: 500),
        ])
        let books = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "IT (Novel)", workCount: 800),
        ])
        #expect(movies.count == 1)
        #expect(books.count == 1)
        #expect(movies[0].parsedTitle == books[0].parsedTitle)
        #expect(movies[0].id != books[0].id)
        #expect(movies[0].includedFilterNames == ["IT (Movies)"])
        #expect(books[0].includedFilterNames == ["IT (Novel)"])
    }

    @Test func multilingualPrimarySegmentIsWhatGetsGrouped() {
        let fandoms = [
            AO3Fandom(
                name: "進撃の巨人 | Shingeki no Kyojin | Attack on Titan (Anime & Manga)",
                workCount: 10_000
            ),
            AO3Fandom(name: "Attack on Titan - All Media Types", workCount: 4_208),
        ]
        let families = FandomFamily.grouped(fandoms: fandoms)
        #expect(families.count == 1)
        #expect(families[0].parsedTitle == "Attack on Titan")
        #expect(families[0].includedFilterNames.contains(fandoms[0].name))
        #expect(families[0].members.contains { $0.aliases.contains("進撃の巨人") })
    }

    @Test func familyIdIsStableAcrossMemberInputOrder() {
        let a = FandomFamily.id(originalNames: ["Bleach - All Media Types", "Bleach (Anime & Manga)"])
        let b = FandomFamily.id(originalNames: ["Bleach (Anime & Manga)", "Bleach - All Media Types"])
        #expect(a == b)
    }

    // MARK: - Ranking

    @Test func familyRankUsesTheSumNotTheLargestTag() {
        // Pretty Guardian Sailor Moon at 17,300 across four tags sits above
        // Attack on Titan at 14,208 — max-tag ranking would invert them.
        let sailorMoon = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Pretty Guardian Sailor Moon (Anime & Manga)", workCount: 8_000),
            AO3Fandom(name: "Pretty Guardian Sailor Moon - All Media Types", workCount: 5_000),
            AO3Fandom(name: "Pretty Guardian Sailor Moon (TV)", workCount: 3_000),
            AO3Fandom(name: "Pretty Guardian Sailor Moon (Manga)", workCount: 1_300),
        ])[0]
        let attackOnTitan = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Attack on Titan (Anime & Manga)", workCount: 14_208),
        ])[0]
        #expect(sailorMoon.summedWorkCount == 17_300)
        #expect(attackOnTitan.summedWorkCount == 14_208)
        #expect(sailorMoon.members.map(\.workCount).max() == 8_000)
        #expect(sailorMoon.members.map(\.workCount).max()! < attackOnTitan.summedWorkCount)

        let ranked = FandomFamily.sorted([attackOnTitan, sailorMoon], by: .familyTotal)
        #expect(ranked.map(\.parsedTitle) == ["Pretty Guardian Sailor Moon", "Attack on Titan"])

        let byMaxTag = [sailorMoon, attackOnTitan].sorted {
            ($0.members.map(\.workCount).max() ?? 0) > ($1.members.map(\.workCount).max() ?? 0)
        }
        #expect(byMaxTag.map(\.parsedTitle) == ["Attack on Titan", "Pretty Guardian Sailor Moon"])
    }

    @Test func alphabeticalSortMakesLetterGroupsAndFamilyTotalDropsThem() {
        let families = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Bleach (Anime & Manga)", workCount: 100),
            AO3Fandom(name: "Attack on Titan (Anime)", workCount: 50),
            AO3Fandom(name: "Naruto (Anime & Manga)", workCount: 80),
        ])
        let az = FandomFamily.sorted(families, by: .alphabetical)
        #expect(az.map(\.parsedTitle) == ["Attack on Titan", "Bleach", "Naruto"])
        let sections = FandomFamily.letterSections(az)
        #expect(sections.map(\.letter) == ["A", "B", "N"])

        let byTotal = FandomFamily.sorted(families, by: .familyTotal)
        #expect(byTotal.map(\.parsedTitle) == ["Bleach", "Naruto", "Attack on Titan"])
    }

    @Test func nonLatinTitlesLandInTheHashLetterGroup() {
        #expect(FandomFamily.letterGroup(for: "進撃の巨人") == "#")
        #expect(FandomFamily.letterGroup(for: "Attack on Titan") == "A")
        #expect(FandomFamily.letterGroup(for: "") == "#")
    }

    // MARK: - Tilde / exact cache

    @Test func aSingleMemberFamilyHasNoTilde() {
        let family = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Haikyuu!!", workCount: 9_000),
        ])[0]
        #expect(family.memberCount == 1)
        #expect(family.showsApproximateCount == false)
        #expect(family.exactWorkCount == nil)
        #expect(family.displayedWorkCount == 9_000)
    }

    @Test func aMultiMemberFamilyIsApproximateUntilTheExactCacheIsSet() {
        var family = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Bleach - All Media Types", workCount: 6_412),
            AO3Fandom(name: "Bleach (Anime & Manga)", workCount: 870),
        ])[0]
        #expect(family.showsApproximateCount)
        #expect(family.displayedWorkCount == 7_282)

        family = family.applyingExactCount(6_900)
        #expect(family.showsApproximateCount == false)
        #expect(family.displayedWorkCount == 6_900)
        #expect(family.exactWorkCount == 6_900)
    }

    @Test @MainActor func exactCountCacheIsKeyedByFamilyIdNotTitle() {
        let cache = FandomFamilyExactCountCache()
        let sixties = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Doctor Who (1963)", workCount: 1),
            AO3Fandom(name: "Doctor Who (2005)", workCount: 2),
        ])[0]
        let movie = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Doctor Who (1996)", workCount: 3),
        ])[0]
        cache.store(1_500, for: sixties.id)
        #expect(cache.exactCount(for: sixties.id) == 1_500)
        #expect(cache.exactCount(for: movie.id) == nil)
        #expect(cache.exactCount(for: sixties.parsedTitle) == nil)
    }

    // MARK: - Qualifier display

    @Test func memberRowsUseTheQualifierStrippedOfItsDelimiter() {
        let family = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Bleach - All Media Types", workCount: 6_412),
            AO3Fandom(name: "Bleach (Anime & Manga)", workCount: 870),
            AO3Fandom(name: "One Direction RPF", workCount: 10),
            AO3Fandom(name: "Sherlock Holmes & Related Fandoms", workCount: 5),
        ])
        let bleach = family.first { $0.parsedTitle == "Bleach" }!
        #expect(Set(bleach.members.map(\.qualifierDisplay)) == ["All Media Types", "Anime & Manga"])

        let rpf = family.first { $0.parsedTitle == "One Direction" }!
        #expect(rpf.members[0].qualifierDisplay == "RPF")

        let related = family.first { $0.parsedTitle == "Sherlock Holmes" }!
        #expect(related.members[0].qualifierDisplay == "Related Fandoms")
    }

    // MARK: - Filter flags

    @Test func filterFlagsComeFromQualifierParts() {
        let rpf = FandomFamily.Member(fandom: AO3Fandom(name: "One Direction RPF", workCount: 10))
        #expect(rpf.isRPF)
        #expect(!rpf.isAllMediaTypes)
        #expect(!rpf.isRelatedFandoms)

        let umbrella = FandomFamily.Member(
            fandom: AO3Fandom(name: "One Piece - All Media Types", workCount: 20)
        )
        #expect(umbrella.isAllMediaTypes)
        #expect(!umbrella.isRPF)

        let related = FandomFamily.Member(
            fandom: AO3Fandom(name: "Sherlock Holmes & Related Fandoms", workCount: 5)
        )
        #expect(related.isRelatedFandoms)

        let plain = FandomFamily.Member(fandom: AO3Fandom(name: "Haikyuu!!", workCount: 9))
        #expect(!plain.isRPF && !plain.isAllMediaTypes && !plain.isRelatedFandoms)
    }

    @Test func countRemovedByCountsRowsASwitchWouldHide() {
        let families = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "One Direction RPF", workCount: 10),
            AO3Fandom(name: "Harry Potter RPF", workCount: 20),
            AO3Fandom(name: "One Piece - All Media Types", workCount: 100),
            AO3Fandom(name: "One Piece (Anime & Manga)", workCount: 50),
            AO3Fandom(name: "Sherlock Holmes & Related Fandoms", workCount: 5),
            AO3Fandom(name: "Haikyuu!!", workCount: 9),
        ])
        #expect(FandomFamilyFilters.countRemovedBy(families, hidingRPF: true) == 2)
        #expect(FandomFamilyFilters.countRemovedBy(families, hidingAllMediaTypes: true) == 1)
        #expect(FandomFamilyFilters.countRemovedBy(families, hidingRelatedFandoms: true) == 1)
        #expect(FandomFamilyFilters.countRemovedBy(families, multiTagOnly: true) == 4)
        #expect(FandomFamilyFilters.countRemovedBy(families, minimumWorks: .ten) == 2)

        let library = FandomLibraryIndex(
            favouriteNamesLowercased: ["haikyuu!!"],
            downloadNamesLowercased: ["one piece (anime & manga)", "haikyuu!!"]
        )
        #expect(FandomFamilyFilters.countRemovedBy(families, favouritedOnly: true, library: library) == 5)
        #expect(FandomFamilyFilters.countRemovedBy(families, downloadsOnly: true, library: library) == 4)

        let tallies = FandomFamilyFilters.tallies(families, library: library)
        #expect(tallies.rpfTags == 2)
        #expect(tallies.allMediaTypesTags == 1)
        #expect(tallies.relatedFandomsTags == 1)
        #expect(tallies.favouritedTags == 1)
        #expect(tallies.downloadTags == 2)
        #expect(tallies.multiTagFamilies == 1)
        #expect(tallies.singleTagFamilies == 4)
        #expect(tallies.tagsBelowMinimumWorks(.hundred) == 5)
    }

    @Test func hidingRPFDropsThoseMembersButKeepsTheFamilyIfSiblingsRemain() {
        let families = FandomFamily.grouped(fandoms: [
            AO3Fandom(name: "Good Omens (TV)", workCount: 100),
            AO3Fandom(name: "Good Omens (TV) RPF", workCount: 10),
        ])
        let filtered = FandomFamilyFilters.apply(
            families,
            options: FandomListFilterOptions(hideRPF: true)
        )
        #expect(filtered.count == 1)
        #expect(filtered[0].memberCount == 1)
        #expect(filtered[0].includedFilterNames == ["Good Omens (TV)"])
    }

    // MARK: - Category card sum

    @Test func summedCategoryTotalsAreMarkedApproximate() {
        let fandoms = [
            AO3Fandom(name: "Naruto (Anime & Manga)", workCount: 100),
            AO3Fandom(name: "Naruto - All Media Types", workCount: 50),
        ]
        let total = CategoryWorkTotal.summedTagCounts(fandoms)
        #expect(total.workCount == 150)
        #expect(total.isApproximate)
    }

    @Test func anEmptyCategorySumIsStillApproximate() {
        let total = CategoryWorkTotal.summedTagCounts([])
        #expect(total.workCount == 0)
        #expect(total.isApproximate)
    }
}
