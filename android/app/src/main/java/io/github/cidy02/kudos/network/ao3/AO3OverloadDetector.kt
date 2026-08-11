package io.github.cidy02.kudos.network.ao3

object AO3OverloadDetector {
    // Specific multi-word phrases only. Bare substrings like "capacity" or
    // "try again later" were removed: every AO3 page contains "Archive of Our Own"
    // in its chrome, so a generic substring would misflag normal works/searches
    // (e.g. a summary containing "incapacity") as an overload page.
    private val overloadPhrases = listOf(
        "temporarily overloaded",
        "over capacity",
        "temporarily unavailable",
        "too many users",
        "is down for maintenance",
        "ao3 is down",
        "archive of our own is down"
    )

    fun isOverloadPage(body: String): Boolean {
        val normalized = body
            .lowercase()
            .replace(Regex("\\s+"), " ")

        if (!normalized.contains("archive of our own") && !normalized.contains("ao3")) {
            return false
        }

        return overloadPhrases.any { normalized.contains(it) }
    }
}
