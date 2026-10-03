package io.github.cidy02.kudos.browse

import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `KudosTests/FandomFamilyTests` and the fandom-list tally cases. */
class FandomFamilyTest {

    @Test
    fun distinctTitlesStayUngrouped() {
        val families = FandomFamily.grouped(
            listOf(
                AO3Fandom("Naruto (Anime & Manga)", 1),
                AO3Fandom("Bleach (Anime & Manga)", 1)
            )
        )
        assertEquals(2, families.size)
        assertEquals(setOf("Naruto", "Bleach"), families.map { it.parsedTitle }.toSet())
    }

    @Test
    fun ungroupedListsEveryRawTagOnItsOwn() {
        val families = FandomFamily.ungrouped(
            listOf(
                AO3Fandom("Doctor Who (1963)", 4_000),
                AO3Fandom("Doctor Who (2005)", 12_000),
                AO3Fandom("Doctor Who (2005)", 12_000)
            )
        )
        assertEquals(2, families.size)
        assertTrue(families.all { it.memberCount == 1 })
        assertEquals(
            listOf(listOf("Doctor Who (1963)"), listOf("Doctor Who (2005)")),
            families.map { it.includedFilterNames }
        )
    }

    @Test
    fun ungroupedRowsSortUnderTheirDisplayedTitle() {
        val families = FandomFamily.ungrouped(
            listOf(
                AO3Fandom("進撃の巨人 | Shingeki no Kyojin | Attack on Titan (Anime)", 90_000),
                AO3Fandom("Bleach (Anime & Manga)", 1)
            )
        )
        assertEquals(listOf("Attack on Titan", "Bleach"), families.map { it.parsedTitle })
        val sections = FandomFamily.letterSections(
            FandomFamily.sorted(families, FandomFamilySort.Alphabetical)
        )
        assertEquals(listOf("A", "B"), sections.map { it.letter })
    }

    @Test
    fun switchingGroupingOffClearsTheGroupingOnlyFilter() {
        var options = FandomListFilterOptions(hideRPF = true, multiTagOnly = true)
        options = options.groupsVariantsChanged(true)
        assertTrue(options.multiTagOnly)
        options = options.groupsVariantsChanged(false)
        assertFalse(options.multiTagOnly)
        assertTrue(options.hideRPF)

        val ungrouped = FandomFamily.ungrouped(listOf(AO3Fandom("Naruto", 3)))
        assertEquals(1, FandomFamilyFilters.apply(ungrouped, options).size)
    }

    @Test
    fun twoTagsWithTheSameParsedTitleGroupAndKeepOriginals() {
        val fandoms = listOf(
            AO3Fandom("Doctor Who (1963)", 4_000),
            AO3Fandom("Doctor Who (2005)", 12_000)
        )
        val families = FandomFamily.grouped(fandoms)
        assertEquals(1, families.size)
        val family = families[0]
        assertEquals("Doctor Who", family.parsedTitle)
        assertEquals(2, family.memberCount)
        assertEquals(fandoms.map { it.name }.toSet(), family.includedFilterNames.toSet())
        assertEquals(family.includedFilterNames, family.members.map { it.displayName.original })
        assertTrue(family.members.any { it.qualifierDisplay == "1963" })
        assertTrue(family.members.any { it.qualifierDisplay == "2005" })
    }

    @Test
    fun familyIdIsNotTheParsedTitle() {
        val family = FandomFamily.grouped(
            listOf(
                AO3Fandom("Doctor Who (1963)", 1),
                AO3Fandom("Doctor Who (2005)", 2)
            )
        )[0]
        assertNotEquals(family.parsedTitle, family.id)
        assertNotEquals("Doctor Who", family.id)
        assertTrue(family.id.contains(FandomFamily.ID_SEPARATOR))
    }

