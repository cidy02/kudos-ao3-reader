package io.github.cidy02.kudos.library

enum class LibrarySectionQuickFilter(val title: String) {
    All("All"),
    Rereads("Rereads"),
    Offline("Offline"),
    Wip("WIP");

    companion object {
        fun fromId(id: String?): LibrarySectionQuickFilter? = entries.firstOrNull {
            it.name.equals(id, ignoreCase = true)
        }
    }
}

fun LibrarySectionKind.quickFilters(): List<LibrarySectionQuickFilter> = when (this) {
    LibrarySectionKind.ReadingNow -> listOf(
        LibrarySectionQuickFilter.All,
        LibrarySectionQuickFilter.Wip
    )
    LibrarySectionKind.Favorites -> LibrarySectionQuickFilter.entries
    else -> emptyList()
}

fun librarySectionQuickFilterLabel(
    kind: LibrarySectionKind,
    filter: LibrarySectionQuickFilter,
    countSource: List<LibraryDisplayItem>
): String {
    if (kind != LibrarySectionKind.ReadingNow) return filter.title
    val count = when (filter) {
        LibrarySectionQuickFilter.All -> countSource.size
        LibrarySectionQuickFilter.Wip -> countSource.count { !it.item.work.isComplete }
        else -> 0
    }
    return "${filter.title} $count"
}

fun filterLibrarySectionItems(
    kind: LibrarySectionKind,
    filter: LibrarySectionQuickFilter,
    items: List<LibraryDisplayItem>,
    finishCounts: Map<String, Int> = emptyMap()
): List<LibraryDisplayItem> {
    if (filter !in kind.quickFilters()) return items
    return when (filter) {
        LibrarySectionQuickFilter.All -> items
        LibrarySectionQuickFilter.Rereads -> items.filter {
            (finishCounts[it.item.work.id] ?: 0) > 1
        }
        LibrarySectionQuickFilter.Offline -> items.filter { it.item.work.isDownloaded }
        LibrarySectionQuickFilter.Wip -> items.filter { !it.item.work.isComplete }
    }
}
