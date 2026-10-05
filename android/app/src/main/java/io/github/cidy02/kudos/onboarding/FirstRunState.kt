package io.github.cidy02.kudos.onboarding

/** One DataStore emission: never briefly offer sync before its saved flags load. */
data class FirstRunState(
    val welcomeCompleted: Boolean = false,
    val syncConfigured: Boolean = false,
    val syncPermanentlyDismissed: Boolean = false,
    val syncConnected: Boolean = false
) {
    fun showsSync(dismissedThisSession: Boolean): Boolean =
        welcomeCompleted && !syncConfigured && !syncConnected &&
            !syncPermanentlyDismissed && !dismissedThisSession
}

enum class FirstRunDemoScreen { Welcome, SyncOnboarding, WhatsNew, Login }

/** Only debug builds with the existing demo launch extra can open these previews. */
fun firstRunDemoScreen(route: String?, debug: Boolean, demo: Boolean): FirstRunDemoScreen? {
    if (!debug || !demo) return null
    return when (route) {
        "nav:welcome" -> FirstRunDemoScreen.Welcome
        "nav:sync-onboarding" -> FirstRunDemoScreen.SyncOnboarding
        "nav:whats-new" -> FirstRunDemoScreen.WhatsNew
        "nav:login" -> FirstRunDemoScreen.Login
        else -> null
    }
}
