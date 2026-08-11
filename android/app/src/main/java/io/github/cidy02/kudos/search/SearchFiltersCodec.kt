package io.github.cidy02.kudos.search

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
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * Encode/decode [AO3SearchFilters] for [io.github.cidy02.kudos.core.model.SavedSearch.filtersJson].
 *
 * Enum cases use Apple's camelCase raw values (`appleCaseName`) so the JSON is
 * semantically compatible with Swift `AO3SearchFilters` Codable payloads stored
 * in `.kudosbackup` / Room.
 */
object SearchFiltersCodec {
    private val json = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    }

    fun encode(filters: AO3SearchFilters): String {
        return json.encodeToString(filters.toDto())
    }

    fun decode(filtersJson: String): AO3SearchFilters {
        if (filtersJson.isBlank()) return AO3SearchFilters()
        return try {
            json.decodeFromString<AO3SearchFiltersDto>(filtersJson).toDomain()
        } catch (_: Exception) {
            AO3SearchFilters()
        }
    }
}

@Serializable
internal data class AO3SearchFiltersDto(
    val query: String = "",
    val fandom: String = "",
    val characters: String = "",
    val relationships: String = "",
    val additionalTags: String = "",
    val excludedFandoms: String = "",
    val excludedCharacters: String = "",
    val excludedRelationships: String = "",
    val excludedAdditionalTags: String = "",
    val rating: String = AO3Rating.ANY.appleCaseName,
    val ratingMatch: String = AO3RatingMatch.EXACT.appleCaseName,
    val includeNotRated: Boolean = true,
    val warnings: List<String> = emptyList(),
    val excludedWarnings: List<String> = emptyList(),
    val categories: List<String> = emptyList(),
    val excludedCategories: List<String> = emptyList(),
    val crossover: String = AO3Crossover.ANY.appleCaseName,
    val completion: String = AO3Completion.ANY.appleCaseName,
    val wordsFrom: String = "",
    val wordsTo: String = "",
    val updated: String = AO3Updated.ANY.appleCaseName,
    /**
     * Deliberately a raw [JsonElement], not a `String`, because this one field has
     * been written three different ways and a type mismatch here is not survivable:
     * `decode` catches the failure and returns default filters, so one unreadable
     * language silently discards *every other filter* in the saved search.
     *
     *  - `"french"` — this app's own older payloads (`appleCaseName`).
     *  - `"fr"` — Apple's original `enum Language: String`, whose raw value was
     *    AO3's language code.
     *  - `{"id": "fr"}` / `{"id": "fr", "title": "Français"}` — Apple today, after
     *    `Language` became a struct.
     *
     * [languageFrom] accepts all four.
     */
    val language: JsonElement? = null,
    val sort: String = AO3SearchSort.RELEVANCE.appleCaseName
)

/**
 * Resolves the language from whichever shape the payload used. Falls back to
 * [AO3Language.ANY] rather than throwing — an unknown language is worth losing,
 * the other twenty filters are not.
 */
internal fun languageFrom(element: JsonElement?): AO3Language {
    val raw = when (element) {
        is JsonPrimitive -> element.contentOrNull
        is JsonObject -> (element["id"] as? JsonPrimitive)?.contentOrNull
        else -> null
    }
    if (raw.isNullOrEmpty()) return AO3Language.ANY
    return AO3Language.entries.firstOrNull { it.appleCaseName == raw }
        ?: AO3Language.entries.firstOrNull { it.code == raw }
        ?: AO3Language.ANY
}

