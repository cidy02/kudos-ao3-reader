package io.github.cidy02.kudos.reader.readium

import io.github.cidy02.kudos.reader.ReaderLocatorCodec
import io.github.cidy02.kudos.reader.ReaderProgress
import io.github.cidy02.kudos.reader.ReaderRestoreTarget
import org.json.JSONObject
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

/**
 * Converts between Readium [Locator]s and the engine-agnostic [ReaderProgress]/
 * [ReaderRestoreTarget]. Cross-platform fallback fields (`spineIndex`,
 * `scrollFraction`) are always derived alongside the raw locator envelope.
 */
object ReadiumProgressAdapter {

    /** Capture a save point. Always populates the cross-platform fallback fields. */
    fun toReaderProgress(publication: Publication, locator: Locator): ReaderProgress {
        val spineIndex = runCatching {
            publication.readingOrder.indexOfFirst { link ->
                link.url().toString() == locator.href.toString()
            }
        }.getOrDefault(-1).coerceAtLeast(0)

        val fraction = fallbackScrollFraction(locator)

        val envelope = ReaderLocatorCodec.encodeEnvelope(locator.toJSON().toString())
        return ReaderProgress(spineIndex = spineIndex, scrollFraction = fraction, locatorJson = envelope)
    }

    /**
     * `lastScrollFraction` is the cross-platform offset within `lastSpineIndex`,
     * so prefer Readium's per-resource progression over the whole-book percent.
     */
    internal fun fallbackScrollFraction(locator: Locator): Double =
        (locator.locations.progression ?: locator.locations.totalProgression ?: 0.0)
            .coerceIn(0.0, 1.0)

    /** Resolve the initial Readium locator (null = open at the beginning). */
    fun initialLocator(target: ReaderRestoreTarget, publication: Publication): Locator? {
        return when (target) {
            is ReaderRestoreTarget.Locator ->
                runCatching { Locator.fromJSON(JSONObject(target.locatorJson)) }.getOrNull()

            is ReaderRestoreTarget.Fallback -> runCatching {
                val link = publication.readingOrder.getOrNull(target.spineIndex)
                    ?: return null
                publication.locatorFromLink(link)
                    ?.copyWithLocations(progression = target.scrollFraction.coerceIn(0.0, 1.0))
            }.getOrNull()

            ReaderRestoreTarget.Beginning -> null
        }
    }
}
