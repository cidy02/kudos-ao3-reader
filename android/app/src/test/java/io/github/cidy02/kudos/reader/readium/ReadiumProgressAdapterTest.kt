package io.github.cidy02.kudos.reader.readium

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Manifest
import org.readium.r2.shared.publication.Metadata
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReadiumProgressAdapterTest {
    @Test
    fun fallbackScrollFractionPrefersSpineProgressionOverTotalProgression() {
        val locator = Locator.fromJSON(
            JSONObject(
                """
                {
                  "href": "chapter1.xhtml",
                  "type": "application/xhtml+xml",
                  "locations": {
                    "progression": 0.25,
                    "totalProgression": 0.8
                  }
                }
                """.trimIndent()
            )
        )!!

        assertEquals(0.25, ReadiumProgressAdapter.fallbackScrollFraction(locator), 0.0)
    }

    @Test
    fun fallbackScrollFractionUsesTotalWhenSpineProgressionMissing() {
        val locator = Locator.fromJSON(
            JSONObject(
                """
                {
                  "href": "chapter1.xhtml",
                  "type": "application/xhtml+xml",
                  "locations": {
                    "totalProgression": 0.8
                  }
                }
                """.trimIndent()
            )
        )!!

        assertEquals(0.8, ReadiumProgressAdapter.fallbackScrollFraction(locator), 0.0)
    }

    @Test
    fun toReaderProgressCarriesTotalProgressionForChrome() {
        // Empty reading order → spineIndex falls back to 0; total still propagates for chrome.
        val locator = Locator.fromJSON(
            JSONObject(
                """
                {
                  "href": "chapter1.xhtml",
                  "type": "application/xhtml+xml",
                  "locations": {
                    "progression": 0.25,
                    "totalProgression": 0.8
                  }
                }
                """.trimIndent()
            )
        )!!

        val progress = ReadiumProgressAdapter.toReaderProgress(
            publication = Publication(manifest = Manifest(metadata = Metadata())),
            locator = locator
        )
        assertEquals(0.25, progress.scrollFraction, 0.0)
        assertEquals(0.8, progress.totalProgression!!, 0.0)
        assertNotNull(progress.locatorJson)
        assertFalse(progress.locatorJson.isNullOrBlank())
    }
}