internal fun AO3SearchFilters.toDto(): AO3SearchFiltersDto {
    return AO3SearchFiltersDto(
        query = query,
        fandom = fandom,
        characters = characters,
        relationships = relationships,
        additionalTags = additionalTags,
        excludedFandoms = excludedFandoms,
        excludedCharacters = excludedCharacters,
        excludedRelationships = excludedRelationships,
        excludedAdditionalTags = excludedAdditionalTags,
        rating = rating.appleCaseName,
        ratingMatch = ratingMatch.appleCaseName,
        includeNotRated = includeNotRated,
        warnings = warnings.map { it.appleCaseName }.sorted(),
        excludedWarnings = excludedWarnings.map { it.appleCaseName }.sorted(),
        categories = categories.map { it.appleCaseName }.sorted(),
        excludedCategories = excludedCategories.map { it.appleCaseName }.sorted(),
        crossover = crossover.appleCaseName,
        completion = completion.appleCaseName,
        wordsFrom = wordsFrom,
        wordsTo = wordsTo,
        updated = updated.appleCaseName,
        // AO3's language code ("fr"), not this app's `appleCaseName` ("french").
        // The code is what Apple's `Language.id` holds and what its decoder reads
        // out of a bare string, so writing it is what makes this payload actually
        // portable — the KDoc above has always claimed compatibility, and for this
        // field it was not true. Older builds of this app read it back through
        // `languageFrom`'s `code` branch. `ANY` has no code and writes "".
        language = JsonPrimitive(language.code ?: ""),
        sort = sort.appleCaseName
    )
}

internal fun AO3SearchFiltersDto.toDomain(): AO3SearchFilters {
    return AO3SearchFilters(
        query = query,
        fandom = fandom,
        characters = characters,
        relationships = relationships,
        additionalTags = additionalTags,
        excludedFandoms = excludedFandoms,
        excludedCharacters = excludedCharacters,
        excludedRelationships = excludedRelationships,
        excludedAdditionalTags = excludedAdditionalTags,
        rating = enumByAppleCase(AO3Rating.entries, rating, AO3Rating.ANY) { it.appleCaseName },
        ratingMatch = enumByAppleCase(
            AO3RatingMatch.entries,
            ratingMatch,
            AO3RatingMatch.EXACT
        ) { it.appleCaseName },
        includeNotRated = includeNotRated,
        warnings = enumSetByAppleCase(AO3Warning.entries, warnings) { it.appleCaseName },
        excludedWarnings = enumSetByAppleCase(
            AO3Warning.entries,
            excludedWarnings
        ) { it.appleCaseName },
        categories = enumSetByAppleCase(AO3Category.entries, categories) { it.appleCaseName },
        excludedCategories = enumSetByAppleCase(
            AO3Category.entries,
            excludedCategories
        ) { it.appleCaseName },
        crossover = enumByAppleCase(
            AO3Crossover.entries,
            crossover,
            AO3Crossover.ANY
        ) { it.appleCaseName },
        completion = enumByAppleCase(
            AO3Completion.entries,
            completion,
            AO3Completion.ANY
        ) { it.appleCaseName },
        wordsFrom = wordsFrom,
        wordsTo = wordsTo,
        updated = enumByAppleCase(AO3Updated.entries, updated, AO3Updated.ANY) { it.appleCaseName },
        language = languageFrom(language),
        sort = enumByAppleCase(
            AO3SearchSort.entries,
            sort,
            AO3SearchSort.RELEVANCE
        ) { it.appleCaseName }
    )
}

private fun <T> enumByAppleCase(
    entries: List<T>,
    raw: String,
    default: T,
    appleCase: (T) -> String
): T {
    val trimmed = raw.trim()
    if (trimmed.isEmpty()) return default
    return entries.firstOrNull { appleCase(it).equals(trimmed, ignoreCase = true) }
        ?: entries.firstOrNull {
            (it as? Enum<*>)?.name.equals(trimmed, ignoreCase = true)
        }
        ?: default
}

private fun <T> enumSetByAppleCase(
    entries: List<T>,
    raw: List<String>,
    appleCase: (T) -> String
): Set<T> {
    if (raw.isEmpty()) return emptySet()
    return raw.mapNotNullTo(linkedSetOf()) { value ->
        val trimmed = value.trim()
        if (trimmed.isEmpty()) {
            null
        } else {
            entries.firstOrNull { appleCase(it).equals(trimmed, ignoreCase = true) }
                ?: entries.firstOrNull {
                    (it as? Enum<*>)?.name.equals(trimmed, ignoreCase = true)
                }
        }
    }
}
