package io.github.cidy02.kudos.app

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import io.github.cidy02.kudos.backup.*
import io.github.cidy02.kudos.core.model.*
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.library.*
import io.github.cidy02.kudos.network.ao3.writing.AO3CollectionOffer
import io.github.cidy02.kudos.reader.*
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.speech.KokoroPronunciationStore
import io.github.cidy02.kudos.settings.*
import io.github.cidy02.kudos.ui.components.*
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.theme.*
import io.github.cidy02.kudos.writing.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Real production content in the activity: no dialog windows, accounts, or network clients. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Brief3hbContentTest {
    @get:Rule val compose = createComposeRule()
    @get:Rule val temporary = TemporaryFolder()
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableFloatStateOf(1f)
    private lateinit var view: View
    private lateinit var tokens: KudosTokens
    private val themes = listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)
    private val store = object : DataStore<Preferences> {
        override val data = MutableStateFlow(emptyPreferences())
        override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences =
            transform(data.value).also { data.value = it }
    }
    private val settings = SettingsRepository(store)
    private fun show(content: @Composable () -> Unit) {
        compose.setContent { KudosTheme(mode) {
            view = LocalView.current
            tokens = LocalKudosTokens.current
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, scale)) {
                Box(Modifier.fillMaxSize().background(tokens.background)) { content() }
            }
        } }
    }
    private fun bitmap(): Bitmap {
        lateinit var result: Bitmap
        compose.runOnIdle {
            result = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(result))
        }
        return result
    }
    private fun pixel(point: Offset): Color = bitmap().let {
        val color = Color(it.getPixel(point.x.toInt(), point.y.toInt())); it.recycle(); color
    }
    private fun assertColor(expected: Color, actual: Color) {
        assertEquals(expected.red, actual.red, 0.012f)
        assertEquals(expected.green, actual.green, 0.012f)
        assertEquals(expected.blue, actual.blue, 0.012f)
    }
    private fun textColor(node: SemanticsNodeInteraction): Color {
        val layouts = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single().layoutInput.style.color
    }
    private fun assertCard(label: String, expected: Color? = null) {
        val row = compose.onNodeWithText(label, useUnmergedTree = true).performScrollTo().fetchSemanticsNode().boundsInRoot
        assertColor(expected ?: tokens.cardFill, pixel(Offset(with(compose.density) { 20.dp.toPx() }, row.center.y)))
    }
    private fun assertAccentPixels(node: SemanticsNodeInteraction, expected: Color) {
        val bounds = node.fetchSemanticsNode().boundsInRoot
        val image = bitmap()
        val matches = (bounds.top.toInt() until bounds.bottom.toInt()).sumOf { y ->
            (bounds.left.toInt() until bounds.right.toInt()).count { x ->
                val color = Color(image.getPixel(x, y))
                kotlin.math.abs(color.red - expected.red) < 0.012f &&
                    kotlin.math.abs(color.green - expected.green) < 0.012f &&
                    kotlin.math.abs(color.blue - expected.blue) < 0.012f
            }
        }
        image.recycle()
        assertTrue("Expected the control's actual tint, found $matches pixels", matches > 3)
    }

    private fun checkScrollingField(listTag: String) {
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            val list = compose.onNodeWithTag(listTag)
            list.performScrollToIndex(0)
            val field = compose.onNodeWithTag("Writing pinned field").fetchSemanticsNode().boundsInRoot
            // The page's one wash runs on through the field's row: no edge where it starts or ends
            // (the field's own wash drew a jump of about 0.04 at its top).
            for (edge in listOf(field.top, field.bottom)) {
                assertColor(pixel(Offset(2f, edge - 3f)), pixel(Offset(2f, edge + 3f)))
            }
            list.performScrollToIndex(20)
            // An ordinary row scrolls away; a focused one stays composed in the lazy list, out of view.
            if (compose.onAllNodesWithTag("Writing pinned field").fetchSemanticsNodes().isNotEmpty()) {
                compose.onNodeWithTag("Writing pinned field").assertIsNotDisplayed()
            }
        }
    }
    @Test fun tagsFieldScrollsAwayUnderOneContinuousWash() {
        var values by mutableStateOf(List(150) { "Chosen tag $it" })
        show { WritingTagsEditorScreen(WritingTagKind.Freeform, values, null, null, { values = it }, { values },
            rememberCoroutineScope(), {}) }
        // Typing must not jump past the input now that it is an ordinary row.
        compose.onNodeWithContentDescription("Add a tag").performTextInput("Comfort")
        compose.onNodeWithTag("Writing pinned field").assertIsDisplayed()
        checkScrollingField("Writing tags editor")
    }
    @Test fun collectionsSearchScrollsAwayUnderOneContinuousWash() {
        val model = runBlocking { workFormSetup().model(null).also { it.load(); it.openCollections() } }
        show {
            val state by model.state.collectAsState()
            val form = state.form!!.copy(collections = List(80) { AO3CollectionOffer("collection$it", "Collection $it") })
            WritingAssociationPicker(WorkAssociation.CollectionsGifts, form, model, null, onBack = {})
        }
        checkScrollingField("Writing association picker")
    }
    @Test fun giftRemovePaintsAFilledMinusCircleAndStillRemovesOnlyThatRecipient() {
        val model = runBlocking { workFormSetup().model(null).also { it.load(); it.addGift("Writer"); it.addGift("Other") } }
        show {
            val state by model.state.collectAsState()
            WritingAssociationPicker(WorkAssociation.CollectionsGifts, state.form!!, model, null, onBack = {})
        }
        compose.onNodeWithTag("Writing association picker").performScrollToNode(hasContentDescription("Remove Writer"))
        val icon = compose.onNodeWithContentDescription("Remove Writer", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        // Inside the filled circle above its minus; an X has no painted pixel here.
        assertColor(SubjectPalette.fromHue(0.0, tokens.theme).accent,
            pixel(Offset(icon.center.x, icon.top + with(compose.density) { 4.dp.toPx() })))
        compose.onNodeWithContentDescription("Remove Writer").performClick()
        compose.runOnIdle { assertFalse(model.state.value.form!!.gifts.contains("Writer")); assertTrue(model.state.value.form!!.gifts.contains("Other")) }
    }

    @Test fun displayCardsUseGlassInLightAndOpaqueGroundInSepiaDarkAndOled() {
        show { ReaderDisplaySheet(ReaderPreferences(), settings, keepScreenAwake = false,
            onFontSizeChange = {}, onThemeChange = {}, listeningContent = { frame -> frame {} }) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            assertCard("Customize Theme…", readerCardGround())
            assertCard("Keep screen awake", readerCardGround())
        }
    }
    @Test fun noteCardsUseGlassInLightAndOpaqueGroundInSepiaDarkAndOled() {
        show { ReaderNoteEditor(ReadingAnnotation(workID = "work", note = "Saved note", selectedText = "Quoted words"), {}, {}, {}, {}) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            assertCard("Quoted words", readerCardGround())
            assertCard("Delete Highlight", readerCardGround())
        }
    }
    private fun readerCardGround(): Color = if (mode == KudosThemeMode.Light)
        tokens.glassFill(0.09).compositeOver(tokens.background) else tokens.cardFill

    @Test fun displayKeepsWhiteSelectedPillsInLight() {
        show { ReaderDisplaySheet(ReaderPreferences(), settings, keepScreenAwake = false,
            onFontSizeChange = {}, onThemeChange = {}, listeningContent = { frame -> frame {} }) }
        listOf("Theme", "Layout").forEach { description ->
            val pill = compose.onNode(isSelected() and hasAnyAncestor(hasContentDescription(description)),
                useUnmergedTree = true).performScrollTo().fetchSemanticsNode().boundsInRoot
            assertColor(Color.White, pixel(Offset(pill.left + with(compose.density) { 5.dp.toPx() }, pill.center.y)))
        }
    }
    @Test fun speechCardsUseGlassInLightAndOpaqueGroundInSepiaDarkAndOled() {
        show { ReaderSpeechSettingsContent({}, listeningContent = { frame -> frame {
            SettingsSection(footnote = null) { SubjectFormRow("Sample Text", value = "Plain Narration") }
            SettingsSection(footnote = null) { SubjectFormRow("Engine", value = "Automatic") }
        } }) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            assertCard("Sample Text", readerCardGround())
            assertCard("Engine", readerCardGround())
        }
    }
    @Test fun customizeThemeUsesOpaqueCardsIncludingTheFontPicker() {
        show { CustomizeThemeContent(settings, onDismiss = {}) }
        for (theme in themes) {
            runBlocking { settings.updateEffectiveReaderTheme(ReaderThemeSetting.valueOf(theme.name)) }
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            assertCard("Font")
            assertCard("Customize")
            assertCard("Reset Theme")
            compose.onNodeWithText("Font").performScrollTo().performClick()
            assertCard("System")
            compose.onNodeWithText("Back").performClick()
        }
    }
    @Test fun pronunciationEmptyAndCorrectionsCardsUseElevatedGround() {
        val lexicon = KokoroPronunciationStore(temporary.root)
        var filled by mutableStateOf(false)
        show { if (filled) PronunciationSettingsContent(lexicon, {}) else PronunciationEmptyState() }
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Sepia)) {
            compose.runOnIdle { mode = theme }
            val card = compose.onNodeWithTag("Pronunciation empty card").fetchSemanticsNode().boundsInRoot
            assertColor(tokens.cardFill, pixel(Offset(card.center.x, card.top + 5f)))
        }
        lexicon.setOverride("Hermione", "hɜːmaɪəni")
        compose.runOnIdle { filled = true }
        compose.waitUntil(5_000) { compose.onAllNodesWithText("Hermione").fetchSemanticsNodes().isNotEmpty() }
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Sepia)) {
            compose.runOnIdle { mode = theme }; assertCard("Hermione")
        }
    }
    @Test fun backupSummaryAndActionsUseElevatedGroundInLightAndSepia() {
        val pending = PendingBackupImport(byteArrayOf(), BackupImportPreview(2, 3, 2, 1, 1),
            KudosBackupManifest(8, "2026-10-23T00:00:00Z"), false)
        show { ImportBackupChoices(pending, false, false, false, true, {}, {}, {}, {}, {}, {}) }
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Sepia)) {
            compose.runOnIdle { mode = theme }; assertCard("Library records"); assertCard("Merge")
        }
    }
    @Test fun queueManagerAddUsesDisabledInkUntilThereIsText() {
        var draft by mutableStateOf("")
        var adds = 0
        show { QueueTagManagerContent(ReadingQueue(name = "Read"), tokens.scopePalette, emptyList(), emptyMap(),
            false, 0, draft, { draft = it }, { adds++ }, { _, _ -> }) }
        val add = compose.onNodeWithText("Add", useUnmergedTree = true)
        compose.onNodeWithText("Add").assertIsNotEnabled()
        assertNotEquals(tokens.scopePalette.accent, textColor(add))
        compose.onNodeWithContentDescription("New tag").performTextInput("Comfort")
        compose.onNodeWithText("Add").assertIsEnabled()
        assertEquals(tokens.scopePalette.accent, textColor(add))
        compose.onNodeWithText("Add").performClick()
        compose.runOnIdle { assertEquals(1, adds) }
    }
    @Test fun bulkTagAddAlsoUsesDisabledInkAndKeepsItsSubmitAction() {
        val added = mutableListOf<String>()
        show { SharedTagContent("Tags", "Footnote", "Empty", "work", tokens.scopePalette, Unit,
            { SharedTags(emptyList(), emptyMap()) }, { added += it }, {}) }
        val add = compose.onNodeWithText("Add", useUnmergedTree = true)
        compose.onNodeWithText("Add").assertIsNotEnabled()
        assertNotEquals(tokens.accentInk, textColor(add))
        compose.onNode(hasSetTextAction()).performTextInput("Comfort")
        assertEquals(tokens.accentInk, textColor(add))
        compose.onNodeWithText("Add").performClick()
        compose.waitUntil(5_000) { added == listOf("Comfort") }
    }
    @Test fun editorBarTitleIsWholeOrAbsent() {
        var width by mutableStateOf(80.dp)
        val title = "Chapter text"
        show { PushedBarTitle(title, true, Modifier.width(width).testTag("Bar title")) }
        for (fontScale in listOf(1f, 2f)) {
            compose.runOnIdle { scale = fontScale; width = 40.dp }
            compose.onNodeWithText(title).assertDoesNotExist()
            compose.runOnIdle { width = 400.dp }
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(title).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            // Whole: one line, not ellipsized. (`hasVisualOverflow` trips on Robolectric's sub-pixel width.)
            assertEquals(1, layouts.single().lineCount)
            assertFalse(layouts.single().isLineEllipsized(0))
        }
    }
    @Test fun otherCustomTitlesKeepTheirExistingEllipsisBehaviour() {
        show { PushedBarTitle("24 selected", false, Modifier.width(50.dp)) }
        compose.onNodeWithText("24 selected").assertExists()
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText("24 selected").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.single().isLineEllipsized(0))
    }

    private fun webViews(root: View): List<WebView> = when (root) {
        is WebView -> listOf(root)
        is ViewGroup -> (0 until root.childCount).flatMap { webViews(root.getChildAt(it)) }
        else -> emptyList()
    }
    @Test fun customizeUsesTitleCaseAndReservesTheFontChevronSpace() {
        show { CustomizeThemeContent(settings, onDismiss = {}) }
        compose.onNodeWithText("Text").assertExists()
        compose.onNodeWithText("Accessibility & Layout").performScrollTo().assertExists()
        compose.onNodeWithText("TEXT").assertDoesNotExist()
        val row = compose.onNodeWithTag("Theme font row").performScrollTo().fetchSemanticsNode().boundsInRoot
        val value = compose.onNodeWithText("System", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("Value leaves space for the disclosure", row.right - value.right >= with(compose.density) { 35.dp.toPx() })
    }
    @Test fun previewRestoresReaderZoomEvenWhenTheSystemOrWebViewHasEnlargedText() {
        show { CustomizeThemeContent(settings, onDismiss = {}) }
        lateinit var web: WebView
        compose.runOnIdle { web = webViews(view).single(); web.settings.textZoom = 200 }
        // A reader preference update repaints the same production WebView at the fixed reader scale.
        runBlocking { settings.updateReaderFontPt(24.0) }
        compose.waitUntil(5_000) { web.settings.textZoom == 100 }
        assertTrue(readerThemePreviewHTML(KudosSettings.Defaults).contains("text-size-adjust: 100%"))
        compose.runOnIdle { scale = 2f }
        compose.runOnIdle { assertEquals(100, web.settings.textZoom) }
    }
    @Test fun nearbyAndNextUseTheExplicitPagePaletteInEveryTheme() {
        lateinit var palette: SubjectPalette
        var committed: Int? = null
        var jump by mutableStateOf(true)
        show {
            // Read from the composition so a theme change recomposes the palette the test compares.
            palette = SubjectPalette.fromHue(0.0663, LocalKudosTokens.current.theme)
            if (jump) PageJumpContent(2, 10, { committed = it }, {}, palette)
            else KudosPaginationBar(1, 10, {}, palette = palette)
        }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            val tile = compose.onNodeWithContentDescription("Page 2").fetchSemanticsNode().boundsInRoot
            assertColor(palette.chipFill.compositeOver(tokens.background), pixel(Offset(tile.center.x, tile.top + 8f)))
            assertEquals(palette.accentOnFill, textColor(compose.onNode(hasText("2") and
                hasAnyAncestor(hasContentDescription("Page 2")), useUnmergedTree = true)))
        }
        compose.onNodeWithContentDescription("Page 3").performClick()
        compose.runOnIdle { assertNull(committed) }
        compose.onNodeWithContentDescription("Go to page 3").performClick()
        compose.runOnIdle { assertEquals(3, committed); jump = false }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle() // so `palette` below is this theme's, not the last one's
            assertAccentPixels(compose.onNodeWithContentDescription("Next Page"), palette.accentOnFill)
        }
    }
    @Test fun contentsDoneAndDisplayControlsUseAccentInkInEveryTheme() {
        var display by mutableStateOf(false)
        show {
            if (display) ReaderDisplaySheet(ReaderPreferences(), settings, keepScreenAwake = false,
                onFontSizeChange = {}, onThemeChange = {}, listeningContent = { frame -> frame {} })
            else ReaderContentsSheet(emptyList(), emptyList(), emptyList(), onSelectEntry = {},
                onSelectAnnotation = {}, onDeleteAnnotation = {}, onDone = {})
        }
        for (theme in themes) {
            compose.runOnIdle { mode = theme; display = false }
            compose.waitForIdle()
            assertAccentPixels(compose.onNodeWithContentDescription("Done"), tokens.accentInk)
            compose.runOnIdle { display = true }
            compose.waitForIdle()
            assertAccentPixels(compose.onNodeWithContentDescription("Done"), tokens.accentInk)
            assertEquals(tokens.accentInk, textColor(compose.onNodeWithText("Customize Theme…", useUnmergedTree = true)))
        }
    }
    @Test fun contentsChaptersHaveDividersBetweenRowsAndKeepNavigation() {
        val entries = (1..3).map { ReaderTocEntry("Chapter $it", "$it.xhtml") }
        var selected: ReaderTocEntry? = null
        show { ReaderContentsSheet(entries, emptyList(), emptyList(), onSelectEntry = { selected = it },
            onSelectAnnotation = {}, onDeleteAnnotation = {}) }
        val separators = compose.onAllNodesWithTag("Contents separator", useUnmergedTree = true)
        separators.assertCountEquals(2)
        repeat(2) { index ->
            val bounds = separators[index].fetchSemanticsNode().boundsInRoot
            val painted = pixel(bounds.center)
            assertTrue("Divider paints a visible hairline",
                kotlin.math.abs(painted.red - tokens.background.red) > 0.005f ||
                    kotlin.math.abs(painted.green - tokens.background.green) > 0.005f ||
                    kotlin.math.abs(painted.blue - tokens.background.blue) > 0.005f)
        }
        compose.onNodeWithText("Chapter 2").performClick()
        compose.runOnIdle { assertEquals(entries[1], selected) }
    }
    @Test fun findAndNoteFieldsAreFocusedWhenTheirContentFirstAppears() {
        var note by mutableStateOf(false)
        var query by mutableStateOf("")
        show {
            if (note) ReaderNoteEditor(ReadingAnnotation(workID = "work", note = "Saved"), {}, {}, {}, {})
            else ReaderSearchContent(query, { query = it }, {}, ReaderSearchState(), emptyList(), null, tokens, {}, {}, {}, {})
        }
        val field = compose.onNode(hasSetTextAction())
        field.assertIsFocused()
        field.performTextInput("Stars")
        compose.runOnIdle { assertEquals("Stars", query); note = true }
        compose.onNodeWithContentDescription("Note").assertIsFocused()
    }
}
