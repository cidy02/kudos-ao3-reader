package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.reader.readium.ReadiumNavigatorController
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A highlight made from a selection was stored with a bare Readium locator, and the page draws
 * only a locator in this reader's envelope: the highlight was saved and never shown.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReaderLocatorStorageTest {
    private val bare = """{"href":"OEBPS/content.html","type":"application/xhtml+xml",
        "locations":{"progression":0.25,"totalProgression":0.1},
        "text":{"before":"amber ","highlight":"shadows","after":" across"}}"""

    @Test fun aSearchResultGetsTheNearestPositionInItsOwnResource() {
        fun place(href: String, progression: Double, position: Int? = null) =
            org.readium.r2.shared.publication.Locator.fromJSON(org.json.JSONObject(
                """{"href":"$href","type":"application/xhtml+xml","locations":{"progression":$progression${position?.let { ",\"position\":$it" }.orEmpty()}}}"""))!!
        val search = place("OEBPS/chapter.xhtml#match", 0.49)
        val positions = listOf(place("other.xhtml", 0.49, 20), place("chapter.xhtml", 0.0, 3), place("chapter.xhtml", 0.5, 4))
        val resolved = io.github.cidy02.kudos.reader.readium.ReadiumProgressAdapter.resolvedPositionLocator(search, positions)
        assertEquals(4, resolved.locations.position)
        assertEquals(search.href, resolved.href)
        assertEquals(search.text, resolved.text)
        assertEquals(0.49, resolved.locations.progression!!, 0.0)
    }

    @Test
    fun aBareLocatorIsStoredInTheFormThePageCanDraw() {
        assertNull(ReadiumNavigatorController.locatorFromJson(bare))
        val stored = ReaderLocatorCodec.forStorage(bare)
        assertNotNull(stored)
        val locator = ReadiumNavigatorController.locatorFromJson(stored!!)
        assertEquals("OEBPS/content.html", locator!!.href.toString())
        assertEquals("shadows", locator.text.highlight)
    }

    @Test
    fun anEnvelopeIsStoredAsItIsAndRubbishIsNotStored() {
        val envelope = ReaderLocatorCodec.encodeEnvelope(bare)!!
        assertEquals(envelope, ReaderLocatorCodec.forStorage(envelope))
        assertNull(ReaderLocatorCodec.forStorage("not json"))
    }
}
