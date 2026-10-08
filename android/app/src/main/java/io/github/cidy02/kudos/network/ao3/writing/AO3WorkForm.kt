package io.github.cidy02.kudos.network.ao3.writing

import io.github.cidy02.kudos.network.ao3.AO3Constants

/** Names from iOS AO3WorkFormField, never option values invented by the app. */
object AO3WorkFormField {
    const val authenticityToken = "authenticity_token"
    const val methodOverride = "_method"
    const val title = "work[title]"
    const val rating = "work[rating_string]"
    const val warnings = "work[archive_warning_strings][]"
    const val categories = "work[category_strings][]"
    const val fandoms = "work[fandom_string]"
    const val relationships = "work[relationship_string]"
    const val characters = "work[character_string]"
    const val additionalTags = "work[freeform_string]"
    const val languageID = "work[language_id]"
    const val summary = "work[summary]"
    const val notes = "work[notes]"
    const val endnotes = "work[endnotes]"
    const val collectionNames = "work[collection_names]"
    const val recipients = "work[recipients]"
    const val wipLength = "work[wip_length]"
    const val backdate = "work[backdate]"
    const val restricted = "work[restricted]"
    const val moderatedCommenting = "work[moderated_commenting_enabled]"
    const val commentPermissions = "work[comment_permissions]"
    const val anonymous = "work[anonymous]"
    const val collectionInbox = "work[collection_inbox]"
    const val workSkinID = "work[work_skin_id]"
    const val seriesID = "work[series_attributes][id]"
    const val seriesTitle = "work[series_attributes][title]"
    const val parentURL = "work[parent_work_relationships_attributes][0][url]"
    const val parentTitle = "work[parent_work_relationships_attributes][0][title]"
    const val parentAuthor = "work[parent_work_relationships_attributes][0][author]"
    const val parentLanguageID = "work[parent_work_relationships_attributes][0][language_id]"
    const val parentTranslation = "work[parent_work_relationships_attributes][0][translation]"
    const val chapterTitle = "work[chapter_attributes][title]"
    const val chapterSummary = "work[chapter_attributes][summary]"
    const val chapterContent = "work[chapter_attributes][content]"
    const val chapterPublishedYear = "work[chapter_attributes][published_at(1i)]"
    const val chapterPublishedMonth = "work[chapter_attributes][published_at(2i)]"
    const val chapterPublishedDay = "work[chapter_attributes][published_at(3i)]"
    const val authorIDs = "work[author_attributes][ids][]"
    const val authorByline = "work[author_attributes][byline]"
}

enum class AO3WorkSubmitAction(val fieldName: String) {
    SaveDraft("save_button"), Preview("preview_button"), Post("post_button"),
    Update("update_button"), Edit("edit_button"), PostWithoutPreview("post_without_preview_button")
}

enum class AO3WorkFormKind { New, Edit, Draft, EditTags }

data class AO3FormOption(val value: String, val title: String, val isSelected: Boolean = false)
data class AO3ServedOption(
    val value: String,
    val text: String,
    val attributes: Map<String, String>,
    val disabled: Boolean
)

/**
 * Ordered, immutable snapshot, independent of the interpreted fields. Even unnamed,
 * unchecked, disabled and unknown controls and every option are retained here.
 * [values] are the browser's current values; [attributes] retain the literal served
 * attributes (including missing value, checked, selected and multiple distinctions).
 */
data class AO3ServedControl(
    val tag: String,
    val attributes: Map<String, String>,
    val text: String,
    val values: List<String>,
    val options: List<AO3ServedOption> = emptyList(),
    val disabled: Boolean = false,
    val browserChecked: Boolean = "checked" in attributes
) {
    val name: String get() = attributes["name"].orEmpty()
    val type: String get() = attributes["type"]?.lowercase() ?: if (tag == "button") "submit" else "text"

    fun successfulValues(submit: AO3WorkSubmitAction): List<String> = when {
        name.isEmpty() || disabled -> emptyList()
        tag == "input" && type in setOf("button", "reset", "image") -> emptyList()
        tag == "button" && type != "submit" -> emptyList()
        (tag == "button" || tag == "input" && type == "submit") && name != submit.fieldName -> emptyList()
        tag == "input" && type in setOf("checkbox", "radio") && !browserChecked -> emptyList()
        else -> values
    }
}

data class AO3WorkChapterDraft(
    val title: String = "", val summary: String = "", val content: String = "",
    val publishedYear: String = "", val publishedMonth: String = "", val publishedDay: String = "",
    /**
     * False when AO3's edit page left the text box out, as it does for a work with more than
     * one chapter (`_standard_form.html.erb`: `unless @chapters`) while still serving chapter
     * 1's title and date. The text is then neither shown nor sent: `works#update` assigns
     * what it is given to chapter 1, so an empty text was refused and took the whole save
     * with it, and a typed one would have replaced chapter 1 (audit A4-1, iOS the same).
     */
    val contentServed: Boolean = true
)
data class AO3ParentWorkDraft(
    val url: String = "", val title: String = "", val author: String = "",
    val languageID: String = "", val isTranslation: Boolean = false
)
data class AO3CreatorDraft(
    val selectedPseudIDs: List<String> = emptyList(),
    val availablePseuds: List<AO3FormOption> = emptyList(),
    val coauthorByline: String = ""
)
data class AO3SeriesMembership(val seriesID: Long, val title: String, val isSelected: Boolean = false)
data class AO3CurrentSeries(val seriesID: Long, val title: String, val serialWorkID: Long?)

