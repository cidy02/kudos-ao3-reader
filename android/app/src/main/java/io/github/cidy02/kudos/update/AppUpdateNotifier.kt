package io.github.cidy02.kudos.update

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Best-effort "your update is ready" notification. Never requests the
 * POST_NOTIFICATIONS permission itself (that needs an Activity to launch the
 * system prompt — see [AppUpdateViewModel]/callers) — if permission isn't
 * granted, posting is silently skipped. The Settings screen is always the
 * reliable fallback surface regardless of notification state.
 */
class AppUpdateNotifier(private val appContext: Context) {
    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = appContext.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "App updates",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Lets you know when a new Kudos version is ready to install."
        }
        manager.createNotificationChannel(channel)
    }

    fun notifyUpdateReady(versionLabel: String, installIntent: Intent) {
        if (!NotificationManagerCompat.from(appContext).areNotificationsEnabled()) return
        ensureChannel()

        val pendingIntent = PendingIntent.getActivity(
            appContext,
            REQUEST_CODE_INSTALL,
            installIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Kudos update ready")
            .setContentText("Version $versionLabel is available — tap to download and install.")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        runCatching {
            NotificationManagerCompat.from(appContext).notify(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val CHANNEL_ID = "app_updates"
        private const val NOTIFICATION_ID = 1001
        private const val REQUEST_CODE_INSTALL = 2001
    }
}
