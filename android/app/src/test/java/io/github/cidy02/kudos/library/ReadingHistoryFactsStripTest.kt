package io.github.cidy02.kudos.library

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class ReadingHistoryFactsStripTest {
    @get:Rule val compose = createComposeRule()
    private val summary = mutableStateOf<WorkReadingSummary?>(WorkReadingSummary(5400.0, 3, 2, chapterCountAtLastVisit = 2))
    private val kind = mutableStateOf(LibrarySectionKind.History)
    private val posted = mutableStateOf(4)
    private fun show() = compose.setContent {
        KudosTheme(KudosThemeMode.Light) { ReadingHistoryFactsStrip(summary.value, kind.value, posted.value) }
    }

    @Test fun historyTimeUsesIOSFormattingAndOnlyPositiveTimeOnVisitedRows() {
        show()
        for ((seconds, label) in listOf(1800.0 to "30 min", 3600.0 to "1h", 5400.0 to "1h 30m", 30.0 to "1 min")) {
            compose.runOnIdle { summary.value = WorkReadingSummary(seconds, 1) }
            compose.onNodeWithText(label).assertExists()
        }
        compose.runOnIdle { summary.value = WorkReadingSummary(0.0, 1) }
        compose.onNodeWithText("0 min").assertDoesNotExist()
        compose.runOnIdle { summary.value = WorkReadingSummary(1800.0, 0) }
        compose.onNodeWithText("30 min").assertDoesNotExist()
        compose.runOnIdle { summary.value = null }
        compose.onNodeWithText("30 min").assertDoesNotExist()
    }

    @Test fun historyRereadsCountFinishesRatherThanVisitsAndRequireMoreThanOne() {
        show()
        compose.onNodeWithText("Read ×2").assertExists()
        compose.runOnIdle { summary.value = WorkReadingSummary(0.0, 3, 1) }
        compose.onNodeWithText("Read ×1").assertDoesNotExist()
        compose.onNodeWithText("Read ×3").assertDoesNotExist()
        compose.runOnIdle { summary.value = WorkReadingSummary(0.0, 0, 2) }
        compose.onNodeWithText("Read ×2").assertDoesNotExist()
    }

    @Test fun historyNewChaptersRequireKnownBaselineAndPositiveDeltaWithSingularAndPlural() {
        show()
        compose.onNodeWithText("2 new chapters").assertExists()
        compose.runOnIdle { posted.value = 3 }
        compose.onNodeWithText("1 new chapter").assertExists()
        for (count in listOf(2, 1, 0)) {
            compose.runOnIdle { posted.value = count }
            compose.onNodeWithText("new chapter", substring = true).assertDoesNotExist()
        }
        compose.runOnIdle { posted.value = 4; summary.value = summary.value!!.copy(chapterCountAtLastVisit = 0) }
        compose.onNodeWithText("new chapter", substring = true).assertDoesNotExist()
    }

    @Test fun favoritesTimeUsesSamePositiveVisitedRuleAndOtherSectionsHaveNoFacts() {
        kind.value = LibrarySectionKind.Favorites
        show()
        compose.onNodeWithText("1h 30m").assertExists()
        compose.onNodeWithText("new chapter", substring = true).assertDoesNotExist()
        compose.runOnIdle { summary.value = summary.value!!.copy(totalSeconds = 0.0) }
        compose.onNodeWithText("0 min").assertDoesNotExist()
        compose.runOnIdle { summary.value = summary.value!!.copy(totalSeconds = 5400.0, visitCount = 0) }
        compose.onNodeWithText("1h 30m").assertDoesNotExist()
        compose.runOnIdle { summary.value = summary.value!!.copy(visitCount = 3); kind.value = LibrarySectionKind.Downloaded }
        compose.onNodeWithText("1h 30m").assertDoesNotExist()
    }

    @Test fun favoritesRereadsRequireTwoFinishesAndAVisit() {
        kind.value = LibrarySectionKind.Favorites
        show()
        compose.onNodeWithText("Read ×2").assertExists()
        for (count in listOf(0, 1)) {
            compose.runOnIdle { summary.value = summary.value!!.copy(finishCount = count) }
            compose.onNodeWithText("Read ×", substring = true).assertDoesNotExist()
        }
        compose.runOnIdle { summary.value = summary.value!!.copy(finishCount = 2, visitCount = 0) }
        compose.onNodeWithText("Read ×2").assertDoesNotExist()
    }

    @Test fun summaryTakesChapterBaselineFromLatestEndedVisitRatherThanLargestChapterCount() {
        val now = Instant.parse("2026-10-22T12:00:00Z")
        fun visit(id: String, offset: Long, chapters: Int) = ReadingSessionEntity(id, "work",
            startedAt = now.plusSeconds(offset), endedAt = now.plusSeconds(offset + 60), durationSeconds = 60.0,
            chapterCountAtVisit = chapters, didFinish = true, lastModifiedAt = now)
        val result = ReadingAffinities.summaries(listOf(visit("new", 100, 2), visit("old", 0, 9))).getValue("work")
        assertEquals(2, result.chapterCountAtLastVisit)
        assertEquals(120.0, result.totalSeconds, 0.0)
        assertEquals(2, result.finishCount)
    }
}
