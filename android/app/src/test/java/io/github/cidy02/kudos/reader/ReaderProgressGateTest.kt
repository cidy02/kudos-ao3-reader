package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of iOS `ReadiumProgressPersistenceTests` for the cases A75 #2 names:
 * `progressionPastThresholdIsWrittenAfterInterval`, `emptyLocatorIsIgnored`,
 * `firstDifferentLocatorAfterSeedCanWrite`, `meaningfulChangeInsideWindowArmsTrailingWrite`.
 */
class ReaderProgressGateTest {

    private class ManualScheduler : TrailingWriteScheduler {
        var delayMillis: Long? = null
        private var block: (() -> Unit)? = null

        override fun schedule(delayMillis: Long, block: () -> Unit) {
            this.delayMillis = delayMillis
            this.block = block
        }

        override fun cancel() {
            delayMillis = null
            block = null
        }

        fun fire() {
            val running = block
            block = null
            running?.invoke()
        }
    }

    private fun locator(total: Double, href: String = "chapter1.xhtml"): String =
        """{"href":"$href","type":"application/xhtml+xml","locations":{"totalProgression":$total,"progression":$total,"position":5}}"""

    private fun progress(total: Double, href: String = "chapter1.xhtml") = ReaderProgress(
        spineIndex = 0,
        scrollFraction = total,
        locatorJson = locator(total, href),
        totalProgression = total
    )

    @Test
    fun progressionPastThresholdIsWrittenAfterInterval() {
        val gate = ReaderProgressGate()
        val start = Instant.ofEpochMilli(4_000_000)
        val writes = mutableListOf<String>()
        gate.onDebouncedWrite = { writes += it.locatorJson!! }
        gate.markPersisted(progress(0.5), start)

        val moved = progress(0.52)
        gate.note("work", moved, start.plusMillis(2_500))
        assertEquals(listOf(moved.locatorJson), writes)
    }

    @Test
    fun emptyLocatorIsIgnored() {
        val gate = ReaderProgressGate()
        gate.note("work", ReaderProgress(0, 0.0, locatorJson = "", totalProgression = 0.5), Instant.EPOCH)
        assertNull(gate.latestLocatorString)
        assertNull(gate.locatorForFlush())

        // A later empty callback that still carries a spine and a progression
        // must not replace the stored place.
        val stored = locator(0.42)
        gate.seed(
            "work",
            SavedWork(
                title = "T",
                author = "A",
                readiumLocator = stored,
                lastSpineIndex = 1,
                lastScrollFraction = 0.42
            )
        )
        gate.note(
            "work",
            ReaderProgress(
                spineIndex = 7,
                scrollFraction = 0.9,
                locatorJson = "",
                totalProgression = 0.8
            ),
            Instant.EPOCH
        )
        assertEquals(stored, gate.latestLocatorString)
        assertEquals(1, gate.latestProgress?.spineIndex)
        assertEquals(0.42, gate.latestProgress!!.scrollFraction, 0.0)
        assertNull(gate.locatorForFlush())
    }

    @Test
    fun firstDifferentLocatorAfterSeedCanWrite() {
        val gate = ReaderProgressGate()
        val start = Instant.ofEpochMilli(8_000_000)
        val writes = mutableListOf<String>()
        gate.onDebouncedWrite = { writes += it.locatorJson!! }
        val opened = locator(0.25)
        gate.seed("work", SavedWork(title = "T", author = "A", readiumLocator = opened))

        val moved = progress(0.40)
        gate.note("work", moved, start)
        assertEquals(listOf(moved.locatorJson), writes)
        assertNull(gate.locatorForFlush())
    }

    @Test
    fun meaningfulChangeInsideWindowArmsTrailingWrite() {
        val scheduler = ManualScheduler()
        var now = Instant.ofEpochMilli(7_000_000)
        val gate = ReaderProgressGate()
        gate.clock = { now }
        gate.scheduler = scheduler
        val writes = mutableListOf<String>()
        gate.onDebouncedWrite = { writes += it.locatorJson!! }
        val start = now
        gate.markPersisted(progress(0.1), start)

        val moved = progress(0.35)
        now = start.plusMillis(200)
        gate.note("work", moved, now)
        assertTrue(writes.isEmpty())
        assertEquals(ReaderProgressGate.MIN_PERSIST_INTERVAL_MS - 200, scheduler.delayMillis)

        now = now.plusMillis(1_800)
        scheduler.fire()
        assertEquals(listOf(moved.locatorJson), writes)
    }
}
