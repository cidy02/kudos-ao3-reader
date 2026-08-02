package io.github.cidy02.kudos.update

import java.nio.file.Path

sealed interface AppUpdateState {
    data object Idle : AppUpdateState
    data object Checking : AppUpdateState
    data object UpToDate : AppUpdateState
    data class UpdateAvailable(val match: AndroidReleaseMatcher.Match) : AppUpdateState
    data class Downloading(val match: AndroidReleaseMatcher.Match, val progress: Float) : AppUpdateState
    data class ReadyToInstall(val match: AndroidReleaseMatcher.Match, val apkPath: Path) : AppUpdateState
    data class Failed(val message: String) : AppUpdateState
}
