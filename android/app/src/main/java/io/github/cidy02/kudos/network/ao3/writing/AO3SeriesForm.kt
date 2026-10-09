package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary

object AO3SeriesFormUrls {
    fun show(id: Long) = "${AO3Constants.BASE_URL}/series/$id"
    fun edit(id: Long) = "${show(id)}/edit"
    fun manage(id: Long) = "${show(id)}/manage"
    fun positions(id: Long) = "${show(id)}/update_positions"
}

object AO3SeriesField {
    const val title = "series[title]"
    const val summary = "series[summary]"
    const val notes = "series[series_notes]"
    const val complete = "series[complete]"
    const val ids = "series[author_attributes][ids][]"
    const val byline = "series[author_attributes][byline]"
}

data class AO3SeriesWorkRow(val serialWorkID: Long, val title: String, val position: Int,
    val workID: Long? = null, val isDraft: Boolean = false, val words: Int? = null, val dateText: String = "") {
    val displayTitle get() = title.ifEmpty { "Untitled work" }
    val metadataText get() = listOfNotNull(words?.let { "%,d %s".format(it, if (it == 1) "word" else "words") },
        dateText.takeIf { it.isNotEmpty() }).joinToString(" · ")
}

/** Transient loaded form, with the complete served-control snapshot independent of edits. */
data class AO3SeriesForm(val seriesID: Long?, val actionUrl: String, val csrfToken: String,
    val methodOverride: String?, val servedControls: List<AO3ServedControl>,
    val title: String = "", val summary: String = "", val notes: String = "", val isComplete: Boolean = false,
    val creators: AO3CreatorDraft = AO3CreatorDraft(), val works: List<AO3SeriesWorkRow> = emptyList(),
    val openOnAO3ForCreate: Boolean = false) {
    fun serves(name: String) = servedControls.any { it.name == name && !it.disabled }
    fun parameters(): List<Pair<String, String>> {
        val modeled = iosParameters().filter { serves(it.first) }
        val overridden = modeled.map { it.first }.toSet()
        return modeled + servedControls.filter { it.name !in overridden }.flatMap { control ->
            control.successfulValues().map { control.name to it }
        }
    }
    /** iOS AO3SeriesForm.parameters, including T-362's literal, nonempty byline. */
    fun iosParameters(): List<Pair<String, String>> = buildList {
        add("authenticity_token" to csrfToken)
        methodOverride?.takeIf(String::isNotEmpty)?.let { add("_method" to it) }
        add(AO3SeriesField.title to title)
        add(AO3SeriesField.summary to summary)
        add(AO3SeriesField.notes to notes)
        add(AO3SeriesField.complete to if (isComplete) "1" else "0")
        creators.selectedPseudIDs.forEach { add(AO3SeriesField.ids to it) }
        if (creators.coauthorByline.isNotEmpty()) add(AO3SeriesField.byline to creators.coauthorByline)
    }
}

/** iOS joins already loaded posted blurbs by title, in order; never guesses write IDs. */
fun attachSeriesBlurbs(rows: List<AO3SeriesWorkRow>, works: List<AO3WorkSummary>): List<AO3SeriesWorkRow> {
    val remaining = works.toMutableList()
    return rows.sortedBy { it.position }.map { row ->
        val index = if (row.isDraft) -1 else remaining.indexOfFirst { it.title == row.title }
        if (index < 0) row else remaining.removeAt(index).let { row.copy(words = it.wordCount, dateText = it.updatedDate) }
    }
}

/** Foundation .whitespaces (not .whitespacesAndNewlines), used only for Save availability. */
internal fun seriesTitleIsBlank(title: String) = title.all { char ->
    char == '\u0009' || char == '\u0020' || char == '\u00a0' || char == '\u1680' ||
        char in '\u2000'..'\u200b' || char == '\u202f' || char == '\u205f' || char == '\u3000'
}
