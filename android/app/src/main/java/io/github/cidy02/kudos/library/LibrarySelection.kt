package io.github.cidy02.kudos.library

/**
 * Pure helpers for Library multi-select. Selection is an in-memory set of work ids
 * owned by [LibraryViewModel]; these keep toggle/enter/exit logic unit-testable.
 */
object LibrarySelection {
    fun toggle(selectedIds: Set<String>, workId: String): Set<String> {
        return if (workId in selectedIds) selectedIds - workId else selectedIds + workId
    }

    fun selectOnly(workId: String): Set<String> = setOf(workId)

    fun clear(): Set<String> = emptySet()

    fun isSelected(selectedIds: Set<String>, workId: String): Boolean = workId in selectedIds
}
