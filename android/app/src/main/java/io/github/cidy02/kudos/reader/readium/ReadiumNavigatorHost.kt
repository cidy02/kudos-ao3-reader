package io.github.cidy02.kudos.reader.readium

import android.content.Context
import android.content.ContextWrapper
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.FragmentContainerView
import kotlinx.coroutines.delay
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
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
 *
 * NOTE: actual rendering/lifecycle can only be verified on a device/emulator;
 * this file compiles against the Readium 3.3.0 API but is not exercised by the
 * JVM unit tests (see HANDOFF.md "manual verification").
 */
@Composable
fun ReadiumNavigatorHost(
    publication: Publication,
    initialLocator: Locator?,
    preferences: EpubPreferences,
    onLocatorChanged: (Locator) -> Unit,
    onExternalLink: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val activity = LocalContext.current.findFragmentActivity() ?: return
    val containerId = remember { View.generateViewId() }

    val listener = remember(publication) {
        object : EpubNavigatorFragment.Listener {
            override fun onExternalLinkActivated(url: AbsoluteUrl) {
                onExternalLink(url.toString())
            }
        }
    }

    val fragmentFactory = remember(publication, initialLocator) {
        EpubNavigatorFactory(publication).createFragmentFactory(
            initialLocator = initialLocator,
            initialPreferences = preferences,
            listener = listener
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
            val fragment = fm.findFragmentByTag(FRAGMENT_TAG)
            if (fragment != null && !fm.isStateSaved) {
                fm.beginTransaction().remove(fragment).commitAllowingStateLoss()
            }
        }
    }

    // Wait for the fragment to be instantiated, then observe location updates.
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
        navigator.submitPreferences(preferences)
        navigator.currentLocator.collect { onLocatorChanged(it) }
    }

    // Apply preference changes after the fragment exists.
    LaunchedEffect(preferences) {
        (activity.supportFragmentManager.findFragmentByTag(FRAGMENT_TAG) as? EpubNavigatorFragment)
            ?.submitPreferences(preferences)
    }
}

private const val FRAGMENT_LOOKUP_MAX_TRIES = 40
private const val FRAGMENT_LOOKUP_DELAY_MS = 50L

private tailrec fun Context.findFragmentActivity(): FragmentActivity? = when (this) {
    is FragmentActivity -> this
    is ContextWrapper -> baseContext.findFragmentActivity()
    else -> null
}
