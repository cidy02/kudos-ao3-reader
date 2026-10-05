package io.github.cidy02.kudos.search

import io.github.cidy02.kudos.network.ao3.search.AO3Category
import io.github.cidy02.kudos.network.ao3.search.AO3ChapterCount
import io.github.cidy02.kudos.network.ao3.search.AO3Completion
import io.github.cidy02.kudos.network.ao3.search.AO3Crossover
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import io.github.cidy02.kudos.network.ao3.search.AO3Rating
import io.github.cidy02.kudos.network.ao3.search.AO3RatingMatch
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.network.ao3.search.AO3SearchSort
import io.github.cidy02.kudos.network.ao3.search.AO3SortDirection
import io.github.cidy02.kudos.network.ao3.search.AO3Updated
import io.github.cidy02.kudos.network.ao3.search.AO3Warning
import io.github.cidy02.kudos.network.ao3.search.PreservedSearchFilterValue
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatterBuilder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * iOS AO3SearchFilters Codable keys inside KudosBackupSavedSearch.filters.
 * Decode each field independently. Unrepresentable values and future keys travel
 * on the domain object, so an unrelated edit cannot silently destroy them.
 */
object SearchFiltersCodec {
    private val json = Json { isLenient = true }
    private val backupDateFormatter = DateTimeFormatterBuilder().appendInstant(3).toFormatter()

    fun encode(filters: AO3SearchFilters): String {
        val fields = canonicalFields(filters).toMutableMap()
        filters.preservedFilterValues.forEach { (key, preserved) ->
            val current = fields[key]
            if (current == preserved.decoded) {
                fields[key] = preserved.raw
            } else if (current is JsonArray && preserved.raw is JsonArray) {
                // A set edit must keep future/unreadable members the UI cannot display.
                val retained = preserved.raw.filter { item ->
                    val known = canonicalFacetItem(key, item)
                    known == null || known in current
                }
                val represented = retained.mapNotNull { canonicalFacetItem(key, it) }.toSet()
                fields[key] = JsonArray(retained + current.filter { it !in represented })
            }
        }
        return JsonObject(fields).toString()
    }

    fun decode(filtersJson: String): AO3SearchFilters {
        val fields = runCatching { json.parseToJsonElement(filtersJson) as? JsonObject }.getOrNull()
            ?: return AO3SearchFilters()
        fun text(key: String): String = stringValue(fields[key]).orEmpty()
        fun date(key: String): LocalDate? {
            val raw = stringValue(fields[key]) ?: return null
            // Backup timestamps are instants; AO3 queries use the picked local calendar day.
            return runCatching { Instant.parse(raw).atZone(ZoneId.systemDefault()).toLocalDate() }.getOrNull()
                ?: runCatching { LocalDate.parse(raw) }.getOrNull()
        }
        fun facetSet(key: String): List<String> =
            (fields[key] as? JsonArray).orEmpty().mapNotNull { item ->
                stringValue(canonicalFacetItem(key, item))
            }
        val filters = AO3SearchFilters(
            query = text("query"), title = text("title"), creators = text("creators"),
            fandom = text("fandom"), characters = text("characters"), relationships = text("relationships"),
            additionalTags = text("additionalTags"), excludedFandoms = text("excludedFandoms"),
            excludedCharacters = text("excludedCharacters"),
            excludedRelationships = text("excludedRelationships"),
            excludedAdditionalTags = text("excludedAdditionalTags"),
            rating = enumValue(AO3Rating.entries, text("rating"), AO3Rating.ANY) { it.appleCaseName },
            ratingMatch = enumValue(AO3RatingMatch.entries, text("ratingMatch"), AO3RatingMatch.EXACT) { it.appleCaseName },
            includeNotRated = (fields["includeNotRated"] as? JsonPrimitive)
                ?.takeUnless { it.isString }?.booleanOrNull ?: true,
            warnings = facetSet("warnings").mapTo(linkedSetOf()) { value ->
                AO3Warning.entries.first { it.appleCaseName == value }
            },
            excludedWarnings = facetSet("excludedWarnings").mapTo(linkedSetOf()) { value ->
                AO3Warning.entries.first { it.appleCaseName == value }
            },
            categories = facetSet("categories").mapTo(linkedSetOf()) { value ->
                AO3Category.entries.first { it.appleCaseName == value }
            },
            excludedCategories = facetSet("excludedCategories").mapTo(linkedSetOf()) { value ->
                AO3Category.entries.first { it.appleCaseName == value }
            },
            crossover = enumValue(AO3Crossover.entries, text("crossover"), AO3Crossover.ANY) { it.appleCaseName },
            completion = enumValue(AO3Completion.entries, text("completion"), AO3Completion.ANY) { it.appleCaseName },
            chapterCount = enumValue(AO3ChapterCount.entries, text("chapterCount"), AO3ChapterCount.ANY) { it.appleCaseName },
            wordsFrom = text("wordsFrom"), wordsTo = text("wordsTo"),
            hitsFrom = text("hitsFrom"), hitsTo = text("hitsTo"),
            kudosFrom = text("kudosFrom"), kudosTo = text("kudosTo"),
            commentsFrom = text("commentsFrom"), commentsTo = text("commentsTo"),
            bookmarksFrom = text("bookmarksFrom"), bookmarksTo = text("bookmarksTo"),
            updated = enumValue(AO3Updated.entries, text("updated"), AO3Updated.ANY) { it.appleCaseName },
            dateFrom = date("dateFrom"), dateTo = date("dateTo"),
            language = languageFrom(fields["language"]),
            sort = enumValue(AO3SearchSort.entries, text("sort"), AO3SearchSort.RELEVANCE) { it.appleCaseName },
            sortDirection = enumValue(AO3SortDirection.entries, text("sortDirection"), AO3SortDirection.DESCENDING) { it.appleCaseName }
        )
        val canonical = canonicalFields(filters)
        val preserved = fields.filter { (key, value) -> value != canonical[key] }
            .mapValues { (key, value) -> PreservedSearchFilterValue(value, canonical[key]) }
        return filters.copy(preservedFilterValues = preserved)
    }

