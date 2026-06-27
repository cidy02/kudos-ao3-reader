package io.github.cidy02.kudos.app

data class TopLevelDestination(
    val route: String,
    val label: String,
    val iconLabel: String
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
    const val Settings = "settings"
    const val Backup = "backup"
    const val BrowseFandoms = "browse-fandoms"
    const val BrowseWorks = "browse-works"
    const val WebFallback = "web-fallback"

    val topLevelDestinations = listOf(
        TopLevelDestination(Home, "Home", "H"),
        TopLevelDestination(Library, "Library", "L"),
        TopLevelDestination(Browse, "Browse", "B"),
        TopLevelDestination(Account, "Account", "A")
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
            Settings -> "Settings"
            Backup -> "Backup"
            BrowseFandoms -> "Fandoms"
            BrowseWorks -> "Works"
            WebFallback -> "AO3"
            else -> "Kudos"
        }
    }
}
