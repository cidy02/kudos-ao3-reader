package io.github.cidy02.kudos.ui.components

import android.app.Application
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import io.github.cidy02.kudos.search.SearchSubjectField
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Brief 3cn: the ledger form of the AO3 result card (iOS `AO3WorkRow.searchLedgerCard`). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class SensitiveWorkRowLedgerTest {
    @get:Rule val compose = createComposeRule()

    private fun show(
        obscured: Boolean = false,
        bookmark: LedgerBookmark? = null,
        fandoms: List<String> = listOf("Doctor Who (2005)", "Torchwood"),
        onReveal: () -> Unit = {},
        onSearch: (SearchSubjectField, String) -> Unit = { _, _ -> }
    ) = compose.setContent {
        KudosTheme(KudosThemeMode.Light) {
            SensitiveWorkRow(
                id = "1", title = "Sodium Lights", author = "nine_of_wands",
                fandoms = fandoms, summary = "A city that never sleeps.",
                discoveryTags = emptyList(), relationships = listOf("Rose Tyler/Tenth Doctor"),
                warnings = listOf("No Archive Warnings Apply"), categories = listOf("F/M"),
                rating = "Teen And Up Audiences", isComplete = true, wordCount = 1200, chapters = "1/1",
                kudos = 3, language = "English", showsZeroStats = false, obscured = obscured,
                ledger = true, dateText = "09 Jul 2026", bookmark = bookmark,
                onClick = {}, onReveal = onReveal, onTagSearch = onSearch
            )
        }
    }

    @Test fun theFandomIsAKickerTheFiguresAreWordsAndTheTagsUnfold() {
        var searched: Pair<SearchSubjectField, String>? = null
        show(onSearch = { field, tag -> searched = field to tag })

        compose.onNodeWithText("DOCTOR WHO").assertExists()
        compose.onNodeWithText("English  ·  1,200 words  ·  1/1  ·  3 kudos").assertExists()
        compose.onNodeWithContentDescription("Updated 09 Jul 2026").assertExists()
        // No row of word chips: the tray of four symbols says them.
        compose.onAllNodesWithText("Teen").assertCountEquals(0)
        compose.onAllNodesWithText("Relationships").assertCountEquals(0)

        compose.onNodeWithContentDescription("Show more").performSemanticsAction(SemanticsActions.OnClick)
        // The second fandom is counted on the kicker until the card is open, then listed.
        listOf("Fandoms", "Torchwood", "Archive Warnings", "Relationships", "Rose Tyler/Tenth Doctor")
            .forEach { compose.onNodeWithText(it).assertExists() }
        compose.onNodeWithContentDescription("Show less").assertExists()

        // The kicker searches the fandom AO3 names, not the shortened title drawn.
        compose.onNodeWithContentDescription("Fandom: Doctor Who (2005)")
            .performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(SearchSubjectField.FANDOM to "Doctor Who (2005)", searched)
    }

    @Test fun aBlurredLedgerRowOnlyReveals() {
        var revealed = 0
        var searched = 0
        show(obscured = true, onReveal = { revealed++ }, onSearch = { _, _ -> searched++ })
        compose.onAllNodesWithText("Sodium Lights", substring = true).assertCountEquals(0)
        // Tap across the top, where the kicker and the glyph that unfolds the card are drawn.
        val taps = 10
        compose.onNodeWithContentDescription("Hidden mature work. Activate to reveal.").performTouchInput {
            repeat(taps) { i -> click(Offset(width * (i + 0.5f) / taps, 24f)) }
        }
        assertEquals(taps, revealed)
        assertEquals(0, searched)
    }

    @Test fun aPrivateBookmarkSaysSoWhenItsWorkNamesNoFandom() {
        show(bookmark = LedgerBookmark(listOf("Private"), "") {}, fandoms = emptyList())
        compose.onNodeWithText("PRIVATE").assertExists()
    }

    @Test fun aBookmarkIsOneCardWithItsNoteWhereTheSummaryWouldBe() {
        show(bookmark = LedgerBookmark(listOf("Rec"), "07 Jul 2026") { androidx.compose.material3.Text("Reread the ending.") })

        compose.onNodeWithText("REC").assertExists()
        compose.onNodeWithText("Reread the ending.").assertExists()
        // The bookmark's note stands where the work's summary would, and its date closes the line.
        compose.onAllNodesWithText("A city that never sleeps.").assertCountEquals(0)
        compose.onNodeWithContentDescription("Bookmarked 07 Jul 2026").assertExists()
        compose.onAllNodesWithText("09 Jul 2026").assertCountEquals(0)
        // Language, words and chapters only: the kudos are the work's, not the bookmark's.
        compose.onNodeWithText("English  ·  1,200 words  ·  1/1").assertExists()
        // Nothing is folded away on a bookmark's card.
        compose.onAllNodesWithText("Show more").assertCountEquals(0)
    }

    @Test fun unfoldControlSitsAtTheFootOfLedgerCard() {
        show()
        val titleBounds = compose.onNodeWithText("Sodium Lights").fetchSemanticsNode().boundsInRoot
        val unfoldBounds = compose.onNodeWithContentDescription("Show more").fetchSemanticsNode().boundsInRoot
        assertTrue(
            "Ledger card unfold control top (${unfoldBounds.top}) should be below title bottom (${titleBounds.bottom})",
            unfoldBounds.top >= titleBounds.bottom
        )
    }

    @Test fun unfoldControlSitsAtTheFootOfDetailedCard() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                SensitiveWorkRow(
                    id = "2", title = "Detailed Sodium Lights", author = "nine_of_wands",
                    fandoms = listOf("Doctor Who (2005)"), summary = "A city that never sleeps with long details.",
                    discoveryTags = listOf("Rose Tyler/Tenth Doctor"), relationships = emptyList(),
                    warnings = listOf("No Archive Warnings Apply"), categories = listOf("F/M"),
                    rating = "Teen And Up Audiences", isComplete = true, wordCount = 1200, chapters = "1/1",
                    kudos = 3, language = "English", showsZeroStats = false, obscured = false,
                    ledger = false, dateText = "09 Jul 2026",
                    onClick = {}
                )
            }
        }
        val titleBounds = compose.onNodeWithText("Detailed Sodium Lights").fetchSemanticsNode().boundsInRoot
        val unfoldBounds = compose.onNodeWithContentDescription("Show more").fetchSemanticsNode().boundsInRoot
        assertTrue(
            "Detailed card unfold control top (${unfoldBounds.top}) should be below title bottom (${titleBounds.bottom})",
            unfoldBounds.top >= titleBounds.bottom
        )
    }
}
