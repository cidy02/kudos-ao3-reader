package io.github.cidy02.kudos.network.ao3

object AO3OverloadDetector {
    private val overloadPhrases = listOf(
        "temporarily overloaded",
        "too many users",
        "capacity",
        "try again later",
        "please try again later",
        "ao3 is down",
        "archive of our own is down",
        "archive of our own is temporarily unavailable"
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