    /** Swift synthesizes encode(to:) from its 37 CodingKeys; nil Date bounds are omitted. */
    private fun canonicalFields(filters: AO3SearchFilters): JsonObject = buildJsonObject {
        put("query", filters.query)
        put("title", filters.title)
        put("creators", filters.creators)
        put("fandom", filters.fandom)
        put("characters", filters.characters)
        put("relationships", filters.relationships)
        put("additionalTags", filters.additionalTags)
        put("excludedFandoms", filters.excludedFandoms)
        put("excludedCharacters", filters.excludedCharacters)
        put("excludedRelationships", filters.excludedRelationships)
        put("excludedAdditionalTags", filters.excludedAdditionalTags)
        put("rating", filters.rating.appleCaseName)
        put("ratingMatch", filters.ratingMatch.appleCaseName)
        put("includeNotRated", filters.includeNotRated)
        put("warnings", JsonArray(filters.warnings.map { JsonPrimitive(it.appleCaseName) }.sortedBy { it.content }))
        put("excludedWarnings", JsonArray(filters.excludedWarnings.map { JsonPrimitive(it.appleCaseName) }.sortedBy { it.content }))
        put("categories", JsonArray(filters.categories.map { JsonPrimitive(it.appleCaseName) }.sortedBy { it.content }))
        put("excludedCategories", JsonArray(filters.excludedCategories.map { JsonPrimitive(it.appleCaseName) }.sortedBy { it.content }))
        put("crossover", filters.crossover.appleCaseName)
        put("completion", filters.completion.appleCaseName)
        put("chapterCount", filters.chapterCount.appleCaseName)
        put("wordsFrom", filters.wordsFrom)
        put("wordsTo", filters.wordsTo)
        put("hitsFrom", filters.hitsFrom)
        put("hitsTo", filters.hitsTo)
        put("kudosFrom", filters.kudosFrom)
        put("kudosTo", filters.kudosTo)
        put("commentsFrom", filters.commentsFrom)
        put("commentsTo", filters.commentsTo)
        put("bookmarksFrom", filters.bookmarksFrom)
        put("bookmarksTo", filters.bookmarksTo)
        put("updated", filters.updated.appleCaseName)
        filters.dateFrom?.let { put("dateFrom", backupDateFormatter.format(it.atStartOfDay(ZoneId.systemDefault()).toInstant())) }
        filters.dateTo?.let { put("dateTo", backupDateFormatter.format(it.atStartOfDay(ZoneId.systemDefault()).toInstant())) }
        put("language", buildJsonObject { put("id", filters.language.code.orEmpty()) })
        put("sort", filters.sort.appleCaseName)
        put("sortDirection", filters.sortDirection.appleCaseName)
    }
}

/** Current {"id":code}, intermediate {"id":code,"title":name}, and legacy code/alias strings. */
internal fun languageFrom(element: JsonElement?): AO3Language {
    val raw = stringValue(if (element is JsonObject) element["id"] else element)
    if (raw.isNullOrEmpty()) return AO3Language.ANY
    return AO3Language.entries.firstOrNull { it.appleCaseName == raw || it.code == raw } ?: AO3Language.ANY
}

private fun stringValue(element: JsonElement?): String? =
    (element as? JsonPrimitive)?.takeIf { it.isString }?.content

private fun <T : Enum<T>> enumValue(entries: List<T>, raw: String, default: T, appleCase: (T) -> String): T =
    entries.firstOrNull { appleCase(it).equals(raw.trim(), ignoreCase = true) || it.name.equals(raw.trim(), ignoreCase = true) }
        ?: default

/** iOS Warning/Category custom decoders accept both case names and legacy string AO3 IDs. */
private fun canonicalFacetItem(key: String, item: JsonElement): JsonPrimitive? {
    val value = stringValue(item) ?: return null
    val token = when (key) {
        "warnings", "excludedWarnings" -> AO3Warning.entries.firstOrNull {
            it.ao3Id == value || it.appleCaseName.equals(value, ignoreCase = true) || it.name.equals(value, ignoreCase = true)
        }?.appleCaseName
        "categories", "excludedCategories" -> AO3Category.entries.firstOrNull {
            it.ao3Id == value || it.appleCaseName.equals(value, ignoreCase = true) || it.name.equals(value, ignoreCase = true)
        }?.appleCaseName
        else -> null
    }
    return token?.let { JsonPrimitive(it) }
}
