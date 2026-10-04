package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionsIndexPage
import java.text.Collator
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.format.ResolverStyle
import java.util.Locale

/** Client-side rules from iOS artboard 1bm. Default preserves AO3's row order. */
data class AO3CollectionsFilter(
    val sort: Sort = Sort.AsReturned,
    val order: Order = Order.Descending,
    val showsOpenOnly: Boolean = false,
    val showsUnrevealedOnly: Boolean = false,
    val showsModeratedOnly: Boolean = false,
    val showsWithWorksOnly: Boolean = false
) {
    enum class Sort(val title: String) {
        AsReturned("AO3 order"), Title("Title"), Works("Works"), Bookmarks("Bookmarks"),
        RecentlyUpdated("Recently updated")
    }

    enum class Order {
        Ascending, Descending;

        fun title(sort: Sort): String = when (sort) {
            Sort.RecentlyUpdated -> if (this == Ascending) "Oldest" else "Newest"
            Sort.Title -> if (this == Ascending) "A–Z" else "Z–A"
            Sort.Works, Sort.Bookmarks -> if (this == Ascending) "Fewest" else "Most"
            Sort.AsReturned -> if (this == Ascending) "Ascending" else "Descending"
        }
    }

    val hasActiveFilters: Boolean
        get() = sort != Sort.AsReturned || showsOpenOnly || showsUnrevealedOnly ||
            showsModeratedOnly || showsWithWorksOnly
    val needsWholeIndex: Boolean get() = hasActiveFilters
    val summaryLabels: List<String>
        get() = buildList {
            if (sort != Sort.AsReturned) add("${sort.title} · ${order.title(sort)}")
            if (showsOpenOnly) add("Open to new works")
            if (showsModeratedOnly) add("Moderated")
            if (showsUnrevealedOnly) add("Unrevealed")
            if (showsWithWorksOnly) add("Has works")
        }

    fun apply(collections: List<AO3Collection>): List<AO3Collection> {
        val narrowed = collections.filter {
            (!showsOpenOnly || !it.isClosed) &&
                (!showsUnrevealedOnly || it.isUnrevealed) &&
                (!showsModeratedOnly || it.isModerated) &&
                (!showsWithWorksOnly || (it.worksCount ?: 0) != 0)
        }
        if (sort == Sort.AsReturned) return narrowed
        val collator = Collator.getInstance().apply { strength = Collator.SECONDARY }
        // sortedWith is stable: ties and unknown ranks retain incoming AO3 order.
        return narrowed.sortedWith { left, right ->
            if (sort == Sort.Title) {
                val comparison = collator.compare(left.title, right.title)
                if (order == Order.Ascending) comparison else -comparison
            } else {
                val a = rank(left)
                val b = rank(right)
                when {
                    a == null && b == null -> 0
                    a == null -> 1
                    b == null -> -1
                    order == Order.Ascending -> a.compareTo(b)
                    else -> b.compareTo(a)
                }
            }
        }
    }

    private fun rank(collection: AO3Collection): Long? = when (sort) {
        Sort.AsReturned, Sort.Title -> null
        Sort.Works -> collection.worksCount?.toLong()
        Sort.Bookmarks -> collection.bookmarksCount?.toLong()
        Sort.RecentlyUpdated -> updatedDate(collection.updatedAtText)?.toEpochDay()
    }

    companion object {
        private val dateFormatters = listOf("d MMM uuuu", "dd MMM uuuu", "uuuu-MM-dd", "d MMMM uuuu")
            .map { DateTimeFormatter.ofPattern(it, Locale.US).withResolverStyle(ResolverStyle.STRICT) }

        /** Only recognised AO3 shapes; locale and the device time zone cannot reinterpret them. */
        fun updatedDate(text: String): LocalDate? {
            val trimmed = text.trim()
            if (trimmed.isEmpty()) return null
            for (formatter in dateFormatters) {
                try {
                    return LocalDate.parse(trimmed, formatter)
                } catch (_: DateTimeParseException) {
                    // Unrecognised text remains unranked.
                }
            }
            return null
        }
    }
}

data class AO3CollectionsFilterDraft(
    val initial: AO3CollectionsFilter,
    var draft: AO3CollectionsFilter = initial
) {
    enum class Resolution { Cancel, Apply }
    fun reset() { draft = AO3CollectionsFilter() }
    fun resolved(resolution: Resolution): AO3CollectionsFilter =
        if (resolution == Resolution.Apply) draft else initial
}

object AO3CollectionsWholeIndex {
    const val maximumPages = 25

    fun refreshPage(currentPage: Int, needsWholeIndex: Boolean): Int =
        if (needsWholeIndex) 1 else currentPage

    fun canReusePageOne(currentPage: Int, ownsScreen: Boolean, listIsLoaded: Boolean): Boolean =
        currentPage == 1 && ownsScreen && listIsLoaded

    fun nextPage(after: Int, reportedTotalPages: Int, pageWasEmpty: Boolean): Int? {
        if (pageWasEmpty) return null
        return (after + 1).takeIf { it <= reportedTotalPages.coerceIn(1, maximumPages) }
    }

    fun partialNote(reportedTotalPages: Int, lastPageWasEmpty: Boolean): String? =
        if (!lastPageWasEmpty && reportedTotalPages > maximumPages) {
            "first $maximumPages of $reportedTotalPages pages"
        } else null

    fun append(
        page: AO3CollectionsIndexPage,
        collections: MutableList<AO3Collection>,
        capturedLoadGeneration: Int,
        loadGeneration: Int,
        capturedSessionGeneration: Int,
        sessionGeneration: Int
    ): Boolean {
        if (capturedLoadGeneration != loadGeneration ||
            capturedSessionGeneration != sessionGeneration
        ) return false
        collections.addAll(page.collections)
        return true
    }
}

/** Visibility labels shared by the card and its iOS parity test. */
object AO3CollectionCardCopy {
    fun statusLabels(isUnrevealed: Boolean, isAnonymous: Boolean): List<String> = buildList {
        add(if (isUnrevealed) "Unrevealed" else "Revealed")
        if (isAnonymous) add("Anonymous")
    }
}
