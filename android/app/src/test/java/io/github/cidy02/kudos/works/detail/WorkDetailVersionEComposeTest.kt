package io.github.cidy02.kudos.works.detail

import androidx.compose.ui.geometry.Offset
import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.search.LocalTagSearch
import io.github.cidy02.kudos.search.SearchSubjectField
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.subject.HomeStatusTray
import io.github.cidy02.kudos.ui.subject.HomeStatusArrangement
import io.github.cidy02.kudos.ui.components.rememberStoredBool
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Instant

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2000dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WorkDetailVersionEComposeTest {
    @get:Rule val compose = createComposeRule()

    @Test fun localOnlyCompletionIsAnnouncedInTheIconStrip() {
        val local = SavedWork(title = "Import", author = "A", dateAdded = Instant.EPOCH,
            sourceUrl = "file:///import.epub", isComplete = true)
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            HomeStatusTray("Not rated", emptyList(), emptyList(),
                WorkDetailPresentation.completion(local, null),
                arrangement = HomeStatusArrangement.Row, announces = true, backed = false)
        } }
        compose.onNode(hasContentDescription("Status: complete", substring = true)).assertExists()
    }

    @Test fun headlineControlsAreNamedAndInvokeTheirOwnActions() {
        var contents = 0
        var aloud = 0
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            WorkDetailResumeCard(
                actionTitle = "Read", model = ResumeCardModel("Title", emptyList(), "1/1", null, null, null, 0),
                chapterLengths = null, isBusy = false, downloadFraction = null, canUpdateDownload = false,
                onPrimaryClick = {}, onContentsClick = { contents++ }, onReadAloudClick = { aloud++ }
            )
        } }
        compose.onNodeWithContentDescription("Contents").assertHasClickAction().assertHeightIsAtLeast(48.dp).performClick()
        compose.onNodeWithContentDescription("Read Aloud").assertHasClickAction().assertHeightIsAtLeast(48.dp).performClick()
        assertEquals(1, contents)
        assertEquals(1, aloud)
    }

    @Test fun tagTextInvokesTheInlineLinkInsteadOfAnInertRow() {
        var tapped: Pair<SearchSubjectField, String>? = null
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            CompositionLocalProvider(LocalTagSearch provides { field, tag -> tapped = field to tag }) {
                Box(Modifier.fillMaxWidth().testTag("tag-row-container")) {
                    WorkDetailTagSections(
                        emptyList(), emptyList(), listOf("Alpha", "Beta"), emptyList(), emptyList(),
                        LocalKudosTokens.current.scopePalette
                    )
                }
            }
        } }
        val results = mutableListOf<TextLayoutResult>()
        val textNode = compose.onNodeWithText("Alpha, Beta")
        textNode.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        val layout = results.single()
        val textBounds = textNode.fetchSemanticsNode().boundsInRoot
        val containerBounds = compose.onNodeWithTag("tag-row-container").fetchSemanticsNode().boundsInRoot

        // Tapping trailing empty row space well to the right of the tag text must do nothing.
        compose.onNodeWithTag("tag-row-container").performTouchInput {
            click(Offset(containerBounds.width - 12f, textBounds.center.y - containerBounds.top))
        }
        assertNull(tapped)

        // Tapping trailing empty row space well to the right of the tag text must do nothing.
        compose.onNodeWithTag("tag-row-container").performTouchInput {
            click(Offset(containerBounds.width - 12f, textBounds.center.y - containerBounds.top))
        }
        assertNull(tapped)

        // Tapping the group label outside any tag link word must do nothing.
        compose.onNodeWithText("Relationships").performTouchInput { click() }
        assertNull(tapped)

        // Tapping each inline tag word triggers only that tag's search.
        textNode.performTouchInput { click(layout.getBoundingBox(1).center) }
        assertEquals(SearchSubjectField.RELATIONSHIP to "Alpha", tapped)

        tapped = null
        textNode.performTouchInput { click(layout.getBoundingBox(8).center) }
        assertEquals(SearchSubjectField.RELATIONSHIP to "Beta", tapped)
    }

    @Test fun contentsButtonExposesPostedChapterStateDescription() {
        val chapters = mutableStateOf("10/12")
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            WorkDetailResumeCard(
                actionTitle = "Read",
                model = ResumeCardModel("Title", emptyList(), chapters.value, null, null, null, 0),
                chapterLengths = null, isBusy = false, downloadFraction = null, canUpdateDownload = false,
                onPrimaryClick = {}, onContentsClick = {}, onReadAloudClick = {}
            )
        } }
        compose.onNodeWithContentDescription("Contents")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "10 of 12 chapters"))
        compose.runOnIdle { chapters.value = "4/?" }
        compose.onNodeWithContentDescription("Contents")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "4 of ? chapters"))
    }

    @Test fun currentWorkSeriesRowIsOneMergedAccessibilityStop() {
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            WorkDetailSeriesSection(
                seriesTitle = "Coast Road", seriesPosition = 2,
                seriesUrl = "https://archiveofourown.org/series/1", queuingSeries = false,
                currentWorkTitle = "Salt & Copper",
                onDownloadSeries = {}, onOpenSeries = {}
            )
        } }
        compose.onNode(hasText("2. Salt & Copper") and hasText("This work"))
            .assertExists()
            .assertHasNoClickAction()
    }

    @Test fun summaryLessSurvivesFontScaleChangeWhileExpanded() {
        val scale = mutableStateOf(1f)
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, scale.value)) {
                WorkDetailSummarySection(
                    "word ".repeat(30),
                    LocalKudosTokens.current.scopePalette,
                    modifier = Modifier.width(160.dp)
                )
            }
        } }
        compose.onNodeWithText("More").assertHasClickAction().performClick()
        compose.onNodeWithText("Less").assertExists()

        compose.runOnIdle { scale.value = 2f }
        compose.onNodeWithText("Less").assertHasClickAction().performClick()
        compose.onNodeWithText("More").assertExists()
    }

    @Test fun disclosureHeaderClearsChildTextSemanticsAndPreservesButtonAction() {
        var expanded = mutableStateOf(false)
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            WorkDetailTagSections(
                emptyList(), emptyList(), listOf("Friends"), emptyList(), emptyList(),
                LocalKudosTokens.current.scopePalette,
                expanded = expanded.value,
                onToggleExpanded = { expanded.value = !expanded.value }
            )
        } }
        val node = compose.onNodeWithContentDescription("Tags, 1 relationship")
            .assertHasClickAction()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Collapsed"))
            .fetchSemanticsNode()
        assertTrue(SemanticsProperties.Heading in node.config)
        assertFalse(SemanticsProperties.Text in node.config)
        compose.onNodeWithContentDescription("Tags, 1 relationship").performClick()
        compose.onNodeWithContentDescription("Tags, 1 relationship")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Expanded"))
    }

    @Test fun summaryMoreAppearsOnlyForMeasuredOverflow() {
        val width = mutableStateOf(120.dp)
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            WorkDetailSummarySection("word ".repeat(20), LocalKudosTokens.current.scopePalette,
                modifier = Modifier.width(width.value))
        } }
        compose.onNodeWithText("More").assertHasClickAction().performClick()
        compose.onNodeWithText("Less").assertExists().performClick()
        compose.runOnIdle { width.value = 600.dp }
        compose.onNodeWithText("More").assertDoesNotExist()
    }

    @Test fun disclosureChoicePersistsAcrossRecomposition() {
        val context = ApplicationProvider.getApplicationContext<Application>()
        val key = "a511-disclosure-test"
        context.getSharedPreferences("layout-choices", 0).edit().remove(key).commit()
        val shown = mutableStateOf(true)
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            if (shown.value) {
                val expanded = rememberStoredBool(key, false)
                WorkDetailTagSections(emptyList(), emptyList(), listOf("Friends"), emptyList(), emptyList(),
                    LocalKudosTokens.current.scopePalette, expanded = expanded.value,
                    onToggleExpanded = { expanded.value = !expanded.value })
            }
        } }
        compose.onNodeWithText("Friends").assertDoesNotExist()
        compose.onNodeWithContentDescription("Tags, 1 relationship").performClick()
        compose.onNodeWithText("Friends").assertExists()
        compose.runOnIdle { shown.value = false }
        compose.runOnIdle { shown.value = true }
        compose.onNodeWithText("Friends").assertExists()
        assertTrue(context.getSharedPreferences("layout-choices", 0).getBoolean(key, false))
    }

    @Test fun seriesActionsHaveAtLeast48DpTargetsAndWork() {
        var downloads = 0
        var opened = ""
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            WorkDetailSeriesSection("Series", 1, "https://archiveofourown.org/series/1", false,
                onDownloadSeries = { downloads++ }, onOpenSeries = { opened = it })
        } }
        for (label in listOf("Download Whole Series", "View Full Series on AO3")) {
            val node = compose.onNode(hasText(label) and hasClickAction())
            node.assertHeightIsAtLeast(48.dp)
            node.performClick()
        }
        assertEquals(1, downloads)
        assertEquals("https://archiveofourown.org/series/1", opened)
    }
}
