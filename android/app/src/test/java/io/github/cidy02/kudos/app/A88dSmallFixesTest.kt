package io.github.cidy02.kudos.app

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.text.TextLayoutResult
import io.github.cidy02.kudos.account.PreferenceHelpContent
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpContent
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpEntry
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpRef
import io.github.cidy02.kudos.network.ao3.writing.AO3BulkEditChanges
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.writing.BulkOptionsScreen
import io.github.cidy02.kudos.writing.BulkPicker
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** A88d's two small differences beside the iPhone (3ha's re-shot screens). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h900dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class A88dSmallFixesTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var view: View
    private lateinit var tokens: KudosTokens

    private fun show(ground: (KudosTokens) -> Color = { it.background }, content: @Composable () -> Unit) {
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            view = LocalView.current
            tokens = LocalKudosTokens.current
            Box(Modifier.fillMaxSize().background(ground(LocalKudosTokens.current))) { content() }
        } }
    }
    private fun textColor(node: SemanticsNodeInteraction): Color {
        val layouts = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single().layoutInput.style.color
    }

    /** The iPhone's Add is pale until a name is typed; Android's forced accent made it look ready. */
    @Test fun bulkNamesAddLooksDisabledUntilANameIsTyped() {
        var changes by mutableStateOf(AO3BulkEditChanges(workIDs = emptyList()))
        show { BulkOptionsScreen(BulkPicker("Add to collections", "collections", "names"), emptyList(), changes,
            { changes = it(changes) }, {}) }
        val add = compose.onNodeWithText("Add", useUnmergedTree = true)
        compose.onNodeWithText("Add").assertIsNotEnabled()
        assertNotEquals(tokens.scopePalette.controlInk, textColor(add))
        compose.onNodeWithContentDescription("Collection name").performTextInput("Winter")
        compose.onNodeWithText("Add").assertIsEnabled()
        compose.onNodeWithText("Add").performClick()
        compose.runOnIdle { assertEquals(listOf("Winter"), changes.collectionsToAdd) }
    }

    /** iOS's help sheet: a ✓ beside the title that closes it, and its topics as cards on the card surface. */
    @Test fun helpHasDoneBesideItsTitleAndItsTopicsAreCards() {
        var done = 0
        show(ground = { it.background }) {
            PreferenceHelpContent(AO3PreferenceHelpRef("Help", "https://archiveofourown.org/help/preferences"),
                AO3Result.Success(AO3PreferenceHelpContent("Privacy Preferences",
                    listOf(AO3PreferenceHelpEntry("Topic", "Instructions")), "Footer", "")),
                {}, {}, onDone = { done++ })
        }
        compose.onNodeWithContentDescription("Done").performClick()
        compose.runOnIdle { assertEquals(1, done) }
        val topic = compose.onNodeWithText("Topic", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        lateinit var image: Bitmap
        compose.runOnIdle {
            image = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(image))
        }
        val card = Color(image.getPixel((topic.left - 6).toInt(), topic.center.y.toInt()))
        val surface = ReaderTheme.Light.cardSurface
        assertTrue("card $card", maxOf(abs(card.red - surface.red), abs(card.green - surface.green),
            abs(card.blue - surface.blue)) < 0.012f)
    }
}
