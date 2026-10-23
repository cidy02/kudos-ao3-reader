package io.github.cidy02.kudos.author

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import io.github.cidy02.kudos.account.AO3DashboardScreen
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.app.NavArgCodecs
import io.github.cidy02.kudos.app.PushedShellChrome
import io.github.cidy02.kudos.app.Routes
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import java.io.File
import kotlinx.coroutines.Dispatchers
import okhttp3.HttpUrl.Companion.toHttpUrl
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
class DashboardBookmarksNavigationTest {
    @get:Rule val compose = createComposeRule()
    private lateinit var nav: NavHostController
    private var destination: String? = null
    private var initialTab: AuthorTab? = null
    private val accountLists = mutableListOf<AccountListType>()
    private val series = mutableListOf<String>()
    private val requests = mutableListOf<String>()
    private val source = FixtureSource { name ->
        listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
            .map { File("$it/fixtures/$name.html") }.firstOrNull(File::isFile)?.readBytes()
    }
    private val client = object : AO3Client {
        override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
            requests += url
            val body = DemoNetwork.webFixture(url.toHttpUrl(), source)?.decodeToString()
                ?: error("Unbundled test address $url")
            // Keep even the independent image loader offline.
            val html = org.jsoup.Jsoup.parse(body).apply { select("img").remove() }.outerHtml()
            return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
        }
    }

    private fun show() {
        val repository = AO3AuthorRepository(publicClient = client, parseDispatcher = Dispatchers.Unconfined,
            pageCache = AO3PageCache(ttlMillis = 0, staleMillis = 0))
        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                CompositionLocalProvider(LocalPushedShellChrome provides remember { PushedShellChrome() }) {
                    nav = rememberNavController()
                    val entry by nav.currentBackStackEntryAsState()
                    destination = entry?.destination?.route
                    NavHost(nav, startDestination = "dashboard") {
                        composable("dashboard") {
                            AO3DashboardScreen(
                                authorRepository = repository, username = "Avery_Archive",
                                onOpenWork = {}, onOpenWeb = {}, onOpenAbout = {}, onOpenAO3Collections = {},
                                onOpenSeries = { series += it },
                                onOpenList = {
                                    accountLists += it
                                    nav.navigate(Routes.accountList(NavArgCodecs.encodeAccountListType(it)))
                                },
                                onOpenAuthorTab = { author, tab -> nav.navigate(Routes.authorProfile(author, tab)) }
                            )
                        }
                        composable(Routes.AccountList, arguments = listOf(Routes.navArgOf("listType"))) { }
                        composable(Routes.AuthorProfile, arguments = listOf(Routes.navArgOf("authorUsername"),
                            navArgument("tab") { type = NavType.StringType; nullable = true; defaultValue = null })) { backStack ->
                            initialTab = Routes.authorProfileInitialTab(Routes.routeArg(backStack, "tab"))
                            AuthorProfileScreen(
                                username = Routes.routeArg(backStack, "authorUsername")!!,
                                initialTab = initialTab, authorRepository = repository,
                                onOpenWork = {}, onOpenAbout = {}
                            )
                        }
                    }
                }
            }
        }
        compose.waitUntil(15_000) {
            // The section header draws its title in capitals.
            compose.onAllNodesWithText("Recent works", ignoreCase = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test fun seeAllBookmarksPushesAuthorProfileOnBookmarksInsteadOfTheAccountList() {
        show()
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("See all series"))
        compose.onNodeWithText("See all series").performClick()
        assertEquals(listOf("https://archiveofourown.org/users/Avery_Archive/series"), series)
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("See all bookmarks"))
        compose.onNodeWithText("See all bookmarks").performClick()
        compose.waitUntil(15_000) { requests.any { it.toHttpUrl().encodedPath == "/users/Avery_Archive/bookmarks" } }
        compose.runOnIdle {
            assertEquals(Routes.AuthorProfile, destination)
            assertEquals(AuthorTab.Bookmarks, initialTab)
            assertTrue(accountLists.isEmpty())
            assertFalse(requests.any { it.toHttpUrl().encodedPath == "/users/Avery_Archive/works" })
        }
        compose.onNode(hasText("Bookmarks") and isSelectable()).assertIsSelected()
        compose.runOnIdle { nav.popBackStack() }
        compose.onNodeWithTag("Author profile").performScrollToNode(hasText("See all works"))
        compose.onNodeWithText("See all works").performClick()
        compose.waitForIdle()
        assertEquals(listOf(AccountListType.MyWorks), accountLists)
        assertEquals(Routes.AccountList, destination)
    }
}
