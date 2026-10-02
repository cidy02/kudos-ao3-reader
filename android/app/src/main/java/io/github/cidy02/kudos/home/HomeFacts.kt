package io.github.cidy02.kudos.home

import androidx.compose.ui.graphics.Color
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.library.LibraryDisplayItem
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.hsb
import io.github.cidy02.kudos.ui.subject.withOpacity
import java.time.Duration
import java.time.Instant
import java.util.Locale
import kotlin.math.round
import kotlin.math.roundToInt

/**
 * Pure Home decisions ported from iOS so the screen and the tests share one
 * implementation: cover hue, queue footer, collection order, subscription copy.
 */

/** One `showsOnHome` collection and the works that belong on its shelf. */
data class HomeCollectionShelf(
    val id: String,
    val name: String,
    val works: List<LibraryDisplayItem>
)

/** Finished / in progress / unread counts for a queue card's strip. */
data class HomeQueueProgress(
    val finished: Int = 0,
    val inProgress: Int = 0,
    val unread: Int = 0
) {
    val total: Int get() = finished + inProgress + unread
}

/** `#RRGGBB` or `#AARRGGBB` parsed to 0–255 channels. Null when the string is not a colour. */
data class ParsedHex(val red: Int, val green: Int, val blue: Int)

object HomeFacts {
    /**
     * djb2 over Unicode code points, then `hash % 360 / 360`.
     * Matches `CoverArt.hue(for:)` (`CarouselCardStyle.swift`). [ULong] so a
     * high hash cannot go negative before the modulo.
     */
    fun coverHue(string: String): Double {
        var hash = 5381UL
        var index = 0
        while (index < string.length) {
            val codePoint = string.codePointAt(index)
            hash = hash * 33u + codePoint.toULong()
            index += Character.charCount(codePoint)
        }
        return (hash % 360u).toDouble() / 360.0
    }

    /** Primary fandom, else the title. Display peeling is not part of the hash. */
    fun workHue(fandoms: List<String>, title: String): Double {
        val subject = fandoms.firstOrNull { it.isNotBlank() } ?: title
        return coverHue(subject)
    }

    /**
     * A kicker name: drop one trailing ` (…)` disambiguator.
     * "Doctor Who (2005)" → "Doctor Who". The full iOS peel table (dash tails,
     * stacked qualifiers) is not ported; one trailing parenthetical is the case
     * Home's kickers actually show.
     */
    fun bareFandomTitle(name: String): String {
        val trimmed = name.trim()
        if (trimmed.length < 4 || !trimmed.endsWith(')')) return trimmed
        val open = trimmed.lastIndexOf(" (")
        if (open <= 0) return trimmed
        val title = trimmed.substring(0, open).trim()
        return title.ifEmpty { trimmed }
    }

    fun primaryFandom(fandoms: List<String>): String? {
        val raw = fandoms.firstOrNull { it.isNotBlank() } ?: return null
        val bare = bareFandomTitle(raw)
        return bare.ifBlank { null }
    }

    fun parseHexColor(hex: String?): ParsedHex? {
        if (hex.isNullOrBlank()) return null
        val raw = hex.trim().removePrefix("#")
        if (raw.length != 6 && raw.length != 8) return null
        val value = raw.toLongOrNull(16) ?: return null
        val rgb = if (raw.length == 8) value and 0xFFFFFF else value
        return ParsedHex(
            red = ((rgb shr 16) and 0xFF).toInt(),
            green = ((rgb shr 8) and 0xFF).toInt(),
            blue = (rgb and 0xFF).toInt()
        )
    }

    fun parsedHexToColor(parsed: ParsedHex): Color = Color(
        red = parsed.red / 255f,
        green = parsed.green / 255f,
        blue = parsed.blue / 255f
    )

    /**
     * Queue-card wash over glass (`ReaderTheme.carouselQueueTint`).
     * A picked hex wins over the derived hue. Null when the queue has neither,
     * so the back cards stay plain glass.
     */
    fun carouselQueueTint(theme: ReaderTheme, hue: Double?, colorHex: String?): Color? {
        val picked = parseHexColor(colorHex)
        if (hue == null && picked == null) return null
        val (saturation, brightness, opacity) = when (theme) {
            ReaderTheme.Dark, ReaderTheme.Oled -> Triple(0.38, 0.78, 0.30)
            ReaderTheme.Light -> Triple(0.42, 0.75, 0.26)
            ReaderTheme.Sepia -> Triple(0.34, 0.70, 0.22)
        }
        val base = picked?.let(::parsedHexToColor) ?: hsb(hue ?: 0.0, saturation, brightness)
        return base.withOpacity(opacity)
    }

