package io.github.cidy02.kudos.core.model

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * Displayed reading fraction, matching iOS `SavedWork.readingProgress`.
 *
 * `legacyReaderProgress` is the macOS reader's whole-book percent and wins
 * over a Readium locator (`publicationProgress`). Neither value is a resume
 * position — see `ReaderProgressMapper`. The chapter ratio and scroll fraction
 * are only the fallback for a work no reader has given a whole-book percent.
 */
private val progressJson = Json { ignoreUnknownKeys = true }

/** `locations.totalProgression` from a raw Readium locator or an Android envelope. */
fun totalProgressionIn(locator: String?): Double? {
    if (locator.isNullOrBlank()) return null
    val root = runCatching { progressJson.parseToJsonElement(locator) }.getOrNull() as? JsonObject
        ?: return null
    val inner = root["locator"] as? JsonObject
    return progressionOf(inner) ?: progressionOf(root)
}

private fun progressionOf(objectOrNull: JsonObject?): Double? {
    val locations = objectOrNull?.get("locations") as? JsonObject ?: return null
    val value = locations["totalProgression"] as? JsonPrimitive ?: return null
    // iOS accepts a JSON number (`as? Double`), not a string.
    if (value.isString) return null
    return value.contentOrNull?.toDoubleOrNull()
}

/** iOS `SavedWork.readiumProgress`. */
val SavedWork.readiumProgress: Double?
    get() = totalProgressionIn(readiumLocator)

/** iOS `SavedWork.publicationProgress`: macOS percent, else Readium's. */
val SavedWork.publicationProgress: Double?
    get() = legacyReaderProgress ?: readiumProgress

/**
 * iOS `SavedWork.readingProgress`. Whole-book percent first; otherwise the
 * legacy chapter position over the AO3 total ("5/10"), otherwise the in-chapter
 * scroll fraction. Null when there is nothing meaningful to show.
 */
val SavedWork.readingProgress: Double?
    get() {
        publicationProgress?.let { return it }
        val parts = chapters.split('/')
        if (parts.size == 2) {
            val total = parts[1].trim().toIntOrNull()
            if (total != null && total > 1) {
                return ((lastSpineIndex + 1).toDouble() / total.toDouble()).coerceIn(0.0, 1.0)
            }
        }
        return if (lastScrollFraction > 0.0) lastScrollFraction.coerceIn(0.0, 1.0) else null
    }
