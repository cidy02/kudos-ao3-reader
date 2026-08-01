package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.SavedWork
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SavedWorkChapterHelpersTest {
    @Test
    fun postedChapterCountParsesFractionAndBareCount() {
        assertEquals(3, work(chapters = "3/5").postedChapterCount)
        assertEquals(12, work(chapters = "12").postedChapterCount)
        assertEquals(0, work(chapters = "").postedChapterCount)
        assertEquals(0, work(chapters = "??").postedChapterCount)
        assertEquals(7, work(chapters = " 7 / 10 ").postedChapterCount)
    }

    @Test
    fun hasUpdateRequiresPositiveKnownAndHigherPosted() {
        assertFalse(work(chapters = "3/5", known = null).hasUpdate)
        assertFalse(work(chapters = "3/5", known = 0).hasUpdate)
        assertFalse(work(chapters = "3/5", known = 3).hasUpdate)
        assertFalse(work(chapters = "2/5", known = 3).hasUpdate)
        assertTrue(work(chapters = "5/10", known = 3).hasUpdate)
    }
}

class WorkUpdateCheckerEligibilityTest {
    private val now: Instant = Instant.parse("2026-07-31T12:00:00Z")

    @Test
    fun skipsCompleteWorksAndBlankSourceUrls() {
        assertFalse(
            WorkUpdateChecker.shouldCheck(
                work(isComplete = true, sourceUrl = "https://archiveofourown.org/works/1"),
                now
            )
        )
        assertFalse(
            WorkUpdateChecker.shouldCheck(
                work(isComplete = false, sourceUrl = ""),
                now
            )
        )
    }

    @Test
    fun respectsSixHourThrottle() {
        val due = work(
            sourceUrl = "https://archiveofourown.org/works/1",
            lastCheck = now.minusSeconds(6 * 3600 + 1)
        )
        val fresh = work(
            sourceUrl = "https://archiveofourown.org/works/2",
            lastCheck = now.minusSeconds(60)
        )
        val neverChecked = work(
            sourceUrl = "https://archiveofourown.org/works/3",
            lastCheck = null
        )

        assertTrue(WorkUpdateChecker.shouldCheck(due, now))
        assertFalse(WorkUpdateChecker.shouldCheck(fresh, now))
        assertTrue(WorkUpdateChecker.shouldCheck(neverChecked, now))
    }
}

class WorkUpdateCheckerApplyTest {
    private val now: Instant = Instant.parse("2026-07-31T12:00:00Z")

    @Test
    fun baselinesKnownChapterCountOnFirstSight() {
        val existing = work(chapters = "2/?", known = null)
        val updated = WorkUpdateChecker.applyChapterUpdate(existing, "4/?", now)

        assertEquals("4/?", updated.chapters)
        assertEquals(4, updated.knownChapterCount)
        assertEquals(now, updated.lastUpdateCheck)
        assertFalse(updated.hasUpdate)
    }

    @Test
    fun baselinesWhenKnownIsZero() {
        val existing = work(chapters = "2/?", known = 0)
        val updated = WorkUpdateChecker.applyChapterUpdate(existing, "3/10", now)

        assertEquals(3, updated.knownChapterCount)
        assertFalse(updated.hasUpdate)
    }

    @Test
    fun preservesKnownBaselineWhenNewChaptersAppear() {
        val existing = work(chapters = "3/?", known = 3)
        val updated = WorkUpdateChecker.applyChapterUpdate(existing, "5/?", now)

        assertEquals("5/?", updated.chapters)
        assertEquals(3, updated.knownChapterCount)
        assertEquals(now, updated.lastUpdateCheck)
        assertTrue(updated.hasUpdate)
    }
}

private fun work(
    id: String = "work",
    chapters: String = "1/1",
    known: Int? = null,
    isComplete: Boolean = false,
    sourceUrl: String = "https://archiveofourown.org/works/1",
    lastCheck: Instant? = null
): SavedWork {
    return SavedWork(
        id = id,
        title = "Title $id",
        author = "Author",
        chapters = chapters,
        knownChapterCount = known,
        isComplete = isComplete,
        sourceUrl = sourceUrl,
        lastUpdateCheck = lastCheck,
        isSaved = true
    )
}
