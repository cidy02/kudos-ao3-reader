package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields

object AO3ChapterField {
    const val title = "chapter[title]"
    const val position = "chapter[position]"
    const val total = "chapter[wip_length]"
    const val summary = "chapter[summary]"
    const val notes = "chapter[notes]"
    const val endnotes = "chapter[endnotes]"
    const val content = "chapter[content]"
    const val year = "chapter[published_at(1i)]"
    const val month = "chapter[published_at(2i)]"
    const val day = "chapter[published_at(3i)]"
    const val authorIDs = "chapter[author_attributes][ids][]"
}

object AO3ChapterUrls {
    fun chapters(workID: Long): String {
        require(workID > 0)
        return "${AO3Constants.BASE_URL}/works/$workID/chapters"
    }
    fun chapter(workID: Long, chapterID: Long): String {
        require(chapterID > 0)
        return "${chapters(workID)}/$chapterID"
    }
    fun form(workID: Long, chapterID: Long?) = chapterID?.let { "${chapter(workID, it)}/edit" }
        ?: "${chapters(workID)}/new"
    fun confirmDelete(workID: Long, chapterID: Long) = "${chapter(workID, chapterID)}/confirm_delete"
}

/** Immutable opening snapshot plus interpreted fields. Never persisted to Room or backup. */
data class AO3ChapterForm(
    val workID: Long,
    val chapterID: Long?,
    val actionUrl: String,
    val methodOverride: String?,
    val csrfToken: String,
    val servedControls: List<AO3ServedControl>,
    val formAttributes: Map<String, String>,
    val title: String = "",
    val position: String = "",
    val includePosition: Boolean = true,
    val wipLength: String = "",
    val summary: String = "",
    val notes: String = "",
    val endnotes: String = "",
    val content: String = "",
    val publishedYear: String = "",
    val publishedMonth: String = "",
    val publishedDay: String = "",
    val isDraft: Boolean = false,
    val creators: AO3CreatorDraft = AO3CreatorDraft()
) {
    val posts: Boolean get() = chapterID == null || isDraft
    fun parameters(submit: AO3WorkSubmitAction) = AO3ChapterFormEncoder.encode(this, submit)
    fun recoveryTarget() = "work:$workID:chapter:${chapterID ?: "new"}"

    /** A new preview is already an AO3 draft. Never create it a second time. */
    fun adopting(preview: AO3ChapterPreview): AO3ChapterForm {
        val originalNames = servedControls.map { it.name }.toSet()
        val combined = servedControls + preview.servedControls.filter { it.name !in originalNames }
        val updated = copy(csrfToken = preview.csrfToken ?: csrfToken, servedControls = combined)
        if (chapterID != null) return updated
        val id = preview.chapterID
        require(id != null && preview.workID == workID) { AO3CollectionFields.UNCONFIRMED }
        // Capture the preview's served posting controls: patch/post_button weren't
        // on the new form, and the replay boundary must not invent either.
        return updated.copy(chapterID = id, actionUrl = AO3ChapterUrls.chapter(workID, id),
            methodOverride = "patch", isDraft = true, servedControls = combined,
            formAttributes = preview.formAttributes)
    }
}

/** Read-only AO3-sanitized markup, images removed. The screen parses paragraphs off-main. */
data class AO3ChapterPreview(
    val workID: Long?, val chapterID: Long?, val csrfToken: String?, val notice: String?,
    val blocks: List<Block>, val servedControls: List<AO3ServedControl>, val formAttributes: Map<String, String>
) {
    data class Block(val kind: Kind, val text: String)
    enum class Kind { Heading, Label, Html }
}

data class AO3ChapterDeleteForm(val actionUrl: String, val csrfToken: String, val methodOverride: String)

/** iOS's modeled pairs first, filtered to enabled served names; then exact browser replay. */
object AO3ChapterFormEncoder {
    fun iosParameters(form: AO3ChapterForm, submit: AO3WorkSubmitAction): List<Pair<String, String>> = buildList {
        with(form) {
            add("authenticity_token" to csrfToken)
            methodOverride?.takeIf(String::isNotEmpty)?.let { add("_method" to it) }
            add(AO3ChapterField.title to title)
            if (includePosition && position.isNotEmpty()) add(AO3ChapterField.position to position)
            if (wipLength.isNotEmpty()) add(AO3ChapterField.total to wipLength)
            add(AO3ChapterField.summary to summary)
            add(AO3ChapterField.notes to notes)
            add(AO3ChapterField.endnotes to endnotes)
            add(AO3ChapterField.content to content)
            if (publishedYear.isNotEmpty()) {
                add(AO3ChapterField.year to publishedYear)
                add(AO3ChapterField.month to publishedMonth)
                add(AO3ChapterField.day to publishedDay)
            }
            creators.selectedPseudIDs.forEach { add(AO3ChapterField.authorIDs to it) }
            add(submit.fieldName to "1")
        }
    }
    fun encode(form: AO3ChapterForm, submit: AO3WorkSubmitAction): List<Pair<String, String>> {
        val served = form.servedControls.filterNot { it.disabled }.map { it.name }.toSet()
        val modeled = iosParameters(form, submit).filter { it.first in served }
        val names = modeled.map { it.first }.toSet()
        return modeled + form.servedControls.flatMap { control ->
            if (control.name in names) emptyList() else control.successfulValues(submit).map { control.name to it }
        }
    }
}
