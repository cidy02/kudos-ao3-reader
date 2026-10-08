package io.github.cidy02.kudos.reader.readium

import android.graphics.Color
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.Selection
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator

/**
 * Thin handle so Compose chrome can drive the Fragment-based navigator without
 * re-creating it. Attached/detached by [ReadiumNavigatorHost].
 */
@OptIn(ExperimentalReadiumApi::class)
class ReadiumNavigatorController {
    @Volatile
    private var navigator: EpubNavigatorFragment? = null
    private var pendingScrub: Locator? = null
    private var scrubInFlight = false

    internal fun attach(fragment: EpubNavigatorFragment?) {
        navigator = fragment
        pendingScrub = null
    }

    /** Readium's own resource-local scroll function; at most one evaluation in flight. */
    suspend fun scrubTo(target: Locator) {
        pendingScrub = target
        if (scrubInFlight) return
        scrubInFlight = true
        try {
            while (true) {
                val next = pendingScrub ?: break
                pendingScrub = null
                val nav = navigator ?: break
                if (!nav.currentLocator.value.href.isEquivalent(next.href)) continue
                val progression = next.locations.progression ?: continue
                nav.evaluateJavascript("readium.scrollToPosition($progression);")
            }
        } finally {
            scrubInFlight = false
        }
    }

    fun go(locator: Locator, animated: Boolean = true): Boolean =
        navigator?.go(locator, animated) == true

    fun go(link: Link, animated: Boolean = true): Boolean =
        navigator?.go(link, animated) == true

    fun goForward(animated: Boolean = true): Boolean =
        navigator?.goForward(animated) == true

    fun goBackward(animated: Boolean = true): Boolean =
        navigator?.goBackward(animated) == true

    suspend fun currentSelection(): Selection? {
        val nav = navigator ?: return null
        return nav.currentSelection()
    }

    fun clearSelection() {
        navigator?.clearSelection()
    }

    /**
     * Applies highlight decorations for the given annotations (group "highlights").
     * Bookmarks are intentionally omitted — they live in the TOC list, not as
     * underlines in the page (matching the iOS split).
     */
    suspend fun applyHighlightDecorations(highlights: List<ReadingAnnotation>) {
        val nav = navigator ?: return
        val decorations = highlights.mapNotNull { annotation ->
            val locator = locatorFromJson(annotation.locatorString) ?: return@mapNotNull null
            val tint = colorForName(annotation.colorRaw)
            Decoration(
                id = annotation.id,
                locator = locator,
                style = if (annotation.colorRaw.equals("underline", ignoreCase = true)) {
                    Decoration.Style.Underline(tint = tint, isActive = false)
                } else {
                    Decoration.Style.Highlight(tint = tint, isActive = false)
                }
            )
        }
        withContext(Dispatchers.Main) {
            nav.applyDecorations(decorations, group = DECORATION_GROUP_HIGHLIGHTS)
        }
    }

    companion object {
        const val DECORATION_GROUP_HIGHLIGHTS = "highlights"

        /**
         * Parse a stored locator only when it is an Android-compatible envelope.
         * Foreign (e.g. iOS bare) locators return null so callers skip navigation —
         * matching iOS which discards annotations it cannot rebuild
         * (`Locator(persistenceString:)` → nil).
         */
        fun locatorFromJson(raw: String): Locator? {
            if (raw.isBlank()) return null
            // Do not fall back to parsing [raw] as a bare Readium locator: an
            // iOS-written bare locator shares the same schema and would navigate
            // into a foreign pagination position.
            val decoded = io.github.cidy02.kudos.reader.ReaderLocatorCodec
                .decodeCompatibleLocator(raw) ?: return null
            return runCatching {
                Locator.fromJSON(org.json.JSONObject(decoded))
            }.getOrNull()
        }

        fun colorForName(name: String): Int {
            return when (name.lowercase()) {
                "green" -> Color.parseColor("#81C784")
                "pink" -> Color.parseColor("#F48FB1")
                "purple" -> Color.parseColor("#CE93D8")
                "blue" -> Color.parseColor("#64B5F6")
                "orange" -> Color.parseColor("#FFB74D")
                "underline" -> Color.rgb(89, 140, 242)
                else -> Color.parseColor("#FFF59D") // yellow default
            }
        }
    }
}
