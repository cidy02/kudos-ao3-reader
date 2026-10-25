package io.github.cidy02.kudos.library

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h900dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Parity3heSheetsTest {
    @get:Rule val compose = createComposeRule()

    @Test fun bulkTagsAreFlatAndUseTheAppPaletteEvenOverAColouredPage() {
        var mode by mutableStateOf(KudosThemeMode.Dark)
        lateinit var view: View
        lateinit var tokens: KudosTokens
        lateinit var app: SubjectPalette
        compose.setContent { KudosTheme(mode) {
            view = LocalView.current
            tokens = LocalKudosTokens.current
            app = LocalAppPalette.current
            val purple = SubjectPalette.fromColor(Color(0xFF733AB5), tokens.theme)
            SubjectPaletteTheme(purple) {
                SharedTagContent("Tag", "Your changes apply to all 2 selected works.", "No tags", "work",
                    purple, "selection", { SharedTags(emptyList(), emptyMap()) }, {}, {}, SharedTagVariant.BulkWork)
            }
        } }
        for (theme in listOf(KudosThemeMode.Dark, KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText("Done", useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(app.theme.accentInk(app.tint), layouts.single().layoutInput.style.color)
            lateinit var bitmap: Bitmap
            compose.runOnIdle {
                bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                view.draw(Canvas(bitmap))
            }
            if (theme == KudosThemeMode.Dark) assertEquals(Color(red = 0.086f, green = 0.086f, blue = 0.105f), tokens.formSheetGround)
            // iOS's Light form sheet is the grouped (242,242,247), not the white of a system sheet.
            else assertEquals(tokens.background, tokens.formSheetGround)
            val ground = Color(bitmap.getPixel(2, bitmap.height / 2))
            assertTrue("Flat $theme ground: $ground", maxOf(abs(ground.red - tokens.formSheetGround.red),
                abs(ground.green - tokens.formSheetGround.green), abs(ground.blue - tokens.formSheetGround.blue)) < 0.012f)
        }
    }
    @Test fun queueTagsKeepTheirWashAndDoneInkInEveryTheme() {
        var mode by mutableStateOf(KudosThemeMode.Dark)
        lateinit var view: View
        lateinit var palette: SubjectPalette
        compose.setContent { KudosTheme(mode) {
            view = LocalView.current
            palette = SubjectPalette.fromColor(Color(0xFF733AB5), LocalKudosTokens.current.theme)
            SharedTagContent("Tags", "Footnote", "No tags", "queue", palette, listOf("queue"),
                { SharedTags(emptyList(), emptyMap()) }, {}, {}, SharedTagVariant.Queue)
        } }
        for (theme in listOf(KudosThemeMode.Dark, KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText("Done", useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(palette.theme.accentInk(palette.tint), layouts.single().layoutInput.style.color)
            lateinit var bitmap: Bitmap
            compose.runOnIdle {
                bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                view.draw(Canvas(bitmap))
            }
            val expected = palette.washStops.first().color.compositeOver(palette.theme.cardBackdrop)
            val actual = Color(bitmap.getPixel(2, 2))
            assertTrue("Queue wash in $theme: $actual", maxOf(abs(actual.red - expected.red),
                abs(actual.green - expected.green), abs(actual.blue - expected.blue)) < 0.012f)
            bitmap.recycle()
        }
    }

    @Test fun reorderAndCollectionEditorHeadersTakeTheSheetsColour() {
        var mode by mutableStateOf(KudosThemeMode.Light)
        var editor by mutableStateOf(false)
        lateinit var palette: SubjectPalette
        compose.setContent { KudosTheme(mode) {
            val tokens = LocalKudosTokens.current
            palette = SubjectPalette.fromColor(Color(0xFF167343), tokens.theme)
            if (editor) SubjectPaletteTheme(palette) {
                CollectionEditorHeader("New collection", false, false, true, {}, {})
            } else CollectionReorderContent(
                io.github.cidy02.kudos.core.model.WorkCollection(name = "Green", colorHex = "#167343"),
                emptyList(), false, {}, {}, { _, _ -> })
        } }
        for (editing in listOf(false, true)) {
            compose.runOnIdle { editor = editing }
            for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
                compose.runOnIdle { mode = theme }
                compose.waitForIdle()
                val expected = palette.theme.accentInk(palette.tint)
                for (label in listOf("Cancel", if (editing) "Create" else "Done")) {
                    val layouts = mutableListOf<TextLayoutResult>()
                    compose.onNodeWithText(label, useUnmergedTree = true)
                        .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
                    assertEquals("$label in $theme", expected, layouts.single().layoutInput.style.color)
                }
            }
        }
    }

}
