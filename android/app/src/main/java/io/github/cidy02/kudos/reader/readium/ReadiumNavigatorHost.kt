package io.github.cidy02.kudos.reader.readium

import android.content.Context
import android.content.ContextWrapper
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentContainerView
import io.github.cidy02.kudos.reader.settings.CustomFontDeclaration
import kotlinx.coroutines.delay
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
    modifier: Modifier = Modifier,
    controller: ReadiumNavigatorController? = null,
    onContentTap: (() -> Unit)? = null,
    fontDeclarations: List<CustomFontDeclaration> = emptyList(),
    /** Fired once the fragment is attached and ready for decorations/go(). */
    onNavigatorReady: (() -> Unit)? = null
) {
    val activity = LocalContext.current.findFragmentActivity() ?: return
    val containerId = remember { View.generateViewId() }
    val currentOnLocatorChanged by rememberUpdatedState(onLocatorChanged)
    val currentOnExternalLink by rememberUpdatedState(onExternalLink)
    val currentOnContentTap by rememberUpdatedState(onContentTap)
    val currentController by rememberUpdatedState(controller)
    val currentOnNavigatorReady by rememberUpdatedState(onNavigatorReady)

    val listener = remember(publication) {
        object : EpubNavigatorFragment.Listener {
            override fun onExternalLinkActivated(url: AbsoluteUrl) {
                currentOnExternalLink(url.toString())
            }
        }
    }

    val fragmentFactory = remember(publication, initialLocator, fontDeclarations) {
        val configuration = EpubNavigatorFragment.Configuration().apply {
            ReadiumSettingsAdapter.configureFontDeclarations(this, fontDeclarations)
            // Otherwise a vertical scroll gesture in scroll-mode reading can latch as a
            // horizontal drag and fire an accidental chapter change mid-scroll.
            disablePageTurnsWhileScrolling = true
        }
        EpubNavigatorFactory(publication).createFragmentFactory(
            initialLocator = initialLocator,
            initialPreferences = preferences,
            listener = listener,
            configuration = configuration
        )
    }

    AndroidView(
        modifier = modifier,
        factory = { ctx -> FragmentContainerView(ctx).apply { id = containerId } }
    )

    DisposableEffect(fragmentFactory) {
        val fm = activity.supportFragmentManager
        fm.fragmentFactory = fragmentFactory
        if (fm.findFragmentByTag(FRAGMENT_TAG) == null) {
            fm.beginTransaction()
                .setReorderingAllowed(true)
                .add(containerId, EpubNavigatorFragment::class.java, null, FRAGMENT_TAG)
                .commitAllowingStateLoss()
        }
        onDispose {
            currentController?.attach(null)
            val fragment = fm.findFragmentByTag(FRAGMENT_TAG)
            if (fragment != null && !fm.isStateSaved) {
                fm.beginTransaction().remove(fragment).commitAllowingStateLoss()
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
        restoreNativeScrollIndicators(navigator.view)

        val tapListener = object : InputListener {
            override fun onTap(event: TapEvent): Boolean {
                val tap = currentOnContentTap ?: return false
                tap()
                // Chrome toggle only; scroll/pagination already handled by Readium
                // before this listener sees an unhandled content tap.
                return true
            }
        }
        navigator.addInputListener(tapListener)
        try {
            navigator.currentLocator.collect {
                currentOnLocatorChanged(it)
                // R2EpubPageFragment.setupWebView() (internal to Readium, not ours to
                // patch or even reference — it's `internal class`) unconditionally
                // disables the WebView's own scrollbar on every page it creates, with
                // no configuration flag to opt back in. Re-applied on every locator
                // change since Readium recreates the page fragment (and re-disables
                // this) on chapter/page transitions.
                restoreNativeScrollIndicators(navigator.view)
            }
        } finally {
            navigator.removeInputListener(tapListener)
            currentController?.attach(null)
        }
    }

    // Apply preference changes after the fragment exists.
    LaunchedEffect(preferences) {
        (activity.supportFragmentManager.findFragmentByTag(FRAGMENT_TAG) as? EpubNavigatorFragment)
            ?.submitPreferences(preferences)
    }
}

/**
 * A2: undoes `R2EpubPageFragment`'s `isVerticalScrollBarEnabled = false` from the
 * outside using only public `WebView`/`View` API — that class is Kotlin `internal`
 * to Readium's own module, so there's no typed reference to it (or to its
 * `R2WebView`) available here; walking the fragment's view tree for any
 * [WebView] works without needing one. Horizontal stays untouched (Readium
 * leaves it off too): paged mode's horizontal scroll is page-snapped, not a
 * continuous scroll a horizontal bar would meaningfully represent.
 *
 * Also attaches [ViewGroup.OnHierarchyChangeListener] to every container found,
 * so a *brand-new* page's `WebView` — created when Readium swaps chapters,
 * something the locator-change call site alone only catches after the fact —
 * gets fixed the instant it's added, not on the next locator emission. Tracked
 * in a [WeakHashMap] so a container isn't re-listened every call (which would
 * otherwise silently replace its own previous listener — a `ViewGroup` has only
 * one hierarchy-listener slot) and so dead containers don't accumulate forever.
 */
private val hierarchyListenedGroups = java.util.WeakHashMap<ViewGroup, Boolean>()

private fun restoreNativeScrollIndicators(root: View?) {
    if (root == null) return
    if (root is WebView) {
        root.isVerticalScrollBarEnabled = true
    }
    if (root is ViewGroup) {
        if (hierarchyListenedGroups.put(root, true) == null) {
            root.setOnHierarchyChangeListener(object : ViewGroup.OnHierarchyChangeListener {
                override fun onChildViewAdded(parent: View, child: View) {
                    restoreNativeScrollIndicators(child)
                }

                override fun onChildViewRemoved(parent: View, child: View) = Unit
            })
        }
        for (i in 0 until root.childCount) {
            restoreNativeScrollIndicators(root.getChildAt(i))
        }
    }
}

private const val FRAGMENT_LOOKUP_MAX_TRIES = 40
private const val FRAGMENT_LOOKUP_DELAY_MS = 50L

private tailrec fun Context.findFragmentActivity(): FragmentActivity? = when (this) {
    is FragmentActivity -> this
    is ContextWrapper -> baseContext.findFragmentActivity()
    else -> null
}
