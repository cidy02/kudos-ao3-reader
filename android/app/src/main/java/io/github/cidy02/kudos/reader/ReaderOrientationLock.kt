package io.github.cidy02.kudos.reader

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.hardware.display.DisplayManager
import android.os.Build
import android.util.DisplayMetrics
import android.view.Display
import android.view.Surface
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ScreenLockRotation
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Concrete orientation persisted by the reader's Rotation Lock (device-local; never in backups
 * or folder sync). Stores a concrete direction rather than
 * [ActivityInfo.SCREEN_ORIENTATION_LOCKED], so re-entering the reader pins the direction the
 * user locked instead of following however the device happens to be held on open.
 */
enum class ReaderLockedOrientation(
    val storageValue: String,
    val activityInfoOrientation: Int
) {
    Portrait("portrait", ActivityInfo.SCREEN_ORIENTATION_PORTRAIT),
    Landscape("landscape", ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE),
    ReversePortrait("reversePortrait", ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT),
    ReverseLandscape("reverseLandscape", ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE);

    companion object {
        fun fromStorage(value: String?): ReaderLockedOrientation? =
            entries.firstOrNull { it.storageValue == value }

        /**
         * Derives the concrete orientation from the display [rotation] (`Surface.ROTATION_*`)
         * and whether the display is currently landscape ([displayIsLandscape]).
         *
         * Handles both portrait-natural phones (`ROTATION_0` = portrait, `ROTATION_90` =
         * landscape) and landscape-natural tablets (`ROTATION_0` = landscape, `ROTATION_270` =
         * portrait).
         */
        fun fromDisplay(rotation: Int, displayIsLandscape: Boolean): ReaderLockedOrientation =
            if (displayIsLandscape) {
                when (rotation) {
                    Surface.ROTATION_0, Surface.ROTATION_90 -> Landscape
                    Surface.ROTATION_180, Surface.ROTATION_270 -> ReverseLandscape
                    else -> Landscape
                }
            } else {
                when (rotation) {
                    Surface.ROTATION_0, Surface.ROTATION_270 -> Portrait
                    Surface.ROTATION_90, Surface.ROTATION_180 -> ReversePortrait
                    else -> Portrait
                }
            }

        fun currentOf(activity: Activity): ReaderLockedOrientation =
            fromDisplay(displayRotationOf(activity), isDisplayLandscape(activity))
    }
}

private data class LoadedOrientationLock(val orientation: ReaderLockedOrientation?)

/**
 * The reader that last took the screen. Only it may free the orientation: opening the next work
 * starts the new reader before the old one stops and leaves the composition, and the old one's
 * STOP/dispose must not unpin the new one (iOS BUG-13 review). Main thread only.
 */
private object ReaderOrientationOwner {
    var current: Any? = null
}

internal data class ReaderOrientationLockState(
    val lockedOrientation: ReaderLockedOrientation?,
    val loaded: Boolean,
    val onToggle: () -> Unit
) {
    val isLocked: Boolean get() = lockedOrientation != null
}

/**
 * Applies the saved device-local rotation lock while the reader is on screen, restores
 * [ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED] when the reader leaves or stops without
 * clearing the saved setting, and returns the button state + toggle callback for the fan menu.
 */
@Composable
internal fun rememberReaderOrientationLock(
    repository: SettingsRepository
): ReaderOrientationLockState {
    val view = LocalView.current
    val context = LocalContext.current
    val activity = remember(context) { context.findOrientationActivity() }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val scope = rememberCoroutineScope()
    val loadedLock by remember(repository) {
        repository.readerOrientationLock.map { LoadedOrientationLock(it) }
    }.collectAsState(initial = null)
    val loaded = loadedLock != null
    val lockedOrientation = loadedLock?.orientation

    val currentLoaded by rememberUpdatedState(loaded)
    val currentLocked by rememberUpdatedState(lockedOrientation)
    val currentActivity by rememberUpdatedState(activity)
    val token = remember { Any() }

    if (!view.isInEditMode && activity != null) {
        fun applyOrientation() {
            if (!currentLoaded) return
            if (lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                ReaderOrientationOwner.current = token
                activity.requestedOrientation = currentLocked?.activityInfoOrientation
                    ?: ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            } else if (ReaderOrientationOwner.current === token) {
                activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            }
        }

        DisposableEffect(activity, lifecycle) {
            val observer = LifecycleEventObserver { _, _ -> applyOrientation() }
            lifecycle.addObserver(observer)
            applyOrientation()
            onDispose {
                lifecycle.removeObserver(observer)
                if (ReaderOrientationOwner.current === token) {
                    ReaderOrientationOwner.current = null
                    activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
            }
        }
        LaunchedEffect(activity, lifecycle, loaded, lockedOrientation) {
            applyOrientation()
        }
    }

    val onToggle: () -> Unit = remember(repository, scope) {
        {
            if (currentLoaded) {
                val target = if (currentLocked != null) {
                    null
                } else {
                    currentActivity?.let(ReaderLockedOrientation::currentOf)
                }
                if (currentLocked != null || target != null) {
                    // Undispatched + NonCancellable so toggling right before leaving the
                    // reader still commits to DataStore.
                    scope.launch(start = CoroutineStart.UNDISPATCHED) {
                        withContext(NonCancellable) {
                            repository.updateReaderOrientationLock(target)
                        }
                    }
                }
            }
        }
    }

    return ReaderOrientationLockState(
        lockedOrientation = lockedOrientation,
        loaded = loaded,
        onToggle = onToggle
    )
}

internal fun readerRotationLockAction(
    state: ReaderOrientationLockState
): ReaderFanRoundAction = ReaderFanRoundAction(
    id = "rotationLock",
    icon = if (state.isLocked) Icons.Filled.ScreenLockRotation else Icons.Filled.ScreenRotation,
    accessibilityLabel = if (state.isLocked) "Unlock rotation" else "Lock rotation",
    isEnabled = state.loaded,
    isEmphasized = state.isLocked,
    action = state.onToggle
)

private fun displayRotationOf(activity: Activity): Int {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val activityDisplay = runCatching { activity.display }.getOrNull()
        if (activityDisplay != null) return activityDisplay.rotation
        val defaultDisplay = activity.getSystemService(DisplayManager::class.java)
            ?.getDisplay(Display.DEFAULT_DISPLAY)
        if (defaultDisplay != null) return defaultDisplay.rotation
        return Surface.ROTATION_0
    }
    @Suppress("DEPRECATION")
    return activity.windowManager.defaultDisplay?.rotation ?: Surface.ROTATION_0
}

private fun isDisplayLandscape(activity: Activity): Boolean {
    val (width, height) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val bounds = activity.windowManager.maximumWindowMetrics.bounds
        bounds.width() to bounds.height()
    } else {
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        activity.windowManager.defaultDisplay?.getRealMetrics(metrics)
        metrics.widthPixels to metrics.heightPixels
    }
    return when {
        width > 0 && height > 0 && width != height -> width > height
        else -> activity.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
    }
}

private tailrec fun Context.findOrientationActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findOrientationActivity()
    else -> null
}