    @Test
    fun twoGroupsWithTheSameTitleAndDifferentMembersHaveDifferentIds() {
        val sixties = FandomFamily.grouped(
            listOf(
                AO3Fandom("Doctor Who (1963)", 1),
                AO3Fandom("Doctor Who (2005)", 2)
            )
        )[0]
        val movie = FandomFamily.grouped(listOf(AO3Fandom("Doctor Who (1996)", 3)))[0]
        assertEquals(movie.parsedTitle, sixties.parsedTitle)
        assertNotEquals(movie.id, sixties.id)
        assertEquals(FandomFamily.id(listOf("Doctor Who (1996)")), movie.id)
    }

    @Test
    fun groupingPerCategoryDoesNotMergeUnrelatedLists() {
        val movies = FandomFamily.grouped(listOf(AO3Fandom("IT (Movies)", 500)))
        val books = FandomFamily.grouped(listOf(AO3Fandom("IT (Novel)", 800)))
        assertEquals(1, movies.size)
        assertEquals(1, books.size)
        assertEquals(books[0].parsedTitle, movies[0].parsedTitle)
        assertNotEquals(books[0].id, movies[0].id)
        assertEquals(listOf("IT (Movies)"), movies[0].includedFilterNames)
        assertEquals(listOf("IT (Novel)"), books[0].includedFilterNames)
    }

    @Test
    fun multilingualPrimarySegmentIsWhatGetsGrouped() {
        val fandoms = listOf(
            AO3Fandom("進撃の巨人 | Shingeki no Kyojin | Attack on Titan (Anime & Manga)", 10_000),
            AO3Fandom("Attack on Titan - All Media Types", 4_208)
        )
        val families = FandomFamily.grouped(fandoms)
        assertEquals(1, families.size)
        assertEquals("Attack on Titan", families[0].parsedTitle)
        assertTrue(families[0].includedFilterNames.contains(fandoms[0].name))
        assertTrue(families[0].members.any { "進撃の巨人" in it.aliases })
    }

    @Test
    fun familyIdIsStableAcrossMemberInputOrder() {
        val a = FandomFamily.id(listOf("Bleach - All Media Types", "Bleach (Anime & Manga)"))
        val b = FandomFamily.id(listOf("Bleach (Anime & Manga)", "Bleach - All Media Types"))
        assertEquals(b, a)
    }

    @Test
    fun familyRankUsesTheSumNotTheLargestTag() {
        val sailorMoon = FandomFamily.grouped(
            listOf(
                AO3Fandom("Pretty Guardian Sailor Moon (Anime & Manga)", 8_000),
                AO3Fandom("Pretty Guardian Sailor Moon - All Media Types", 5_000),
                AO3Fandom("Pretty Guardian Sailor Moon (TV)", 3_000),
                AO3Fandom("Pretty Guardian Sailor Moon (Manga)", 1_300)
            )
        )[0]
        val attackOnTitan = FandomFamily.grouped(
            listOf(AO3Fandom("Attack on Titan (Anime & Manga)", 14_208))
        )[0]
        assertEquals(17_300, sailorMoon.summedWorkCount)
        assertEquals(14_208, attackOnTitan.summedWorkCount)
        assertEquals(8_000, sailorMoon.members.maxOf { it.workCount })
        assertTrue(sailorMoon.members.maxOf { it.workCount } < attackOnTitan.summedWorkCount)

        val ranked = FandomFamily.sorted(
            listOf(attackOnTitan, sailorMoon),
            FandomFamilySort.FamilyTotal
        )
        assertEquals(
            listOf("Pretty Guardian Sailor Moon", "Attack on Titan"),
            ranked.map { it.parsedTitle }
        )
    }

