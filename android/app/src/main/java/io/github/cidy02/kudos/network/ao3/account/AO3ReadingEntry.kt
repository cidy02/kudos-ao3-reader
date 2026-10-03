package io.github.cidy02.kudos.network.ao3.account

import org.jsoup.nodes.Element

/**
 * One row's reading metadata on `/users/:id/readings` (History and Marked for Later).
 * Mirrors iOS `AO3ReadingEntry` (Services/AO3Client+Readings.swift).
 */
data class AO3ReadingEntry(
    val workId: Long? = null,
    val readingId: String? = null,
    val lastVisited: String = "",
    val visitCount: Int? = null,
    val versionStatus: VersionStatus = VersionStatus.Unknown,
    val isMarkedForLater: Boolean = false,
    val isFlaggedToSkip: Boolean = false,
    val isDeletedWork: Boolean = false
) {
    enum class VersionStatus {
        UpdateAvailable,
        MinorEdits,
        LatestVersion,
        Unknown
    }

    val lastVisitedIsRelative: Boolean
        get() = !Regex("""^\d{1,2} \w{3} \d{4}$""").matches(lastVisited.trim())

    val lastVisitedDisplay: String?
        get() = when {
            lastVisited.isBlank() -> null
            lastVisitedIsRelative -> "Last visited $lastVisited ago"
            else -> "Last visited $lastVisited"
        }

    val visitCountDisplay: String?
        get() = when (visitCount) {
            null, 0 -> null
            1 -> "Visited once"
            2 -> "Visited twice"
            else -> "Visited $visitCount times"
        }

    val versionDisplay: String?
        get() = when (versionStatus) {
            VersionStatus.UpdateAvailable -> "Update available"
            VersionStatus.MinorEdits -> "Minor edits since then"
            VersionStatus.LatestVersion -> "Latest version"
            VersionStatus.Unknown -> null
        }

    companion object {
        fun parseFromBlurb(row: Element): AO3ReadingEntry? {
            val heading = row.selectFirst("div.user.module h4.viewed") ?: return null
            val text = heading.text()
            val idRaw = row.attr("id").removePrefix("work_")
            val workId = idRaw.toLongOrNull()
            val deleteAction = row.selectFirst("form.ajax-remove")?.attr("action").orEmpty()
            val readingId = Regex("""/readings/(\d+)""").find(deleteAction)?.groupValues?.getOrNull(1)

            val isDeleted = row.hasClass("deleted") || text.contains("Deleted work", ignoreCase = true)
            val lastVisited = parseLastVisited(text)
            val visitCount = parseVisitCount(text)
            val versionStatus = parseVersionStatus(text)
            val isMarked = text.contains("Marked for Later", ignoreCase = true)
            val isFlagged = text.contains("Flagged to skip", ignoreCase = true)

            return AO3ReadingEntry(
                workId = workId,
                readingId = readingId,
                lastVisited = lastVisited,
                visitCount = visitCount,
                versionStatus = versionStatus,
                isMarkedForLater = isMarked,
                isFlaggedToSkip = isFlagged,
                isDeletedWork = isDeleted
            )
        }

        private fun parseLastVisited(text: String): String {
            val marker = "Last visited:"
            val start = text.indexOf(marker)
            if (start < 0) return ""
            val rest = text.substring(start + marker.length).trim()
            val candidate = rest.substringBefore("(").substringBefore("Visited").trim()
            return candidate
        }

        private fun parseVisitCount(text: String): Int? {
            if (text.contains("Visited once", ignoreCase = true)) return 1
            if (text.contains("Visited twice", ignoreCase = true)) return 2
            val match = Regex("""Visited (\d+) times""", RegexOption.IGNORE_CASE).find(text)
            return match?.groupValues?.getOrNull(1)?.toIntOrNull()
        }

        private fun parseVersionStatus(text: String): VersionStatus {
            return when {
                text.contains("Update available", ignoreCase = true) -> VersionStatus.UpdateAvailable
                text.contains("Minor edits", ignoreCase = true) -> VersionStatus.MinorEdits
                text.contains("Latest version", ignoreCase = true) -> VersionStatus.LatestVersion
                else -> VersionStatus.Unknown
            }
        }
    }
}
