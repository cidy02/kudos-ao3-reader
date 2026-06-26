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
    const val Settings = "settings"
    const val Backup = "backup"

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
            Settings -> "Settings"
            Backup -> "Backup"
            else -> "Kudos"
        }
    }
}
