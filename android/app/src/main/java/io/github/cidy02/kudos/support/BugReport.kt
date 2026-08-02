package io.github.cidy02.kudos.support

import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * Opens the same "Report a Bug" mailto flow as Settings → Help & Project.
 * Shared so shake-to-report and the Settings row stay in lockstep.
 */
fun openBugReport(context: Context) {
    val intent = Intent(Intent.ACTION_SENDTO).apply {
        data = Uri.parse("mailto:")
        putExtra(Intent.EXTRA_EMAIL, arrayOf("cidy02@users.noreply.github.com"))
        putExtra(Intent.EXTRA_SUBJECT, "Kudos Android bug report")
    }
    runCatching { context.startActivity(intent) }
}
