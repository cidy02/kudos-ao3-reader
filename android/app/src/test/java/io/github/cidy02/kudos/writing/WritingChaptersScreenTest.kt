package io.github.cidy02.kudos.writing

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.writes.DefaultAO3AuthenticatedClient
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h2400dp")
class WritingChaptersScreenTest {
    @get:Rule val composeTestRule = createComposeRule()

    @Test
    fun chaptersScreenDisplaysCorrectly() = runTest {
        val auth = AO3AuthRepository(MemorySessionStore(testSession()), MemoryCookieStore())
        auth.restoreSession()
        val baseClient = WorkFormScreenClient()
        val client = DefaultAO3AuthenticatedClient(baseClient, baseClient, auth)
        
        composeTestRule.setContent {
            WritingChaptersScreen(workID = 995006L, workTitle = "Demo Title", client = client, auth = auth, onBack = {})
        }
        
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("Chapters").assertExists()
        composeTestRule.onNodeWithText("Demo Title · 2 chapters").assertExists()
        composeTestRule.onNodeWithText("Chapter 1").assertExists()
        composeTestRule.onNodeWithText("2026-10-01").assertExists()
        val longTextNode = composeTestRule.onNodeWithText("2. This is a very long title for a chapter that should probably wrap to multiple lines at accessibility sizes")
        longTextNode.assertExists()
        
        longTextNode.assert(hasTextExactly("2. This is a very long title for a chapter that should probably wrap to multiple lines at accessibility sizes"))
        
        // No click action on chapter rows
        val node = composeTestRule.onNodeWithText("Chapter 1")
        node.assertHasNoClickAction()
    }
}
