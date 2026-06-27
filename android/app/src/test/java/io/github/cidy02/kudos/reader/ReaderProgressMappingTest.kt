package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private const val WORK_UUID = "11111111-1111-1111-1111-111111111111"
private const val RAW_LOCATOR =
    """{"href":"chapter1.xhtml","type":"application/xhtml+xml","locations":{"progression":0.5,"totalProgression":0.25}}"""

private fun work(
    locator: String? = null,
    spineIndex: Int = 0,
    scrollFraction: Double = 0.0,
    favorite: Boolean = false,
    finished: Boolean = false
) = SavedWork(
    id = WORK_UUID,
    title = "Example",
    author = "Author",
    readiumLocator = locator,
    lastSpineIndex = spineIndex,
    lastScrollFraction = scrollFraction,
    isFavorite = favorite,
    isFinished = finished
)

class ReaderLocatorSerializationTest {
    @Test
    fun envelopeRoundTripsForThisPlatform() {
        val envelope = ReaderLocatorCodec.encodeEnvelope(RAW_LOCATOR)
        assertNotNull(envelope)
        assertTrue(envelope!!.contains("\"platform\":\"android\""))

        val decoded = ReaderLocatorCodec.decodeCompatibleLocator(envelope)
        assertNotNull(decoded)
        assertTrue(decoded!!.contains("chapter1.xhtml"))
    }

    @Test
    fun foreignPlatformLocatorIsRejected() {
        val foreign = """{"platform":"ios","engine":"readium-swift","version":1,"locator":{"href":"x"}}"""
        assertNull(ReaderLocatorCodec.decodeCompatibleLocator(foreign))
    }

    @Test
    fun incompatibleEngineVersionIsRejected() {
        val future = """{"platform":"android","engine":"readium-kotlin","version":99,"locator":{"href":"x"}}"""
        assertNull(ReaderLocatorCodec.decodeCompatibleLocator(future))
    }

    @Test
    fun rawUnwrappedLocatorIsRejected() {
        // A bare Readium locator (no envelope) is treated as not-this-platform.
        assertNull(ReaderLocatorCodec.decodeCompatibleLocator(RAW_LOCATOR))
    }

    @Test
    fun malformedOrBlankIsRejected() {
        assertNull(ReaderLocatorCodec.decodeCompatibleLocator(null))
        assertNull(ReaderLocatorCodec.decodeCompatibleLocator(""))
        assertNull(ReaderLocatorCodec.decodeCompatibleLocator("not json"))
        assertNull(ReaderLocatorCodec.encodeEnvelope("not json"))
    }
}

class ReaderProgressMapperTest {
    private val mapper = ReaderProgressMapper()

    @Test
    fun restoresFromCompatibleLocatorFirst() {
        val envelope = ReaderLocatorCodec.encodeEnvelope(RAW_LOCATOR)
        val target = mapper.restoreTarget(work(locator = envelope, spineIndex = 9, scrollFraction = 0.9))
        assertTrue(target is ReaderRestoreTarget.Locator)
        assertTrue((target as ReaderRestoreTarget.Locator).locatorJson.contains("chapter1.xhtml"))
    }

    @Test
    fun beginningWhenNoProgress() {
        assertEquals(ReaderRestoreTarget.Beginning, mapper.restoreTarget(work()))
    }
}

class ReaderProgressFallbackTest {
    private val mapper = ReaderProgressMapper()

    @Test
    fun foreignLocatorFallsBackToLegacyFields() {
        val foreign = """{"platform":"ios","engine":"readium-swift","locator":{"href":"x"}}"""
        val target = mapper.restoreTarget(work(locator = foreign, spineIndex = 4, scrollFraction = 0.3))
        assertTrue(target is ReaderRestoreTarget.Fallback)
        target as ReaderRestoreTarget.Fallback
        assertEquals(4, target.spineIndex)
        assertEquals(0.3, target.scrollFraction, 0.0)
    }

    @Test
    fun invalidLocatorWithProgressFallsBack() {
        val target = mapper.restoreTarget(work(locator = "garbage", spineIndex = 2, scrollFraction = 0.1))
        assertTrue(target is ReaderRestoreTarget.Fallback)
    }
}

class ReaderProgressPreservesLegacyFieldsTest {
    private val mapper = ReaderProgressMapper()
    private val now = Instant.parse("2026-06-26T12:00:00Z")

    @Test
    fun applyProgressKeepsLegacyFieldsPopulatedAlongsideLocator() {
        val envelope = ReaderLocatorCodec.encodeEnvelope(RAW_LOCATOR)
        val progress = ReaderProgress(spineIndex = 5, scrollFraction = 0.42, locatorJson = envelope)

        val updated = mapper.applyProgress(work(favorite = true, finished = true), progress, now)

        assertEquals(5, updated.lastSpineIndex)
        assertEquals(0.42, updated.lastScrollFraction, 0.0)
        assertEquals(envelope, updated.readiumLocator)
        assertEquals(now, updated.lastReadDate)
        // Local user state is never touched by progress saves.
        assertTrue(updated.isFavorite)
        assertTrue(updated.isFinished)
    }

    @Test
    fun applyProgressClampsAndKeepsLegacyEvenWithoutNewLocator() {
        val previous = work(locator = "existing").copy(lastSpineIndex = 1, lastScrollFraction = 0.1)
        val progress = ReaderProgress(spineIndex = 7, scrollFraction = 1.5, locatorJson = null)

        val updated = mapper.applyProgress(previous, progress, now)

        assertEquals(7, updated.lastSpineIndex)
        assertEquals(1.0, updated.lastScrollFraction, 0.0) // clamped to [0,1]
        assertEquals("existing", updated.readiumLocator) // not erased when no new locator
        assertFalse(updated.lastScrollFraction > 1.0)
    }
}
