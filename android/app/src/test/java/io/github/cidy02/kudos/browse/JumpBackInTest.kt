package io.github.cidy02.kudos.browse

import java.time.Instant
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

/** Port of the Jump Back In cases in `BrowseAndWorkDetailRulesTests`. */
class JumpBackInTest {

    @Test
    fun jumpBackInIsMostRecentlyReadFirst() {
        val early = Instant.ofEpochSecond(1_000)
        val late = Instant.ofEpochSecond(9_000)
        val addedLate = snapshot(listOf("Fandom A"), added = late, read = early)
        val readLate = snapshot(listOf("Fandom B"), added = early, read = late)
        val again = snapshot(listOf("Fandom B"), added = early, read = early)
        val categories = mapOf("fandom a" to "A", "fandom b" to "B")

        val picks = JumpBackIn.fandoms(
            works = listOf(addedLate, readLate, again),
            categoryFor = { categories[it] },
            workCountFor = { null },
            limit = 3
        )

        assertEquals(listOf("Fandom B", "Fandom A"), picks.map { it.fandom })
        assertEquals(listOf("B", "A"), picks.map { it.categoryId })
    }

    @Test
    fun jumpBackInSkipsUnreadAndUncategorisedAndStopsAtTheLimit() {
        val unread = LibraryWorkSnapshot(
            fandomsLower = listOf("fandom a"),
            fandomsDisplay = listOf("Fandom A"),
            hasBeenRead = false,
            dateAdded = Instant.ofEpochSecond(5_000),
            lastReadDate = null
        )
        val read = snapshot(
            listOf("Unknown", "Fandom B", "Fandom C"),
            added = Instant.EPOCH,
            read = null
        )
        val categories = mapOf("fandom a" to "A", "fandom b" to "B", "fandom c" to "C")

        val picks = JumpBackIn.fandoms(
            works = listOf(unread, read),
            categoryFor = { categories[it] },
            workCountFor = { null },
            limit = 1
        )

        assertEquals(listOf("Fandom B"), picks.map { it.fandom })
    }

    @Test
    fun jumpBackInCarriesTheWorkCount() {
        val picks = JumpBackIn.fandoms(
            works = listOf(snapshot(listOf("Small Fandom"), added = Instant.EPOCH, read = Instant.now())),
            categoryFor = { "A" },
            workCountFor = { if (it == "small fandom") 42 else null },
            limit = 3
        )

        assertEquals(42, picks.first().workCount)
    }

    @Test
    fun jumpBackInRanksVisitsWithReads() {
        val read = snapshot(
            listOf("Fandom A", "Fandom B"),
            added = Instant.EPOCH,
            read = Instant.ofEpochSecond(5_000)
        )

        val picks = JumpBackIn.fandoms(
            works = listOf(read),
            visits = listOf(
                JumpBackIn.Visit("fandom b", Instant.ofEpochSecond(9_000)),
                JumpBackIn.Visit("Fandom C", Instant.ofEpochSecond(7_000)),
                JumpBackIn.Visit("Fandom A", Instant.ofEpochSecond(1_000))
            ),
            categoryFor = { "X" },
            workCountFor = { null },
            limit = 10
        )

        assertEquals(listOf("Fandom B", "Fandom C", "Fandom A"), picks.map { it.fandom })
    }

    private fun snapshot(fandoms: List<String>, added: Instant, read: Instant?) = LibraryWorkSnapshot(
        fandomsLower = fandoms.map { it.lowercase(Locale.US) },
        fandomsDisplay = fandoms,
        hasBeenRead = true,
        dateAdded = added,
        lastReadDate = read
    )
}