    @Test
    fun alphabeticalSortMakesLetterGroupsAndFamilyTotalDropsThem() {
        val families = FandomFamily.grouped(
            listOf(
                AO3Fandom("Bleach (Anime & Manga)", 100),
                AO3Fandom("Attack on Titan (Anime)", 50),
                AO3Fandom("Naruto (Anime & Manga)", 80)
            )
        )
        val az = FandomFamily.sorted(families, FandomFamilySort.Alphabetical)
        assertEquals(listOf("Attack on Titan", "Bleach", "Naruto"), az.map { it.parsedTitle })
        assertEquals(listOf("A", "B", "N"), FandomFamily.letterSections(az).map { it.letter })

        val byTotal = FandomFamily.sorted(families, FandomFamilySort.FamilyTotal)
        assertEquals(listOf("Bleach", "Naruto", "Attack on Titan"), byTotal.map { it.parsedTitle })
    }

    @Test
    fun nonLatinTitlesLandInTheHashLetterGroup() {
        assertEquals("#", FandomFamily.letterGroup("進撃の巨人"))
        assertEquals("A", FandomFamily.letterGroup("Attack on Titan"))
        assertEquals("#", FandomFamily.letterGroup(""))
    }

    @Test
    fun aSingleMemberFamilyHasNoTilde() {
        val family = FandomFamily.grouped(listOf(AO3Fandom("Haikyuu!!", 9_000)))[0]
        assertEquals(1, family.memberCount)
        assertFalse(family.showsApproximateCount)
        assertNull(family.exactWorkCount)
        assertEquals(9_000, family.displayedWorkCount)
    }

    @Test
    fun aMultiMemberFamilyIsApproximateUntilAnExactCountIsSet() {
        var family = FandomFamily.grouped(
            listOf(
                AO3Fandom("Bleach - All Media Types", 6_412),
                AO3Fandom("Bleach (Anime & Manga)", 870)
            )
        )[0]
        assertTrue(family.showsApproximateCount)
        assertEquals(7_282, family.displayedWorkCount)

        family = family.copy(exactWorkCount = 6_900)
        assertFalse(family.showsApproximateCount)
        assertEquals(6_900, family.displayedWorkCount)
        assertEquals(6_900, family.exactWorkCount)
    }

    @Test
    fun memberRowsUseTheQualifierStrippedOfItsDelimiter() {
        val family = FandomFamily.grouped(
            listOf(
                AO3Fandom("Bleach - All Media Types", 6_412),
                AO3Fandom("Bleach (Anime & Manga)", 870),
                AO3Fandom("One Direction RPF", 10),
                AO3Fandom("Sherlock Holmes & Related Fandoms", 5)
            )
        )
        val bleach = family.first { it.parsedTitle == "Bleach" }
        assertEquals(
            setOf("All Media Types", "Anime & Manga"),
            bleach.members.map { it.qualifierDisplay }.toSet()
        )
        assertEquals("RPF", family.first { it.parsedTitle == "One Direction" }.members[0].qualifierDisplay)
        assertEquals(
            "Related Fandoms",
            family.first { it.parsedTitle == "Sherlock Holmes" }.members[0].qualifierDisplay
        )
    }

    @Test
    fun filterFlagsComeFromQualifierParts() {
        val rpf = FandomFamily.Member.from(AO3Fandom("One Direction RPF", 10))
        assertTrue(rpf.isRPF)
        assertFalse(rpf.isAllMediaTypes)
        assertFalse(rpf.isRelatedFandoms)

        val umbrella = FandomFamily.Member.from(AO3Fandom("One Piece - All Media Types", 20))
        assertTrue(umbrella.isAllMediaTypes)
        assertFalse(umbrella.isRPF)

        val related = FandomFamily.Member.from(AO3Fandom("Sherlock Holmes & Related Fandoms", 5))
        assertTrue(related.isRelatedFandoms)

        val plain = FandomFamily.Member.from(AO3Fandom("Haikyuu!!", 9))
        assertFalse(plain.isRPF)
        assertFalse(plain.isAllMediaTypes)
        assertFalse(plain.isRelatedFandoms)
    }

