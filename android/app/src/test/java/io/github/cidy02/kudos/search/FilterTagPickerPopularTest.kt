package io.github.cidy02.kudos.search

import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class FilterTagPickerPopularTest {
    @get:Rule val compose = createComposeRule()

    @Test fun emptyNonFandomQueryExplainsHowToGetPopularTags() {
        var kind by mutableStateOf("character")
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                FilterTagRow("Characters", kind, "", "", emptyList(), null, emptyList(), { _, _ -> })
            }
        }
        compose.onNodeWithText("Characters").performClick()
        compose.onNodeWithText("Type above to search AO3 characters.").assertExists()
        val hint = "Choose a fandom to see its most-used characters here."
        compose.onNodeWithText(hint).assertExists()
        compose.onNode(hasSetTextAction()).performTextInput("Leia")
        compose.onNodeWithText(hint).assertDoesNotExist()
        compose.onNode(hasSetTextAction()).performTextClearance()
        compose.runOnIdle { kind = "fandom" }
        compose.onNodeWithText(hint).assertDoesNotExist()
    }

    @Test fun openingShowsPopularTagsAndCyclesWithoutAnotherRead() {
        val urls = mutableListOf<String>()
        val repository = AO3TagAutocompleteRepository(object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                urls += url
                return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
                    "<label><input type='checkbox' name='include_work_search[character_ids][]'>Leia (42)</label>"))
            }
        })
        var included by mutableStateOf("")
        var excluded by mutableStateOf("")
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                FilterTagRow("Characters", "character", included, excluded, emptyList(), repository,
                    fandomContext = listOf("Star Wars"), onChange = { yes, no -> included = yes; excluded = no })
            }
        }
        assertTrue(urls.isEmpty())
        compose.onNodeWithText("Characters").performClick()
        compose.waitUntil(10_000) { compose.onAllNodesWithText("Leia").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("POPULAR IN STAR WARS").assertExists() // SubjectFieldLabel draws capitals
        compose.onNodeWithText("Choose a fandom to see its most-used characters here.").assertDoesNotExist()
        compose.onNodeWithText("Leia").performClick()
        assertEquals("Leia", included)
        val capsule = compose.onNodeWithContentDescription("Included: Leia")
        val actions = capsule.fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsActions.CustomActions]
        assertEquals(listOf("Cycle tag"), actions.map { it.label })
        compose.runOnIdle { assertTrue(actions.single().action()) }
        assertEquals("Leia", excluded)
        // Cycle back to included before testing the ordinary row's tap.
        compose.onAllNodesWithText("Leia").onLast().performClick()
        compose.onAllNodesWithText("Leia").onLast().performClick()
        // The selected section and underlying form both carry it; act on the sheet's first row.
        compose.onAllNodesWithText("Leia").onLast().performClick()
        assertEquals("Leia", excluded)
        compose.onAllNodesWithText("Leia").onLast().performClick()
        assertEquals("", included); assertEquals("", excluded)
        assertEquals(1, urls.size)
    }
}
