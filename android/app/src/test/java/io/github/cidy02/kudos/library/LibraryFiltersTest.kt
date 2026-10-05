package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Matching regressions named after iOS KudosTests/LibraryFiltersTests.swift. */
class LibraryFiltersTest {
    private fun work(title: String) = SavedWork(id = title, title = title, author = "Writer")

    private fun matching(filters: LibraryFilterState, vararg works: SavedWork): List<String> =
        LibraryQuery.filterOnly(works.map { LibraryDisplayItem(LibraryWorkListItem(it)) }, filters = filters)
            .map { it.item.work.title }

    @Test
    fun fandomFacetUsesCategorizedTagsAndFallsBackToFlatTags() {
        val categorized = work("Categorized").copy(workFandoms = listOf("Fandom A"))
        val flatOnly = work("FlatOnly").copy(workTags = listOf("Fandom A", "Fluff"))
        val neither = work("Neither").copy(workFandoms = listOf("Fandom B"), workTags = listOf("Fandom A"))
        assertEquals(listOf("Categorized", "FlatOnly"), matching(
            LibraryFilterState(fandoms = setOf("Fandom A")), categorized, flatOnly, neither
        ))
    }

    @Test
    fun fandomFacetMatchesTheSameFamily() {
        val who = work("Who").copy(workFandoms = listOf("Doctor Who (2005)"))
        assertEquals(listOf("Who"), matching(LibraryFilterState(fandoms = setOf("Doctor Who")), who))
        assertTrue(matching(LibraryFilterState(fandoms = setOf("doctor who")), who).isEmpty())
    }

    @Test
    fun excludeTagsRejectAnyFlatTagMatch() {
        val angsty = work("Angsty").copy(workTags = listOf("Angst"))
        val fluffy = work("Fluffy").copy(workTags = listOf("Fluff"))
        val filters = LibraryFilterState(excludeTags = setOf("Angst", "Violence"))
        assertEquals(listOf("Fluffy"), matching(filters, angsty, fluffy))
        // Library exclusions use exact flat-tag membership, not Search's substring rule.
        assertEquals(listOf("Angsty"), matching(filters.copy(excludeTags = setOf("angst")), angsty))
        assertEquals(listOf("Angsty"), matching(filters.copy(excludeTags = setOf("Ang")), angsty))
        assertEquals(listOf("Fluffy"), matching(filters, fluffy.copy(workFreeforms = listOf("Angst"))))
    }

    @Test
    fun userTagFacetMatchesTheTagRelationship() {
        val tagged = LibraryDisplayItem(LibraryWorkListItem(
            work("Tagged"), userTags = listOf(Tag(id = "comfort", name = "comfort reads"))
        ))
        val untagged = LibraryDisplayItem(LibraryWorkListItem(work("Untagged")))
        assertEquals(listOf("Tagged"), LibraryQuery.filterOnly(
            listOf(tagged, untagged), filters = LibraryFilterState(userTagIds = setOf("comfort"))
        ).map { it.item.work.title })
    }

    @Test
    fun ratingMatchesLenientText() {
        val teen = work("Teen").copy(rating = "Teen And Up Audiences")
        val explicit = work("Explicit").copy(rating = "Explicit")
        val filters = LibraryFilterState(rating = AO3Rating.TEEN)
        assertEquals(listOf("Teen"), matching(filters, teen, explicit))
        assertEquals(listOf("Teen"), matching(filters, teen.copy(rating = "TEEN and up")))
        assertTrue(matching(filters, teen.copy(rating = "T")).isEmpty())
        assertTrue(matching(filters, teen.copy(rating = "")).isEmpty())
        val words = mapOf(
            AO3Rating.GENERAL to "General Audiences", AO3Rating.TEEN to "Teen And Up Audiences",
            AO3Rating.MATURE to "Mature", AO3Rating.EXPLICIT to "Explicit", AO3Rating.NOT_RATED to "Not Rated"
        )
        words.forEach { (rating, text) ->
            assertEquals(listOf("Teen"), matching(filters.copy(rating = rating), teen.copy(rating = text)))
        }
        assertEquals(listOf("Teen", "Explicit"), matching(filters.copy(rating = AO3Rating.ANY), teen, explicit))
    }

