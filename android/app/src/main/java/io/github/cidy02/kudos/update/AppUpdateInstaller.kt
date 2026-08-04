package io.github.cidy02.kudos.update

import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Handles directing the user to the update by opening the browser.
 * 
 * To comply with Google Play Protect's security policies (which flag apps
 * that download and install APKs via ACTION_VIEW as "bypassing Android's
 * security protections"), this installer simply hands the download off to
 * the user's browser, bypassing the need for REQUEST_INSTALL_PACKAGES.
 */
class AppUpdateInstaller(
    private val appContext: Context
) {
    /** Builds an intent that opens the GitHub release download URL in the browser. */
    fun installIntent(match: AndroidReleaseMatcher.Match): Intent {
        val uri = Uri.parse(match.release.htmlUrl.takeIf { it.isNotBlank() } ?: match.apk.browserDownloadUrl)
        return Intent(Intent.ACTION_VIEW, uri).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }
}
