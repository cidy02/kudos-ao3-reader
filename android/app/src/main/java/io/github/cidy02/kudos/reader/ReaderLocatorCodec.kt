package io.github.cidy02.kudos.reader

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put

/**
 * Wraps a raw Readium Kotlin locator in a portable envelope that records the
 * platform/engine that produced it. This lets Android recognise its own locators
 * for precise same-platform restore while treating foreign (e.g. Apple) locators
 * as incompatible, falling back to `lastSpineIndex`/`lastScrollFraction`.
 *
 * Envelope shape:
 * ```json
 * { "platform": "android", "engine": "readium-kotlin", "version": 1, "locator": { ... } }
 * ```
 *
 * The cross-platform contract (READER_STATE_CONTRACT.md) reserves
 * `readiumLocatorPlatform`/`readiumLocatorEngine`/`readiumLocatorVersion` as
 * future top-level backup fields; until those exist, this self-describing
 * envelope carries the same information inside the single `readiumLocator` string.
 */
object ReaderLocatorCodec {
    const val PLATFORM = "android"
    const val ENGINE = "readium-kotlin"
    const val VERSION = 1

    private val json = Json { ignoreUnknownKeys = true }

    /** Wrap a raw Readium locator JSON string. Returns null if it is not valid JSON. */
    fun encodeEnvelope(rawLocatorJson: String): String? {
        val inner = runCatching { json.parseToJsonElement(rawLocatorJson) }.getOrNull()
        if (inner !is JsonObject) return null
        val envelope = buildJsonObject {
            put("platform", PLATFORM)
            put("engine", ENGINE)
            put("version", VERSION)
            put("locator", inner)
        }
        return envelope.toString()
    }

    /**
     * Return the inner Readium locator JSON only when the stored value is an
     * envelope produced by this platform/engine; otherwise null (caller should
     * fall back to the cross-platform fields).
     */
    fun decodeCompatibleLocator(stored: String?): String? {
        if (stored.isNullOrBlank()) return null
        val element = runCatching { json.parseToJsonElement(stored) }.getOrNull() as? JsonObject
            ?: return null
        val platform = (element["platform"] as? JsonPrimitive)?.contentOrNull
        val engine = (element["engine"] as? JsonPrimitive)?.contentOrNull
        val version = (element["version"] as? JsonPrimitive)?.intOrNull
        if (platform != PLATFORM || engine != ENGINE || version != VERSION) return null
        val locator = element["locator"] as? JsonObject ?: return null
        return locator.toString()
    }
}
