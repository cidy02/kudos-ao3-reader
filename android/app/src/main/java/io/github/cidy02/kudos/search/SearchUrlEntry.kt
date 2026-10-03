package io.github.cidy02.kudos.search

/**
 * An explicit URL pasted into Search opens the web fallback. A normal query,
 * including one with a dot ("dr. who"), stays a search. iOS Search is not a
 * URL bar; this only keeps the path the Browse root used to be the only place for.
 */
internal object SearchUrlEntry {
    fun normalize(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        val lower = trimmed.lowercase()
        if (lower.startsWith("https://") || lower.startsWith("http://")) return trimmed
        if (lower.startsWith("www.")) return "https://$trimmed"
        val host = lower.substringBefore('/').substringBefore('?').substringBefore('#')
        val ao3 = host == "archiveofourown.org" || host.endsWith(".archiveofourown.org")
        return if (ao3) "https://$trimmed" else null
    }
}
