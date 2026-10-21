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
class ReaderSpeechSkipTest {
    private fun locator(spine: Int, progression: Double) = Locator.fromJSON(JSONObject("""
        {"href":"spine$spine.xhtml","type":"application/xhtml+xml","locations":{"progression":$progression}}
    """))!!
    private val positions = (0..3).map { listOf(locator(it, 0.0), locator(it, 0.5), locator(it, 1.0)) }

    @Test fun previousRestartsMidChapterAndGoesBackWithinTheFirstTwoPages() {
        assertEquals(positions[2][0], ReaderSpeechSkip.target(positions, 2, 3, false))
        assertEquals(positions[1][0], ReaderSpeechSkip.target(positions, 2, 1, false))
        assertEquals(positions[1][0], ReaderSpeechSkip.target(positions, 2, 2, false))
        assertEquals(positions[1][0], ReaderSpeechSkip.target(positions, 2, 0, false))
    }

    @Test fun firstChapterRestartsOnlyPastPageOneAndNextStopsAtTheLastChapter() {
        assertNull(ReaderSpeechSkip.target(positions, 0, 1, false))
        assertEquals(positions[0][0], ReaderSpeechSkip.target(positions, 0, 2, false))
        assertEquals(positions[0][0], ReaderSpeechSkip.target(positions, 0, 5, false))
        assertEquals(positions[1][0], ReaderSpeechSkip.target(positions, 0, 100, true))
        assertNull(ReaderSpeechSkip.target(positions, 3, 1, true))
    }

    @Test fun chaptersAreSpineItemsAndMissingTargetsNeverFallThroughToParagraphSkipping() {
        assertEquals(positions[3][0], ReaderSpeechSkip.target(positions, 2, 1, true))
        assertNull(ReaderSpeechSkip.target(positions, -1, 1, true))
        assertNull(ReaderSpeechSkip.target(emptyList(), 0, 1, true))
        assertNull(ReaderSpeechSkip.target(listOf(positions[0], emptyList()), 0, 1, true))
        assertNull(ReaderSpeechSkip.target(listOf(positions[0]), 0, 1, true))
    }
}
