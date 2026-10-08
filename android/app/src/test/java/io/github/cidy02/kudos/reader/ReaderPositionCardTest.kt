package io.github.cidy02.kudos.reader

import android.app.Application
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ReaderPositionCardTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun draggingPreviewsChapterPagesAndReleaseCommitsOnce() {
        val values = mutableListOf<Float>()
        var commits = 0
        compose.setContent {
            var value by remember { mutableStateOf(0.5f) }
            MaterialTheme {
                ReaderPositionCard(
                    page = ReaderProgressDisplay.scrubPage(value, 11), pageCount = 11,
                    chapterRemainingMinutes = 8, workLine = "Chapter 5 of 10 · 50% of work",
                    sliderValue = value, onSeek = { value = it; values += it }, onSeekEnd = { commits++ }
                )
            }
        }
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Seek within chapter").performTouchInput {
            swipe(Offset(width * 0.5f, height * 0.5f), Offset(width * 0.8f, height * 0.5f), 200)
        }
        compose.waitForIdle()
        assertTrue(values.isNotEmpty())
        assertTrue(values.last() > 0.5f)
        assertEquals(1, commits)
        val page = ReaderProgressDisplay.scrubPage(values.last(), 11)
        compose.onNodeWithContentDescription("Seek within chapter")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Page $page of 11"))
    }

    @Test
    fun chapterThumbTimeAndWorkWordsAreDistinctAndAccessible() {
        compose.setContent {
            MaterialTheme {
                ReaderPositionCard(
                    page = 6, pageCount = 11, chapterRemainingMinutes = 8,
                    workLine = "Chapter 2 of 10 · 34% of work · 1 hr 5 min left",
                    sliderValue = ReaderProgressDisplay.sliderValue(6, 11), onSeek = {}
                )
            }
        }
        compose.waitForIdle()
        compose.onNodeWithText("8 min").assertExists()
        compose.onNodeWithText(" left in chapter").assertExists()
        compose.onNodeWithText("Chapter 2 of 10 · 34% of work · 1 hr 5 min left").assertExists()
        compose.onNodeWithContentDescription("Seek within chapter")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Page 6 of 11"))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo(0.5f, 0f..1f)))
    }

    @Test
    fun singlePageChapterIsFullAndDisabled() {
        compose.setContent {
            MaterialTheme {
                ReaderPositionCard(
                    page = 1, pageCount = 1, chapterRemainingMinutes = 0,
                    workLine = "100% of work · 0 min left", sliderValue = 1f,
                    sliderEnabled = false, onSeek = {}
                )
            }
        }
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Seek within chapter").assertIsNotEnabled()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Page 1 of 1"))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo(1f, 0f..1f)))
    }

    @Test
    fun measuringDoesNotInventPagesOrChapterTime() {
        compose.setContent {
            MaterialTheme {
                ReaderPositionCard(
                    page = 0, pageCount = 0, chapterRemainingMinutes = null,
                    workLine = "34% of work", sliderValue = 0f,
                    sliderEnabled = false, onSeek = {}
                )
            }
        }
        compose.waitForIdle()
        compose.onNodeWithText("Page …").assertExists()
        compose.onNodeWithText(" left in chapter").assertDoesNotExist()
        compose.onNodeWithContentDescription("Seek within chapter").assertIsNotEnabled()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Measuring pages"))
    }
}
