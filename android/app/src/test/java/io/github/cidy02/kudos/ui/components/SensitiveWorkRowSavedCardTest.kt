package io.github.cidy02.kudos.ui.components

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.detail.LocalOpenAuthor
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1600dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SensitiveWorkRowSavedCardTest {
    @get:Rule val compose = createComposeRule()
    private var theme by mutableStateOf(KudosThemeMode.Light)
    private var verified by mutableStateOf(false)
    private var named by mutableStateOf(true)
    private var tagged by mutableStateOf(false)
    private var opened = ""
    private var secondary = Color.Unspecified
    private var cardFill = Color.Unspecified
    private var palette: SubjectPalette? = null
    private val work = SavedWork(id = "saved", title = "A saved work", author = "A writer",
        summary = "A short summary.", wordCount = 1200, chapters = "1/1", comments = 0, bookmarks = 0,
        workFandoms = listOf("Doctor Who"))

    private fun show() = compose.setContent {
        KudosTheme(theme) {
            val tokens = LocalKudosTokens.current
            secondary = tokens.secondaryInk
            cardFill = tokens.cardFill
            palette = SubjectPalette.fromHue(HomeFacts.workHue(work.workFandoms, work.title), tokens.theme)
            CompositionLocalProvider(LocalOpenAuthor provides { opened = it }) {
                SensitiveWorkRow(
                    work = work.copy(author = if (named) work.author else "",
                        workFreeforms = if (tagged) listOf("Found Family") else emptyList(),
                        authorIdentitiesJSON = if (verified)
                            """[{"username":"Writer","displayName":"A writer","kind":"registered"}]""" else ""),
                    onOpenWork = {}, modifier = Modifier.testTag("saved-card")
                )
            }
        }
    }

    @Test fun savedBylineHasSecondaryByAndUnlinkedNamesAndKeepsVerifiedNavigation() {
        show()
        for (text in listOf("by", "A writer")) {
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(text, useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(secondary, layouts.single().layoutInput.style.color)
        }
        compose.runOnIdle { verified = true }
        compose.onNodeWithContentDescription("Author: A writer").performClick()
        assertEquals("Writer", opened)
        compose.runOnIdle { verified = false; named = false }
        compose.onNodeWithText("by Anonymous").assertExists()
    }

    @Test fun aTaggedSavedCardUnfoldsBesideTheTitleAndKeepsItsTagsAccessible() {
        tagged = true
        show()
        val title = compose.onNodeWithText("A saved work", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val unfold = compose.onNodeWithContentDescription("Show more").fetchSemanticsNode().boundsInRoot
        assertTrue(unfold.top < title.bottom && unfold.bottom > title.top)
        compose.onNodeWithContentDescription("Show more").performClick()
        compose.onNodeWithText("Found Family").assertExists()
    }

    @Test fun knownZerosKeepTheirPlacesButAShortUntaggedCardDoesNotUnfold() {
        show()
        compose.onNodeWithContentDescription("0 comments").assertExists()
        compose.onNodeWithContentDescription("0 bookmarks").assertExists()
        compose.onNodeWithContentDescription("Show more").assertDoesNotExist()
    }
}
