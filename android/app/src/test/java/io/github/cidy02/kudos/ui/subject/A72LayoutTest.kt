package io.github.cidy02.kudos.ui.subject

import android.app.Application
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material.icons.outlined.Book
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.account.ChallengeBottomActions
import io.github.cidy02.kudos.comments.CommentReplyButton
import io.github.cidy02.kudos.comments.CommentsFilterRail
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.library.CollectionCard
import io.github.cidy02.kudos.library.QueueHeaderDetails
import io.github.cidy02.kudos.library.QueueQuickFilter
import io.github.cidy02.kudos.settings.ListeningSpeedPresets
import io.github.cidy02.kudos.ui.components.GlassFieldBar
import io.github.cidy02.kudos.ui.components.KudosPaginationBar
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Actual shared components, native text measurement and semantics; no captureToImage. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h1400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class A72LayoutTest {
    @get:Rule val compose = createComposeRule()

    @Test fun commentsNewestIsWholeOnItsOwnRowAtScaleTwo() {
        show {
            CommentsFilterRail {
                SubjectChip("All comments", leadingIcon = Icons.Outlined.Book,
                    trailingIcon = Icons.Default.KeyboardArrowDown, style = SubjectChipStyle.Pill(false))
                SubjectChip("Newest", leadingIcon = Icons.Default.SwapVert,
                    trailingIcon = Icons.Default.KeyboardArrowDown, style = SubjectChipStyle.Pill(false))
            }
        }
        readable("All comments")
        readable("Newest")
        assertTrue(bounds("Newest").top >= bounds("All comments").bottom)
    }

    @Test fun threadReplyKeepsItsAccessibleActionWithoutVisibleWord() {
        var replies = 0
        show {
            Column {
                CommentReplyButton("Reply to Reader", plainAccent = LocalKudosTokens.current.accent) { replies++ }
                CommentReplyButton("Reply from Inbox") { replies++ }
            }
        }
        compose.onAllNodesWithText("Reply", useUnmergedTree = true).assertCountEquals(1)
        compose.onNodeWithContentDescription("Reply to Reader").assertHasClickAction().performClick()
        compose.onNodeWithContentDescription("Reply from Inbox").performClick()
        assertEquals(2, replies)
    }

    @Test fun fandomChipDisplaysItsEntireTextAtScaleTwo() {
        val fandom = "呪術廻戦 | Jujutsu Kaisen (Manga)"
        show { SubjectChip(fandom) }
        assertTrue(readable(fandom).lineCount > 1)
    }

    @Test fun queueSearchPlaceholderDisplaysItsEntireTextAtScaleTwo() {
        val placeholder = "Search queues, tags and works"
        show {
            GlassFieldBar("", {}, placeholder, Modifier.fillMaxWidth(), leading = {
                Spacer(Modifier.size(18.dp))
            })
        }
        assertTrue(readable(placeholder).lineCount > 1)
    }

    @Test fun queueLastFilterCanBeScrolledFullyIntoViewAtScaleTwo() {
        var selected: QueueQuickFilter? = null
        show {
            QueueHeaderDetails(emptyList(), emptySet(), emptyList(), LocalKudosTokens.current.scopePalette,
                QueueQuickFilter.All, { selected = it }, {})
        }
        compose.onNodeWithText("WIP 0").performScrollTo().assertIsDisplayed().performClick()
        readable("WIP 0")
        assertEquals(QueueQuickFilter.entries.last(), selected)
    }

    @Test fun listeningPresetsKeepFullWidthButtonTargetsAtScaleTwo() {
        var chosen = 1f
        show { ListeningSpeedPresets(1f) { chosen = it } }
        listOf("0.9x", "1.0x (default)", "1.1x").forEach {
            readable(it)
            compose.onNodeWithText(it).assertWidthIsAtLeast(300.dp)
        }
        compose.onNodeWithText("1.1x").performClick()
        assertEquals(1.1f, chosen, 0.0001f)
        assertTrue(bounds("1.0x (default)").top > bounds("0.9x").bottom)
    }

    @Test fun collectionMosaicKeepsTwoColumnsIncludingItsEmptySlotsAtScaleTwo() {
        val works = listOf(SavedWork(title = "First", author = "Writer"), SavedWork(title = "Second", author = "Reader"))
        show {
            CollectionCard(WorkCollection(name = "Weekend", workIds = works.map { it.id }), works, {}, {})
        }
        val slots = (0..3).map { compose.onNodeWithTag("Collection mosaic slot $it", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot }
        assertEquals(slots[0].top, slots[1].top, 1f)
        assertEquals(slots[2].top, slots[3].top, 1f)
        assertEquals(slots[0].left, slots[2].left, 1f)
        assertEquals(slots[1].left, slots[3].left, 1f)
        assertTrue(slots[0].right < slots[1].left)
        assertTrue(slots[0].bottom < slots[2].top)
    }

    @Test fun authorPickerKeepsFourWholeLabelsOnOneRowAtScaleTwo() {
        val tabs = listOf("Works", "Series", "Bookmarks", "About")
        show { SubjectSegmentedControl(tabs, "Works", {}, { it }) }
        tabs.forEach { readable(it) }
        val first = bounds("Works")
        tabs.forEach { assertEquals(first.center.y, bounds(it).center.y, 1f) }
    }

    @Test fun challengeFiltersKeepThreeWholeLabelsOnOneTrackAtScaleTwo() {
        val tabs = listOf("Matched", "Unmatched", "Pinch hits")
        show { SubjectSegmentedControl(tabs, "Unmatched", {}, { it }) }
        tabs.forEach { readable(it) }
        tabs.forEach { assertEquals(bounds("Matched").center.y, bounds(it).center.y, 1f) }
    }

    @Test fun challengeBottomActionsKeepTwoColumnsAndWrapEveryWordAtScaleTwo() {
        show { ChallengeBottomActions("Report a default", "Claim a pinch hit", onSecondary = {}, onPrimary = {}) }
        readable("Report a default")
        readable("Claim a pinch hit")
        val left = compose.onNodeWithText("Report a default").fetchSemanticsNode().boundsInRoot
        val right = compose.onNodeWithText("Claim a pinch hit").fetchSemanticsNode().boundsInRoot
        assertTrue(left.right < right.left)
        assertEquals(left.center.y, right.center.y, 1f)
    }

    @Test fun pageCapsuleKeepsWholePositionAndArrowsOnOneRowAtScaleTwo() {
        show { KudosPaginationBar(1, 4, {}) }
        readable("Page 1 / 4")
        val position = bounds("Page 1 / 4")
        val previous = compose.onNodeWithContentDescription("Previous Page").fetchSemanticsNode().boundsInRoot
        val next = compose.onNodeWithContentDescription("Next Page").fetchSemanticsNode().boundsInRoot
        assertTrue(previous.right <= position.left)
        assertTrue(position.right <= next.left)
        compose.onNodeWithContentDescription("Page 1 of 4").performClick()
        compose.onNodeWithText("Go").assertExists()
    }

    @Test fun narrowPageCapsuleUsesAWholeShorterLabelAndKeepsTheFullSpokenPosition() {
        var selected = 0
        show(width = 240.dp) { KudosPaginationBar(2731, 5000, { selected = it }) }
        readable("2731")
        compose.onNodeWithContentDescription("Page 2731 of 5000").assertExists()
        compose.onNodeWithContentDescription("Next Page").performClick()
        assertEquals(2732, selected)
    }

    private fun show(width: Dp = 360.dp, content: @Composable () -> Unit) {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                    Box(Modifier.width(width)) { content() }
                }
            }
        }
    }

    private fun readable(text: String): TextLayoutResult {
        val node = compose.onNodeWithText(text, useUnmergedTree = true)
        val layouts = mutableListOf<TextLayoutResult>()
        node.assertIsDisplayed().performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue("Missing text layout for $text", layouts.isNotEmpty())
        val layout = layouts.single()
        assertFalse("Height overflow: $text", layout.didOverflowHeight)
        // Not didOverflowWidth: centred or unbounded text is laid out at the whole available
        // width (a 52px "0.9x" in a 322px paragraph reports an overflow it does not have).
        repeat(layout.lineCount) {
            assertTrue("Width overflow: $text", layout.getLineRight(it) - layout.getLineLeft(it) <= layout.size.width + 1)
            assertFalse("Ellipsis: $text", layout.isLineEllipsized(it))
        }
        val bounds = node.fetchSemanticsNode().boundsInRoot
        assertTrue("Clipped height: $text", bounds.height >= layout.size.height - 1)
        assertTrue("Clipped width: $text", bounds.width >= layout.size.width - 1)
        return layout
    }

    private fun bounds(text: String) = compose.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
}
