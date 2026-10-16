package io.github.cidy02.kudos.works.detail

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle
import java.util.Locale

/** WorkStat.displayDate: AO3 detail ISO and search-blurb dates share one display format. */
object WorkDetailDates {
    private val parsers = listOf("uuuu-MM-dd", "dd MMM uuuu").map {
        DateTimeFormatter.ofPattern(it, Locale.US).withResolverStyle(ResolverStyle.STRICT)
    }
    private val display = DateTimeFormatter.ofPattern("MM/dd/uuuu", Locale.US)

    fun displayDate(raw: String): String {
        for (parser in parsers) {
            val date = runCatching { LocalDate.parse(raw, parser) }.getOrNull() ?: continue
            return date.format(display)
        }
        return raw
    }
}
