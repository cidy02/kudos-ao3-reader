package io.github.cidy02.kudos.core.model

import io.github.cidy02.kudos.reader.ReaderLocatorCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReadingProgressTest {
    @Test
    fun legacyPercentBeatsChapterRatioAndScroll() {
        val work = SavedWork(
            title = "Mac",
            author = "A",
            chapters = "5/10",
            lastSpineIndex = 4,
            lastScrollFraction = 0.9,
            legacyReaderProgress = 0.42
        )
        assertEquals(0.42, work.publicationProgress!!, 0.0)
        assertEquals(0.42, work.readingProgress!!, 0.0)
    }

    @Test
    fun readiumTotalBeatsTheChapterFallback() {
        val raw = """{"href":"chapter1.xhtml","locations":{"progression":0.1,"totalProgression":0.8}}"""
        val work = SavedWork(
            title = "Readium",
            author = "A",
            chapters = "5/10",
            lastSpineIndex = 4,
            readiumLocator = raw
        )
        assertEquals(0.8, work.readingProgress!!, 0.0)
    }

    @Test
    fun androidEnvelopeTotalProgressionIsTheReadiumPercent() {
        val envelope = ReaderLocatorCodec.encodeEnvelope(
            """{"href":"c.xhtml","locations":{"totalProgression":0.42}}"""
        )
        val work = SavedWork(title = "Android", author = "A", readiumLocator = envelope)
        assertEquals(0.42, work.readiumProgress!!, 0.0)
        assertEquals(0.42, work.readingProgress!!, 0.0)
    }

    @Test
    fun legacyPercentBeatsAStoredReadiumPercent() {
        val work = SavedWork(
            title = "Both",
            author = "A",
            readiumLocator = """{"locations":{"totalProgression":0.8}}""",
            legacyReaderProgress = 0.3
        )
        assertEquals(0.3, work.publicationProgress!!, 0.0)
        assertEquals(0.3, work.readingProgress!!, 0.0)
    }

    @Test
    fun chapterRatioIsTheFallback() {
        val work = SavedWork(
            title = "Chapters",
            author = "A",
            chapters = "10/10",
            lastSpineIndex = 20
        )
        assertEquals(1.0, work.readingProgress!!, 0.0)
    }

    @Test
    fun scrollFractionIsTheLastFallback() {
        val work = SavedWork(
            title = "Scroll",
            author = "A",
            chapters = "1/?",
            lastScrollFraction = 0.4
        )
        assertEquals(0.4, work.readingProgress!!, 0.0)
    }

    @Test
    fun nothingMeaningfulIsNull() {
        assertNull(SavedWork(title = "New", author = "A").readingProgress)
    }
}
