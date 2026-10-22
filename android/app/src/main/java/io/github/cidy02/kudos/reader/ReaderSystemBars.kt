package io.github.cidy02.kudos.reader

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

/** Only the resumed reader owns immersion; sheets and screens above it need ordinary bars. */
@Composable
internal fun ReaderSystemBars(chromeVisible: Boolean, overlayVisible: Boolean) {
    val view = LocalView.current
    val window = view.context.readerActivity()?.window ?: return
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val visible by rememberUpdatedState(chromeVisible || overlayVisible)
    if (view.isInEditMode) return

    fun apply() {
        val controller = WindowCompat.getInsetsController(window, view)
        if (visible || !lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
            controller.show(WindowInsetsCompat.Type.systemBars())
        } else {
            controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    DisposableEffect(window, view, lifecycle) {
        val controller = WindowCompat.getInsetsController(window, view)
        val previousBehavior = controller.systemBarsBehavior
        val observer = LifecycleEventObserver { _, _ -> apply() }
        lifecycle.addObserver(observer)
        apply()
        onDispose {
            lifecycle.removeObserver(observer)
            controller.show(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior = previousBehavior
        }
    }
    // Page/progress/speech recompositions must not cut short a transient swipe reveal.
    LaunchedEffect(window, view, lifecycle, chromeVisible, overlayVisible) { apply() }
}

private tailrec fun Context.readerActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.readerActivity()
    else -> null
}
