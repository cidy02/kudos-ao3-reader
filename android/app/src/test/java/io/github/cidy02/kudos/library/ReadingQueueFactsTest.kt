package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.subject.SubjectHueSwatches
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReadingQueueFactsTest {
    @Test
    fun progressCountsAMissingCopyAsUnread() {
        val works = listOf(
            work("a", finished = true, epub = false),
            work("b", started = true),
            work("c"),
            work("d", epub = false)
        )
        val progress = ReadingQueueFacts.progress(works)
        assertEquals(1, progress.finished)
        assertEquals(1, progress.inProgress)
        assertEquals(2, progress.unread)
        assertEquals(
            "1 finished · 1 in progress · 2 unread · 1 of 4 kept offline",
            ReadingQueueFacts.legend(progress, offlineCount = 1)
        )
    }

    @Test
    fun upNextIsTheFirstUnfinishedAndInLineKeepsTheRest() {
        val works = listOf(work("done", finished = true), work("next"), work("after"))
        val (upNext, inLine) = ReadingQueueFacts.upNext(works)
        assertEquals("next", upNext?.id)
        assertEquals(listOf("done", "after"), inLine.map { it.id })
        assertEquals(2, ReadingQueueFacts.nextUpPosition(works))
        assertNull(ReadingQueueFacts.nextUpPosition(listOf(work("only", finished = true))))
    }

    @Test
    fun dragStaysLiveWhileSelectingUnlessTheListIsNarrowed() {
        assertTrue(ReadingQueueFacts.isDragLive(isReordering = false, isSelecting = true, isNarrowed = false))
        assertFalse(ReadingQueueFacts.isDragLive(isReordering = false, isSelecting = true, isNarrowed = true))
        assertTrue(ReadingQueueFacts.isDragLive(isReordering = true, isSelecting = false, isNarrowed = true))
        assertFalse(ReadingQueueFacts.canReorder(tagFilterActive = true, searchActive = false))
    }

    @Test
    fun pinAndDeleteFollowTheSelectionRules() {
        val saved = ReadingQueue(name = "Saved for Later", kindRaw = ReadingQueueKind.SAVED_FOR_LATER)
        val loose = ReadingQueue(id = "loose", name = "Loose", isPinned = false)
        val pinned = ReadingQueue(id = "pinned", name = "Pinned", isPinned = true)
        assertTrue(ReadingQueueFacts.pinTarget(listOf(loose, pinned)))
        assertFalse(ReadingQueueFacts.pinTarget(listOf(pinned)))
        assertEquals(listOf(loose.id), ReadingQueueFacts.deletable(listOf(saved, loose)).map { it.id })
        assertEquals("Delete “Loose”?", ReadingQueueFacts.deleteTitle(listOf(loose)))
    }

    @Test
    fun quickFilterAndSearchAgreeWithTheOrganizer() {
        val unread = work("u")
        val offline = work("o", started = true)
        assertTrue(QueueQuickFilter.Unread.matches(unread, preserved = true))
        assertFalse(QueueQuickFilter.Offline.matches(unread, preserved = false))
        assertTrue(QueueQuickFilter.Wip.matches(work("w", complete = false), preserved = true))
        val queue = ReadingQueue(name = "Rereads")
        assertTrue(
            ReadingQueueFacts.matchesSearch(queue, listOf("Comfort"), listOf(work("x", title = "Sodium")), "sodium")
        )
        assertTrue(ReadingQueueFacts.matchesTagFilter(emptyList(), ReadingQueueFacts.UNTAGGED))
        assertFalse(ReadingQueueFacts.matchesTagFilter(listOf("Comfort"), ReadingQueueFacts.UNTAGGED))
    }

    @Test
    fun hueFallbackAndByteCount() {
        val named = ReadingQueue(name = "a")
        assertEquals(190.0 / 360.0, ReadingQueueFacts.displayHue(named), 0.000_000_1)
        val picked = named.copy(hue = 0.2)
        assertEquals(0.2, ReadingQueueFacts.displayHue(picked), 0.0)
        assertEquals("1.5 KB", ReadingQueueFacts.byteCountString(1500))
        assertEquals("nothing kept yet", ReadingQueueFacts.storageLine(0, 0))
        assertEquals("Home › Queues › Queue details", ReadingQueueFacts.kicker("Home", isDetails = true))
        assertTrue(SubjectHueSwatches.matches(SubjectHueSwatches.all[1], 0.4424))
        assertFalse(SubjectHueSwatches.isPreset(0.2))
        val latest = java.time.Instant.parse("2026-07-01T00:00:00Z")
        assertEquals(
            latest,
            ReadingQueueFacts.lastRead(listOf(null, latest, latest.minusSeconds(60)))
        )
        assertEquals(
            "yesterday",
            ReadingQueueFacts.relativeNamed(latest, latest.plusSeconds(86_400))
        )
    }

    private fun work(
        id: String,
        title: String = id,
        finished: Boolean = false,
        started: Boolean = false,
        epub: Boolean = true,
        complete: Boolean = true
    ) = SavedWork(
        id = id,
        title = title,
        author = "Author",
        isFinished = finished,
        hasEpub = epub,
        isComplete = complete,
        lastReadDate = if (started) java.time.Instant.parse("2026-01-01T00:00:00Z") else null
    )
}
