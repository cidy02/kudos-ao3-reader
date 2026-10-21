package io.github.cidy02.kudos.reader.readium

import android.content.Context
import android.content.ContextWrapper
import android.view.View
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentContainerView
import io.github.cidy02.kudos.reader.settings.CustomFontDeclaration
import io.github.cidy02.kudos.reader.ReaderViewport
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.preferences.ReadingProgression
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.input.InputListener
import org.readium.r2.navigator.input.TapEvent
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl

private const val FRAGMENT_TAG = "kudos-epub-navigator"

/**
 * Compose owns the reader's fragment and adds it again when the reader is drawn. Android also
 * rebuilds an activity's fragments itself after a restart, and Readium's has no empty
 * constructor: with a work open the app crashed when the activity was recreated, and when the
 * reader came back to it after its process had been killed. Readium's dummy stands in for the
 * rebuild and is removed before it is ever shown.
 */
internal object ReaderFragmentRestore {
    /** Ahead of `super.onCreate`, which is where the fragments are rebuilt. */
    fun before(activity: androidx.fragment.app.FragmentActivity) {
        activity.supportFragmentManager.fragmentFactory = EpubNavigatorFragment.createDummyFactory()
    }

    /** Straight after `super.onCreate`. */
    fun after(activity: androidx.fragment.app.FragmentActivity, savedInstanceState: android.os.Bundle?) {
        val fm = activity.supportFragmentManager
        val rebuilt = fm.fragments
        if (savedInstanceState == null || rebuilt.isEmpty()) return
        fm.beginTransaction().apply { rebuilt.forEach { remove(it) } }.commitNowAllowingStateLoss()
    }
}

/**
 * Hosts Readium's Fragment-based [EpubNavigatorFragment] inside Compose.
 *
 * Readium's navigator is View/Fragment-based (its reflowable EPUB navigator uses
 * a WebView internally), so this is the single Compose↔Fragment interop seam. It
 * requires a [FragmentActivity] host (see MainActivity). Location changes are
 * forwarded to [onLocatorChanged]; external links go to [onExternalLink].
 * Content taps call [onContentTap] (immersive chrome toggle). [controller]
 * exposes go() for TOC jumps.
 *
 * NOTE: actual rendering/lifecycle can only be verified on a device/emulator;
 * this file compiles against the Readium 3.3.0 API but is not exercised by the
 * JVM unit tests (see HANDOFF.md "manual verification").
 */
