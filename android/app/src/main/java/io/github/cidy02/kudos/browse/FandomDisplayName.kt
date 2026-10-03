package io.github.cidy02.kudos.browse

enum class FandomQualifierKind {
    Parenthetical,
    Creator,
    Rpf,
    AllMediaTypes,
    RelatedFandoms,
    FandomSuffix
}

data class FandomQualifier(
    val kind: FandomQualifierKind,
    val text: String
)

data class FandomName(
    val original: String,
    val title: String,
    val parts: List<FandomQualifier>,
    val qualifier: String = parts.joinToString(" ") { it.text }
)

/**
 * Port of iOS `FandomDisplayName` in `Features/Search/FandomListView.swift`.
 * Peels AO3 disambiguation suffixes (medium, author, media umbrella, RPF, etc.)
 * from fandom tag names for display while preserving the canonical tag for indexing.
 */
object FandomDisplayName {
    fun segments(name: String): List<String> {
        val parts = name
            .split('|')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        return parts.ifEmpty { listOf(name) }
    }

    fun primarySegment(name: String): String {
        return segments(name).lastOrNull() ?: name
    }

    fun aliasSegments(name: String): List<String> {
        val all = segments(name)
        return if (all.size <= 1) emptyList() else all.dropLast(1)
    }

    private val closingBrackets = setOf(')', '）')
    private val separators = listOf(" - ", " – ", " — ", " ‐ ")
    private val dashes = setOf('-', '–', '—', '‐')
    private val mediaUmbrellas = listOf(
        "All Media Types",
        "所有媒体类型",
        "所有媒體類型",
        "所有媒體型別",
        "Todos os Tipos de Mídia",
        "Todos los tipos de medios"
    )
    private val relatedFandoms = listOf(" & Related Fandoms", " and Related Fandoms")
    private val debrisChars = setOf(' ', '\t', '-', '–', '—', '‐', ':')

    private data class Peel(val head: String, val qualifier: String)

    private class Rule(
        val name: String,
        val kind: FandomQualifierKind,
        val cut: (String) -> Peel?
    )

    fun bareTitle(name: String): String {
        val title = split(primarySegment(name)).title
        return title.ifEmpty { name }
    }

    fun bareTitle(name: String, among: Collection<String>): String {
        val bare = bareTitle(name)
        val collides = among.any { it != name && bareTitle(it) == bare }
        return if (collides) primarySegment(name) else bare
    }

    fun split(name: String): FandomName {
        var title = name.trim()
        if (title.isEmpty()) {
            return FandomName(original = name, title = name, parts = emptyList())
        }

        val keepsDashTail = FandomDisplayExceptions.keepWhole.contains(title)
        val qualifiers = mutableListOf<FandomQualifier>()
        val taken = mutableSetOf<String>()

        val rules = mutableListOf(
            Rule("relatedFandoms", FandomQualifierKind.RelatedFandoms, ::takeRelatedFandoms),
            Rule("rpf", FandomQualifierKind.Rpf, ::takeRPF),
            Rule("mediaUmbrella", FandomQualifierKind.AllMediaTypes, ::takeMediaUmbrella),
            Rule("bracket", FandomQualifierKind.Parenthetical, ::takeBracket),
            Rule("separator", FandomQualifierKind.Creator, ::takeSeparator),
            Rule("gluedFandom", FandomQualifierKind.FandomSuffix, ::takeGluedFandom)
        )
        if (keepsDashTail) {
            rules.removeAll { it.name == "separator" }
        }

        for (i in 0 until rules.size) {
            val before = title
            for (rule in rules) {
                if (taken.contains(rule.name)) continue
                val peel = rule.cut(title) ?: continue
                if (peel.head.isEmpty()) continue
                qualifiers.add(0, FandomQualifier(rule.kind, peel.qualifier))
                title = peel.head
                taken.add(rule.name)
            }
            if (title == before) break
        }

        return FandomName(original = name, title = title, parts = qualifiers)
    }

    private fun takeRelatedFandoms(title: String): Peel? {
        for (needle in relatedFandoms) {
            if (title.endsWith(needle, ignoreCase = true)) {
                val cutIndex = title.length - needle.length
                return Peel(
                    tidied(title.substring(0, cutIndex)),
                    title.substring(cutIndex).trim()
                )
            }
        }
        return null
    }

    private fun takeRPF(title: String): Peel? {
        if (!title.endsWith("RPF", ignoreCase = true)) return null
        val cutIndex = title.length - 3
        val head = tidied(title.substring(0, cutIndex))
        if (FandomUmbrellas.rpfKeepAttached.contains(head)) return null
        return Peel(head, title.substring(cutIndex).trim())
    }

    private fun takeMediaUmbrella(title: String): Peel? {
        for (umbrella in mediaUmbrellas) {
            if (title.endsWith(umbrella, ignoreCase = true)) {
                val cutIndex = title.length - umbrella.length
                return Peel(
                    tidied(title.substring(0, cutIndex)),
                    "- " + title.substring(cutIndex).trim()
                )
            }
        }
        return null
    }

    private fun takeBracket(title: String): Peel? {
        val last = title.lastOrNull() ?: return null
        if (last !in closingBrackets) return null
        val lastAscii = title.lastIndexOf('(')
        val lastFull = title.lastIndexOf('（')
        val open = maxOf(lastAscii, lastFull)
        if (open < 0) return null
        return Peel(
            tidied(title.substring(0, open)),
            title.substring(open)
        )
    }

    private fun takeSeparator(title: String): Peel? {
        var bestIndex = -1
        var bestSep = ""
        for (sep in separators) {
            val idx = title.lastIndexOf(sep)
            if (idx > bestIndex) {
                bestIndex = idx
                bestSep = sep
            }
        }
        if (bestIndex < 0) return null
        val tail = title.substring(bestIndex + bestSep.length).trim()
        if (tail.isEmpty()) return null
        return Peel(
            tidied(title.substring(0, bestIndex)),
            "- $tail"
        )
    }

    private fun takeGluedFandom(title: String): Peel? {
        if (!title.endsWith("Fandom", ignoreCase = true)) return null
        val cutIndex = title.length - 6 // "Fandom".length
        val beforeWord = title.substring(0, cutIndex).trim()
        val joiner = beforeWord.lastOrNull() ?: return null
        if (joiner !in dashes) return null
        val head = tidied(beforeWord)
        if (FandomUmbrellas.fandomKeepAttached.contains(head)) return null
        return Peel(
            head,
            "- " + title.substring(cutIndex).trim()
        )
    }

    private fun tidied(text: String): String {
        var out = text.trim()
        while (out.isNotEmpty() && (out.last() in debrisChars || out.last().isWhitespace())) {
            out = out.substring(0, out.length - 1).trim()
        }
        return out.trim()
    }
}
