package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.network.ao3.search.AO3ChapterCount
import io.github.cidy02.kudos.network.ao3.search.AO3SortDirection
import io.github.cidy02.kudos.network.ao3.search.AO3Category
import io.github.cidy02.kudos.network.ao3.search.AO3Completion
import io.github.cidy02.kudos.network.ao3.search.AO3Crossover
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.network.ao3.search.AO3RatingMatch
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3Updated
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatterBuilder
import java.util.TimeZone
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchFiltersCodecTest {
    @Test
    fun roundTripsFullFilterSet() {
        val original = AO3SearchFilters(
            query = "slow burn",
            fandom = "Naruto",
            characters = "Naruto, Sasuke",
            relationships = "Naruto/Sasuke",
            additionalTags = "Fluff",
            excludedFandoms = "Crossover",
            excludedCharacters = "Sakura",
            excludedRelationships = "Naruto/Hinata",
            excludedAdditionalTags = "Angst",
            rating = AO3Rating.MATURE,
            ratingMatch = AO3RatingMatch.OR_HIGHER,
            includeNotRated = false,
            warnings = setOf(AO3Warning.VIOLENCE, AO3Warning.DEATH),
            excludedWarnings = setOf(AO3Warning.UNDERAGE),
            categories = setOf(AO3Category.MM),
            excludedCategories = setOf(AO3Category.OTHER),
            crossover = AO3Crossover.EXCLUDE,
            completion = AO3Completion.COMPLETE,
            wordsFrom = "1000",
            wordsTo = "50000",
            updated = AO3Updated.YEAR,
            language = AO3Language.ENGLISH,
            sort = AO3SearchSort.KUDOS
        )

        val encoded = SearchFiltersCodec.encode(original)
        val decoded = SearchFiltersCodec.decode(encoded)

        assertEquals(original, decoded)
        assertTrue(encoded.contains("\"rating\":\"mature\""))
        assertTrue(encoded.contains("\"ratingMatch\":\"orHigher\""))
        assertTrue(encoded.contains("\"sort\":\"kudos\""))
        assertTrue(encoded.contains("\"violence\""))
        assertTrue(encoded.contains("\"mm\""))
    }

    @Test
    fun roundTripsEmptyDefaults() {
        val original = AO3SearchFilters()
        assertEquals(original, SearchFiltersCodec.decode(SearchFiltersCodec.encode(original)))
    }

    @Test
    fun decodesAppleStylePayload() {
        val appleJson = """
            {
              "query": "found family",
              "fandom": "The Untamed",
              "characters": "",
              "relationships": "",
              "additionalTags": "",
              "excludedFandoms": "",
              "excludedCharacters": "",
              "excludedRelationships": "",
              "excludedAdditionalTags": "",
              "rating": "teen",
              "ratingMatch": "exact",
              "includeNotRated": true,
              "warnings": ["noWarnings"],
              "excludedWarnings": [],
              "categories": ["mm"],
              "excludedCategories": [],
              "crossover": "any",
              "completion": "complete",
              "wordsFrom": "",
              "wordsTo": "",
              "updated": "any",
              "language": "english",
              "sort": "dateUpdated"
            }
        """.trimIndent()

        val filters = SearchFiltersCodec.decode(appleJson)
        assertEquals("found family", filters.query)
        assertEquals("The Untamed", filters.fandom)
        assertEquals(AO3Rating.TEEN, filters.rating)
        assertEquals(setOf(AO3Warning.NO_WARNINGS), filters.warnings)
        assertEquals(setOf(AO3Category.MM), filters.categories)
        assertEquals(AO3Completion.COMPLETE, filters.completion)
        assertEquals(AO3SearchSort.DATE_UPDATED, filters.sort)
    }

    @Test
    fun blankOrInvalidJsonFallsBackToEmptyFilters() {
        assertEquals(AO3SearchFilters(), SearchFiltersCodec.decode(""))
        assertEquals(AO3SearchFilters(), SearchFiltersCodec.decode("not-json"))
        assertEquals(AO3SearchFilters(), SearchFiltersCodec.decode("{}"))
    }

    @Test
    fun unknownEnumValuesUseDefaults() {
        val json = """
            {
              "query": "x",
              "rating": "not-a-rating",
              "sort": "mystery",
              "warnings": ["noWarnings", "unknownWarning"]
            }
        """.trimIndent()

        val filters = SearchFiltersCodec.decode(json)
        assertEquals("x", filters.query)
        assertEquals(AO3Rating.ANY, filters.rating)
        assertEquals(AO3SearchSort.RELEVANCE, filters.sort)
        assertEquals(setOf(AO3Warning.NO_WARNINGS), filters.warnings)
        // Known warning is usable; the unknown token is preserved for re-saving.
        assertTrue(filters.hasActiveFilters)
    }

    @Test
    fun anAppleLanguageObjectDoesNotDiscardEveryOtherFilter() {
        // Apple's `Language` became a struct, so its saved searches carry an
        // *object* here where this app declared a String. That is a type mismatch,
        // and `decode` catches the failure by returning default filters — so one
        // unreadable language silently threw away the whole saved search. The
        // field is a raw JsonElement now precisely so this cannot happen.
        val json = """
            {"query":"time travel","fandom":"Naruto","wordsFrom":"1000",
             "language":{"id":"fr","title":"Français"},"sort":"kudos"}
        """.trimIndent()

        val filters = SearchFiltersCodec.decode(json)
        assertEquals("time travel", filters.query)
        assertEquals("Naruto", filters.fandom)
        assertEquals("1000", filters.wordsFrom)
        assertEquals(AO3SearchSort.KUDOS, filters.sort)
        assertEquals(AO3Language.FRENCH, filters.language)
    }

    @Test
    fun everyLanguageShapeEverWrittenStillDecodes() {
        fun language(raw: String): AO3Language =
            SearchFiltersCodec.decode("""{"language":$raw}""").language

        // This app's own older payloads.
        assertEquals(AO3Language.FRENCH, language(""""french""""))
        // Apple's original bare-string enum, whose raw value was AO3's code.
        assertEquals(AO3Language.FRENCH, language(""""fr""""))
        // Apple today, and the intermediate shape that also carried a title.
        assertEquals(AO3Language.FRENCH, language("""{"id":"fr"}"""))
        assertEquals(AO3Language.FRENCH, language("""{"id":"fr","title":"Français"}"""))
        // Unset, empty and unrecognised all mean "no language filter" — never a throw.
        assertEquals(AO3Language.ANY, language("""""""))
        assertEquals(AO3Language.ANY, language("null"))
        assertEquals(AO3Language.ANY, language(""""klingon""""))
        assertEquals(AO3Language.ANY, language("""{"id":"zzz"}"""))
        assertEquals(AO3Language.ANY, language("""{}"""))
    }

    @Test
    fun languageIsWrittenAsIOSsIDObject() {
        val encoded = jsonObject(SearchFiltersCodec.encode(AO3SearchFilters(language = AO3Language.FRENCH)))
        assertEquals(jsonObject("""{"id":"fr"}"""), encoded["language"])
        val any = jsonObject(SearchFiltersCodec.encode(AO3SearchFilters()))
        assertEquals(jsonObject("""{"id":""}"""), any["language"])
        val filters = AO3SearchFilters(query = "x", language = AO3Language.JAPANESE)
        assertEquals(filters, SearchFiltersCodec.decode(SearchFiltersCodec.encode(filters)))
    }

    private fun jsonObject(text: String): JsonObject = Json.parseToJsonElement(text) as JsonObject

    // Every CodingKey in iOS AO3Models.swift:267–273; date strings follow KudosBackupContents.makeEncoder.
    private val allIOSKeys = """
        {
          "query":"slow burn", "title":"A Title", "creators":"writer_pseud",
          "fandom":"Naruto", "characters":"Naruto, Sasuke", "relationships":"Naruto/Sasuke",
          "additionalTags":"Fluff", "excludedFandoms":"Bleach", "excludedCharacters":"Sakura",
          "excludedRelationships":"Naruto/Hinata", "excludedAdditionalTags":"Angst",
          "rating":"mature", "ratingMatch":"orHigher", "includeNotRated":false,
          "warnings":["violence","death"], "excludedWarnings":["underage"],
          "categories":["mm"], "excludedCategories":["other"],
          "crossover":"exclude", "completion":"complete", "chapterCount":"singleChapter",
          "wordsFrom":"1000", "wordsTo":"50000", "hitsFrom":"101", "hitsTo":"202",
          "kudosFrom":"11", "kudosTo":"22", "commentsFrom":"3", "commentsTo":"4",
          "bookmarksFrom":"5", "bookmarksTo":"6", "updated":"year",
          "dateFrom":"2024-01-31T00:30:00.123Z", "dateTo":"2025-12-25T23:30:00.987Z",
          "language":{"id":"fr"}, "sort":"workTitle", "sortDirection":"ascending"
        }
    """.trimIndent()

    @Test
    fun everyIOSKeyRoundTripsItsExactJSONValue() {
        val input = jsonObject(allIOSKeys)
        assertEquals(37, input.size)
        val decoded = SearchFiltersCodec.decode(allIOSKeys)
        assertEquals(AO3ChapterCount.SINGLE_CHAPTER, decoded.chapterCount)
        assertEquals(AO3SortDirection.ASCENDING, decoded.sortDirection)
        assertEquals(AO3SearchSort.TITLE, decoded.sort)
        assertEquals("A Title", decoded.title)
        assertEquals("writer_pseud", decoded.creators)
        assertEquals("101", decoded.hitsFrom)
        assertEquals("22", decoded.kudosTo)
        assertEquals("3", decoded.commentsFrom)
        assertEquals("6", decoded.bookmarksTo)
        assertEquals(AO3Language.FRENCH, decoded.language)
        assertEquals(Instant.parse("2024-01-31T00:30:00.123Z").atZone(ZoneId.systemDefault()).toLocalDate(),
            decoded.dateFrom)
        assertEquals(input, jsonObject(SearchFiltersCodec.encode(decoded)))
        val edited = jsonObject(SearchFiltersCodec.encode(decoded.copy(query = "changed on Android")))
        assertEquals(input.keys, edited.keys)
        input.filterKeys { it != "query" }.forEach { (key, value) -> assertEquals(key, value, edited[key]) }
        assertEquals(JsonPrimitive("changed on Android"), edited["query"])
    }

    @Test
    fun eachAndroidFacetUsesIOSsKeyAndRawValue() {
        val dateFrom = LocalDate.of(2024, 1, 31)
        val dateTo = LocalDate.of(2025, 12, 25)
        val filters = AO3SearchFilters(
            title = "Title", creators = "Creator", chapterCount = AO3ChapterCount.SINGLE_CHAPTER,
            hitsFrom = "100", hitsTo = "200", kudosFrom = "10", kudosTo = "20",
            commentsFrom = "1", commentsTo = "2", bookmarksFrom = "3", bookmarksTo = "4",
            sort = AO3SearchSort.CREATOR, sortDirection = AO3SortDirection.ASCENDING,
            dateFrom = dateFrom, dateTo = dateTo
        )
        val output = jsonObject(SearchFiltersCodec.encode(filters))
        val expectedStrings = mapOf(
            "title" to "Title", "creators" to "Creator", "chapterCount" to "singleChapter",
            "hitsFrom" to "100", "hitsTo" to "200", "kudosFrom" to "10", "kudosTo" to "20",
            "commentsFrom" to "1", "commentsTo" to "2", "bookmarksFrom" to "3", "bookmarksTo" to "4",
            "sort" to "creator", "sortDirection" to "ascending"
        )
        expectedStrings.forEach { (key, value) -> assertEquals(key, JsonPrimitive(value), output[key]) }
        val dateFormatter = DateTimeFormatterBuilder().appendInstant(3).toFormatter()
        assertEquals(JsonPrimitive(dateFormatter.format(dateFrom.atStartOfDay(ZoneId.systemDefault()).toInstant())),
            output["dateFrom"])
        assertEquals(JsonPrimitive(dateFormatter.format(dateTo.atStartOfDay(ZoneId.systemDefault()).toInstant())),
            output["dateTo"])
        assertEquals(filters, SearchFiltersCodec.decode(SearchFiltersCodec.encode(filters)))
        val defaults = jsonObject(SearchFiltersCodec.encode(AO3SearchFilters()))
        assertFalse(defaults.containsKey("dateFrom"))
        assertFalse(defaults.containsKey("dateTo"))
        assertEquals(JsonPrimitive("descending"), defaults["sortDirection"])
        assertEquals(JsonPrimitive("any"), defaults["chapterCount"])
    }

    @Test
    fun anUnknownFutureKeySurvivesAnAndroidEdit() {
        val original = jsonObject(allIOSKeys).toMutableMap()
        original["futureFilter"] = jsonObject("""{"enabled":true,"values":[1,"two",null]}""")
        val decoded = SearchFiltersCodec.decode(JsonObject(original).toString())
        val output = jsonObject(SearchFiltersCodec.encode(decoded.copy(title = "Edited")))
        assertEquals(original["futureFilter"], output["futureFilter"])
        original.filterKeys { it != "title" }.forEach { (key, value) -> assertEquals(key, value, output[key]) }
        assertEquals(JsonPrimitive("Edited"), output["title"])
    }

    @Test
    fun oneMalformedFieldNeverLosesTheOtherFields() {
        val valid = jsonObject(allIOSKeys)
        for (key in valid.keys) {
            val broken = JsonObject(valid.toMutableMap().apply { this[key] = jsonObject("""{"broken":true}""") })
            val decoded = SearchFiltersCodec.decode(broken.toString())
            assertEquals(if (key == "query") "" else "slow burn", decoded.query)
            assertEquals(if (key == "title") "" else "A Title", decoded.title)
            assertEquals(if (key == "includeNotRated") true else false, decoded.includeNotRated)
            if (key == "hitsFrom") assertEquals("", decoded.hitsFrom)
            if (key == "dateFrom") assertNull(decoded.dateFrom)
            if (key == "rating") assertEquals(AO3Rating.ANY, decoded.rating)
            if (key == "warnings") assertTrue(decoded.warnings.isEmpty())
            // Unreadable values remain available to a future decoder; none of the other 36 keys is lost.
            assertEquals(key, broken, jsonObject(SearchFiltersCodec.encode(decoded)))
        }
    }

    @Test
    fun unrepresentableValuesAndLegacyFacetIDsRemainLossless() {
        val original = jsonObject(allIOSKeys).toMutableMap().apply {
            this["language"] = jsonObject("""{"id":"future-language","title":"Future Language","extra":7}""")
            this["rating"] = JsonPrimitive("futureRating")
            this["sort"] = JsonPrimitive("futureSort")
            this["warnings"] = Json.parseToJsonElement("""["17","unknownWarning",{"future":true}]""")
            this["categories"] = Json.parseToJsonElement("""["23","futureCategory"]""")
            this["dateTo"] = JsonPrimitive(123.456) // Not a backup ISO timestamp; kept raw.
        }
        val decoded = SearchFiltersCodec.decode(JsonObject(original).toString())
        assertEquals(AO3Language.ANY, decoded.language)
        assertEquals(AO3Rating.ANY, decoded.rating)
        assertEquals(AO3SearchSort.RELEVANCE, decoded.sort)
        assertEquals(setOf(AO3Warning.VIOLENCE), decoded.warnings)
        assertEquals(setOf(AO3Category.MM), decoded.categories)
        assertNull(decoded.dateTo)
        assertEquals(JsonObject(original), jsonObject(SearchFiltersCodec.encode(decoded)))
        val edited = jsonObject(SearchFiltersCodec.encode(decoded.copy(
            warnings = decoded.warnings + AO3Warning.DEATH,
            categories = decoded.categories + AO3Category.GEN
        )))
        assertEquals(Json.parseToJsonElement("""["17","unknownWarning",{"future":true},"death"]"""), edited["warnings"])
        assertEquals(Json.parseToJsonElement("""["23","futureCategory","gen"]"""), edited["categories"])
        assertEquals(original["dateTo"], edited["dateTo"])
        assertEquals(original["language"], edited["language"])
    }

    @Test
    fun changingAControlReplacesOnlyItsPreservedValue() {
        val decoded = SearchFiltersCodec.decode(allIOSKeys)
        val newDate = decoded.dateFrom!!.plusDays(1)
        val output = jsonObject(SearchFiltersCodec.encode(decoded.copy(dateFrom = newDate)))
        val formatter = DateTimeFormatterBuilder().appendInstant(3).toFormatter()
        assertEquals(JsonPrimitive(formatter.format(newDate.atStartOfDay(ZoneId.systemDefault()).toInstant())),
            output["dateFrom"])
        assertEquals(jsonObject(allIOSKeys)["dateTo"], output["dateTo"])
        val cleared = jsonObject(SearchFiltersCodec.encode(decoded.copy(dateFrom = null)))
        assertFalse(cleared.containsKey("dateFrom"))
        assertEquals(jsonObject(allIOSKeys)["dateTo"], cleared["dateTo"])
    }

    @Test
    fun everyLegacyLanguageShapeAlsoSurvivesResaving() {
        for (raw in listOf(
            """"fr"""", """{"id":"fr"}""", """{"id":"fr","title":"Français"}""",
            """"french"""", """{"id":"zzz","future":true}"""
        )) {
            val input = jsonObject("""{"query":"x","language":$raw}""")
            val output = jsonObject(SearchFiltersCodec.encode(SearchFiltersCodec.decode(input.toString()).copy(title = "Edited")))
            assertEquals(input["language"], output["language"])
            assertEquals(JsonPrimitive("x"), output["query"])
        }
    }
    @Test
    fun androidDateBoundsKeepThePickedDayAcrossTimeZones() {
        val originalZone = TimeZone.getDefault()
        try {
            val day = LocalDate.of(2024, 1, 31)
            val expected = mapOf(
                "Pacific/Kiritimati" to "2024-01-30T10:00:00.000Z",
                "America/New_York" to "2024-01-31T05:00:00.000Z",
                "Europe/Paris" to "2024-01-30T23:00:00.000Z"
            )
            for ((zone, timestamp) in expected) {
                TimeZone.setDefault(TimeZone.getTimeZone(zone))
                val encoded = SearchFiltersCodec.encode(AO3SearchFilters(dateFrom = day))
                assertEquals(zone, JsonPrimitive(timestamp), jsonObject(encoded)["dateFrom"])
                assertEquals(zone, day, SearchFiltersCodec.decode(encoded).dateFrom)
            }
        } finally {
            TimeZone.setDefault(originalZone)
        }
    }

    @Test
    fun valuesThePanelDoesNotExposeStillSaveAndOnlyExplicitResetClearsThem() {
        val input = jsonObject("""{"rating":"notRated","language":{"id":"future"},"futureFacet":["value"]}""")
        val decoded = SearchFiltersCodec.decode(input.toString())
        assertEquals(AO3Rating.NOT_RATED, decoded.rating)
        assertTrue(decoded.isSearchable)
        val encoded = jsonObject(SearchFiltersCodec.encode(decoded.copy(wordsFrom = "1000")))
        input.forEach { (key, value) -> assertEquals(key, value, encoded[key]) }
        val reset = jsonObject(SearchFiltersCodec.encode(clearedFiltersPreservingQuery(decoded)))
        assertFalse(reset.containsKey("futureFacet"))
        assertEquals(jsonObject("""{"id":""}"""), reset["language"])
        assertEquals(JsonPrimitive("any"), reset["rating"])
    }

}
