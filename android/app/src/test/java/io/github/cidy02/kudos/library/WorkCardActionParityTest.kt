package io.github.cidy02.kudos.library

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.search.SearchSubjectField
import io.github.cidy02.kudos.ui.components.SensitiveWorkRow
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.works.detail.LocalOpenAuthor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WorkCardActionParityTest {
    @get:Rule val compose = createComposeRule()
    private val identities = """[{"username":"account","pseud":"Pen Name","displayName":"Pen Name","kind":"registered"}]"""
    private val work = SavedWork(title = "Work", author = "Pen Name", authorIdentitiesJSON = identities,
        workFreeforms = (1..17).map { "Tag $it" })

    @Test fun detailedBylineOpensTheVerifiedAccountAndTheSeventeenthTagCanSearch() {
        val authors = mutableListOf<String>()
        val tags = mutableListOf<Pair<SearchSubjectField, String>>()
        compose.setContent { KudosTheme(themeMode = io.github.cidy02.kudos.ui.theme.KudosThemeMode.Light) {
            CompositionLocalProvider(LocalOpenAuthor provides { authors += it }) {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    SensitiveWorkRow(work, {}, expandAll = true, onTagSearch = { field, tag -> tags += field to tag })
                }
            }
        } }
        compose.onNodeWithText("Pen Name").performClick()
        compose.onNodeWithText("Tag 17").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(listOf("Pen Name (account)"), authors)
            assertEquals(listOf(SearchSubjectField.FREEFORM to "Tag 17"), tags)
        }
    }

    @Test fun pickerDismissesBeforeOpeningTheVerifiedAuthor() {
        val events = mutableListOf<String>()
        compose.setContent { KudosTheme(themeMode = io.github.cidy02.kudos.ui.theme.KudosThemeMode.Light) {
            CompositionLocalProvider(LocalOpenAuthor provides { events += it }) {
                AddLibraryWorksSheet("Shelf", "collection", listOf(work),
                    PrivacySettings(hideMatureContent = false), PrivacyRevealState(), {},
                    onDismiss = { events += "dismiss" }, onAdd = {})
            }
        } }
        compose.onNodeWithText("Pen Name").performClick()
        compose.runOnIdle { assertEquals(listOf("dismiss", "Pen Name (account)"), events) }
    }

    @Test fun queueMenuLeadsWithReadMovesAndShareBeforeItsExistingActions() {
        var movedTop = 0
        val actions = LibraryCardActions(
            onOpenWork = {}, onOpenReader = {}, onToggleFavorite = {}, onToggleFinished = {},
            onRemove = {}, onDownloadAction = { _, _ -> }, onSelect = {}, onReveal = {},
            onAddToQueue = {}, onAddToCollection = {}, onOpenComments = {}
        )
        compose.setContent { KudosTheme(themeMode = io.github.cidy02.kudos.ui.theme.KudosThemeMode.Light) {
            LibraryWorkMenu(
                expanded = true,
                onDismiss = {},
                work = work.copy(id = "queued", hasEpub = true, ao3WorkID = 123,
                    sourceUrl = "https://archiveofourown.org/works/123"),
                actions = actions,
                queueActions = QueueItemMenuActions(
                    moveToTop = { movedTop++ }, moveToBottom = {}, share = {}
                )
            )
        } }
        val labels = listOf("Read", "To Top", "To Bottom", "Share", "Comments")
        val tops = labels.map { compose.onNodeWithText(it).fetchSemanticsNode().boundsInRoot.top }
        assertEquals(tops.sorted(), tops)
        assertTrue(tops.zipWithNext().all { (before, after) -> before < after })
        compose.onNodeWithText("To Top").performClick()
        compose.runOnIdle { assertEquals(1, movedTop) }
    }
}
