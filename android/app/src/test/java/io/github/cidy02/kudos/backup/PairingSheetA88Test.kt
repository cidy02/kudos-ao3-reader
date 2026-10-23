package io.github.cidy02.kudos.backup

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import java.io.File
import java.nio.file.Files
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The pairing sheet beside iOS's grouped form (`Settings/PairingSheet.swift`, `pairingForm`; A88b). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1200dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PairingSheetA88Test {
    @get:Rule val compose = createComposeRule()
    private val settingsScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var view: View

    @After fun tearDown() {
        settingsScope.cancel()
        TombstoneSigning.resetForTests()
    }

    private fun show() {
        val dir = Files.createTempDirectory("kudos-pairing-sheet").toFile()
        val store = TombstoneTrustStore(SettingsRepository(PreferenceDataStoreFactory.create(
            scope = settingsScope, produceFile = { File(dir, "settings.preferences_pb") })))
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            view = LocalView.current
            // The sheet's own ground, as `PairingBottomSheet` gives it.
            Box(Modifier.fillMaxSize().background(LocalKudosTokens.current.background)) {
                PairingSheetContent(store, onDismiss = {}, onTrusted = {})
            }
        } }
    }
    private fun snapshot(): Bitmap {
        lateinit var bitmap: Bitmap
        compose.runOnIdle {
            bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
        }
        return bitmap
    }
    private fun Bitmap.at(x: Float, y: Float) = Color(getPixel(x.toInt(), y.toInt()))
    private fun distance(a: Color, b: Color) = maxOf(abs(a.red - b.red), abs(a.green - b.green), abs(a.blue - b.blue))

    /** iOS: Show My QR Code and Copy My Key are icon rows in one card on the card surface. */
    @Test fun theTwoActionsAreOneCardOfIconRows() {
        show()
        val show = compose.onNodeWithText("Show My QR Code", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val copy = compose.onNodeWithText("Copy My Key", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val image = snapshot()
        val card = ReaderTheme.Light.cardSurface
        // Between the two rows, left of the hairline's inset: the card, not the sheet's ground.
        assertTrue("one card", ((show.bottom + 1).toInt() until copy.top.toInt()).all {
            distance(image.at(show.left - 40, it.toFloat()), card) < 0.012f
        })
        assertTrue("an icon before Copy My Key",
            (8 until copy.left.toInt() - 4).any { distance(image.at(it.toFloat(), copy.center.y), card) > 0.2f })
    }

    /** iOS's DisclosureGroup: Advanced opens its field in place and says whether it's open. */
    @Test fun advancedOpensInPlaceAndSaysSo() {
        show()
        fun state(value: String) = SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, value)
        val advanced = compose.onNodeWithText("Advanced: paste a key manually")
        advanced.assert(state("Collapsed"))
        compose.onNodeWithText("Other device's key").assertDoesNotExist()
        advanced.performClick()
        advanced.assert(state("Expanded"))
        compose.onNodeWithText("Other device's key").assertExists()
        compose.onNodeWithText("I got this key from my other device").assertExists()
        advanced.performClick()
        advanced.assert(state("Collapsed"))
        compose.onNodeWithText("Other device's key").assertDoesNotExist()
    }
}
