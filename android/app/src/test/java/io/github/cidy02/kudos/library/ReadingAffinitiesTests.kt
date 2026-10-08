package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

/** Ported by name from KudosTests/ReadingAffinitiesTests.swift. */
class ReadingAffinitiesTests {
    private fun work(title: String, author: String = "", fandoms: List<String> = emptyList(),
                     freeforms: List<String> = emptyList(), started: Boolean = false,
                     hasEPUB: Boolean = true, savedForLater: Boolean = false, lastRead: Instant? = null) =
        SavedWork(id = title, title = title, author = author, workFandoms = fandoms, workFreeforms = freeforms,
            lastSpineIndex = if (started) 3 else 0, hasEpub = hasEPUB, isSaved = savedForLater, lastReadDate = lastRead)

    private fun summary(seconds: Double, lastEnded: Instant? = null) =
        WorkReadingSummary(totalSeconds = seconds, visitCount = 1, lastEndedAt = lastEnded)

    @Test fun onlyNamesWithSomethingReadBehindThemAppear() {
        val read = work("Read", author = "kestrelmoon", started = true)
        val shelved = work("Shelved", author = "neveropened")
        assertEquals(listOf("kestrelmoon"), ReadingAffinities.authors(listOf(read, shelved), emptyMap()).map { it.name })
    }

    @Test fun onlyASingleRegisteredAuthorGivesABylineAUsername() {
        val solo = work("Solo", author = "kestrelmoon", started = true).copy(
            authorIdentitiesJSON = """[{"kind":"registered","username":"account","pseud":"kestrelmoon","displayName":"kestrelmoon"}]""")
        val joint = work("Joint", author = "alpha, beta", started = true).copy(
            authorIdentitiesJSON = """[{"kind":"registered","username":"alpha"},{"kind":"registered","username":"beta"}]""")
        val unknown = work("Unknown", author = "looks_like_a_username", started = true)
        val orphan = work("Orphan", author = "orphan_account", started = true).copy(
            authorIdentitiesJSON = """[{"kind":"orphaned","username":"orphan_account"}]""")
        val rows = ReadingAffinities.authors(listOf(solo, joint, unknown, orphan), emptyMap()).associateBy { it.name }
        assertEquals("account", rows.getValue("kestrelmoon").username)
        assertNull(rows.getValue("alpha, beta").username)
        assertNull(rows.getValue("looks_like_a_username").username)
        assertNull(rows.getValue("orphan_account").username)
    }

    @Test fun aWorkWithTwoTagsIsCountedByBothRatherThanSplit() {
        val both = work("Both", freeforms = listOf("Slow Burn", "Fix-It"), started = true)
        val rows = ReadingAffinities.tags(listOf(both), mapOf(both.id to summary(120.0)))
        assertEquals(2, rows.size)
        assertTrue(rows.all { it.worksRead == 1 && it.totalSeconds == 120.0 })
    }

    @Test fun unreadCountsSplitOutDownloadsAndSavedForLater() {
        val read = work("Read", freeforms = listOf("Slow Burn"), started = true)
        val downloaded = work("Waiting", freeforms = listOf("Slow Burn"))
        val queued = work("Queued", freeforms = listOf("Slow Burn"), hasEPUB = false, savedForLater = true)
        val row = ReadingAffinities.tags(listOf(read, downloaded, queued), emptyMap()).single()
        assertEquals(1, row.worksRead); assertEquals(2, row.unreadInLibrary)
        assertEquals(1, row.downloadedInLibrary); assertEquals(1, row.savedForLater)
    }

    @Test fun favoritedCountsStarredWorksCarryingTheName() {
        val works = listOf(
            work("A", fandoms = listOf("Good Omens"), started = true).copy(isFavorite = true),
            work("B", fandoms = listOf("Good Omens")).copy(isFavorite = true),
            work("C", fandoms = listOf("Good Omens"), started = true),
            work("D", fandoms = listOf("Star Wars"), started = true).copy(isFavorite = true))
        val rows = ReadingAffinities.fandoms(works, emptyMap()).associateBy { it.name }
        assertEquals(2, rows.getValue("Good Omens").favorited)
        assertEquals(2, rows.getValue("Good Omens").worksRead)
        assertEquals(1, rows.getValue("Star Wars").favorited)
    }

    @Test fun mostReadAndMostTimeAreDifferentAnswers() {
        val short1 = work("S1", author = "prolific", started = true)
        val short2 = work("S2", author = "prolific", started = true)
        val epic = work("Epic", author = "oneBigBook", started = true)
        val summaries = mapOf(short1.id to summary(600.0), short2.id to summary(600.0), epic.id to summary(40_000.0))
        val works = listOf(short1, short2, epic)
        assertEquals(listOf("prolific", "oneBigBook"), ReadingAffinities.authors(works, summaries, ReadingAffinities.Order.MostRead).map { it.name })
        assertEquals(listOf("oneBigBook", "prolific"), ReadingAffinities.authors(works, summaries, ReadingAffinities.Order.MostTime).map { it.name })
    }