    @Test
    fun talliesCountRowsASwitchWouldHide() {
        val families = FandomFamily.grouped(
            listOf(
                AO3Fandom("One Direction RPF", 10),
                AO3Fandom("Harry Potter RPF", 20),
                AO3Fandom("One Piece - All Media Types", 100),
                AO3Fandom("One Piece (Anime & Manga)", 50),
                AO3Fandom("Sherlock Holmes & Related Fandoms", 5),
                AO3Fandom("Haikyuu!!", 9)
            )
        )
        val library = FandomLibraryIndex(
            favouriteNamesLowercased = setOf("haikyuu!!"),
            downloadCountsByNameLowercased = mapOf(
                "one piece (anime & manga)" to 1,
                "haikyuu!!" to 1
            )
        )
        assertEquals(2, removed(families, FandomListFilterOptions(hideRPF = true)))
        assertEquals(1, removed(families, FandomListFilterOptions(hideAllMediaTypes = true)))
        assertEquals(1, removed(families, FandomListFilterOptions(hideRelatedFandoms = true)))
        assertEquals(4, removed(families, FandomListFilterOptions(multiTagOnly = true)))
        assertEquals(2, removed(families, FandomListFilterOptions(minimumWorks = MinimumWorks.Ten)))
        assertEquals(5, removed(families, FandomListFilterOptions(favouritedOnly = true), library))
        assertEquals(4, removed(families, FandomListFilterOptions(downloadsOnly = true), library))

        val tallies = FandomFamilyFilters.tallies(families, library)
        assertEquals(2, tallies.rpfTags)
        assertEquals(1, tallies.allMediaTypesTags)
        assertEquals(1, tallies.relatedFandomsTags)
        assertEquals(1, tallies.favouritedTags)
        assertEquals(2, tallies.downloadTags)
        assertEquals(1, tallies.multiTagFamilies)
        assertEquals(5, tallies.tagsBelowMinimumWorks(MinimumWorks.Hundred))
    }

    @Test
    fun libraryIndexExposesRowMetadata() {
        val library = FandomLibraryIndex(
            favouriteNamesLowercased = setOf("haikyuu!!"),
            downloadCountsByNameLowercased = mapOf("haikyuu!!" to 3)
        )
        assertTrue(library.isFavourited("Haikyuu!!"))
        assertEquals(3, library.downloadCount("Haikyuu!!"))
    }

    @Test
    fun hidingRpfDropsThoseMembersButKeepsTheFamilyIfSiblingsRemain() {
        val families = FandomFamily.grouped(
            listOf(
                AO3Fandom("Good Omens (TV)", 100),
                AO3Fandom("Good Omens (TV) RPF", 10)
            )
        )
        val filtered = FandomFamilyFilters.apply(families, FandomListFilterOptions(hideRPF = true))
        assertEquals(1, filtered.size)
        assertEquals(1, filtered[0].memberCount)
        assertEquals(listOf("Good Omens (TV)"), filtered[0].includedFilterNames)
    }

    @Test
    fun fandomListTallyNamesSizeAndOrder() {
        assertEquals(
            "9,412 tags in 8,106 fandoms · A–Z",
            FandomListTally.text(9_412, 8_106, 9_412, false, FandomFamilySort.Alphabetical)
        )
        assertEquals(
            "1,204 of 9,412 tags · most works",
            FandomListTally.text(9_412, 8_106, 1_204, true, FandomFamilySort.FamilyTotal)
        )
        assertEquals(
            "2 tags · A–Z",
            FandomListTally.text(2, null, 2, false, FandomFamilySort.Alphabetical)
        )
        assertEquals(
            "2 tags in 1 fandom · A–Z",
            FandomListTally.text(2, 1, 2, false, FandomFamilySort.Alphabetical)
        )
    }

    private fun removed(
        families: List<FandomFamily>,
        options: FandomListFilterOptions,
        library: FandomLibraryIndex = FandomLibraryIndex.empty
    ): Int {
        val before = FandomFamilyFilters.tagCount(families)
        val after = FandomFamilyFilters.tagCount(FandomFamilyFilters.apply(families, options, library))
        return before - after
    }
}
