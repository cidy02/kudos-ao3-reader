package io.github.cidy02.kudos.reader

import android.app.Application
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import io.github.cidy02.kudos.reader.readium.ReadiumTocAdapter
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Brief 3dl: the reader's Contents sheet has what its sibling sheets and iOS's have. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class ReaderContentsSheetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun theSheetHasATitleADoneAndEachChaptersStart() {
        var done = 0
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                ReaderContentsSheet(
                    entries = listOf(ReaderTocEntry("Chapter 1: The Arcade", "OEBPS/ch1.xhtml"),
                        ReaderTocEntry("Chapter 2: Nine Minutes", "OEBPS/ch2.xhtml#start")),
                    bookmarks = emptyList(), highlights = emptyList(),
                    onSelectEntry = {}, onSelectAnnotation = {}, onDeleteAnnotation = {},
                    onDone = { done++ },
                    startPercent = { mapOf("ch1.xhtml" to 0, "ch2.xhtml" to 50)[ReaderSectionBuilder.hrefKey(it.href)] }
                )
            }
        }
        compose.onNodeWithText("0%").assertExists()
        compose.onNodeWithText("50%").assertExists()
        compose.onNodeWithContentDescription("Done").performClick()
        assertEquals(1, done)
        compose.onNodeWithText("Bookmarks").performClick()
        compose.onNodeWithText("No Bookmarks Yet").assertExists()
    }

    @Test fun aFileStartsWhereItsFirstPositionDoes() {
        assertEquals(
            mapOf("ch1.xhtml" to 0, "ch2.xhtml" to 50),
            ReadiumTocAdapter.startPercents(listOf(
                "OEBPS/ch1.xhtml" to 0.0, "OEBPS/ch1.xhtml" to 0.25,
                "OEBPS/ch2.xhtml" to 0.496, "OEBPS/ch2.xhtml" to 0.75, "OEBPS/nav.xhtml" to null
            ))
        )
    }
}
