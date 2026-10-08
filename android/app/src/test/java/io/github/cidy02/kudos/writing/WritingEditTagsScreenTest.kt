package io.github.cidy02.kudos.writing

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.writing.*
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WritingEditTagsScreenTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var setup: WorkFormTestSetup
    private lateinit var parent: WritingWorkFormState
    private val chrome = PushedShellChrome()
    private var mode by mutableStateOf(KudosThemeMode.Light)
    private var scale by mutableFloatStateOf(1f)
    private fun show(id: Long = 995006) {
        setup = runBlocking { workFormSetup() }
        parent = setup.model(id)
        runBlocking { parent.load() }
        compose.setContent {
            KudosTheme(mode) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, scale), LocalPushedShellChrome provides chrome) {
                    Column {
                        Row { chrome.trailingContent?.invoke(this) }
                        WritingWorkFormContent(parent, setup.auth.username().orEmpty(), "Edit work", {})
                    }
                }
            }
        }
    }
    private fun awaitText(text: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty() }
        compose.waitForIdle()
    }
    private fun reach(text: String) = compose.onNodeWithTag("Writing edit tags").performScrollToNode(hasText(text))
    private fun open() {
        compose.onNodeWithTag("Writing work form").performScrollToNode(hasText("Edit tags"))
        compose.onNodeWithText("Edit tags").performClick()
        awaitText("Teen And Up Audiences")
        assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }
    private fun back() { compose.runOnIdle { chrome.onBack!!.invoke() }; compose.waitForIdle() }

    @Test fun postedRowOpensItsOwnPageAndEveryAddUsesTheLandedEditorWithBackRetainingChanges() {
        show(); open()
        awaitText("The Cartographer’s \"Second\" Tide & 星 · changes here do not touch the text")
        val initial = AO3WorkFormParser().parse(workFixture("ao3_demo_work_edit_tags"))
        for (kind in WritingTagKind.entries) {
            compose.onNodeWithTag("Writing edit tags").performScrollToNode(hasContentDescription("Add ${kind.title}"))
            compose.onNodeWithContentDescription("Add ${kind.title}").performClick()
            val count = kind.values(initial).size
            awaitText("$count chosen · drag to reorder · $WritingTagOffer")
            compose.onNodeWithContentDescription("Add a tag").performTextInput("Local ${kind.title}")
            compose.onNodeWithContentDescription("Add a tag").performImeAction()
            back()
            compose.onNodeWithTag("Writing edit tags").performScrollToNode(hasContentDescription("Remove Local ${kind.title}"))
            compose.onNodeWithContentDescription("Remove Local ${kind.title}").assertExists()
            assertNotNull(chrome.trailingContent)
        }
        assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
        back()
        compose.onNodeWithTag("Writing work form").assertExists()
        assertNotNull(chrome.trailingContent)
        assertEquals(listOf("Maps", "\"Wait & See\"", "夜の約束"), parent.state.value.form!!.additionalTags)
    }

    @Test fun ratingWarningsCategoriesRemovalAndFailedSaveRetainTheExactDraftAndNoRefreshRuns() {
        show(); open()
        reach("Mature"); compose.onNodeWithText("Mature").performClick()
        reach("Graphic Depictions Of Violence"); compose.onNodeWithText("Graphic Depictions Of Violence").performClick()
        reach("F/F"); compose.onNodeWithContentDescription("F/F").performClick()
        compose.onNodeWithTag("Writing edit tags").performScrollToNode(hasContentDescription("Remove Maps"))
        compose.onNodeWithContentDescription("Remove Maps").performClick()
        setup.client.postBody = "<div id=error><ul><li>Tag refused by AO3</li></ul></div>"
        setup.client.postStatus = 422
        compose.onNodeWithText("Save").performClick()
        awaitText("AO3 could not save the change"); awaitText("Tag refused by AO3")
        val fields = setup.client.recordedPosts.single().fields
        assertEquals(listOf("Mature"), fields.filter { it.first == AO3WorkFormField.rating }.map { it.second })
        assertEquals(listOf("No Archive Warnings Apply", "Graphic Depictions Of Violence"),
            fields.filter { it.first == AO3WorkFormField.warnings }.map { it.second })
        assertEquals(listOf("Gen", "Multi", "F/F"), fields.filter { it.first == AO3WorkFormField.categories }.map { it.second })
        assertEquals(listOf("\"Wait & See\", 夜の約束"), fields.filter { it.first == AO3WorkFormField.additionalTags }.map { it.second })
        compose.onNodeWithText("OK").performClick()
        compose.onNodeWithTag("Writing edit tags").assertExists()
        compose.onNodeWithTag("Writing edit tags").performScrollToNode(hasContentDescription("Remove 夜の約束"))
        compose.onNodeWithContentDescription("Remove 夜の約束").assertExists()
        assertEquals(3, setup.client.gets.size); assertEquals(1, setup.client.posts)
        assertEquals("Teen And Up Audiences", parent.state.value.form!!.rating)
    }

    @Test fun unconfirmedPageShowsIosWordsAndSuccessDismissesOnlyAfterConfirmationThenReloadsTags() {
        show(); open()
        val original = parent.state.value.form!!
        setup.client.postBody = "<form>successfully updated</form>"
        compose.onNodeWithText("Save").performClick()
        awaitText(AO3CollectionFields.UNCONFIRMED)
        compose.onNodeWithText("OK").performClick()
        val entered = CompletableDeferred<Unit>(); val answer = CompletableDeferred<Unit>()
        setup.client.beforePostResponse = {
            entered.complete(Unit); answer.await()
            setup.client.body = workFixture("ao3_demo_work_posted_edit").replace("Mill Lantern Chronicles,  星の地図", "Confirmed fandom")
        }
        setup.client.postBody = "<main id=main><div class='flash notice'>Tags saved.</div></main>"
        compose.onNodeWithText("Save").performClick()
        compose.waitUntil(15_000) { entered.isCompleted }
        compose.onNodeWithText("Save").assertIsNotEnabled()
        compose.onNodeWithTag("Writing edit tags").assertExists()
        assertEquals(original, parent.state.value.form)
        answer.complete(Unit)
        compose.waitUntil(15_000) { parent.state.value.form?.fandoms == listOf("Confirmed fandom") }
        compose.onNodeWithTag("Writing work form").assertExists()
        assertEquals(original.title, parent.state.value.form!!.title)
        assertEquals(5, setup.client.gets.size); assertEquals(2, setup.client.posts)
        assertNotNull(chrome.trailingContent)
    }

    @Test fun backDuringDispatchedSaveStillRefreshesTheOwningWorkFormOnConfirmation() {
        show(); open()
        val entered = CompletableDeferred<Unit>(); val answer = CompletableDeferred<Unit>()
        setup.client.beforePostResponse = {
            entered.complete(Unit); answer.await()
            setup.client.body = workFixture("ao3_demo_work_posted_edit").replace("Mill Lantern Chronicles,  星の地図", "Saved after Back")
        }
        compose.onNodeWithText("Save").performClick()
        compose.waitUntil(15_000) { entered.isCompleted }
        back()
        compose.onNodeWithTag("Writing work form").assertExists()
        answer.complete(Unit)
        compose.waitUntil(15_000) { parent.state.value.form?.fandoms == listOf("Saved after Back") }
        assertEquals(4, setup.client.gets.size); assertEquals(1, setup.client.posts)
        assertFalse(parent.state.value.tagsNeedRefresh)
    }

    @Test fun refusedOpeningHasAnExplicitRetryAndNoSaveOrPost() {
        show()
        setup.client.failure = AO3Error.Forbidden
        compose.onNodeWithTag("Writing work form").performScrollToNode(hasText("Edit tags"))
        compose.onNodeWithText("Edit tags").performClick()
        awaitText(workFormFailure(AO3Error.Forbidden))
        compose.onNodeWithText("Try Again").assertExists()
        compose.onAllNodesWithText("Save").assertCountEquals(0)
        assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
        setup.client.failure = null
        compose.onNodeWithText("Try Again").performClick()
        awaitText("Teen And Up Audiences")
        assertEquals(3, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }

    @Test fun draftHasNoSeparateTagsRow() {
        show(995001)
        compose.onNodeWithTag("Writing work form").performScrollToNode(hasText("Work skin"))
        compose.onAllNodesWithText("Edit tags").assertCountEquals(0)
        assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }

    @Test fun everyThemeAtAccessibilityScaleWrapsLongLabelsAndChipsWithoutEllipsis() {
        show()
        val longTag = "A lantern under a very long sky 星 ".repeat(8).trim()
        setup.client.body = workFixture("ao3_demo_work_edit_tags").replace("Maps, &quot;Wait &amp; See&quot;, 夜の約束", longTag)
        open()
        for (theme in listOf(KudosThemeMode.Light, KudosThemeMode.Dark, KudosThemeMode.Sepia, KudosThemeMode.Oled)) {
            compose.runOnIdle { mode = theme; scale = 2f }
            compose.waitForIdle()
            for (label in listOf("Choose Not To Use Archive Warnings", "Graphic Depictions Of Violence", "Additional tags")) {
                reach(label)
                assertTextFits(compose.onNodeWithText(label))
            }
            compose.onNodeWithTag("Writing edit tags").performScrollToNode(hasContentDescription("Remove $longTag"))
            assertTextFits(compose.onNodeWithText(longTag))
            assertTextFits(compose.onNodeWithText("Save"))
        }
        assertEquals(2, setup.client.gets.size); assertEquals(0, setup.client.posts)
    }

    private fun assertTextFits(node: SemanticsNodeInteraction) {
        val layouts = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.isNotEmpty())
        layouts.forEach { layout ->
            assertFalse(layout.didOverflowHeight)
            assertFalse(layout.isLineEllipsized(layout.lineCount - 1))
        }
    }
}
