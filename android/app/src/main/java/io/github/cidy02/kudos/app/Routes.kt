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
    const val WorkDetail = "work-detail"
    const val Reader = "reader"
    const val Comments = "comments"
    const val AccountLogin = "account-login"
    const val AccountList = "account-list"
    const val AO3Collections = "ao3-collections"
    const val Settings = "settings"
    const val Backup = "backup"
    const val BrowseFandoms = "browse-fandoms"
    const val BrowseWorks = "browse-works"
    const val WebFallback = "web-fallback"
    const val RecentlyDeleted = "recently-deleted"
    const val ReadingQueues = "reading-queues"
    const val QueueDetail = "queue-detail"
    const val ReadingStatistics = "reading-statistics"
    const val Collections = "collections"
    const val CollectionDetail = "collection-detail"

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
            else -> "Kudos"
        }
    }
}