    /** Readium locator JSON `title`, or null. A small scan so unit tests need no Android JSON stub. */
    fun locatorTitle(locatorJson: String?): String? {
        if (locatorJson.isNullOrBlank()) return null
        val key = "\"title\""
        val index = locatorJson.indexOf(key)
        if (index < 0) return null
        var cursor = index + key.length
        while (cursor < locatorJson.length && locatorJson[cursor].isWhitespace()) cursor++
        if (cursor >= locatorJson.length || locatorJson[cursor] != ':') return null
        cursor++
        while (cursor < locatorJson.length && locatorJson[cursor].isWhitespace()) cursor++
        if (cursor >= locatorJson.length || locatorJson[cursor] != '"') return null
        cursor++
        val buffer = StringBuilder()
        while (cursor < locatorJson.length) {
            val character = locatorJson[cursor]
            if (character == '\\' && cursor + 1 < locatorJson.length) {
                buffer.append(locatorJson[cursor + 1])
                cursor += 2
                continue
            }
            if (character == '"') break
            buffer.append(character)
            cursor++
        }
        return buffer.toString().trim().ifEmpty { null }
    }

    /**
     * Named relative time: "just now", "N minutes ago", "N hours ago",
     * "yesterday", "N days ago". A future instant reads as "just now".
     */
    fun relativeNamed(from: Instant, now: Instant): String {
        val seconds = Duration.between(from, now).seconds
        if (seconds < 60) return "just now"
        val minutes = seconds / 60
        if (minutes < 60) {
            return if (minutes == 1L) "1 minute ago" else "$minutes minutes ago"
        }
        val hours = seconds / 3600
        if (hours < 24) {
            return if (hours == 1L) "1 hour ago" else "$hours hours ago"
        }
        val days = seconds / 86400
        if (days < 2) return "yesterday"
        return "$days days ago"
    }

    /**
     * Author · words · chapters. Words compact past 999 with up to two fraction
     * digits (`WorkStat.localWorkMetadata`).
     */
    fun localWorkMetadata(author: String, wordCount: Int, chapters: String): List<String> {
        val segments = mutableListOf<String>()
        val name = author.trim()
        if (name.isNotEmpty()) segments += name
        if (wordCount > 0) segments += compactWordCount(wordCount)
        val chapterRange = chapters.trim()
        if (chapterRange.isNotEmpty()) segments += chapterRange
        return segments
    }

    fun compactWordCount(count: Int): String = compactFigure(count) + " words"

    /** 999 → "999", 1_250 → "1.25K", 1_200_000 → "1.2M". */
    fun compactFigure(count: Int): String {
        if (count < 1_000) return count.toString()
        val (scaled, suffix) = when {
            count >= 1_000_000_000 -> count / 1_000_000_000.0 to "B"
            count >= 1_000_000 -> count / 1_000_000.0 to "M"
            else -> count / 1_000.0 to "K"
        }
        val rounded = round(scaled * 100.0) / 100.0
        val digits = String.format(Locale.US, "%.2f", rounded).trimEnd('0').trimEnd('.')
        return digits + suffix
    }

    fun cardProgressLabel(progress: Double?): String? {
        progress ?: return null
        return "${(progress * 100.0).roundToInt()}%"
    }

    /** "+N new" / "Updated" only when the work actually has an unseen chapter. */
    fun updateFooter(work: SavedWork): String? {
        if (!work.hasUpdate) return null
        val known = work.knownChapterCount ?: return "Updated"
        val delta = work.postedChapterCount - known
        return if (delta > 0) "+$delta new" else "Updated"
    }

    /**
     * Caller progress wins. A footer with no progress is an update badge, not a ring.
     * Otherwise a finished work is 100%, then the stored fraction.
     * Port of `WorkCoverCard.resolvedProgress`.
     */
    fun resolvedCoverProgress(
        explicit: Double?,
        footer: String?,
        isFinished: Boolean,
        saved: Double?
    ): Double? {
        if (explicit != null) return explicit.coerceIn(0.0, 1.0)
        if (footer != null) return null
        if (isFinished) return 1.0
        return saved?.coerceIn(0.0, 1.0)
    }

    fun queueProgress(works: List<SavedWork>): HomeQueueProgress {
        var finished = 0
        var inProgress = 0
        var unread = 0
        for (work in works) {
            when {
                work.isFinished -> finished += 1
                work.isInProgress -> inProgress += 1
                else -> unread += 1
            }
        }
        return HomeQueueProgress(finished, inProgress, unread)
    }

