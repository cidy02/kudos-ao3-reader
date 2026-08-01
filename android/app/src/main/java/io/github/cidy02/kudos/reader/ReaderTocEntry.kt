package io.github.cidy02.kudos.reader

/**
 * One navigable chapter/section row for the in-reader TOC sheet.
 * Engine-agnostic so unit tests don't need Readium types.
 *
 * [href] is the publication resource URL string used to jump via the navigator.
 * [depth] indents nested TOC children in the sheet list.
 */
data class ReaderTocEntry(
    val title: String,
    val href: String,
    val depth: Int = 0
)
