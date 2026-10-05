package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParser
import io.github.cidy02.kudos.network.ao3.account.AO3AccountParseException
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorUrls
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.jsoup.Jsoup
import java.time.Clock
import java.time.LocalDate
import java.time.temporal.ChronoUnit

data class AO3DraftsPage(val page: AO3SearchPage, val deletionDates: Map<Long, LocalDate>)

object AO3DraftsUrls {
    fun page(username: String, page: Int): String? = AO3AuthorUrls.userDraftsUrl(username)?.toHttpUrl()
        ?.newBuilder()?.apply { if (page > 1) addQueryParameter("page", page.toString()) }?.build()?.toString()
}

/** The one index response supplies both the work blurbs and their deletion notices. */
class AO3DraftsParser {
    fun parse(html: String, page: Int, finalUrl: String? = null): AO3DraftsPage {
        val works = AO3AccountParser().parseAccountList(html, page, AccountListType.MyWorks, finalUrl)
        // iOS parseWorksList rejects a page where blurbs exist but none parsed.
        if (works.works.isEmpty() && Jsoup.parse(html).select("li.work.blurb").isNotEmpty()) {
            throw AO3AccountParseException.MissingRequiredStructure("AO3's page format wasn't what the app expected.")
        }
        return AO3DraftsPage(works, parseDraftDeletionDates(html))
    }

    /** iOS parseDraftDeletionDates: never use p.datetime (the revised date) as an expiry. */
    fun parseDraftDeletionDates(html: String): Map<Long, LocalDate> = buildMap {
        for (blurb in Jsoup.parse(html).select("li.work.blurb")) {
            if (!blurb.id().startsWith("work_")) continue
            val id = blurb.id().removePrefix("work_").toLongOrNull() ?: continue
            val notice = blurb.selectFirst("p.caution.notice") ?: continue
            val day = notice.selectFirst("span.date")?.text()?.trim()?.toIntOrNull() ?: continue
            val year = notice.selectFirst("span.year")?.text()?.trim()?.toIntOrNull() ?: continue
            val monthName = notice.selectFirst("abbr.month")?.attr("title")?.trim() ?: continue
            val month = months.indexOf(monthName) + 1
            if (month == 0) continue
            // Calendar.date(from:) on iOS normalizes the date components too.
            val date = runCatching { LocalDate.of(year, month, 1).plusDays(day.toLong() - 1) }.getOrNull()
            if (date != null) put(id, date)
        }
    }

    private val months = listOf("January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December")
}

/** Calendar-day arithmetic, not a duration rounded from hours. AO3's notice is creation + 29 days. */
object DraftExpiry {
    const val noticeOffsetDays = 29L
    enum class Tone(val hue: Double) { Red(0.0), Orange(0.08), Mint(0.45) }

    fun daysLeft(deletion: LocalDate, clock: Clock): Int = daysLeft(deletion, LocalDate.now(clock))
    fun daysLeft(deletion: LocalDate, today: LocalDate): Int =
        ChronoUnit.DAYS.between(today, deletion).coerceIn(0, Int.MAX_VALUE.toLong()).toInt()
    fun createdDate(deletion: LocalDate): LocalDate = deletion.minusDays(noticeOffsetDays)
    fun chipText(days: Int): String = when {
        days <= 0 -> "Last day"
        days == 1 -> "1 day left"
        else -> "$days days left"
    }
    fun tone(days: Int): Tone = when {
        days <= 3 -> Tone.Red
        days <= 7 -> Tone.Orange
        else -> Tone.Mint
    }
    fun tally(drafts: AO3DraftsPage, clock: Clock): String = tally(drafts, LocalDate.now(clock))
    fun tally(drafts: AO3DraftsPage, today: LocalDate): String {
        val page = drafts.page
        val expiring = page.works.count { work ->
            drafts.deletionDates[work.id]?.let { daysLeft(it, today) <= 7 } == true
        }
        if (page.totalPages > 1) {
            return "page ${page.currentPage} of ${page.totalPages}" +
                if (expiring > 0) " · $expiring expiring this week on this page" else ""
        }
        val count = page.works.size
        return (if (count == 1) "1 draft" else "$count drafts") +
            if (expiring > 0) " · $expiring expiring this week" else ""
    }
}
