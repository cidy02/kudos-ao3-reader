package io.github.cidy02.kudos.reader.readium

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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
    fun everyDragTargetStaysInItsFirstMiddleOrLastChapter() {
        for (chapter in listOf(1, 5, 10)) {
            val origin = Locator.fromJSON(JSONObject("""
                {"href":"chapter$chapter.xhtml","type":"application/xhtml+xml",
                 "locations":{"progression":0.25,"totalProgression":0.8,"position":123}}
            """))!!
            for (value in listOf(0.0, 0.5, 1.0)) {
                val target = ReadiumProgressAdapter.chapterSeekTarget(origin, value)
                assertEquals(origin.href, target.href)
                assertEquals(value, target.locations.progression!!, 0.0)
                assertNull(target.locations.position)
            }
            assertEquals(123, origin.locations.position)
        }
    }

    /**
     * A position saved against another file names a resource this book lacks. Handed to
     * Readium it opens at the start and never reports a location again, so nothing more was
     * saved for that work. It opens the book at the beginning instead.
     */
    @Test
    fun aPositionFromAnotherFileOpensTheBookAtTheBeginning() {
        val book = Publication(manifest = Manifest(metadata = Metadata(), readingOrder = listOf(
            org.readium.r2.shared.publication.Link(href = org.readium.r2.shared.publication.Href("c1.xhtml")!!),
            org.readium.r2.shared.publication.Link(href = org.readium.r2.shared.publication.Href("c2.xhtml")!!)
        )))
        fun stored(href: String) = io.github.cidy02.kudos.reader.ReaderRestoreTarget.Locator(
            """{"href":"$href","type":"application/xhtml+xml","locations":{"progression":0.5}}""")
        assertEquals("c2.xhtml", ReadiumProgressAdapter.initialLocator(stored("c2.xhtml"), book)?.href.toString())
        assertNull(ReadiumProgressAdapter.initialLocator(stored("chapter-of-the-old-file.xhtml"), book))
    }

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