    @Test fun tiesBreakOnNameSoTheListDoesNotReshuffleBetweenRenders() {
        val works = listOf(work("B", author = "bravo", started = true), work("A", author = "alpha", started = true))
        assertEquals(listOf("alpha", "bravo"), ReadingAffinities.authors(works, emptyMap(), ReadingAffinities.Order.MostRead).map { it.name })
    }

    @Test fun recentOrderUsesTheSessionEndNotJustTheWorksLastReadDate() {
        val old = Instant.ofEpochSecond(1_000_000); val recent = Instant.ofEpochSecond(2_000_000)
        val quiet = work("Quiet", author = "quiet", started = true, lastRead = recent)
        val logged = work("Logged", author = "logged", started = true, lastRead = old)
        assertEquals(listOf("logged", "quiet"), ReadingAffinities.authors(listOf(quiet, logged),
            mapOf(logged.id to summary(60.0, recent.plusSeconds(100)))).map { it.name })
    }

    @Test fun blankAndWhitespaceOnlyNamesAreDropped() {
        val blank = work("Blank", author = "   ", fandoms = listOf("", "  "), started = true)
        assertTrue(ReadingAffinities.authors(listOf(blank), emptyMap()).isEmpty())
        assertTrue(ReadingAffinities.fandoms(listOf(blank), emptyMap()).isEmpty())
    }

    @Test fun namesAreTrimmedSoOneFandomDoesNotBecomeTwoRows() {
        val rows = ReadingAffinities.fandoms(listOf(work("A", fandoms = listOf(" Naruto "), started = true),
            work("B", fandoms = listOf("Naruto"), started = true)), emptyMap())
        assertEquals(1, rows.size); assertEquals(2, rows.single().worksRead)
    }

    @Test fun sessionsAloneCountAsReadAndKeepAllVisitsFinishesTimeAndLastEnd() {
        val end = Instant.parse("2026-10-08T12:00:00Z")
        val work = work("Logged", author = "A")
        val sessions = listOf(ReadingSessionEntity(id = "1", workID = work.id, startedAt = end.minusSeconds(60),
            endedAt = end, durationSeconds = 60.0, didFinish = true, lastModifiedAt = end),
            ReadingSessionEntity(id = "2", workID = work.id, startedAt = end, endedAt = end.plusSeconds(120),
                durationSeconds = 120.0, lastModifiedAt = end))
        val summaries = ReadingAffinities.summaries(sessions)
        assertEquals(WorkReadingSummary(180.0, 2, 1, end.plusSeconds(120)), summaries[work.id])
        val row = ReadingAffinities.authors(listOf(work), summaries).single()
        assertEquals(1, row.worksRead); assertEquals(0, row.unreadInLibrary)
        assertEquals(180.0, row.totalSeconds, 0.0)
    }

    @Test fun fallbackTagsAndLegacyOrNativeShelfMembershipMatchIos() {
        val read = work("Read", started = true).copy(workTags = listOf("Fallback"), workCharacters = listOf("Ignored"))
        val legacy = work("Legacy", savedForLater = true).copy(workTags = listOf("Fallback"))
        val native = work("Native").copy(workTags = listOf("Fallback"), isQueuedForLater = true, isFavorite = true)
        val row = ReadingAffinities.tags(listOf(read, legacy, native), emptyMap(), savedForLaterIds = setOf(native.id)).single()
        assertEquals("Fallback", row.name); assertEquals(2, row.savedForLater)
        val categorized = read.copy(workFreeforms = listOf("Only freeform"))
        assertEquals(listOf("Only freeform"), ReadingAffinities.tags(listOf(categorized), emptyMap()).map { it.name })
    }

    @Test fun allAggregateScopesExcludeObscuredDeletedAndQueueOnlyNames() {
        val base = work("Visible", author = "Visible", fandoms = listOf("Visible"), freeforms = listOf("Visible"), started = true)
        val items = listOf(LibraryDisplayItem(LibraryWorkListItem(base)),
            LibraryDisplayItem(LibraryWorkListItem(base.copy(id = "blur", author = "Secret")), LibraryPrivacyVisibility.Obscured),
            LibraryDisplayItem(LibraryWorkListItem(base.copy(id = "deleted", author = "Deleted", isDeleted = true))),
            LibraryDisplayItem(LibraryWorkListItem(base.copy(id = "queue", author = "Queue", isQueuedForLater = true))))
        for (scope in listOf(FavoriteScope.Authors, FavoriteScope.Fandoms, FavoriteScope.Tags)) {
            val row = ReadingAffinities.forScope(scope, items, emptyMap(), ReadingAffinities.Order.Recent).single()
            assertEquals("Visible", row.name); assertEquals(1, row.worksRead)
        }
    }
}
