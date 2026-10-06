package io.github.cidy02.kudos.network.ao3.writing

/** Parameter construction only; this object cannot dispatch a request. */
object AO3WorkFormEncoder {
    fun encode(form: AO3WorkForm, submit: AO3WorkSubmitAction): List<Pair<String, String>> {
        val modeled = iosParameters(form, submit)
        val overridden = modeled.map { it.first }.toSet()
        return modeled + carriedParameters(form, submit, overridden)
    }

    /** Exact order, representations and conditional branches of iOS's modeled fields. */
    fun iosParameters(form: AO3WorkForm, submit: AO3WorkSubmitAction): List<Pair<String, String>> = buildList {
        with(form) {
            add(AO3WorkFormField.authenticityToken to csrfToken)
            methodOverride?.takeIf(String::isNotEmpty)?.let { add(AO3WorkFormField.methodOverride to it) }
            add(AO3WorkFormField.title to title)
            if (rating.isNotEmpty()) add(AO3WorkFormField.rating to rating)
            (warnings.ifEmpty { listOf("") }).forEach { add(AO3WorkFormField.warnings to it) }
            (categories.ifEmpty { listOf("") }).forEach { add(AO3WorkFormField.categories to it) }
            add(AO3WorkFormField.fandoms to joinWorkList(fandoms))
            add(AO3WorkFormField.relationships to joinWorkList(relationships))
            add(AO3WorkFormField.characters to joinWorkList(characters))
            add(AO3WorkFormField.additionalTags to joinWorkList(additionalTags))
            add(AO3WorkFormField.languageID to languageID)
            add(AO3WorkFormField.summary to summary)
            add(AO3WorkFormField.notes to notes)
            add(AO3WorkFormField.endnotes to endnotes)
            add(AO3WorkFormField.collectionNames to joinWorkList(collectionNames))
            add(AO3WorkFormField.recipients to joinWorkList(gifts))
            val selectedSeries = series.firstOrNull { it.isSelected }
            val newTitle = newSeriesTitle.trim()
            when {
                selectedSeries != null -> add(AO3WorkFormField.seriesID to selectedSeries.seriesID.toString())
                newTitle.isNotEmpty() -> add(AO3WorkFormField.seriesTitle to newTitle)
                else -> {
                    add(AO3WorkFormField.seriesID to "")
                    add(AO3WorkFormField.seriesTitle to "")
                }
            }
            if (parentWork.url.isNotEmpty() || parentWork.title.isNotEmpty()) {
                add(AO3WorkFormField.parentURL to parentWork.url)
                add(AO3WorkFormField.parentTitle to parentWork.title)
                add(AO3WorkFormField.parentAuthor to parentWork.author)
                add(AO3WorkFormField.parentLanguageID to parentWork.languageID)
                if (parentWork.isTranslation) add(AO3WorkFormField.parentTranslation to "1")
            }
            add(AO3WorkFormField.wipLength to chapterTotal)
            add(AO3WorkFormField.backdate to flag(backdate))
            add(AO3WorkFormField.restricted to flag(restricted))
            add(AO3WorkFormField.moderatedCommenting to flag(moderatedCommenting))
            if (commentPermissions.isNotEmpty()) add(AO3WorkFormField.commentPermissions to commentPermissions)
            anonymous?.let { add(AO3WorkFormField.anonymous to flag(it)) }
            collectionInbox?.let { add(AO3WorkFormField.collectionInbox to flag(it)) }
            add(AO3WorkFormField.workSkinID to workSkinID)
            chapter?.let {
                add(AO3WorkFormField.chapterTitle to it.title)
                add(AO3WorkFormField.chapterSummary to it.summary)
                add(AO3WorkFormField.chapterContent to it.content)
                if (it.publishedYear.isNotEmpty()) {
                    add(AO3WorkFormField.chapterPublishedYear to it.publishedYear)
                    add(AO3WorkFormField.chapterPublishedMonth to it.publishedMonth)
                    add(AO3WorkFormField.chapterPublishedDay to it.publishedDay)
                }
            }
            creators.selectedPseudIDs.forEach { add(AO3WorkFormField.authorIDs to it) }
            if (creators.coauthorByline.isNotEmpty()) add(AO3WorkFormField.authorByline to creators.coauthorByline)
            // iOS's hidden carry can provide a modeled field omitted by a conditional
            // branch, notably translation=0. Unknown hidden names belong to lossless
            // replay instead, so their duplicates must not be collapsed here.
            val overridden = map { it.first }.toMutableSet()
            servedControls.filter { it.tag == "input" && it.type == "hidden" && it.name in conditionalHiddenNames }
                .forEach { control ->
                    if (overridden.add(control.name)) add(control.name to control.attributes["value"].orEmpty())
                }
            add(submit.fieldName to "1")
        }
    }

    /** Unknown names and names omitted by the modeled branch retain their browser payload. */
    fun carriedParameters(
        form: AO3WorkForm,
        submit: AO3WorkSubmitAction,
        overriddenNames: Set<String> = iosParameters(form, submit).map { it.first }.toSet()
    ): List<Pair<String, String>> = form.servedControls.flatMap { control ->
        if (control.name in overriddenNames) emptyList()
        else control.successfulValues(submit).map { control.name to it }
    }

    private fun flag(value: Boolean) = if (value) "1" else "0"

    private val conditionalHiddenNames = setOf(
        AO3WorkFormField.rating, AO3WorkFormField.seriesID, AO3WorkFormField.seriesTitle,
        AO3WorkFormField.parentURL, AO3WorkFormField.parentTitle, AO3WorkFormField.parentAuthor,
        AO3WorkFormField.parentLanguageID, AO3WorkFormField.parentTranslation,
        AO3WorkFormField.commentPermissions, AO3WorkFormField.authorByline,
        AO3WorkFormField.chapterTitle, AO3WorkFormField.chapterSummary, AO3WorkFormField.chapterContent,
        AO3WorkFormField.chapterPublishedYear, AO3WorkFormField.chapterPublishedMonth, AO3WorkFormField.chapterPublishedDay
    )
}
