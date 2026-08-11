package io.github.cidy02.kudos.app

import android.content.Context
import androidx.navigation.compose.composable
import androidx.navigation.createGraph
import androidx.navigation.testing.TestNavHostController
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Empirical check of a specific claim from Grok's T-90 review: that
 * AndroidX Navigation already URL-decodes a string route argument when
 * populating [androidx.navigation.NavBackStackEntry.arguments], which would
 * make Routes.routeArg's own URLDecoder.decode call a second, corrupting
 * decode pass. Verified here against a real NavController/NavGraph
 * (Robolectric), not just reasoned about - this is exactly the kind of
 * navigation-internals behavior worth confirming rather than assuming.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RoutesNavigationTest {
    private lateinit var navController: TestNavHostController

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        navController = TestNavHostController(context)
        navController.navigatorProvider.addNavigator(androidx.navigation.compose.ComposeNavigator())
        navController.graph = navController.createGraph(startDestination = "start") {
            composable("start") { }
            composable(
                Routes.AuthorWorks,
                arguments = listOf(Routes.navArgOf("authorName"))
            ) { }
            composable(
                Routes.AccountList,
                arguments = listOf(Routes.navArgOf("listType"))
            ) { }
        }
    }

    @Test
    fun authorNameWithPlusAndSpecialCharactersRoundTripsThroughARealNavController() {
        val authorName = "A+B \"Quoted\" Author/Slash:Colon"
        navController.navigate(Routes.authorWorks(authorName))

        val readBack = Routes.routeArg(navController.currentBackStackEntry!!, "authorName")

        assertEquals(authorName, readBack)
    }

    @Test
    fun accountListCollectionTypeRoundTripsThroughARealNavController() {
        val type = io.github.cidy02.kudos.account.AccountListType.Collection(
            name = "weird:name/with-slash+plus",
            displayTitle = "Title: With a Colon / Slash + Plus"
        )
        navController.navigate(Routes.accountList(NavArgCodecs.encodeAccountListType(type)))

        val encoded = Routes.routeArg(navController.currentBackStackEntry!!, "listType")
        val decoded = encoded?.let(NavArgCodecs::decodeAccountListType)

        assertEquals(type, decoded)
    }
}
