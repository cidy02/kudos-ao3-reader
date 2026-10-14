package io.github.cidy02.kudos.works.detail

import android.app.Application
import androidx.compose.ui.test.assertHasNoClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Brief 3do: a name opens its author only when AO3 linked it to an account, as iOS. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
class WorkDetailBylineTest {
    @get:Rule val compose = createComposeRule()

    @Test fun aNameWithNoAccountIsPlainText() {
        val opened = mutableListOf<String>()
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                WorkDetailIdentityHeader(
                    title = "T", author = "Avery Writes, Jane", authorNames = listOf("Avery Writes", "Jane"),
                    fandoms = emptyList(), palette = SubjectPalette.fromHue(0.3, ReaderTheme.Light),
                    isLinked = { it == "Avery Writes" }, onOpenAuthor = { opened += it }
                )
            }
        }
        compose.onNodeWithContentDescription("Author: Avery Writes").performClick()
        assertEquals(listOf("Avery Writes"), opened)
        compose.onNodeWithText("Jane").assertHasNoClickAction()
    }

    @Test fun preservationReadsAsIos() {
        assertEquals("Preserved offline", preservationStatusLabel("preserved"))
        assertEquals("Needs restore", preservationStatusLabel("missingFile"))
        assertEquals("Not preserved", preservationStatusLabel(null))
    }
}
