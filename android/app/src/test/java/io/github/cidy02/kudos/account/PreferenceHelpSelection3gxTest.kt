package io.github.cidy02.kudos.account

import org.junit.Ignore
import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalTextToolbar
import androidx.compose.ui.platform.TextToolbar
import androidx.compose.ui.platform.TextToolbarStatus
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.preferences.*
import io.github.cidy02.kudos.ui.theme.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PreferenceHelpSelection3gxTest {
    @get:Rule val compose = createComposeRule()

    @Ignore("3gx, held for 3gy: NullPointerException in Surface.destroy (Robolectric graphics)")

    @Test fun helpBodyAndFooterOfferCopyAfterSelection() {
        var copy: (() -> Unit)? = null
        val toolbar = object : TextToolbar {
            override var status = TextToolbarStatus.Hidden
            override fun hide() { status = TextToolbarStatus.Hidden; copy = null }
            override fun showMenu(rect: Rect, onCopyRequested: (() -> Unit)?, onPasteRequested: (() -> Unit)?,
                onCutRequested: (() -> Unit)?, onSelectAllRequested: (() -> Unit)?) {
                status = TextToolbarStatus.Shown
                copy = onCopyRequested
            }
        }
        val body = "These are AO3's preference instructions."
        val footer = "Read more in the Preferences FAQ."
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            CompositionLocalProvider(LocalTextToolbar provides toolbar) {
                PreferenceHelpSheet(AO3PreferenceHelpRef("Help", "https://archiveofourown.org/help/preferences"),
                    AO3Result.Success(AO3PreferenceHelpContent("Help", listOf(AO3PreferenceHelpEntry("Topic", body)), footer, "")),
                    {}, {}, {})
            }
        } }
        compose.onNodeWithText(body).performTouchInput { longClick() }
        compose.runOnIdle { assertNotNull(copy); toolbar.hide() }
        compose.onNodeWithText(footer).performTouchInput { longClick() }
        compose.runOnIdle { assertNotNull(copy) }
    }
}
