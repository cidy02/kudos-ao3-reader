package io.github.cidy02.kudos.author

import android.app.Application
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import io.github.cidy02.kudos.app.Routes
import io.github.cidy02.kudos.network.ao3.author.*
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import java.io.File
import java.net.URLDecoder
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SeriesCreatorScreenTest {
    @get:Rule val compose = createComposeRule()
    private fun series(id: Long): AO3AuthorSeriesSummary {
        val html = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/ao3_author_series.html") }.first(File::isFile).readText()
        return AO3AuthorParser().parseSeriesPage(html, 1).series.first { it.id == id }
    }

    @Test fun tappingACreatorKeepsThePseudThroughNativeNavigation() {
        var opened: AO3AuthorRoute? = null
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                AO3SeriesRow(series(321), AuthorDisplayMode.Ledger, onOpenSeries = {}, onOpenAuthor = { opened = it })
            }
        }
        compose.onNodeWithContentDescription("Author: Avery Writes").assertHasClickAction().performClick()
        val expected = AO3AuthorRoute("AO3_Reader", "Avery Writes")
        assertEquals(expected, opened)
        val argument = URLDecoder.decode(Routes.authorProfile(opened!!).substringAfter("author-profile/"), "UTF-8")
        assertEquals(expected, AO3AuthorRoute.fromByline(argument))
    }

    @Test fun anonymousHasNoAuthorAction() {
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                AO3SeriesRow(series(322), AuthorDisplayMode.Ledger, onOpenSeries = {})
            }
        }
        compose.onNodeWithText("Anonymous", useUnmergedTree = true).assertExists()
        compose.onNodeWithContentDescription("Author: Anonymous").assertDoesNotExist()
    }
}
