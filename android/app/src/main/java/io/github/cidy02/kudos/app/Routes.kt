package io.github.cidy02.kudos.app

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavType
import androidx.navigation.navArgument
import java.net.URLEncoder

data class TopLevelDestination(
    val route: String,
    val label: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
)

object Routes {
    const val Home = "home"
    const val Library = "library"
    const val Browse = "browse"
    const val Account = "account"
    const val Search = "search"
    const val AccountLogin = "account-login"
    const val AO3Collections = "ao3-collections"
    const val Settings = "settings"
    const val Backup = "backup"
    const val RecentlyDeleted = "recently-deleted"
    const val ReadingQueues = "reading-queues"
    const val ReadingStatistics = "reading-statistics"
    const val Collections = "collections"
    const val AO3Dashboard = "ao3-dashboard"
    const val LocalHistory = "local-history"
    const val LocalFavorites = "local-favorites"
    const val About = "about"
    const val NativeLogin = "native-login"
    const val AO3Preferences = "ao3-preferences"
    const val BugReport = "bug-report"

    // --- Routes carrying a per-back-stack-entry argument (T-90) ---
    //
    // Each of these used to be a shared mutable Compose var in AppNavHost that every
    // instance of the route read from - so navigating to the same route twice with
    // different content, then pressing Back through both entries, showed the wrong
    // (most recently set) content on the older entry. The var is gone; the value now
    // travels as a real navigation argument, tied to that specific back-stack entry.
    // AndroidX Navigation's own string-route matching already percent-decodes a path
    // segment once when it populates NavBackStackEntry.arguments (confirmed empirically
    // in RoutesNavigationTest, not just assumed) - so encode() must only run on the way
    // IN, and routeArg() must NOT decode again on the way out, or a literal '+'/':' gets
    // silently corrupted by a second decode pass. URLEncoder's own '+'-for-space form
    // encoding is also wrong here for the same reason (Navigation's decode is
    // percent-only, not form-encoding-aware) - normalize '+' to '%20' after encoding so
    // the single decode pass Navigation performs is standard percent-decoding, not form
    // decoding.
    private fun encode(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    private const val ARG_WORK_SOURCE = "workSource"
    const val WorkDetail = "work-detail/{$ARG_WORK_SOURCE}"
    fun workDetail(encodedSource: String) = "work-detail/${encode(encodedSource)}"

    private const val ARG_READER_WORK_ID = "workId"
    const val Reader = "reader/{$ARG_READER_WORK_ID}"
    fun reader(workId: String) = "reader/${encode(workId)}"

    private const val ARG_COMMENT_WORK_ID = "commentWorkId"
    private const val ARG_COMMENT_FOCUSED_ID = "focusedCommentId"
    const val Comments = "comments/{$ARG_COMMENT_WORK_ID}?focused={$ARG_COMMENT_FOCUSED_ID}"
    fun comments(workId: Long, focusedCommentId: Long? = null) = 
        "comments/$workId" + (focusedCommentId?.let { "?focused=$it" } ?: "")

    private const val ARG_HOME_SECTION = "homeSection"
    const val HomeSection = "home-section/{$ARG_HOME_SECTION}"
    fun homeSection(sectionId: String) = "home-section/${encode(sectionId)}"

    private const val ARG_ACCOUNT_LIST_TYPE = "listType"
    const val AccountList = "account-list/{$ARG_ACCOUNT_LIST_TYPE}"
    fun accountList(encodedType: String) = "account-list/${encode(encodedType)}"

    private const val ARG_CATEGORY_NAME = "categoryName"
    private const val ARG_CATEGORY_FANDOMS_PATH = "categoryFandomsPath"
    const val BrowseFandoms = "browse-fandoms/{$ARG_CATEGORY_NAME}/{$ARG_CATEGORY_FANDOMS_PATH}"
    fun browseFandoms(name: String, fandomsPath: String) =
        "browse-fandoms/${encode(name)}/${encode(fandomsPath)}"

    private const val ARG_FANDOM_NAME = "fandomName"
    const val BrowseWorks = "browse-works/{$ARG_FANDOM_NAME}"
    fun browseWorks(fandomName: String) = "browse-works/${encode(fandomName)}"

    private const val ARG_WEB_URL = "url"
    const val WebFallback = "web-fallback/{$ARG_WEB_URL}"
    fun webFallback(url: String) = "web-fallback/${encode(url)}"

    private const val ARG_QUEUE_ID = "queueId"
    const val QueueDetail = "queue-detail/{$ARG_QUEUE_ID}"
    fun queueDetail(queueId: String) = "queue-detail/${encode(queueId)}"

    private const val ARG_COLLECTION_ID = "collectionId"
    const val CollectionDetail = "collection-detail/{$ARG_COLLECTION_ID}"
    fun collectionDetail(collectionId: String) = "collection-detail/${encode(collectionId)}"

    private const val ARG_AUTHOR_NAME = "authorName"
    const val AuthorWorks = "author-works/{$ARG_AUTHOR_NAME}"
    fun authorWorks(authorName: String) = "author-works/${encode(authorName)}"

    private const val ARG_AUTHOR_USERNAME = "authorUsername"
    const val AuthorProfile = "author-profile/{$ARG_AUTHOR_USERNAME}"
    fun authorProfile(username: String) = "author-profile/${encode(username)}"

    private const val ARG_TAG_NAME = "tagName"
    const val TagWorks = "tag-works/{$ARG_TAG_NAME}"
    fun tagWorks(tagName: String) = "tag-works/${encode(tagName)}"

    fun routeArg(entry: NavBackStackEntry, name: String): String? =
        entry.arguments?.getString(name)

    fun navArgOf(name: String) = navArgument(name) { type = NavType.StringType }

    val topLevelDestinations = listOf(
        TopLevelDestination(
            route = Home,
            label = "Home",
            selectedIcon = Icons.Filled.Home,
            unselectedIcon = Icons.Outlined.Home
        ),
        TopLevelDestination(
            route = Library,
            label = "Library",
            selectedIcon = Icons.AutoMirrored.Filled.MenuBook,
            unselectedIcon = Icons.AutoMirrored.Outlined.MenuBook
        ),
        TopLevelDestination(
            route = Browse,
            label = "Browse",
            selectedIcon = Icons.Filled.Explore,
            unselectedIcon = Icons.Outlined.Explore
        ),
        TopLevelDestination(
            route = Account,
            label = "Account",
            selectedIcon = Icons.Filled.Person,
            unselectedIcon = Icons.Outlined.Person
        )
    )

    fun titleFor(route: String?): String {
        return when (route) {
            Home -> "Kudos"
            Library -> "Library"
            Browse -> "Browse"
            Account -> "Account"
            Search -> "Search"
            WorkDetail -> "Work"
            Reader -> "Reader"
            Comments -> "Comments"
            AccountLogin -> "AO3 Login"
            AccountList -> "Account List"
            AO3Collections -> "My Collections"
            Settings -> "Settings"
            Backup -> "Backup"
            BrowseFandoms -> "Fandoms"
            BrowseWorks -> "Works"
            WebFallback -> "AO3"
            RecentlyDeleted -> "Recently Deleted"
            ReadingQueues -> "Reading Queues"
            QueueDetail -> "Queue"
            ReadingStatistics -> "Reading Insights"
            Collections -> "Collections"
            CollectionDetail -> "Collection"
            AuthorWorks -> "Author"
            AuthorProfile -> "Author"
            TagWorks -> "Works"
            AO3Dashboard -> "My Dashboard"
            LocalHistory -> "Reading History"
            LocalFavorites -> "Favorites"
            About -> "About"
            NativeLogin -> "Sign In"
            AO3Preferences -> "AO3 Preferences"
            HomeSection -> "Section"
            BugReport -> "Report a Bug"
            else -> "Kudos"
        }
    }

    fun isTopLevel(route: String?): Boolean =
        topLevelDestinations.any { it.route == route }
}
