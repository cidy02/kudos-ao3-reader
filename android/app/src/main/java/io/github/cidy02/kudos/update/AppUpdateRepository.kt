package io.github.cidy02.kudos.update

import android.content.Intent
import io.github.cidy02.kudos.network.github.GitHubReleaseClient
import java.nio.file.Path
import java.time.Duration
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Orchestrates the GitHub-releases update check: fetch → match → (optionally)
 * download → ready-to-install, publishing [state] for the Settings UI and
 * driving the launch-time auto-check.
 */
class AppUpdateRepository(
    private val releaseClient: GitHubReleaseClient,
    private val installer: AppUpdateInstaller,
    private val notifier: AppUpdateNotifier,
    private val preferences: AppUpdatePreferences,
    private val currentVersion: AppVersion,
    private val clock: () -> Long = { System.currentTimeMillis() }
) {
    private val mutableState = MutableStateFlow<AppUpdateState>(AppUpdateState.Idle)
    val state: StateFlow<AppUpdateState> = mutableState.asStateFlow()

    /** Runs [checkNow] only if it hasn't run within [minInterval] — the launch-time entry point. */
    suspend fun checkIfDue(minInterval: Duration = Duration.ofHours(24)) {
        val last = preferences.lastCheckedAtMillis()
        val now = clock()
        if (last != null && (now - last) < minInterval.toMillis()) return
        checkNow(autoDownload = true)
    }

    /** Explicit user-triggered check (Settings "Check Now"), always runs. */
    suspend fun checkNow(autoDownload: Boolean): AppUpdateState {
        mutableState.value = AppUpdateState.Checking
        val result = try {
            val releases = releaseClient.fetchReleases()
            preferences.setLastCheckedAtMillis(clock())
            when (val match = AndroidReleaseMatcher.latest(releases)) {
                null -> AppUpdateState.UpToDate
                else -> if (match.version > currentVersion) {
                    AppUpdateState.UpdateAvailable(match)
                } else {
                    AppUpdateState.UpToDate
                }
            }
        } catch (error: Exception) {
            AppUpdateState.Failed(error.message ?: "Couldn't check for updates.")
        }
        mutableState.value = result

        if (autoDownload && result is AppUpdateState.UpdateAvailable) {
            downloadAndPrepareInstall(result.match)
        }
        return mutableState.value
    }

    /** Downloads [match]'s APK and, on success, posts the ready-to-install notification. */
    suspend fun downloadAndPrepareInstall(match: AndroidReleaseMatcher.Match) {
        mutableState.value = AppUpdateState.Downloading(match, 0f)
        try {
            val path = installer.download(match.apk) { progress ->
                mutableState.value = AppUpdateState.Downloading(match, progress)
            }
            mutableState.value = AppUpdateState.ReadyToInstall(match, path)
            notifier.notifyUpdateReady(match.version.toString(), installer.installIntent(path))
        } catch (error: Exception) {
            mutableState.value = AppUpdateState.Failed(error.message ?: "Couldn't download the update.")
        }
    }

    fun installIntentFor(apkPath: Path): Intent = installer.installIntent(apkPath)
}
