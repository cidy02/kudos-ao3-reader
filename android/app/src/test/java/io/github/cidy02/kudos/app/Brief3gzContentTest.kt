package io.github.cidy02.kudos.app

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.comments.*
import io.github.cidy02.kudos.core.model.*
import io.github.cidy02.kudos.library.*
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterRef
import io.github.cidy02.kudos.settings.PronunciationEmptyState
import io.github.cidy02.kudos.ui.components.PageJumpContent
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Hosts the production content, never a dialog window. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Brief3gzContentTest {
    @get:Rule val compose = createComposeRule()
    private fun show(scale: Float = 1f, content: @Composable () -> Unit) {
        compose.setContent { KudosTheme(KudosThemeMode.Light) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, scale)) { content() }
        } }
    }

    @Test fun queueTagsAreFullRowsAndBothFootnotesUseThePageGutter() {
        show { QueueTagManagerContent(ReadingQueue(name = "Read"), LocalKudosTokens.current.scopePalette,
            listOf(Tag(id = "used", name = "Used"), Tag(id = "one", name = "Long fic"), Tag(id = "two", name = "Rereads")),
            mapOf("used" to 3), false, 5, "", {}, {}, { _, _ -> }) }
        listOf("Used", "Long fic", "Rereads").forEach { label ->
            compose.onNode(hasText(label) and hasClickAction()).assertHeightIsAtLeast(44.dp)
        }
        val gutter = compose.onNodeWithText("UNUSED").fetchSemanticsNode().boundsInRoot.left
        listOf("Unused tags stay here until you remove them. You can apply them later.",
            "A tag you use here is the same tag on your works.").forEach {
            val note = compose.onNodeWithText(it).performScrollTo().fetchSemanticsNode().boundsInRoot
            assertTrue("Footnote starts inside the page gutter", note.left >= gutter)
        }
    }

    @Test fun queueNewTagIsAPlainFieldWithAnAddActionAndKeyboardSubmission() {
        var draft by mutableStateOf("")
        val submitted = mutableListOf<String>()
        show { QueueTagManagerContent(ReadingQueue(name = "Read"), LocalKudosTokens.current.scopePalette,
            emptyList(), emptyMap(), false, 0, draft, { draft = it }, { submitted += draft; draft = "" }, { _, _ -> }) }
        val input = compose.onNodeWithContentDescription("New tag")
        // Basic text has the text's height. An outlined Material field forces at least 56dp.
        val height = input.fetchSemanticsNode().boundsInRoot.height
        assertTrue("No outlined field minimum height", height > 0f && height <= with(compose.density) { 32.dp.toPx() })
        compose.onNodeWithText("Add").assertIsNotEnabled()
        input.performTextInput("Comfort")
        compose.onNodeWithText("Add").performClick()
        input.performTextInput("Rereads")
        input.performImeAction()
        compose.runOnIdle { assertEquals(listOf("Comfort", "Rereads"), submitted) }
    }

    @Test fun newCollectionTitleWrapsAtScaleTwoAndBothActionsStayReachable() {
        var cancelled = false
        var saved = false
        show(2f) { CollectionEditorHeader("New collection", false, false, true, { cancelled = true }, { saved = true }) }
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("New collection").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        val layout = layouts.single()
        assertTrue("Title wraps", layout.lineCount > 1)
        assertFalse(layout.hasVisualOverflow)
        repeat(layout.lineCount) { assertFalse(layout.isLineEllipsized(it)) }
        compose.onNodeWithText("Cancel").assertIsDisplayed().performClick()
        compose.onNodeWithText("Create").assertIsDisplayed().performClick()
        compose.runOnIdle { assertTrue(cancelled); assertTrue(saved) }
    }

    @Test fun formattingDoneDismissesWithoutEditingAndTilesStayOpen() {
        var value by mutableStateOf(TextFieldValue("Words"))
        var dismissed = false
        show(2f) { CommentFormattingContent(value, { value = it }, { dismissed = true }) }
        compose.onNodeWithText("Bold").performClick()
        compose.runOnIdle { assertFalse(dismissed); assertTrue(value.text.contains("<strong>")) }
        val beforeDone = value
        compose.onNodeWithText("Spoiler").performScrollTo()
        compose.onNodeWithText("Done").assertIsDisplayed().performClick()
        compose.runOnIdle { assertTrue(dismissed); assertEquals(beforeDone, value) }
    }

    @Test fun chapterChoicesShareOnePanelWithSeparatorsAndKeepSelectionAndCounts() {
        val chapters = (1..3).map { AO3ChapterRef(it.toLong(), it, "Chapter $it") }
        var chosen: AO3ChapterRef? = null
        var all = false
        show { ChapterPickerContent(chapters, selectedChapter = chapters[0], isScopeAll = false,
            totalComments = 1234, onSelectAll = { all = true }, onSelectChapter = { chosen = it }) }
        compose.onAllNodesWithTag("Chapter choices").assertCountEquals(1)
        compose.onAllNodesWithTag("Chapter separator", useUnmergedTree = true).assertCountEquals(3)
        listOf("All Comments", "Chapter 1", "Chapter 2", "Chapter 3").forEach {
            compose.onNode(hasText(it, substring = true) and hasClickAction() and
                hasAnyAncestor(hasTestTag("Chapter choices"))).assertExists()
        }
        val allBounds = compose.onNodeWithText("All Comments").fetchSemanticsNode().boundsInRoot
        val chapterBounds = compose.onNode(hasText("Chapter 1", substring = true) and hasClickAction()).fetchSemanticsNode().boundsInRoot
        assertTrue("Only a separator between rows", chapterBounds.top - allBounds.bottom <= with(compose.density) { 1.dp.toPx() })
        compose.onNode(hasText("Chapter 1", substring = true) and hasClickAction())
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Selected, true))
        compose.onNodeWithText(java.text.NumberFormat.getIntegerInstance().format(1234)).assertExists()
        compose.onNodeWithText("Chapter 2", substring = true).performClick()
        compose.onNodeWithText("All Comments").performClick()
        compose.runOnIdle { assertEquals(chapters[1], chosen); assertTrue(all) }
    }

    @Test fun pronunciationEmptyCardShowsASpeechBubbleAAboveTheTitle() {
        show { PronunciationEmptyState() }
        compose.onNode(hasText("No corrections yet") and hasAnyAncestor(hasTestTag("Pronunciation empty card"))).assertExists()
        compose.onNode(hasText("A") and hasAnyAncestor(hasTestTag("Pronunciation speech bubble"))).assertExists()
        compose.onNodeWithTag("Pronunciation speech outline", useUnmergedTree = true).assertExists()
        val icon = compose.onNodeWithTag("Pronunciation speech bubble").fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithText("No corrections yet").fetchSemanticsNode().boundsInRoot
        assertTrue("Icon is above the title", icon.bottom <= title.top)
    }

    @Test fun collectionHandlesDragAndAccessibilityMovesChangeTheDraftBeforeDone() {
        var ordered by mutableStateOf(listOf(SavedWork(id = "a", title = "Alpha", author = "A"),
            SavedWork(id = "b", title = "Beta", author = "B"), SavedWork(id = "c", title = "Gamma", author = "C")))
        var saved: List<String>? = null
        show { CollectionReorderContent(WorkCollection(name = "Reading"), ordered, false, {},
            onSave = { saved = ordered.map { it.id } }, onMove = { from, to ->
                if (from in ordered.indices && to in ordered.indices) ordered = ordered.toMutableList().apply { add(to, removeAt(from)) }
            }) }
        compose.onAllNodesWithTag("Collection reorder handle", useUnmergedTree = true).assertCountEquals(3)
        compose.onNodeWithContentDescription("Move up").assertDoesNotExist()
        compose.onNodeWithContentDescription("Move down").assertDoesNotExist()
        val alpha = compose.onNodeWithContentDescription("1. Alpha, A")
        val beta = compose.onNodeWithContentDescription("2. Beta, B").fetchSemanticsNode().boundsInRoot
        val start = alpha.fetchSemanticsNode().boundsInRoot
        compose.onRoot().performTouchInput {
            down(start.center)
            advanceEventTime(1000L)
            moveTo(beta.center)
            up()
        }
        compose.runOnIdle { assertEquals(listOf("b", "a", "c"), ordered.map { it.id }); assertNull(saved) }
        val actions = compose.onNodeWithContentDescription("2. Alpha, A").fetchSemanticsNode().config[SemanticsActions.CustomActions]
        compose.runOnIdle { assertTrue(actions.single { it.label == "Move down" }.action()) }
        compose.runOnIdle { assertEquals(listOf("b", "c", "a"), ordered.map { it.id }); assertNull(saved) }
        compose.onNodeWithText("Done").performClick()
        compose.runOnIdle { assertEquals(listOf("b", "c", "a"), saved) }
    }

    // Drawing the Compose view into a bitmap works in Robolectric's native graphics mode and
    // avoids PixelCopy/captureToImage and modal windows. Coordinates are in that view's root.
    private fun pixel(view: View, point: Offset): Color {
        var result = Color.Unspecified
        compose.runOnIdle {
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
            result = Color(bitmap.getPixel(point.x.toInt(), point.y.toInt()))
            bitmap.recycle()
        }
        return result
    }
    private fun assertColor(expected: Color, actual: Color) {
        assertEquals(expected.red, actual.red, 0.012f)
        assertEquals(expected.green, actual.green, 0.012f)
        assertEquals(expected.blue, actual.blue, 0.012f)
        assertEquals(expected.alpha, actual.alpha, 0.012f)
    }

    @Test fun presetSwatchesUseIosThemeOpacityAndCustomColoursStayExact() {
        var mode by mutableStateOf(KudosThemeMode.Light)
        var hue by mutableStateOf<Double?>(0.7194)
        var hex by mutableStateOf<String?>("#123456")
        lateinit var view: View
        compose.setContent { KudosTheme(mode) {
            view = LocalView.current
            Box(Modifier.fillMaxSize().background(LocalKudosTokens.current.background)) {
                SubjectHueSwatchRow(hue, hex, { h, c -> hue = h; hex = c })
            }
        } }
        val cases = listOf(
            KudosThemeMode.Light to floatArrayOf(0.42f, 0.75f, 0.26f),
            KudosThemeMode.Sepia to floatArrayOf(0.34f, 0.70f, 0.22f),
            KudosThemeMode.Dark to floatArrayOf(0.38f, 0.78f, 0.30f),
            KudosThemeMode.Oled to floatArrayOf(0.38f, 0.78f, 0.30f))
        for ((theme, hsv) in cases) {
            compose.runOnIdle { mode = theme }
            val background = when (theme) {
                KudosThemeMode.Light -> ReaderTheme.Light.cardBackdrop
                KudosThemeMode.Sepia -> ReaderTheme.Sepia.cardBackdrop
                KudosThemeMode.Dark -> ReaderTheme.Dark.cardBackdrop
                else -> ReaderTheme.Oled.cardBackdrop
            }
            for ((label, value) in listOf("Violet" to 0.7194, "Mint" to 0.4424, "Rose" to 0.0, "Amber" to 0.0663, "Blue" to 0.5395)) {
                val centre = compose.onNodeWithContentDescription(label).fetchSemanticsNode().boundsInRoot.center
                assertColor(Color.hsv((value * 360).toFloat(), hsv[0], hsv[1], hsv[2]).compositeOver(background), pixel(view, centre))
            }
            val custom = compose.onNodeWithContentDescription("Custom colour").fetchSemanticsNode().boundsInRoot.center
            assertColor(Color(0xFF123456), pixel(view, custom))
        }
        compose.onNodeWithContentDescription("Mint").performClick()
        compose.runOnIdle { assertEquals(0.4424, hue!!, 0.0001); assertNull(hex) }
    }

    @Test fun nearbyTilesUseTheScopePaletteAndOledHasAnUnselectedFill() {
        var mode by mutableStateOf(KudosThemeMode.Oled)
        lateinit var view: View
        lateinit var tokens: KudosTokens
        var committed: Int? = null
        compose.setContent { KudosTheme(mode) {
            val palette = SubjectPalette.fromHue(0.0663, LocalKudosTokens.current.theme)
            SubjectPaletteTheme(palette) {
                tokens = LocalKudosTokens.current
                view = LocalView.current
                Box(Modifier.fillMaxSize().background(tokens.background)) { PageJumpContent(2, 10, { committed = it }, {}) }
            }
        } }
        for (theme in listOf(KudosThemeMode.Oled, KudosThemeMode.Dark, KudosThemeMode.Light, KudosThemeMode.Sepia)) {
            compose.runOnIdle { mode = theme }
            val selected = compose.onNodeWithContentDescription("Page 2").fetchSemanticsNode().boundsInRoot
            val ordinary = compose.onNodeWithContentDescription("Page 3").fetchSemanticsNode().boundsInRoot
            assertColor(tokens.scopePalette.controlChipFill.compositeOver(tokens.background), pixel(view, Offset(selected.center.x, selected.top + 8f)))
            assertColor(tokens.glassFill(0.08).compositeOver(tokens.background), pixel(view, Offset(ordinary.center.x, ordinary.top + 8f)))
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNode(hasText("2") and hasAnyAncestor(hasContentDescription("Page 2")), useUnmergedTree = true).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(tokens.scopePalette.controlInk, layouts.single().layoutInput.style.color)
        }
        compose.onNodeWithContentDescription("Page 3").performClick()
        compose.runOnIdle { assertNull(committed) }
        compose.onNodeWithContentDescription("Go to page 3").performClick()
        compose.runOnIdle { assertEquals(3, committed) }
    }
}
