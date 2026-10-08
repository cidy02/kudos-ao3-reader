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

    /** Unknown hrefs must not masquerade as resource zero for completion. */
    fun spineIndex(publication: Publication, locator: Locator): Int =
        publication.readingOrder.indexOfFirst { it.url().isEquivalent(locator.href.removeFragment()) }

    /** Frozen resource identity; only progression changes, never the chapter. */
    fun chapterSeekTarget(origin: Locator, progression: Double): Locator = origin.copy(
        locations = origin.locations.copy(progression = progression.coerceIn(0.0, 1.0), position = null)
    )

    /** Capture a save point. Always populates the cross-platform fallback fields. */
    fun toReaderProgress(publication: Publication, locator: Locator): ReaderProgress {
        val spineIndex = runCatching {
            publication.readingOrder.indexOfFirst { link ->
                link.url().toString() == locator.href.toString()
            }
        }.getOrDefault(-1).coerceAtLeast(0)

        val fraction = fallbackScrollFraction(locator)

        val envelope = ReaderLocatorCodec.encodeEnvelope(locator.toJSON().toString())
        val total = locator.locations.totalProgression?.coerceIn(0.0, 1.0)
        return ReaderProgress(
            spineIndex = spineIndex,
            scrollFraction = fraction,
            locatorJson = envelope,
            totalProgression = total
        )
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
                    // A position saved against another file (the work was rebuilt, replaced or
                    // re-downloaded with different parts) names a resource this book does not
                    // have. Given that, Readium opens at the start and never reports a location
                    // again: the position card froze and nothing was saved for that work from
                    // then on. Such a position opens the book at the beginning.
                    ?.takeIf { spineIndex(publication, it) >= 0 }

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
