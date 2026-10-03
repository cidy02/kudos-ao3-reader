package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.library.LibraryDisplayItem
import io.github.cidy02.kudos.library.LibraryWorkListItem
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeFactsTest {
    @Test
    fun coverHueStaysInRangeAndFollowsTheFandom() {
        val hue = HomeFacts.coverHue("a")
        assertEquals(190.0 / 360.0, hue, 0.000_000_1)
        assertEquals(
            HomeFacts.coverHue("Doctor Who"),
            HomeFacts.workHue(listOf("Doctor Who", "Torchwood"), "Sodium Lights"),
            0.0
        )
        assertEquals(
            HomeFacts.coverHue("Sodium Lights"),
            HomeFacts.workHue(emptyList(), "Sodium Lights"),
            0.0
        )
        assertTrue(HomeFacts.coverHue("Doctor Who") in 0.0..1.0)
    }

    @Test
    fun bareFandomTitleDropsOneTrailingDisambiguator() {
        assertEquals("Doctor Who", HomeFacts.bareFandomTitle("Doctor Who (2005)"))
        assertEquals("Doctor Who", HomeFacts.bareFandomTitle("Doctor Who"))
        assertEquals("Star Wars", HomeFacts.bareFandomTitle("Star Wars - All Media Types"))
        assertEquals(
            "My Hero Academia",
            HomeFacts.bareFandomTitle("僕のヒーローアカデミア | Boku no Hero Academia | My Hero Academia")
        )
        assertEquals("Star Wars", HomeFacts.primaryFandom(listOf("Star Wars - All Media Types")))
        assertEquals(
            "Ellie and Abbie (and Ellie's Dead Aunt)",
            HomeFacts.bareFandomTitle("Ellie and Abbie (and Ellie's Dead Aunt) (2020)")
        )
    }

    @Test
    fun localWorkMetadataMatchesTheIosCompactLine() {
        assertEquals(
            listOf("Rosalita", "1.77K words", "3/3"),
            HomeFacts.localWorkMetadata("Rosalita", 1_773, "3/3")
        )
        assertEquals("999 words", HomeFacts.compactWordCount(999))
        assertEquals("1K words", HomeFacts.compactWordCount(1_000))
        assertEquals("1.25K words", HomeFacts.compactWordCount(1_250))
        assertEquals("33.7K words", HomeFacts.compactWordCount(33_700))
        assertEquals("62K words", HomeFacts.compactWordCount(62_000))
        assertEquals("1.2M words", HomeFacts.compactWordCount(1_200_000))
        assertEquals(emptyList<String>(), HomeFacts.localWorkMetadata("   ", 0, "  "))
    }

    @Test
    fun queueFooterNamesTheNextUnfinishedWork() {
        val finished = work("f", finished = true)
        val reading = work("r", finished = false, inProgress = true)
        val unread = work("u")
        assertEquals("0 works", HomeFacts.queueCardFooter(emptyList()))
        assertEquals("1 work", HomeFacts.queueCardFooter(listOf(finished)))
        assertEquals(
            "3 works · next up 2",
            HomeFacts.queueCardFooter(listOf(finished, unread, reading))
        )
        assertEquals(reading.id, HomeFacts.upNext(listOf(finished, reading, unread))?.id)
        assertEquals(finished.id, HomeFacts.upNext(listOf(finished))?.id)
        val progress = HomeFacts.queueProgress(listOf(finished, unread, reading))
        assertEquals(1, progress.finished)
        assertEquals(1, progress.inProgress)
        assertEquals(1, progress.unread)
    }

    @Test
    fun readingOrderKeepsUnorderedWorksAfterTheStoredList() {
        val older = row("older", 200)
        val newer = row("newer", 10)
        val middle = row("middle", 50)
        val newestFirst = HomeFacts.inReadingOrder("", listOf(older, newer, middle), Row::id, Row::added)
        assertEquals(listOf("newer", "middle", "older"), newestFirst.map { it.id })

        val ordered = HomeFacts.inReadingOrder(
            "older,missing,newer",
            listOf(newer, middle, older),
            Row::id,
            Row::added
        )
        assertEquals(listOf("older", "newer", "middle"), ordered.map { it.id })
    }

    @Test
    fun locatorTitleReadsTheJsonField() {
        assertEquals("Chapter 2: Nine Minutes", HomeFacts.locatorTitle("""{"title":"Chapter 2: Nine Minutes"}"""))
        assertNull(HomeFacts.locatorTitle("""{"href":"/ch1.xhtml"}"""))
        assertNull(HomeFacts.locatorTitle("  "))
        assertEquals("Say \"hi\"", HomeFacts.locatorTitle("""{"title":"Say \"hi\""}"""))
    }

    @Test
    fun relativeNamedUsesTheNamedBuckets() {
        val now = Instant.parse("2026-10-02T12:00:00Z")
        assertEquals("just now", HomeFacts.relativeNamed(now.minusSeconds(20), now))
        assertEquals("3 minutes ago", HomeFacts.relativeNamed(now.minusSeconds(180), now))
        assertEquals("1 hour ago", HomeFacts.relativeNamed(now.minusSeconds(3600), now))
        assertEquals("yesterday", HomeFacts.relativeNamed(now.minusSeconds(86_400), now))
        assertEquals("3 days ago", HomeFacts.relativeNamed(now.minusSeconds(3 * 86_400), now))
    }

    @Test
    fun updateFooterOnlySpeaksWhenThereIsAnUnseenChapter() {
        val steady = work("steady", chapters = "2/2", known = 2)
        val updated = work("updated", chapters = "5/?", known = 3)
        assertNull(HomeFacts.updateFooter(steady))
        assertEquals("+2 new", HomeFacts.updateFooter(updated))
    }

    @Test
    fun subscriptionCopyDistinguishesSignedOutEmptyAndFailed() {
        assertEquals(
            "Log in to AO3 to see updates from works and series you subscribe to.",
            HomeSubscriptionsCopy.emptyMessage(isLoggedIn = false, loadFailed = true)
        )
        assertEquals(
            "Couldn't load your subscriptions. Pull down to try again.",
            HomeSubscriptionsCopy.emptyMessage(isLoggedIn = true, loadFailed = true)
        )
        assertTrue(
            HomeSubscriptionsCopy.emptyMessage(isLoggedIn = true, loadFailed = false)
                .contains("no work or series subscriptions")
        )
    }

    @Test
    fun collectionShelvesKeepHomeOrderAndTheStoredReadingOrder() {
        val first = work("first")
        val second = work("second")
        val hiddenFromHome = WorkCollection(id = "nope", name = "To recommend", showsOnHome = false, sortOrder = 0)
        val later = WorkCollection(
            id = "later",
            name = "zeta",
            showsOnHome = true,
            sortOrder = 2,
            workIds = listOf(second.id)
        )
        val sooner = WorkCollection(
            id = "sooner",
            name = "Comfort reads",
            showsOnHome = true,
            sortOrder = 1,
            workOrderRaw = "${second.id},${first.id}",
            workIds = listOf(first.id, second.id)
        )
        val deleted = WorkCollection(
            id = "gone",
            name = "Gone",
            showsOnHome = true,
            isDeleted = true,
            workIds = listOf(first.id)
        )
        val items = listOf(display(first), display(second))
        val shelves = HomeCollections.shelves(listOf(hiddenFromHome, later, sooner, deleted), items)
        assertEquals(listOf("sooner", "later"), shelves.map { it.id })
        assertEquals(listOf("second", "first"), shelves.first().works.map { it.item.work.id })
        assertEquals(listOf("second"), shelves.last().works.map { it.item.work.id })
    }

    @Test
    fun emptyWorkIdsFallBackToMembershipOnTheItem() {
        val work = work("member")
        val collection = WorkCollection(id = "shelf", name = "Shelf", showsOnHome = true)
        val item = LibraryDisplayItem(
            item = LibraryWorkListItem(work = work, collections = listOf(collection))
        )
        val shelves = HomeCollections.shelves(listOf(collection), listOf(item))
        assertEquals(listOf("member"), shelves.single().works.map { it.item.work.id })
    }

    @Test
    fun queueTintUsesThePickedHexAndSkipsAnUncolouredQueue() {
        assertNull(HomeFacts.carouselQueueTint(ReaderTheme.Dark, hue = null, colorHex = null))
        val derived = HomeFacts.carouselQueueTint(ReaderTheme.Dark, hue = 0.5, colorHex = null)
        assertEquals(0.30f, derived!!.alpha, 0.02f)
        val picked = HomeFacts.carouselQueueTint(ReaderTheme.Light, hue = 0.2, colorHex = "#FF0000")
        assertEquals(1f, picked!!.red, 0.02f)
        assertEquals(0f, picked.green, 0.02f)
        assertEquals(0.26f, picked.alpha, 0.02f)
    }

    @Test
    fun selectionTitleMatchesTheBulkBar() {
        assertEquals("Select Works", HomeSelectionTitle.text(0))
        assertEquals("3 Selected", HomeSelectionTitle.text(3))
    }

    private data class Row(val id: String, val added: Instant)

    private fun row(id: String, ageSeconds: Long) = Row(id, base.minusSeconds(ageSeconds))

    private fun display(work: SavedWork) = LibraryDisplayItem(item = LibraryWorkListItem(work = work))

    private fun work(
        id: String,
        finished: Boolean = false,
        inProgress: Boolean = false,
        chapters: String = "1/1",
        known: Int? = null
    ): SavedWork = SavedWork(
        id = id,
        title = id,
        author = "Author",
        hasEpub = true,
        isFinished = finished,
        lastReadDate = if (inProgress) base else null,
        lastScrollFraction = if (inProgress) 0.4 else 0.0,
        chapters = chapters,
        knownChapterCount = known,
        dateAdded = base
    )

    private val base: Instant = Instant.parse("2026-10-02T12:00:00Z")
}