/** In-memory work-picker offers; autocomplete describes only whether a collection is closed. */
data class AO3CollectionAccess(
    val isOpen: Boolean = true, val isModerated: Boolean = false,
    val isUnrevealed: Boolean = false, val isAnonymous: Boolean = false, val isDescribed: Boolean = true
)
data class AO3CollectionOffer(
    val name: String, val title: String, val access: AO3CollectionAccess = AO3CollectionAccess(),
    val isSelected: Boolean = false
)

object AO3WorkFormUrls {
    fun newWork() = "${AO3Constants.BASE_URL}/works/new"
    fun chapterIndex(workID: Long): String {
        require(workID > 0)
        return "${AO3Constants.BASE_URL}/works/$workID/navigate"
    }
    fun editWork(workID: Long): String {
        require(workID > 0)
        return "${AO3Constants.BASE_URL}/works/$workID/edit"
    }
}

/** Pure in-memory form data. No persistent schema or write API. */
data class AO3WorkForm(
    val kind: AO3WorkFormKind,
    val workID: Long?,
    val actionUrl: String,
    val csrfToken: String,
    val methodOverride: String?,
    val isPosted: Boolean,
    val servedControls: List<AO3ServedControl>,
    val formAttributes: Map<String, String>,
    val title: String = "",
    val rating: String = "",
    val ratingOptions: List<AO3FormOption> = emptyList(),
    val warnings: List<String> = emptyList(),
    val warningOptions: List<AO3FormOption> = emptyList(),
    val categories: List<String> = emptyList(),
    val categoryOptions: List<AO3FormOption> = emptyList(),
    val fandoms: List<String> = emptyList(),
    val relationships: List<String> = emptyList(),
    val characters: List<String> = emptyList(),
    val additionalTags: List<String> = emptyList(),
    val languageID: String = "",
    val languageOptions: List<AO3FormOption> = emptyList(),
    val summary: String = "",
    val notes: String = "",
    val endnotes: String = "",
    val collectionNames: List<String> = emptyList(),
    val collections: List<AO3CollectionOffer> = emptyList(),
    val gifts: List<String> = emptyList(),
    val series: List<AO3SeriesMembership> = emptyList(),
    val seriesOptions: List<AO3FormOption> = emptyList(),
    val newSeriesTitle: String = "",
    val currentSeries: List<AO3CurrentSeries> = emptyList(),
    val parentWork: AO3ParentWorkDraft = AO3ParentWorkDraft(),
    val parentLanguageOptions: List<AO3FormOption> = emptyList(),
    val existingParentTitles: List<String> = emptyList(),
    val chapter: AO3WorkChapterDraft? = null,
    val creators: AO3CreatorDraft = AO3CreatorDraft(),
    val chaptersPosted: Int? = null,
    val chapterTotal: String = "",
    val isChaptered: Boolean = false,
    val backdate: Boolean = false,
    val restricted: Boolean = false,
    val moderatedCommenting: Boolean = false,
    val commentPermissions: String = "",
    val commentPermissionOptions: List<AO3FormOption> = emptyList(),
    val anonymous: Boolean? = null,
    val collectionInbox: Boolean? = null,
    val workSkinID: String = "",
    val workSkinOptions: List<AO3FormOption> = emptyList()
) {
    val isDraft: Boolean get() = !isPosted
    val postedCollectionNames: List<String> get() = if (collections.isEmpty()) collectionNames
        else collections.filter { it.isSelected }.map { it.name }

    fun applyingCollectionStates(offers: List<AO3CollectionOffer>): AO3WorkForm {
        val merged = offers.map { offer -> offer.copy(isSelected = collectionNames.any { it.equals(offer.name, true) }) }
        val missing = collectionNames.filter { name -> offers.none { it.name.equals(name, true) } }
            .map { AO3CollectionOffer(it, it, isSelected = true) }
        return copy(collections = merged + missing)
    }

    fun missingRequiredFields(): List<String> = buildList {
        if (title.isBlank()) add("Title")
        if (rating.isBlank()) add("Rating")
        if (warnings.isEmpty()) add("Archive Warning")
        if (fandoms.isEmpty()) add("Fandoms")
        if (languageID.isBlank()) add("Language")
        if ((kind == AO3WorkFormKind.New || isDraft) && chapter?.let { it.contentServed && it.content.isBlank() } == true) add("Work Text")
    }

    fun parameters(submit: AO3WorkSubmitAction): List<Pair<String, String>> = AO3WorkFormEncoder.encode(this, submit)
}

// iOS AO3TagListDiff.split trims with Foundation's set. Kotlin's trim differs on a few characters
// (a zero-width space, NEL), so a served tag padded with one stayed a different chip from the
// same tag typed in the editor (audit A1-1).
internal fun splitWorkList(raw: String): List<String> = raw.split(',').map(::trimWritingTag).filter(String::isNotEmpty)
internal fun joinWorkList(names: List<String>): String = names.map(::trimWritingTag).filter(String::isNotEmpty).joinToString(", ")

/** Foundation whitespacesAndNewlines, rather than Kotlin's extra C0 separators. */
internal fun trimWritingTag(name: String): String = name.trim { char ->
    char in '\u0009'..'\u000d' || char == '\u0020' || char == '\u0085' || char == '\u00a0' ||
        char == '\u1680' || char in '\u2000'..'\u200b' || char == '\u2028' || char == '\u2029' ||
        char == '\u202f' || char == '\u205f' || char == '\u3000'
}
internal fun joinWritingTags(names: List<String>): String = joinWorkList(names)