@OptIn(ExperimentalReadiumApi::class)
@Composable
fun ReadiumNavigatorHost(
    publication: Publication,
    initialLocator: Locator?,
    preferences: EpubPreferences,
    onLocatorChanged: (Locator) -> Unit,
    onExternalLink: (String) -> Unit,
    onHighlightSelection: (() -> Unit) -> Unit,
    onAddNoteSelection: (() -> Unit) -> Unit,
    onHighlightTap: (String) -> Unit,
    onViewportChanged: (ReaderViewport?) -> Unit,
    modifier: Modifier = Modifier,
    controller: ReadiumNavigatorController? = null,
    onContentTap: (() -> Unit)? = null,
    fontDeclarations: List<CustomFontDeclaration> = emptyList(),
    /** Fired once the fragment is attached and ready for decorations/go(). */
    onNavigatorReady: (() -> Unit)? = null,
    onFixPronunciationSelection: (() -> Unit) -> Unit = { complete -> complete() }
) {
    val activity = LocalContext.current.findFragmentActivity() ?: return
    val containerId = remember { View.generateViewId() }
    val currentOnLocatorChanged by rememberUpdatedState(onLocatorChanged)
    val currentOnExternalLink by rememberUpdatedState(onExternalLink)
    val currentOnContentTap by rememberUpdatedState(onContentTap)
    val currentOnHighlightTap by rememberUpdatedState(onHighlightTap)
    val currentOnHighlightSelection by rememberUpdatedState(onHighlightSelection)
    val currentOnAddNoteSelection by rememberUpdatedState(onAddNoteSelection)
    val currentOnFixPronunciationSelection by rememberUpdatedState(onFixPronunciationSelection)
    val currentController by rememberUpdatedState(controller)
    val currentOnNavigatorReady by rememberUpdatedState(onNavigatorReady)
    val currentOnViewportChanged by rememberUpdatedState(onViewportChanged)
    val scope = rememberCoroutineScope()
    var viewportJob by remember(publication) { mutableStateOf<Job?>(null) }

    val listener = remember(publication) {
        object : EpubNavigatorFragment.Listener {
            override fun onExternalLinkActivated(url: AbsoluteUrl) {
                currentOnExternalLink(url.toString())
            }
        }
    }

    val paginationListener = remember(publication) {
        object : EpubNavigatorFragment.PaginationListener {
            override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
                viewportJob?.cancel()
                val nav = activity.supportFragmentManager.findFragmentByTag(FRAGMENT_TAG)
                    as? EpubNavigatorFragment ?: return
                val settings = nav.settings.value
                val index = ReadiumProgressAdapter.spineIndex(publication, locator)
                currentOnLocatorChanged(locator)
                if (!settings.scroll) {
                    val page = if (settings.readingProgression == ReadingProgression.RTL)
                        totalPages - pageIndex else pageIndex + 1
                    currentOnViewportChanged(ReaderViewport(index, page, totalPages))
                    return
                }
                // PaginationListener's horizontal count is not a scrolled page count.
                // Read the loaded current resource's scroll extent, never a book percent.
                viewportJob = scope.launch {
                    val raw = nav.evaluateJavascript(SCROLL_EXTENT_SCRIPT) ?: return@launch
                    if (nav.currentLocator.value != locator || nav.settings.value != settings) return@launch
                    val metrics = runCatching { JSONObject(raw) }.getOrNull() ?: return@launch
                    currentOnViewportChanged(ReaderViewport.scrolled(
                        index, metrics.optDouble("offset"), metrics.optDouble("extent"), metrics.optDouble("range")
                    ))
                }
            }
        }
    }

    val fragmentFactory = remember(publication, initialLocator, fontDeclarations) {
        val configuration = EpubNavigatorFragment.Configuration().apply {
            ReadiumSettingsAdapter.configureFontDeclarations(this, fontDeclarations)
        }
        EpubNavigatorFactory(publication).createFragmentFactory(
            // New imported fonts need new declarations, without returning to the opening page.
            initialLocator = controller?.currentLocator ?: initialLocator,
            initialPreferences = preferences,
            listener = listener,
            paginationListener = paginationListener,
            configuration = configuration
        )
    }

    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            ReaderSelectionContainer(
                ctx,
                onHighlight = { complete -> currentOnHighlightSelection(complete) },
                onAddNote = { complete -> currentOnAddNoteSelection(complete) },
                onFixPronunciation = { complete -> currentOnFixPronunciationSelection(complete) }
            ).apply {
                addView(
                    FragmentContainerView(ctx).apply { id = containerId },
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                )
            }
        }
    )

    DisposableEffect(fragmentFactory) {
        val fm = activity.supportFragmentManager
        fm.fragmentFactory = fragmentFactory
        if (fm.findFragmentByTag(FRAGMENT_TAG) == null) {
            fm.beginTransaction()
                .setReorderingAllowed(true)
                .add(containerId, EpubNavigatorFragment::class.java, null, FRAGMENT_TAG)
                .commitNowAllowingStateLoss()
        }
        onDispose {
            viewportJob?.cancel()
            currentController?.attach(null)
            val fragment = fm.findFragmentByTag(FRAGMENT_TAG)
            if (fragment != null && !fm.isDestroyed) {
                // Finish removal before a changed font factory mounts its replacement.
                fm.beginTransaction().remove(fragment).commitNowAllowingStateLoss()
            }
        }
    }

    // Wait for the fragment to be instantiated, then observe location updates + taps.
    LaunchedEffect(fragmentFactory) {
        val fm = activity.supportFragmentManager
        var fragment = fm.findFragmentByTag(FRAGMENT_TAG) as? EpubNavigatorFragment
        var tries = 0
        while (fragment == null && tries < FRAGMENT_LOOKUP_MAX_TRIES) {
            delay(FRAGMENT_LOOKUP_DELAY_MS)
            tries++
            fragment = fm.findFragmentByTag(FRAGMENT_TAG) as? EpubNavigatorFragment
        }
        val navigator = fragment ?: return@LaunchedEffect
        currentController?.attach(navigator)
        navigator.submitPreferences(preferences)
        currentOnNavigatorReady?.invoke()

        val tapListener = object : InputListener {
            override fun onTap(event: TapEvent): Boolean {
                val tap = currentOnContentTap ?: return false
                tap()
                // Chrome toggle only; scroll/pagination already handled by Readium
                // before this listener sees an unhandled content tap.
                return true
            }
        }
        val highlightListener = ReaderHighlightDecorationListener { currentOnHighlightTap(it) }
        navigator.addDecorationListener(
            ReadiumNavigatorController.DECORATION_GROUP_HIGHLIGHTS, highlightListener
        )
        navigator.addInputListener(tapListener)
        try {
            navigator.currentLocator.collect { currentOnLocatorChanged(it) }
        } finally {
            navigator.removeDecorationListener(highlightListener)
            navigator.removeInputListener(tapListener)
            currentController?.attach(null)
        }
    }

    // Apply preference changes after the fragment exists.
    LaunchedEffect(preferences) {
        currentOnViewportChanged(null)
        (activity.supportFragmentManager.findFragmentByTag(FRAGMENT_TAG) as? EpubNavigatorFragment)
            ?.submitPreferences(preferences)
    }
}

/** Same scrolling element/axes used by Readium's bundled scrollToPosition. No network. */
internal val SCROLL_EXTENT_SCRIPT = """
    (function() {
        var e = document.scrollingElement;
        if (!e || document.readyState !== 'complete' || !document.body || !document.body.firstChild ||
            (window.innerWidth || 0) < 32 || (window.innerHeight || 0) < 32) return null;
        var vertical = getComputedStyle(document.documentElement).writingMode.startsWith('vertical');
        return vertical
            ? {offset: Math.abs(e.scrollLeft), extent: e.clientWidth, range: e.scrollWidth}
            : {offset: e.scrollTop, extent: e.clientHeight, range: e.scrollHeight};
    })();
""".trimIndent()

private const val FRAGMENT_LOOKUP_MAX_TRIES = 40
private const val FRAGMENT_LOOKUP_DELAY_MS = 50L

private tailrec fun Context.findFragmentActivity(): FragmentActivity? = when (this) {
    is FragmentActivity -> this
    is ContextWrapper -> baseContext.findFragmentActivity()
    else -> null
}
