package io.github.cidy02.kudos.settings

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.sp
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.detail.LocalOpenAuthor
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class QueueStorageBylineTest {
    @get:Rule val compose = createComposeRule()

    @Test fun verifiedPseudOpensItsAccountAndUnverifiedCoauthorStaysPlain() {
        val opened = mutableListOf<String>()
        val work = SavedWork(title = "Queued work", author = "Avery Writes, Jane",
            authorIdentitiesJSON = """[{"username":"avery","pseud":"Avery Writes","displayName":"Avery Writes","kind":"registered"}]""")
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalOpenAuthor provides { opened += it }) {
                    PreservedWorkRow(work, inSavedForLater = true, size = "1 MB", onRemove = {}, onKeepDownload = {})
                }
            }
        }
        for (name in listOf("Avery Writes", "Jane", ",")) {
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(name, useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertEquals(12.sp, layouts.single().layoutInput.style.fontSize)
        }
        compose.onNodeWithContentDescription("Author: Avery Writes").performClick()
        assertEquals(listOf("Avery Writes (avery)"), opened)
        compose.onNodeWithText("Jane", useUnmergedTree = true).assertHasNoClickAction()
    }
}
