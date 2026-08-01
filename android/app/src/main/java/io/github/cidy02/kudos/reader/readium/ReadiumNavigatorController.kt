package io.github.cidy02.kudos.reader.readium

import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator

/**
 * Thin handle so Compose chrome (TOC sheet, etc.) can drive the Fragment-based
 * navigator without re-creating it. Attached/detached by [ReadiumNavigatorHost].
 */
class ReadiumNavigatorController {
    @Volatile
    private var navigator: EpubNavigatorFragment? = null

    internal fun attach(fragment: EpubNavigatorFragment?) {
        navigator = fragment
    }

    fun go(locator: Locator, animated: Boolean = true): Boolean =
        navigator?.go(locator, animated) == true

    fun go(link: Link, animated: Boolean = true): Boolean =
        navigator?.go(link, animated) == true
}
