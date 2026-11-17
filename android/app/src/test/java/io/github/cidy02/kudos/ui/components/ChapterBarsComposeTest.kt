package io.github.cidy02.kudos.ui.components

import android.app.Application
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.home.HomeResumeHero
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.WorkLedgerRow
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.detail.WorkDetailResumeCard
import java.time.Instant
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
class ChapterBarsComposeTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun unknownTotalCardShowsMoreToComeLegendAndTalkBackSummary() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                WorkDetailResumeCard(
                    actionTitle = "Read",
                    isBusy = false,
                    downloadFraction = null,
                    readingProgress = 0.58,
                    savedPositionTitle = "Ch 7",
                    lastReadDate = null,
                    palette = LocalKudosTokens.current.scopePalette,
                    onClick = {},
                    chapters = "12/?"
                )
            }
        }
        compose.onNodeWithText("More to come, total not set", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithText("Not posted yet", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithContentDescription("Chapters: 6 read, 12 posted, total not set by the author", useUnmergedTree = true)
            .assertExists()
    }

    @Test
    fun oneChapterWorkShowsOneChapterLabelAndResumeButtonOncePositionExists() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                WorkDetailResumeCard(
                    actionTitle = "Continue Reading",
                    isBusy = false,
                    downloadFraction = null,
                    readingProgress = 0.38,
                    savedPositionTitle = "Chapter 1",
                    lastReadDate = null,
                    palette = LocalKudosTokens.current.scopePalette,
                    onClick = {},
                    chapters = "1/1"
                )
            }
        }
        compose.onNodeWithText("Resume", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("One chapter", substring = true, useUnmergedTree = true).assertExists()
        compose.onAllNodesWithText("Not posted yet", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("More to come, total not set", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithContentDescription("One chapter, 38 percent read", useUnmergedTree = true).assertExists()
    }

    @Test
    fun groupedCardShowsGroupNoteAndTalkBackSummary() {
        val layout = ChapterBarGeometry.layout(
            planned = 200,
            posted = 143,
            read = 61,
            chapterProgress = 0.40,
            scale = ChapterBarScale.Card,
            fit = 37
        )
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                ChapterBars(layout = layout, scale = ChapterBarScale.Card)
            }
        }
        compose.onNodeWithText("Each bar is 6 chapters", useUnmergedTree = true).assertExists()
        compose.onNodeWithContentDescription(
            "Chapters: 61 read, 143 posted, 57 not posted yet. Each bar is 6 chapters",
            useUnmergedTree = true
        ).assertExists()
    }

    @Test
    fun defaultTwelveOfTwentyCardShowsNotPostedYetLegendAndResumeChapterTitle() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                WorkDetailResumeCard(
                    actionTitle = "Continue Reading",
                    isBusy = false,
                    downloadFraction = null,
                    readingProgress = 0.58,
                    savedPositionTitle = "Ch 7, The Salt Road",
                    lastReadDate = null,
                    palette = LocalKudosTokens.current.scopePalette,
                    onClick = {},
                    chapters = "12/20"
                )
            }
        }
        compose.onNodeWithText("Resume Chapter 7", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Not posted yet", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithText("More to come, total not set", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithContentDescription("Chapters: 6 read, 12 posted, 8 not posted yet", useUnmergedTree = true)
            .assertExists()
    }

    @Test
    fun homeResumeHeroDrawsChapterBarsAndOneChapterLabel() {
        val work = SavedWork(
            id = "hero-1",
            title = "One-shot",
            author = "wren",
            chapters = "1/1",
            hasEpub = false,
            lastReadDate = Instant.parse("2026-10-02T12:00:00Z"),
            lastScrollFraction = 0.40
        )
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                HomeResumeHero(
                    work = work,
                    downloadFraction = null,
                    obscured = false,
                    isSelecting = false,
                    isSelected = false
                )
            }
        }
        compose.onNodeWithText("One chapter", substring = true, useUnmergedTree = true).assertExists()
        compose.onNodeWithContentDescription("One chapter, 40 percent read", useUnmergedTree = true).assertExists()
    }

    @Test
    fun workLedgerRowAndSensitiveWorkRowExposeTalkBackChapterSummary() {
        val work = SavedWork(
            id = "row-1",
            title = "Long WIP",
            author = "author",
            chapters = "12/?",
            hasEpub = false
        )
        val rowLayout = ChapterBarModel.layout(
            chapters = work.chapters,
            progress = null,
            weights = null,
            scale = ChapterBarScale.Row
        )
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                androidx.compose.foundation.layout.Column {
                    WorkLedgerRow(
                        title = work.title,
                        author = work.author,
                        fandoms = emptyList(),
                        metadata = "12/?",
                        progress = 0.0,
                        progressState = null,
                        rating = "General Audiences",
                        categories = emptyList(),
                        warnings = emptyList(),
                        isComplete = false,
                        obscured = false,
                        favorite = false,
                        selected = false,
                        onClick = {},
                        onLongClick = {},
                        chapterBarLayout = rowLayout
                    )
                    SensitiveWorkRow(
                        work = work,
                        onOpenWork = {}
                    )
                }
            }
        }
        compose.onAllNodesWithText("Long WIP", useUnmergedTree = true).assertCountEquals(2)
        compose.onAllNodesWithContentDescription(
            "Chapters: 0 read, 12 posted, total not set by the author",
            useUnmergedTree = true
        ).assertCountEquals(2)
    }
}