    @Test
    fun underageWarningMatchesBothAO3Spellings() {
        val epub = work("EPUB").copy(workWarnings = listOf("Underage Sex"))
        val page = work("Page").copy(workWarnings = listOf("Underage"))
        val flat = work("Flat").copy(workTags = listOf("UNDERAGE"))
        val clean = work("Clean").copy(workWarnings = listOf("No Archive Warnings Apply"))
        val filters = LibraryFilterState(warnings = setOf("Underage Sex"))
        assertEquals(listOf("EPUB", "Page", "Flat"), matching(filters, epub, page, flat, clean))
        // When categorized metadata exists, unrelated flat tags don't override it.
        assertTrue(matching(filters, clean.copy(workTags = listOf("Underage Sex"))).isEmpty())
        assertTrue(matching(filters, epub.copy(workWarnings = listOf("Underage Sex Mentioned"))).isEmpty())
    }

    @Test
    fun warningAndCategorySelectionsRequireEveryChoice() {
        val both = work("Both").copy(
            workWarnings = listOf("Underage", "MAJOR CHARACTER DEATH"), workCategories = listOf("f/f", "Multi")
        )
        val filters = LibraryFilterState(
            warnings = setOf("Underage Sex", "Major Character Death"), categories = setOf("F/F", "Multi")
        )
        assertEquals(listOf("Both"), matching(filters, both))
        assertTrue(matching(filters, both.copy(workWarnings = listOf("Underage"))).isEmpty())
        assertTrue(matching(filters, both.copy(workCategories = listOf("F/F"))).isEmpty())
        assertEquals(listOf("Both"), matching(filters, both.copy(
            workWarnings = emptyList(), workCategories = emptyList(),
            workTags = listOf("Underage", "Major Character Death", "F/F", "Multi")
        )))
    }

    @Test
    fun categorizedIncludesRequireExactTagsAndFallBackOnlyWhenEmpty() {
        val filters = LibraryFilterState(
            characters = setOf("Katara", "Toph"), relationships = setOf("Katara/Toph"), freeforms = setOf("Fluff")
        )
        val flat = work("Flat").copy(workTags = listOf("Katara", "Toph", "Katara/Toph", "Fluff"))
        assertEquals(listOf("Flat"), matching(filters, flat))
        assertTrue(matching(filters, flat.copy(workCharacters = listOf("Katara"))).isEmpty())
        assertTrue(matching(filters, flat.copy(workRelationships = listOf("Katara/Toph Beifong"))).isEmpty())
        assertTrue(matching(filters, flat.copy(workFreeforms = listOf("fluff"))).isEmpty())
    }

    @Test
    fun completionFacetSplitsCompleteAndWIP() {
        val complete = work("Complete").copy(isComplete = true)
        val wip = work("WIP").copy(isComplete = false)
        assertEquals(listOf("Complete"), matching(
            LibraryFilterState(completion = LibraryCompletionFilter.Complete), complete, wip
        ))
        assertEquals(listOf("WIP"), matching(
            LibraryFilterState(completion = LibraryCompletionFilter.InProgress), complete, wip
        ))
    }

    @Test
    fun languageMatchesCaseInsensitively() {
        val english = work("English").copy(language = "English")
        val french = work("French").copy(language = "Français")
        val filters = LibraryFilterState(language = "english")
        assertEquals(listOf("English"), matching(filters, english, french))
        assertTrue(matching(filters, english.copy(language = "")).isEmpty())
        assertTrue(matching(filters.copy(language = " English "), english).isEmpty())
        assertEquals(listOf("English", "French"), matching(filters.copy(language = ""), english, french))
    }