    /** 1-based index of the first unfinished work. Null when every work is finished, or the queue is empty. */
    fun nextUpPosition(works: List<SavedWork>): Int? {
        val index = works.indexOfFirst { !it.isFinished }
        return if (index < 0) null else index + 1
    }

    /** First unfinished work, else the first work of a fully-read queue. */
    fun upNext(works: List<SavedWork>): SavedWork? {
        if (works.isEmpty()) return null
        return works.firstOrNull { !it.isFinished } ?: works.first()
    }

    /** "7 works · next up 3". The position is omitted when nothing is left unfinished. */
    fun queueCardFooter(works: List<SavedWork>): String {
        val count = works.size
        val noun = if (count == 1) "1 work" else "$count works"
        val position = nextUpPosition(works) ?: return noun
        return "$noun · next up $position"
    }

    fun hasRealArchiveWarning(warnings: List<String>): Boolean = warnings.any { warning ->
        val trimmed = warning.trim()
        trimmed.isNotEmpty() && !trimmed.equals("No Archive Warnings Apply", ignoreCase = true)
    }

    /**
     * `workOrderRaw` is a comma-joined id list. Empty means newest [dateAdded] first.
     * Ids missing from the list follow, newest first, and are never dropped.
     */
    fun <T> inReadingOrder(
        workOrderRaw: String,
        works: List<T>,
        id: (T) -> String,
        dateAdded: (T) -> Instant
    ): List<T> {
        val order = LinkedHashMap<String, Int>()
        for (raw in workOrderRaw.split(',')) {
            val key = raw.trim()
            if (key.isNotEmpty() && key !in order) order[key] = order.size
        }
        if (order.isEmpty()) {
            return works.sortedWith(compareByDescending<T>(dateAdded).thenBy(id))
        }
        return works.sortedWith { lhs, rhs ->
            val left = order[id(lhs)]
            val right = order[id(rhs)]
            when {
                left != null && right != null -> left.compareTo(right)
                left != null -> -1
                right != null -> 1
                else -> {
                    val byDate = dateAdded(rhs).compareTo(dateAdded(lhs))
                    if (byDate != 0) byDate else id(lhs).compareTo(id(rhs))
                }
            }
        }
    }

}

object HomeCollections {
    /** Flagged collections, not deleted, reader's sort order then name. */
    fun shelves(
        collections: List<WorkCollection>,
        items: List<LibraryDisplayItem>
    ): List<HomeCollectionShelf> {
        return collections
            .asSequence()
            .filter { it.showsOnHome && !it.isDeleted }
            .sortedWith(
                compareBy<WorkCollection> { if (it.sortOrder == null) 1 else 0 }
                    .thenBy { it.sortOrder ?: Int.MAX_VALUE }
                    .thenBy(String.CASE_INSENSITIVE_ORDER) { it.name }
                    .thenBy { it.id }
            )
            .map { collection ->
                HomeCollectionShelf(
                    id = collection.id,
                    name = collection.name,
                    works = worksIn(collection, items)
                )
            }
            .toList()
    }

    private fun worksIn(
        collection: WorkCollection,
        items: List<LibraryDisplayItem>
    ): List<LibraryDisplayItem> {
        val pool = items.filter { !it.item.work.isDeleted }
        val members = if (collection.workIds.isNotEmpty()) {
            val ids = collection.workIds.toSet()
            pool.filter { it.item.work.id in ids }
        } else {
            pool.filter { row -> row.item.collections.any { it.id == collection.id } }
        }
        return HomeFacts.inReadingOrder(
            workOrderRaw = collection.workOrderRaw,
            works = members,
            id = { it.item.work.id },
            dateAdded = { it.item.work.dateAdded }
        )
    }
}

/** Subscriptions empty-state copy. A failed load is not "you have no subscriptions". */
object HomeSubscriptionsCopy {
    fun emptyMessage(isLoggedIn: Boolean, loadFailed: Boolean): String {
        if (!isLoggedIn) {
            return "Log in to AO3 to see updates from works and series you subscribe to."
        }
        return if (loadFailed) {
            "Couldn't load your subscriptions. Pull down to try again."
        } else {
            "You have no work or series subscriptions yet. When you subscribe on AO3, updates appear here."
        }
    }
}

/** "Select Works" with nothing picked, otherwise "N Selected". */
object HomeSelectionTitle {
    fun text(count: Int): String = if (count == 0) "Select Works" else "$count Selected"
}
