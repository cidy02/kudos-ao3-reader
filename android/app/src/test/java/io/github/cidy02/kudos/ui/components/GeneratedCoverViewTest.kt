package io.github.cidy02.kudos.ui.components

import android.app.Application
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.library.CollectionCard
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.subject.SubjectRemoteCoverCard
import io.github.cidy02.kudos.ui.subject.SubjectWorkCoverCard
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class GeneratedCoverViewTest {
    @get:Rule val compose = createComposeRule()

    private val work = SavedWork(
        id = "work-1",
        ao3WorkID = 123456,
        title = "A Secret Work",
        author = "An Author",
        rating = "Explicit",
        wordCount = 12_000,
        chapters = "3/3",
        isComplete = true,
        workFandoms = listOf("Original Work")
    )

    private val remoteSummary = AO3WorkSummary(
        id = 654321,
        title = "Remote Title",
        authors = listOf("Remote Author"),
        fandoms = listOf("Good Omens (TV)"),
        rating = "Mature",
        warnings = emptyList(),
        categories = listOf("M/M"),
        wordCount = 24_000,
        chapters = "2/?",
        isComplete = false,
        updatedDate = "14 Nov 2026"
    )

    @Test fun generatedCoverShowsWordsWhenVisibleAndDrawsGroundOnlyWhenHidden() {
        val recipe = work.generatedCoverRecipe()
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                GeneratedCoverView(recipe = recipe, width = 164.dp, showsWords = true, showsArt = true)
            }
        }
        compose.onNodeWithContentDescription("A Secret Work, An Author, Original Work").assertExists()

        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                GeneratedCoverView(recipe = recipe, width = 164.dp, showsWords = false, showsArt = false)
            }
        }
        compose.onAllNodesWithText("A Secret Work", substring = true).assertCountEquals(0)
        compose.onAllNodesWithText("An Author", substring = true).assertCountEquals(0)
        compose.onAllNodesWithContentDescription("A Secret Work", substring = true).assertCountEquals(0)
    }

    @Test fun subjectWorkCoverCardHidesDetailsWhenObscuredAndShowsSummaryWhenVisible() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SubjectWorkCoverCard(work = work, obscured = false, downloadFraction = null)
            }
        }
        compose.onNodeWithContentDescription("A Secret Work", substring = true).assertExists()
        compose.onNodeWithText("12K words · 3/3").assertExists()

        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SubjectWorkCoverCard(work = work, obscured = true, downloadFraction = null)
            }
        }
        compose.onAllNodesWithText("A Secret Work", substring = true).assertCountEquals(0)
        compose.onAllNodesWithText("12K words", substring = true).assertCountEquals(0)
        compose.onAllNodesWithContentDescription("A Secret Work", substring = true).assertCountEquals(0)
        compose.onNodeWithContentDescription("Hidden mature work. Activate to reveal.").assertExists()
    }

    @Test fun subjectRemoteCoverCardRespectsProvenanceAndObscuredMode() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SubjectRemoteCoverCard(summary = remoteSummary, showsProvenance = true, obscured = false)
            }
        }
        compose.onNodeWithContentDescription("Remote Title", substring = true).assertExists()
        compose.onNodeWithContentDescription("From AO3").assertExists()
        compose.onNodeWithText("24K words · 2/? · 14 Nov 2026").assertExists()

        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SubjectRemoteCoverCard(summary = remoteSummary, showsProvenance = true, obscured = true)
            }
        }
        compose.onAllNodesWithText("Remote Title", substring = true).assertCountEquals(0)
        compose.onAllNodesWithContentDescription("From AO3").assertCountEquals(0)
        compose.onNodeWithContentDescription("Hidden mature work. Activate to reveal.").assertExists()
    }

    @Test fun collectionCardUsesCoverStackBothEmptyAndPopulated() {
        val emptyCollection = WorkCollection(id = "col-empty", name = "Empty Shelf", workIds = emptyList())
        val fullCollection = WorkCollection(id = "col-full", name = "Populated Shelf", workIds = listOf(work.id))
        compose.setContent {
            KudosTheme(KudosThemeMode.Dark) {
                CollectionCard(
                    collection = emptyCollection,
                    previewWorks = emptyList(),
                    onClick = {},
                    onLongClick = {}
                )
            }
        }
        compose.onNodeWithText("Empty Shelf").assertExists()
        compose.onNodeWithText("0 works").assertExists()

        compose.setContent {
            KudosTheme(KudosThemeMode.Dark) {
                CollectionCard(
                    collection = fullCollection,
                    previewWorks = listOf(work),
                    onClick = {},
                    onLongClick = {}
                )
            }
        }
        compose.onNodeWithText("Populated Shelf").assertExists()
        compose.onNodeWithText("1 work").assertExists()
    }

    @Test fun artCacheKeyIsDeterministicAndTracksDimensionsAndRecipe() {
        val recipe = work.generatedCoverRecipe()
        val a = artCacheKey(recipe, 164.0, 232.88)
        val b = artCacheKey(recipe, 164.0, 232.88)
        val wider = artCacheKey(recipe, 180.0, 255.6)
        val other = artCacheKey(work.copy(title = "Different Title").generatedCoverRecipe(), 164.0, 232.88)
        assertEquals(a, b)
        assertNotEquals(a, wider)
        assertNotEquals(a, other)
    }
}
