package io.github.cidy02.kudos.settings

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h900dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CollectionTaglineLayoutTest {
    @get:Rule val compose = createComposeRule()

    @Test fun theDemoTaglineUsesTheSpaceAfterItsLabelWithoutClippingItsText() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                Box(Modifier.fillMaxWidth().padding(horizontal = 22.dp)) {
                    SubjectTextFieldRow("Tagline", "A fictional exchange of warm letters.", "Optional", {},
                        fillsRemainingWidth = true)
                }
            }
        }
        val field = compose.onNodeWithContentDescription("Tagline")
        val layouts = mutableListOf<TextLayoutResult>()
        field.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        val viewport = field.fetchSemanticsNode().boundsInRoot
        assertTrue("The single-line field must fit this demo tagline at the default text size",
            viewport.width + 1f >= layouts.single().getLineRight(0))
    }
}
