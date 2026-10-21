package io.github.cidy02.kudos.reader.speech

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReaderSpeechSeekSessionTest {
    private fun locator(chapter: Int, position: Int, progression: Double) = Locator.fromJSON(JSONObject("""
        {"href":"chapter$chapter.xhtml","type":"application/xhtml+xml",
         "locations":{"position":$position,"progression":$progression}}
    """))!!

    private val chapter = (0..4).map { locator(2, 11 + it, it / 4.0) }
    private val book = listOf(listOf(locator(1, 1, 0.0)), chapter, listOf(locator(3, 16, 0.0)))

    @Test fun holdMovesThePageBeforeTheSpeechStartAndReanchorsAtTheLastAcceptedTarget() {
        val pages = mutableListOf<Locator>()
        val releases = mutableListOf<Locator>()
        var starts = 0
        val seek = ReaderSpeechSeekSession({ starts++ }, { pages.add(it); true }, releases::add)
        seek.begin(chapter[2])
        assertTrue(seek.step(book, 50, 100, -1))
        assertTrue(seek.step(book, 50, 100, -1))
        assertFalse(seek.step(book, 50, 100, -1))
        // No navigator location callback between ticks: the accepted target still advances.
        assertEquals(listOf(chapter[1], chapter[0]), pages)
        assertTrue(releases.isEmpty())
        seek.end()
        seek.end()
        assertEquals(1, starts)
        assertEquals(listOf(chapter[0]), releases)
    }

    @Test fun positionsStayInTheirChapterAndUseGlobalPositionBeforeProgressionOrVisualPages() {
        assertEquals(chapter[1], ReaderSpeechSeek.target(book,
            chapter[0].copy(locations = chapter[0].locations.copy(progression = 1.0)), 100, 100, 1))
        assertNull(ReaderSpeechSeek.target(book, chapter.last(), 1, 100, 1))
        assertNull(ReaderSpeechSeek.target(book, book.first().first(), 1, 100, 1))
    }

    @Test fun fallbackMapsProgressionOrVisualPagesOntoPositionsRatherThanUsingPageMinusOne() {
        val noPosition = chapter[2].copy(locations = chapter[2].locations.copy(position = null))
        assertEquals(chapter[3], ReaderSpeechSeek.target(book, noPosition, 1, 100, 1))
        val visualOnly = noPosition.copy(locations = noPosition.locations.copy(progression = null))
        assertEquals(chapter[3], ReaderSpeechSeek.target(book, visualOnly, 51, 101, 1))
        assertEquals(chapter[1], ReaderSpeechSeek.target(book, visualOnly, 1, 1, 1))
    }

    @Test fun refusedNavigationDoesNotAdvanceTheSpeechAnchor() {
        val releases = mutableListOf<Locator>()
        val seek = ReaderSpeechSeekSession({}, { false }, releases::add)
        seek.begin(chapter[2])
        assertFalse(seek.step(book, 1, 10, -1))
        seek.end()
        assertEquals(listOf(chapter[2]), releases)
    }
}
