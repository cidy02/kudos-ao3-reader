package io.github.cidy02.kudos.app

import android.content.Context
import androidx.navigation.compose.composable
import androidx.navigation.createGraph
import androidx.navigation.NavType
import androidx.navigation.navArgument
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
            composable(Routes.AO3ChallengeSettings, arguments = listOf(
                Routes.navArgOf("collectionSlug"), Routes.navArgOf("collectionTitle"),
                navArgument("owner") { type = NavType.BoolType; defaultValue = false }
            )) { }
            composable(Routes.AO3CollectionModeration, arguments = listOf(
                Routes.navArgOf("collectionSlug"), Routes.navArgOf("collectionTitle"),
                navArgument("owner") { type = NavType.BoolType; defaultValue = false }
            )) { }
            composable(Routes.AO3CollectionItems, arguments = listOf(
                Routes.navArgOf("collectionSlug"), Routes.navArgOf("collectionTitle"),
                navArgument("tab") { type = NavType.StringType; nullable = true; defaultValue = null }
            )) { }
            composable(Routes.Comments, arguments = listOf(
                Routes.navArgOf("commentWorkId"),
                navArgument("focusedCommentId") { type = NavType.StringType; nullable = true; defaultValue = null },
                navArgument("chapterPosition") { type = NavType.StringType; nullable = true; defaultValue = null },
                navArgument("compose") { type = NavType.BoolType; defaultValue = false }
            )) { }
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

    @Test fun moderationCarriesOwnerAndRecentlyDecidedCarriesApprovedWithoutChangingListDefault() {
        navController.navigate(Routes.ao3CollectionModeration("winter_exchange", "Winter + Letters / 2026", true))
        val moderation = navController.currentBackStackEntry!!
        assertEquals(Routes.AO3CollectionModeration, moderation.destination.route)
        assertEquals("Winter + Letters / 2026", Routes.routeArg(moderation, "collectionTitle"))
        assertEquals(true, moderation.arguments?.getBoolean("owner"))
        assertEquals(true, Routes.hasSubjectHeader(moderation.destination.route))
        assertEquals(true, Routes.hidesTabBar(moderation.destination.route))
        navController.navigate(Routes.ao3CollectionItems("winter_exchange", "Winter + Letters / 2026", "approved"))
        assertEquals("approved", Routes.routeArg(navController.currentBackStackEntry!!, "tab"))
        navController.navigate(Routes.ao3CollectionItems("winter_exchange", "Winter + Letters / 2026"))
        assertEquals(null, Routes.routeArg(navController.currentBackStackEntry!!, "tab"))
    }

    @Test fun challengeSettingsArgumentsRoundTripWithOwnerAndSubjectChrome() {
        navController.navigate(Routes.ao3ChallengeSettings("snow/letters", "Winter + Letters / 2026", true))
        val entry = navController.currentBackStackEntry!!
        assertEquals(Routes.AO3ChallengeSettings, entry.destination.route)
        assertEquals("snow/letters", Routes.routeArg(entry, "collectionSlug"))
        assertEquals("Winter + Letters / 2026", Routes.routeArg(entry, "collectionTitle"))
        assertEquals(true, entry.arguments?.getBoolean("owner"))
        assertEquals("Challenge", Routes.titleFor(entry.destination.route))
        assertEquals(true, Routes.hasSubjectHeader(entry.destination.route))
        assertEquals(true, Routes.hidesTabBar(entry.destination.route))
    }

    @Test fun messageCreatorOpensNativeCommentsWithComposerRequested() {
        navController.navigate(Routes.comments(123, composes = true))
        assertEquals("123", Routes.routeArg(navController.currentBackStackEntry!!, "commentWorkId"))
        assertEquals(true, navController.currentBackStackEntry!!.arguments?.getBoolean("compose"))
        navController.navigate(Routes.comments(124))
        assertEquals(false, navController.currentBackStackEntry!!.arguments?.getBoolean("compose"))
    }
}
