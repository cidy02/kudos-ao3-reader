package io.github.cidy02.kudos.app

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.author.AO3SeriesRow
import io.github.cidy02.kudos.author.AuthorDisplayMode
import io.github.cidy02.kudos.author.AuthorProfileScreen
import io.github.cidy02.kudos.author.AuthorTab
import io.github.cidy02.kudos.author.SeriesDetailCard
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3PageCache
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorParser
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorSeriesSummary
import io.github.cidy02.kudos.network.ao3.author.AO3SeriesCreator
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.detail.LocalOpenAuthor
import io.github.cidy02.kudos.writing.seriesFixture
import kotlinx.coroutines.Dispatchers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** A96: real-data parity, including the identity branches the demo screenshots cannot prove. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class, qualifiers = "w411dp-h1400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BriefA96ContentTest {
    @get:Rule val compose = createComposeRule()
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableStateOf(1f)
    private lateinit var tokens: KudosTokens
    private val themes = listOf(KudosThemeMode.Light, KudosThemeMode.Sepia, KudosThemeMode.Dark, KudosThemeMode.Oled)
    private val series = AO3AuthorSeriesSummary(
        id = 321, title = "The Dawn Cycle", creators = listOf("Avery Writes", "Guest"),
        fandoms = listOf("Star Wars"), summary = "Three stories about a difficult sunrise.",
        words = 45678, workCount = 3, dateUpdated = "08 Jul 2026", isComplete = true,
        url = "https://archiveofourown.org/series/321", bookmarkCount = 62, isRestricted = true,
        creatorIdentities = listOf(AO3SeriesCreator("Avery Writes", AO3AuthorRoute("AO3_Reader", "Avery Writes")),
            AO3SeriesCreator("Guest", null))
    )

    private fun show(content: @Composable () -> Unit) {
        compose.setContent {
            KudosTheme(mode, accentColorHex = "#7954B3") {
                tokens = LocalKudosTokens.current
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                    Box(Modifier.fillMaxSize().background(tokens.background)) { content() }
                }
            }
        }
    }

    private fun layout(node: SemanticsNodeInteraction): TextLayoutResult {
        val layouts = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single()
    }

    private fun textLayout(text: String) = layout(compose.onNodeWithText(text, useUnmergedTree = true))

    private fun assertFigureHasIcon(text: String) {
        val figure = compose.onNodeWithContentDescription(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val label = compose.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("$text has room for an icon before its label",
            label.left - figure.left >= with(compose.density) { 16.dp.toPx() })
        compose.onNodeWithText(text, useUnmergedTree = true).assertIsDisplayed()
        // Not hasVisualOverflow: a one-line, ellipsised Text lays its paragraph out at the full width and
        // reports a narrower box, so it "overflows" with nothing cut. What matters is that no line ends in "…".
        val layout = textLayout(text)
        assertFalse("$text remains readable", (0 until layout.lineCount).any(layout::isLineEllipsized))
    }

    @Test fun seriesFiguresHaveIconsIncludingTheDateAndWrapAtLargeText() {
        show { SeriesDetailCard(series) }
        for (fontScale in listOf(1f, 2f)) {
            compose.runOnIdle { scale = fontScale }
            listOf("3 works", "%,d words".format(45678), "62 bookmarks", "Restricted", "Complete", "08 Jul 2026")
                .forEach(::assertFigureHasIcon)
            val first = compose.onNodeWithText("3 works", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            val last = compose.onNodeWithText("08 Jul 2026", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            assertTrue("Figures wrap onto more than one line", last.top > first.top)
        }
    }

    @Test fun inProgressHasAnIconAndMissingSeriesFiguresStayAbsent() {
        var shown by mutableStateOf(series.copy(isComplete = false))
        show { SeriesDetailCard(shown) }
        assertFigureHasIcon("In progress")
        compose.onNodeWithText("Complete").assertDoesNotExist()
        compose.runOnIdle {
            shown = shown.copy(workCount = null, words = null, bookmarkCount = null, isComplete = null,
                isRestricted = false, dateUpdated = "")
        }
        listOf("3 works", "%,d words".format(45678), "62 bookmarks", "Restricted", "In progress", "08 Jul 2026")
            .forEach { compose.onNodeWithText(it).assertDoesNotExist() }
        compose.onNodeWithContentDescription("Author: Avery Writes").assertExists()
    }

    @Test fun seriesCreatorsUseAppAccentForLinksAndSecondaryInkForGuestsInBothPresentations() {
        var ledger by mutableStateOf(false)
        var opened: AO3AuthorRoute? = null
        show {
            if (ledger) AO3SeriesRow(series, AuthorDisplayMode.Ledger, null, onOpenAuthor = { opened = it })
            else SeriesDetailCard(series, onOpenAuthor = { opened = it })
        }
        for (presentation in listOf(false, true)) {
            compose.runOnIdle { ledger = presentation }
            for (theme in themes) {
                compose.runOnIdle { mode = theme }
                compose.waitForIdle()
                assertEquals(tokens.scopePalette.accent, textLayout("Avery Writes,").layoutInput.style.color)
                assertEquals(tokens.secondaryInk, textLayout("Guest").layoutInput.style.color)
                assertEquals(tokens.secondaryInk, textLayout("by").layoutInput.style.color)
            }
            compose.onNodeWithContentDescription("Author: Avery Writes", useUnmergedTree = true).performClick()
            compose.runOnIdle { assertEquals(AO3AuthorRoute("AO3_Reader", "Avery Writes"), opened) }
        }
    }

    @Test fun seriesWorkBylinesIncludeByForLinkedAndUnlinkedNamesIncludingSelection() {
        val linked = AO3AuthorParser().parseWorksPage(seriesFixture("ao3_demo_dawn_series"), 1).works.first()
        assertTrue("Fixture represents a registered AO3 author", linked.authorIdentitiesJSON.isNotBlank())
        var work by mutableStateOf(linked)
        var selecting by mutableStateOf(false)
        var opened: String? = null
        show {
            CompositionLocalProvider(LocalOpenAuthor provides { opened = it }) {
                SeriesWorkRow(work, selecting, false, {}, {}, false)
            }
        }
        for (hasIdentity in listOf(true, false)) {
            compose.runOnIdle { work = linked.copy(authorIdentitiesJSON = if (hasIdentity) linked.authorIdentitiesJSON else "") }
            compose.onAllNodesWithText("by", useUnmergedTree = true).assertCountEquals(1)
            assertEquals(tokens.secondaryInk, textLayout("by").layoutInput.style.color)
            assertEquals(if (hasIdentity) tokens.scopePalette.accent else tokens.secondaryInk,
                textLayout("Avery Writes").layoutInput.style.color)
            if (hasIdentity) {
                compose.onNodeWithContentDescription("Author: Avery Writes", useUnmergedTree = true).performClick()
                compose.runOnIdle { assertEquals("Avery Writes (AO3_Reader)", opened) }
            } else compose.onNodeWithContentDescription("Author: Avery Writes", useUnmergedTree = true).assertDoesNotExist()
        }
        // Selection already uses the ledger's combined byline; keep that existing prefix.
        compose.runOnIdle { selecting = true }
        compose.onNodeWithText("by Avery Writes", useUnmergedTree = true).assertExists()
    }

    @Test fun seriesFandomHasAQuietIconAndWrapsWithinTheCard() {
        var shown by mutableStateOf(series)
        show { SeriesDetailCard(shown) }
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val icon = compose.onNodeWithTag("Series fandom icon", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            val text = compose.onNodeWithText("Star Wars", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            assertTrue("Fandom icon precedes text", icon.right < text.left)
            assertEquals(tokens.secondaryInk, textLayout("Star Wars").layoutInput.style.color)
        }
        val fandoms = listOf("A long fandom name that wraps across the card", "Another fandom")
        compose.runOnIdle { scale = 2f; shown = series.copy(fandoms = fandoms) }
        val label = textLayout(fandoms.joinToString(", "))
        assertEquals(2, label.lineCount)
        assertEquals(2, label.layoutInput.maxLines)
        compose.runOnIdle { shown = series.copy(fandoms = emptyList()) }
        compose.onNodeWithTag("Series fandom icon", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test fun authorBookmarksUsesAMixedCaseSubheadlineAboveTheCards() {
        val repo = AO3AuthorRepository(publicClient = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                val name = when (java.net.URI(url).path) {
                    "/users/Avery_Archive" -> "ao3_author_dashboard"
                    "/users/Avery_Archive/bookmarks" -> "ao3_author_bookmarks"
                    else -> error("Unexpected fixture request: $url")
                }
                val body = org.jsoup.Jsoup.parse(seriesFixture(name)).apply { select("img").remove() }.outerHtml()
                return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), body))
            }
        }, parseDispatcher = Dispatchers.Unconfined, pageCache = AO3PageCache())
        show {
            AuthorProfileScreen("Avery_Archive", initialTab = AuthorTab.Bookmarks, authorRepository = repo,
                onOpenWork = {}, onOpenAbout = {})
        }
        compose.waitUntil(20_000) {
            compose.onAllNodesWithText("A Recommended Work", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        val heading = compose.onNode(hasText("Bookmarks") and
            SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading), useUnmergedTree = true)
        for (theme in themes) {
            compose.runOnIdle { mode = theme }
            compose.waitForIdle()
            val style = layout(heading).layoutInput.style
            assertEquals(tokens.secondaryInk, style.color)
            assertEquals(15f, style.fontSize.value, 0f)
            assertEquals(FontWeight.SemiBold, style.fontWeight)
            assertEquals(0f, style.letterSpacing.value, 0f)
        }
        compose.onNodeWithText("BOOKMARKS", useUnmergedTree = true).assertDoesNotExist()
        val firstCard = compose.onNodeWithText("A Recommended Work", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("Section heading precedes the cards", heading.fetchSemanticsNode().boundsInRoot.bottom <= firstCard.top)
    }
}
