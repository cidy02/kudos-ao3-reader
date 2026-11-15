package io.github.cidy02.kudos.library

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.home.HomeSectionLedgerRow
import io.github.cidy02.kudos.search.LocalTagSearch
import io.github.cidy02.kudos.search.SearchSubjectField
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
class LibrarySectionRowPresentationTest {
    @get:Rule val compose = createComposeRule()
    private val kind = mutableStateOf(LibrarySectionKind.History)
    private val selecting = mutableStateOf(false)
    private val obscured = mutableStateOf(false)
    private val selected = mutableStateOf(false)
    private val progress = mutableStateOf(0.42)
    private var opened = 0
    private var revealed = 0
    private var picked = 0
    private val actions = LibraryCardActions(
        onOpenWork = { opened++ }, onOpenReader = { opened++ }, onToggleFavorite = {},
        onToggleFinished = {}, onRemove = {}, onDownloadAction = { _, _ -> },
        onSelect = { picked++ }, onReveal = { revealed++ }, onAddToQueue = {}, onAddToCollection = {},
        onOpenComments = {}
    )
    private fun show() = compose.setContent {
        KudosTheme(KudosThemeMode.Light) {
            LibrarySubjectLedgerRow(
                display = LibraryDisplayItem(
                    LibraryWorkListItem(SavedWork(id = "row", title = "A work", author = "A writer",
                        summary = "A summary shown only by detailed cards.", wordCount = 1200, chapters = "1/1",
                        workFandoms = listOf("Doctor Who"), legacyReaderProgress = progress.value,
                        workFreeforms = listOf("Found Family"))),
                    if (obscured.value) LibraryPrivacyVisibility.Obscured else LibraryPrivacyVisibility.Visible
                ),
                kind = kind.value, actions = actions, onRemoveFromHistory = {}, onRemoveFromAllQueues = {},
                selecting = selecting.value, selected = selected.value
            )
        }
    }

    @Test fun sectionDefaultsChooseSavedLedgerRowsOnlyForHistoryAndFavorites() {
        show()
        LibrarySectionKind.entries.forEach { section ->
            compose.runOnIdle { kind.value = section }
            val compact = section == LibrarySectionKind.History || section == LibrarySectionKind.Favorites
            if (compact) {
                compose.onNodeWithText("42%", substring = true).assertExists()
                // iOS T-509: the grey line is the author alone; the compact figures keep a line of their own.
                compose.onNodeWithText("A writer").assertExists()
                compose.onNodeWithText("1.2K words · 1/1").assertExists()
                compose.onNodeWithText("A writer · 1.2K words · 1/1").assertDoesNotExist()
                compose.onNodeWithText("A summary shown only by detailed cards.").assertDoesNotExist()
                compose.onNodeWithContentDescription("Show more").assertDoesNotExist()
            } else {
                compose.onNodeWithText("A summary shown only by detailed cards.").assertExists()
                compose.onNodeWithText("42%", substring = true).assertDoesNotExist()
                // Android's affinity tags remain accessible on detailed cards.
                compose.onNodeWithContentDescription("Show more").assertExists()
            }
        }
    }

    @Test fun anUnopenedCompactWorkShowsZeroPercentWithoutClaimingAReadingSession() {
        progress.value = 0.0
        show()
        compose.onNodeWithText("0%").assertExists()
        compose.onNodeWithText("READING").assertDoesNotExist()
    }

    @Test fun compactRowKeepsRevealSelectionAndOpenActions() {
        obscured.value = true
        show()
        compose.onNodeWithContentDescription("Hidden mature work. Activate to reveal.").performClick()
        assertEquals(1, revealed)
        assertEquals(0, opened)
        compose.runOnIdle { selecting.value = true; selected.value = true }
        compose.onNodeWithContentDescription("Hidden mature work").performClick()
        assertEquals(1, picked)
        compose.runOnIdle { obscured.value = false }
        compose.onAllNodes(isToggleable()).filter(isOn()).assertCountEquals(1)
        compose.onNodeWithContentDescription("A work, by A writer").performClick()
        assertEquals(2, picked)
        compose.runOnIdle { selecting.value = false }
        compose.onNodeWithContentDescription("A work, by A writer").performClick()
        assertEquals(1, opened)
    }

    @Test fun homeSectionLedgerRowSplitsFiguresAndDropsFandomLinkWhileSelecting() {
        var searched: Pair<SearchSubjectField, String>? = null
        val work = SavedWork(
            id = "home-row", title = "A work", author = "A writer",
            summary = "Hidden on ledger rows.", wordCount = 1200, chapters = "1/1",
            workFandoms = listOf("Doctor Who"), legacyReaderProgress = 0.42
        )
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalTagSearch provides { f, v -> searched = f to v }) {
                    HomeSectionLedgerRow(
                        display = LibraryDisplayItem(LibraryWorkListItem(work), LibraryPrivacyVisibility.Visible),
                        actions = actions,
                        selected = selected.value,
                        selecting = selecting.value,
                        onRemoveFromAllQueues = {}
                    )
                }
            }
        }
        compose.onNodeWithText("A writer").assertExists()
        compose.onNodeWithText("1.2K words · 1/1").assertExists()
        compose.onNodeWithText("A writer · 1.2K words · 1/1").assertDoesNotExist()
        compose.onNodeWithContentDescription("Fandom: Doctor Who").assertExists()

        compose.runOnIdle { selecting.value = true; selected.value = true }
        compose.onAllNodes(isToggleable()).filter(isOn()).assertCountEquals(1)
        compose.onAllNodesWithContentDescription("Fandom: Doctor Who", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithText("DOCTOR WHO", useUnmergedTree = true).performClick()
        assertNull(searched)
    }

    @Test fun collectionLedgerRowSplitsFiguresAndDropsFandomLinkWhileSelecting() {
        var searched: Pair<SearchSubjectField, String>? = null
        val work = SavedWork(
            id = "col-row", title = "A work", author = "A writer",
            summary = "Hidden on ledger rows.", wordCount = 1200, chapters = "1/1",
            workFandoms = listOf("Doctor Who"), legacyReaderProgress = 0.42
        )
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalTagSearch provides { f, v -> searched = f to v }) {
                    CollectionWorkListItem(
                        work = work,
                        collection = WorkCollection(name = "Favorites"),
                        displayMode = CollectionDisplayMode.Ledger,
                        expandAll = false,
                        isSelecting = selecting.value,
                        isSelected = selected.value,
                        obscured = false,
                        palette = SubjectPalette.fromHue(0.5, ReaderTheme.Light),
                        actions = actions,
                        onToggleSelection = { picked++ },
                        onOpenWork = { opened++ },
                        onOpenReader = { opened++ },
                        onReveal = { revealed++ },
                        onRemove = {}
                    )
                }
            }
        }
        compose.onNodeWithText("A writer").assertExists()
        compose.onNodeWithText("1.2K words · 1/1").assertExists()
        compose.onNodeWithText("A writer · 1.2K words · 1/1").assertDoesNotExist()
        compose.onNodeWithContentDescription("Fandom: Doctor Who").assertExists()

        compose.runOnIdle { selecting.value = true; selected.value = true }
        compose.onAllNodes(isToggleable()).filter(isOn()).assertCountEquals(1)
        compose.onAllNodesWithContentDescription("Fandom: Doctor Who", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithText("DOCTOR WHO", useUnmergedTree = true).performClick()
        assertNull(searched)
    }
}
