package io.github.cidy02.kudos.core

import org.jsoup.parser.Parser

private val LineBreakTags = Regex("(?i)<br\\s*/?>|</(p|div|li|h[1-6])>")
private val AnyTag = Regex("<[^>]+>")
private val TrailingSpaces = Regex("[ \\t]+\n")
private val BlankLineRuns = Regex("\n{3,}")

/**
 * Port of iOS `String.strippingHTML()` (`Utilities/HTMLText.swift`): HTML as found in an EPUB's
 * `dc:description` becomes readable text. Line breaks and block ends become new lines, every
 * other tag is dropped, entities are decoded. As on iOS, the stored summary keeps its HTML (so
 * backups match) and this runs where the summary is shown or indexed.
 */
fun String.strippingHtml(): String {
    if ('<' !in this && '&' !in this) return this
    val text = Parser.unescapeEntities(replace(LineBreakTags, "\n").replace(AnyTag, ""), false)
    return text.replace(TrailingSpaces, "\n").replace(BlankLineRuns, "\n\n").trim()
}