    @Test
    fun wordBoundsSkipWorksWithUnknownCounts() {
        val known = work("Known").copy(wordCount = 5000)
        val unknown = work("Unknown")
        val big = work("Big").copy(wordCount = 100000)
        val filters = LibraryFilterState(wordsFrom = "1,000", wordsTo = "10,000")
        assertEquals(listOf("Known", "Unknown"), matching(filters, known, unknown, big))
        assertEquals(listOf("Known", "Unknown"), matching(filters, known.copy(wordCount = 1000), unknown))
        assertEquals(listOf("Known"), matching(filters, known.copy(wordCount = 10000)))
        assertEquals(listOf("Unknown"), matching(filters.copy(wordsFrom = "10,001"), known, unknown, big))
        assertEquals(listOf("Unknown"), matching(filters, unknown.copy(wordCount = -1)))
    }

    @Test
    fun wordBoundsIgnoreNonDigitsAndUnparseableBounds() {
        val known = work("Known").copy(wordCount = 5000)
        assertEquals(listOf("Known"), matching(LibraryFilterState(wordsFrom = "1k000 words", wordsTo = "10 000"), known))
        assertEquals(listOf("Known"), matching(LibraryFilterState(wordsFrom = "abc", wordsTo = " "), known))
        assertEquals(listOf("Known"), matching(LibraryFilterState(wordsFrom = "99999999999999999999999999"), known))
        // Swift Int is 64-bit: a valid large lower bound is a constraint, not a parse failure.
        assertTrue(matching(LibraryFilterState(wordsFrom = "2147483648"), known).isEmpty())
    }

    @Test
    fun newFieldsCombineWithExistingFiltersAndBothQueryPaths() {
        val yes = work("Yes").copy(isFavorite = true, rating = "Teen And Up", language = "English", wordCount = 5000)
        val no = yes.copy(id = "No", title = "No", workTags = listOf("Angst"))
        val filters = LibraryFilterState(
            favoriteOnly = true, rating = AO3Rating.TEEN, language = "english", wordsFrom = "1000",
            wordsTo = "10000", excludeTags = setOf("Angst")
        )
        assertEquals(listOf("Yes"), matching(filters, yes, no))
        assertEquals(listOf("Yes"), LibraryQuery.apply(
            listOf(yes, no).map { LibraryDisplayItem(LibraryWorkListItem(it)) }, filters = filters
        ).map { it.item.work.title })
        assertTrue(matching(filters, yes.copy(isFavorite = false)).isEmpty())
    }

    @Test
    fun defaultsAndActiveCountCoverAllNewFields() {
        val defaults = LibraryFilterState()
        assertFalse(defaults.hasActiveFilters)
        assertEquals(0, defaults.activeCount)
        assertEquals(AO3Rating.ANY, defaults.rating)
        assertEquals("", defaults.language)
        assertEquals("", defaults.wordsFrom)
        assertEquals("", defaults.wordsTo)
        assertTrue(defaults.excludeTags.isEmpty())
        val variants = listOf(
            defaults.copy(rating = AO3Rating.TEEN), defaults.copy(language = "English"),
            defaults.copy(wordsFrom = "1,000"), defaults.copy(wordsTo = "10,000"),
            defaults.copy(excludeTags = setOf("Angst"))
        )
        variants.forEach { assertTrue(it.hasActiveFilters); assertEquals(1, it.activeCount) }
        assertEquals(1, defaults.copy(wordsFrom = "1000", wordsTo = "10000").activeCount)
        assertFalse(defaults.copy(wordsFrom = " ", wordsTo = "\n").hasActiveFilters)
        assertEquals(2, defaults.copy(excludeTags = setOf("Angst", "Fluff")).activeCount)
        assertTrue(defaults.copy(wordsFrom = "not a number").hasActiveFilters)
        // Appending fields leaves existing construction/copy behavior intact.
        assertTrue(defaults.copy(userTagIds = setOf("comfort")).copy(language = "English").userTagIds.contains("comfort"))
    }
}
