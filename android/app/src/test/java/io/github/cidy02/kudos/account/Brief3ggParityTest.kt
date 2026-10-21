package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.network.ao3.inbox.*
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceWebLink
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.CanonicalWork
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Brief3ggParityTest {
    @get:Rule val compose = createComposeRule()
    private val work = AO3WorkSummary(123, "Work", listOf("Writer"), listOf("Fandom"), "General Audiences", emptyList(), emptyList())
    private val reader = AO3InboxItem(id = 1, commenterName = "ReaderOne", commenterUsername = "reader",
        subjectTitle = "Work", workId = 123, excerpt = "A comment", postedAgo = "3 days ago",
        isUnread = true, isReplied = false, canReply = true)

    @Test fun preferenceRowsFollowIosOrderAndWordsWithoutDroppingUnknownLinksOrChangingUrls() {
        val base = "https://archiveofourown.org/users/Reader/"
        val paths = listOf("muted/users", "blocked/users", "change_email", "change_password", "pseuds", "profile/edit", "change_username")
        val extra = AO3PreferenceWebLink("Extra account information", base + "extra")
        val original = paths.map { AO3PreferenceWebLink("Web label", base + it) } + extra
        val rows = orderedPreferenceAccountLinks(original)
        assertEquals(listOf("Edit profile", "Manage pseuds", "Change username", "Change password", "Change email", "Blocked users", "Muted users", extra.title), rows.map { it.title })
        assertEquals(original.map { it.url }.toSet(), rows.map { it.url }.toSet())
        assertEquals(extra, rows.last())
    }

    @Test fun aRemoteCoverOmitsAnAbsentAuthorButRetainsExplicitAnonymousAndNamedAuthors() {
        assertEquals("", work.copy(authors = emptyList()).coverFace().author)
        assertEquals("", work.copy(authors = listOf("")).coverFace().author)
        assertEquals("Anonymous", work.copy(authors = listOf("Anonymous")).coverFace().author)
        assertEquals("Writer", work.coverFace().author)
    }

    @Test fun inboxKeepsMeaningfulRolesAtEveryTextSizeAndReplyStillOpensItsComposer() {
        var item by mutableStateOf(reader)
        var theme by mutableStateOf(KudosThemeMode.Light)
        var scale by mutableStateOf(1f)
        var workAuthors by mutableStateOf(emptyList<io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor>())
        var replies = 0
        compose.setContent { KudosTheme(theme) {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                InboxItemCard(item, workAuthors, "owner", false, false, false, true, true,
                    false, false, false, false, onOpen = {}, onReply = { replies++ },
                    onToggleSelection = {}, onMarkRead = {}, onMarkUnread = {}, onDelete = {})
            }
        } }
        for (mode in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            for (size in listOf(1f, 2f)) {
                compose.runOnIdle { theme = mode; scale = size; item = reader; workAuthors = emptyList() }
                compose.onAllNodesWithText("User").assertCountEquals(0)
                compose.onNodeWithContentDescription("Reply to ReaderOne").assertIsDisplayed().performClick()
                compose.runOnIdle { item = reader.copy(isGuest = true, commenterUsername = null) }
                compose.onNodeWithText("Guest").assertExists()
                compose.runOnIdle {
                    item = reader
                    workAuthors = listOf(io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor("ReaderOne", "reader"))
                }
                compose.onNodeWithText("Author").assertExists()
                compose.runOnIdle { item = reader.copy(commenterUsername = "owner") }
                compose.onNodeWithText("Me").assertExists()
            }
        }
        compose.runOnIdle { assertEquals(8, replies) }
    }

    @Test fun unreadSegmentDoesNotBadgeTheInboxFilterButton() {
        val form = AO3InboxFilterForm("https://archiveofourown.org/users/owner/inbox", emptyList(), listOf(
            AO3InboxFilterField("filters[read]", "Read", listOf(
                AO3InboxFilterOption("all", "All", false), AO3InboxFilterOption("false", "Unread", true)))
        ))
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            InboxToolbar(AccountInboxUiState(filterForm = form), LocalSubjectPalette.current, {}, {}, {})
        } }
        compose.onNodeWithContentDescription("Filter").assertExists()
        compose.onAllNodesWithContentDescription("Filter, 1 active").assertCountEquals(0)
        compose.onAllNodesWithText("1").assertCountEquals(0)
    }

    @Test fun unmarkLivesInsideTheWorkCardAndKeepsItsAction() {
        var unmarked = 0
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            Column { MarkedForLaterRow(CanonicalWork(null, work), false, LocalSubjectPalette.current, {}, { unmarked++ },
                Modifier.testTag("Marked for Later card")) }
        } }
        val card = compose.onNodeWithTag("Marked for Later card").fetchSemanticsNode().boundsInRoot
        val action = compose.onNodeWithText("Unmark").fetchSemanticsNode().boundsInRoot
        assertTrue("Unmark must end inside the card", action.bottom <= card.bottom)
        assertTrue(action.top >= card.top)
        compose.onNodeWithText("Unmark").performClick()
        compose.runOnIdle { assertEquals(1, unmarked) }
    }
}
