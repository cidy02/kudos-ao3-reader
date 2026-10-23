package io.github.cidy02.kudos.browse

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import io.github.cidy02.kudos.network.ao3.browse.AO3Fandom
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs

/** What A88 left on the fandom list beside the iPhone's (`Features/Search/FandomListView.swift`, `FandomFamilyRows.swift`). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h900dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class FandomListA88Test {
    @get:Rule val compose = createComposeRule()
    private lateinit var view: View

    private fun show(content: @Composable () -> Unit) {
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            view = LocalView.current
            Box(Modifier.fillMaxSize().background(LocalKudosTokens.current.background)) { content() }
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

    /** iOS draws each fandom with `.cardRow()` on the card surface (white in Light), not a glass panel. */
    @Test fun aFandomIsACardOnTheCardSurface() {
        val fandom = FandomFamily.ungrouped(listOf(AO3Fandom("Supernatural", 312_445))).single()
        show { FandomFamilyRow(fandom, FandomFamilySort.FamilyTotal, FandomLibraryIndex.empty,
            LocalKudosTokens.current.scopePalette, {}, {}) }
        val title = compose.onNodeWithText("Supernatural", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val ground = snapshot().at(title.left - 6, title.center.y)
        assertTrue("card ground $ground", distance(ReaderTheme.Light.cardSurface, ground) < 0.012f)
    }

    /** iOS: Group variants is a tinted rect with `square.stack` while on; the solid pills are the two sorts. */
    @Test fun groupVariantsIsATintedChipWithItsIconNotASortPill() {
        show { FandomListSortRail(FandomFamilySort.FamilyTotal, true, LocalKudosTokens.current.scopePalette, {}, {}) }
        val chip = compose.onNode(isToggleable()).fetchSemanticsNode().boundsInRoot
        val text = compose.onNodeWithText("Group variants", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val sort = compose.onNodeWithText("Most works", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val image = snapshot()
        val ground = image.at(chip.left + 3, chip.center.y)
        assertTrue("not the selected sort's fill", distance(image.at(sort.left - 4, sort.center.y), ground) > 0.1f)
        assertTrue("an icon before the words",
            (chip.left.toInt() + 4 until text.left.toInt() - 1).any { distance(image.at(it.toFloat(), text.center.y), ground) > 0.2f })
    }
}
