package io.github.cidy02.kudos.app

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ImportContacts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Density
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.comments.ChapterPickerContent
import io.github.cidy02.kudos.comments.chapterPickerBookIcon
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.library.AddLibraryWorks
import io.github.cidy02.kudos.library.AddLibraryWorksContent
import io.github.cidy02.kudos.library.CollectionEditorContent
import io.github.cidy02.kudos.library.CollectionReorderContent
import io.github.cidy02.kudos.library.QueueSeedPanel
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterRef
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.writing.WritingSeriesContent
import io.github.cidy02.kudos.writing.seriesSetup
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Brief 3hc (A88c part two) visual and behaviour parity tests. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class Brief3hcContentTest {
    @get:Rule val compose = createComposeRule()
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private lateinit var tokens: KudosTokens
    private lateinit var view: View

    private fun show(content: @Composable () -> Unit) {
        compose.setContent {
            KudosTheme(mode) {
                tokens = LocalKudosTokens.current
                view = LocalView.current
                Box(Modifier.fillMaxSize().background(tokens.background)) { content() }
            }
        }
    }

    private fun textLayout(text: String): TextLayoutResult {
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(text, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single()
    }

    // Native view drawing follows Brief3gzContentTest, without PixelCopy or a modal window.
    private fun pixel(point: Offset): Color {
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

    @Test fun collectionReorderRowsShareOneCardWithSeparators() {
        val works = listOf(
            SavedWork(id = "a", title = "Alpha", author = "A"),
            SavedWork(id = "b", title = "Beta", author = "B"),
            SavedWork(id = "c", title = "Gamma", author = "C")
        )
        show {
            CollectionReorderContent(
                collection = WorkCollection(name = "Reading"),
                ordered = works,
                saving = false,
                onDismiss = {},
                onSave = {},
                onMove = { _, _ -> }
            )
        }
        compose.onAllNodesWithTag("Collection reorder rows").assertCountEquals(1)
        compose.onAllNodesWithTag("Collection reorder row").assertCountEquals(3)
        compose.onAllNodesWithTag("Collection reorder separator", useUnmergedTree = true).assertCountEquals(2)
        listOf("1. Alpha, A", "2. Beta, B", "3. Gamma, C").forEach { desc ->
            compose.onNode(
                hasContentDescription(desc) and hasAnyAncestor(hasTestTag("Collection reorder rows"))
            ).assertExists()
        }
        val firstBounds = compose.onNodeWithContentDescription("1. Alpha, A").fetchSemanticsNode().boundsInRoot
        val secondBounds = compose.onNodeWithContentDescription("2. Beta, B").fetchSemanticsNode().boundsInRoot
        val thirdBounds = compose.onNodeWithContentDescription("3. Gamma, C").fetchSemanticsNode().boundsInRoot
        val maxSeparatorPx = with(compose.density) { 22.dp.toPx() }
        assertTrue(
            "Rows 1 and 2 are in the same segmented card without an inter-card gap",
            secondBounds.top - firstBounds.bottom < maxSeparatorPx
        )
        assertTrue(
            "Rows 2 and 3 are in the same segmented card without an inter-card gap",
            thirdBounds.top - secondBounds.bottom < maxSeparatorPx
        )
    }

    @Test fun collectionEditorGroupsNameDescriptionAndSwatchesInOneCardAndWrapsColourOnDetails() {
        var editing by mutableStateOf(false)
        var name by mutableStateOf("")
        var description by mutableStateOf("Before")
        var hue by mutableStateOf<Double?>(null)
        var hex by mutableStateOf<String?>(null)
        show {
            CollectionEditorContent(
                editing = editing,
                name = name,
                onNameChange = { name = it },
                description = description,
                onDescriptionChange = { description = it },
                hue = hue,
                colorHex = hex,
                onColorChange = { nextHue, nextHex -> hue = nextHue; hex = nextHex },
                keepsWorksOffline = false,
                onKeepsWorksOfflineChange = {},
                showsOnHome = false,
                onShowsOnHomeChange = {}
            )
        }

        compose.onAllNodesWithTag("Collection panel").assertCountEquals(1)
        compose.onAllNodesWithTag("Collection panel separator", useUnmergedTree = true).assertCountEquals(2)
        val collectionHeader = compose.onNodeWithText("COLLECTION").fetchSemanticsNode().boundsInRoot
        val panelBounds = compose.onNodeWithTag("Collection panel").fetchSemanticsNode().boundsInRoot
        assertTrue("Collection card sits below COLLECTION header", panelBounds.top >= collectionHeader.bottom)

        listOf("NAME", "DESCRIPTION").forEach { label ->
            compose.onNode(hasText(label) and hasAnyAncestor(hasTestTag("Collection panel"))).assertExists()
        }
        listOf("Violet", "Custom colour").forEach { swatch ->
            compose.onNode(
                hasContentDescription(swatch) and hasAnyAncestor(hasTestTag("Collection panel"))
            ).assertExists()
        }

        compose.runOnIdle { editing = true }
        compose.onAllNodesWithTag("Collection colour panel").assertCountEquals(1)
        listOf("Violet", "Custom colour").forEach { swatch ->
            compose.onNode(
                hasContentDescription(swatch) and hasAnyAncestor(hasTestTag("Collection colour panel"))
            ).assertExists()
        }
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val expected = if (theme == KudosThemeMode.Light) {
                tokens.glassFill(0.09).compositeOver(tokens.background)
            } else tokens.theme.cardSurface
            listOf("Collection colour panel", "Collection behaviour panel").forEach { tag ->
                val bounds = compose.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot
                assertColor(expected, pixel(Offset(bounds.left + with(compose.density) { 6.dp.toPx() }, bounds.center.y)))
            }
        }
        compose.runOnIdle { editing = false; mode = KudosThemeMode.Sepia }
        val creationPanel = compose.onNodeWithTag("Collection panel").fetchSemanticsNode().boundsInRoot
        assertColor(tokens.glassFill(0.09).compositeOver(tokens.background),
            pixel(Offset(creationPanel.left + with(compose.density) { 6.dp.toPx() }, creationPanel.center.y)))
    }

    @Test fun queueSeedRowsHaveHorizontalGapAndIndentedSeparator() {
        var seed by mutableStateOf(false)
        show {
            QueueSeedPanel(
                seed = seed,
                seedCount = 3,
                onSeedChange = { seed = it }
            )
        }

        compose.onAllNodesWithTag("Queue seed separator", useUnmergedTree = true).assertCountEquals(1)
        val radioBounds = compose.onNodeWithTag("Queue seed radio Empty", useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot
        val labelBounds = compose.onNodeWithText("Empty", useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot
        val separatorBounds = compose.onNodeWithTag("Queue seed separator", useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot
        val savedLabelBounds = compose.onNodeWithText("Saved for Later", useUnmergedTree = true)
            .fetchSemanticsNode().boundsInRoot

        assertTrue(
            "Radio circle and label have horizontal spacing",
            labelBounds.left - radioBounds.right >= with(compose.density) { 10.dp.toPx() }
        )
        assertTrue(
            "Separator sits between Empty and Saved for Later rows",
            separatorBounds.top >= labelBounds.bottom && separatorBounds.bottom <= savedLabelBounds.top
        )
        // The separator tag includes its own start padding; inspect the drawn line instead.
        val beforeInset = separatorBounds.left + with(compose.density) { 45.dp.toPx() }
        val afterInset = separatorBounds.left + with(compose.density) { 51.dp.toPx() }
        val ground = tokens.glassFill(0.09).compositeOver(tokens.background)
        assertColor(ground, pixel(Offset(beforeInset, separatorBounds.center.y)))
        assertTrue("Separator begins at the label, after 45 dp and before 51 dp",
            pixel(Offset(afterInset, separatorBounds.center.y)).red < ground.red - 0.015f)

        compose.onNodeWithText("Saved for Later").performClick()
        compose.runOnIdle { assertTrue(seed) }
    }

    @Test fun queueNameFieldKeepsTextInputAndFocusOnTheSameSemanticsNode() {
        var name by mutableStateOf("")
        show {
            io.github.cidy02.kudos.settings.SubjectTextFieldRow(
                "New queue", name, "New queue", { name = it }, fieldOnly = true,
                trailing = { androidx.compose.material3.TextButton(onClick = {}) { androidx.compose.material3.Text("Add") } }
            )
        }
        compose.onNode(hasSetTextAction()).performTextInput("Another queue")
        compose.runOnIdle { assertEquals("Another queue", name) }
    }

    @Test fun collectionReorderComposesOnlyVisibleRowsAndCanReachTheEnd() {
        val works = (1..200).map { SavedWork(id = "$it", title = "Work $it", author = "Author") }
        show {
            CollectionReorderContent(WorkCollection(name = "Long collection"), works, false, {}, {}, { _, _ -> })
        }
        assertTrue("Off-screen works stay uncomposed",
            compose.onAllNodesWithTag("Collection reorder handle", useUnmergedTree = true).fetchSemanticsNodes().size < 200)
        compose.onNodeWithContentDescription("200. Work 200, Author").assertDoesNotExist()
        compose.onNodeWithTag("Collection reorder rows").performScrollToNode(hasContentDescription("200. Work 200, Author"))
        compose.onNodeWithContentDescription("200. Work 200, Author").assertIsDisplayed()
    }

    @Test fun addLibraryWorksPrefixesByAndTintsLinkedAuthorsInCompactCaption() {
        val candidates = listOf(
            SavedWork(
                id = "w1",
                title = "Held Copy",
                author = "uncle_iroh_fan",
                authorIdentitiesJSON = ""
            ),
            SavedWork(
                id = "w2",
                title = "Salt & Signal",
                author = "undertow",
                authorIdentitiesJSON = """[{"displayName":"undertow","kind":"registered","username":"undertow","pseud":"undertow"}]"""
            )
        )
        val privacy = PrivacySettings()
        val reveal = PrivacyRevealState()
        val eligible = AddLibraryWorks.eligible(candidates, privacy, reveal)
        var dismissed = false
        var openedAuthor: String? = null

        var fontScale by mutableStateOf(1f)
        show {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                AddLibraryWorksContent(
                    destinationName = "Rainy Day",
                    scopeName = "collection",
                    candidates = candidates,
                    eligible = eligible,
                    matches = eligible,
                    chosen = emptyList(),
                    query = "",
                    onQueryChange = {},
                    selection = emptySet(),
                    onSelectionChange = {},
                    privacy = privacy,
                    reveal = reveal,
                    onToggleMature = {},
                    onDismiss = { dismissed = true },
                    onAdd = {},
                    openAuthor = { openedAuthor = it }
                )
            }
        }

        compose.onAllNodesWithText("by", useUnmergedTree = true).assertCountEquals(2)
        val undertowLayout = textLayout("undertow")
        val uncleLayout = textLayout("uncle_iroh_fan")
        assertEquals(tokens.scopePalette.controlInk, undertowLayout.layoutInput.style.color)
        assertEquals(tokens.secondaryInk, uncleLayout.layoutInput.style.color)
        assertEquals(FontWeight.Normal, undertowLayout.layoutInput.style.fontWeight)
        assertEquals(FontWeight.Normal, uncleLayout.layoutInput.style.fontWeight)
        assertEquals(12f, undertowLayout.layoutInput.style.fontSize.value, 0f)
        assertEquals(12f, uncleLayout.layoutInput.style.fontSize.value, 0f)

        compose.onNodeWithContentDescription("Author: undertow", useUnmergedTree = true).performClick()
        compose.runOnIdle {
            assertTrue(dismissed)
            assertEquals("undertow", openedAuthor)
        }
        compose.runOnIdle { fontScale = 1.5f }
        assertEquals(15.5f, textLayout("undertow").layoutInput.style.fontSize.value, 0f)
        assertEquals(tokens.scopePalette.controlInk, textLayout("undertow").layoutInput.style.color)
    }

    @Test fun chapterPickerUsesOpenBookIconAndPaletteAccentOnAllRowLabels() {
        assertEquals(Icons.Outlined.ImportContacts, chapterPickerBookIcon)

        val chapters = listOf(
            AO3ChapterRef(1L, 1, "1. Arrival"),
            AO3ChapterRef(2L, 2, "2. Departure")
        )
        var isScopeAll by mutableStateOf(false)
        lateinit var customPalette: SubjectPalette

        show {
            customPalette = SubjectPalette.fromHue(0.0663, LocalKudosTokens.current.theme)
            ChapterPickerContent(
                chapters = chapters,
                selectedChapter = chapters[0],
                isScopeAll = isScopeAll,
                totalComments = 42,
                onSelectAll = { isScopeAll = true },
                onSelectChapter = {},
                palette = customPalette
            )
        }

        val allLayout = textLayout("All Comments")
        val firstChapterLayout = textLayout(chapters[0].displayName)
        val secondChapterLayout = textLayout(chapters[1].displayName)
        val countWhenChapterScoped = textLayout("42")

        assertEquals(customPalette.accent, allLayout.layoutInput.style.color)
        assertEquals(FontWeight.Normal, allLayout.layoutInput.style.fontWeight)
        assertEquals(customPalette.accent, firstChapterLayout.layoutInput.style.color)
        assertEquals(FontWeight.SemiBold, firstChapterLayout.layoutInput.style.fontWeight)
        assertEquals(customPalette.accent, secondChapterLayout.layoutInput.style.color)
        assertEquals(FontWeight.Normal, secondChapterLayout.layoutInput.style.fontWeight)
        assertEquals(customPalette.accent.copy(alpha = 0.6f), countWhenChapterScoped.layoutInput.style.color)

        compose.runOnIdle { isScopeAll = true }
        val countWhenAllScoped = textLayout("42")
        assertEquals(customPalette.accent, countWhenAllScoped.layoutInput.style.color)
        assertEquals(FontWeight.SemiBold, textLayout("All Comments").layoutInput.style.fontWeight)
    }

    @Test fun seriesDraftBadgeRendersMixedCaseDraftInReorderAndRemoveModes() {
        val setup = runBlocking { seriesSetup() }
        val model = setup.model(reorderOnly = false)
        runBlocking { model.load() }
        val chrome = PushedShellChrome()

        show {
            CompositionLocalProvider(LocalPushedShellChrome provides chrome) {
                WritingSeriesContent(model, "The Dawn Cycle", onBack = {})
            }
        }

        compose.onNodeWithTag("Writing series form").performScrollToNode(hasText("Reorder works"))
        compose.onNodeWithText("Reorder works").performClick()
        compose.waitForIdle()

        compose.onNodeWithText("Draft", useUnmergedTree = true).assertIsDisplayed()
        compose.onAllNodesWithText("DRAFT", useUnmergedTree = true).assertCountEquals(0)
        assertEquals("Draft", textLayout("Draft").layoutInput.text.text)

        compose.runOnIdle { chrome.onBack?.invoke() }
        compose.waitForIdle()
        compose.onNodeWithTag("Writing series form").performScrollToNode(hasText("Remove works"))
        compose.onNodeWithText("Remove works").performClick()
        compose.waitForIdle()

        compose.onNodeWithText("Draft", useUnmergedTree = true).assertIsDisplayed()
        compose.onAllNodesWithText("DRAFT", useUnmergedTree = true).assertCountEquals(0)
        assertEquals("Draft", textLayout("Draft").layoutInput.text.text)
    }
}
