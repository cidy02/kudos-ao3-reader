package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import io.github.cidy02.kudos.network.ao3.AO3RedirectCookieRelay
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import okhttp3.HttpUrl.Companion.toHttpUrl

/** Collection scope only: AO3's collection default differs from its account-wide default. */
enum class AO3CollectionItemTab(val status: String?, val title: String) {
    Unreviewed(null, "Awaiting collection"),
    Invited("unreviewed_by_user", "Awaiting you"),
    Rejected("rejected_by_collection", "Rejected"),
    Approved("approved", "Approved")
}

enum class AO3CollectionItemApproval(val value: String, val title: String) {
    Unreviewed("unreviewed", "Awaiting"), Approved("approved", "Approved"), Rejected("rejected", "Rejected");

    companion object {
        fun from(value: String) = entries.firstOrNull { it.value == value.trim().lowercase() } ?: Unreviewed
    }
}

data class AO3CollectionItem(
    val id: Int,
    val collectionTitle: String,
    val workTitle: String,
    val role: String,
    val creatorByline: String,
    val dateText: String,
    val creatorApproval: AO3CollectionItemApproval,
    val moderatorApproval: AO3CollectionItemApproval,
    val unrevealed: Boolean,
    val anonymous: Boolean,
    val creatorEditable: Boolean,
    val moderatorEditable: Boolean,
    val unrevealedEditable: Boolean,
    val anonymousEditable: Boolean,
    val removeEditable: Boolean
)

data class AO3CollectionItemsPage(
    val items: List<AO3CollectionItem>,
    val tab: AO3CollectionItemTab,
    val currentPage: Int,
    val totalPages: Int,
    val actionUrl: String,
    val csrfToken: String,
    val methodOverride: String?
)

data class AO3CollectionItemDraft(
    val itemId: Int,
    val creatorApproval: AO3CollectionItemApproval? = null,
    val moderatorApproval: AO3CollectionItemApproval? = null,
    val unrevealed: Boolean? = null,
    val anonymous: Boolean? = null,
    val remove: Boolean = false
) {
    fun forItem(item: AO3CollectionItem) = copy(
        creatorApproval = creatorApproval.takeIf { item.creatorEditable },
        moderatorApproval = moderatorApproval.takeIf { item.moderatorEditable },
        unrevealed = unrevealed.takeIf { item.unrevealedEditable },
        anonymous = anonymous.takeIf { item.anonymousEditable },
        remove = remove && item.removeEditable
    )

    fun changes(item: AO3CollectionItem): Boolean = remove ||
        (creatorApproval != null && creatorApproval != item.creatorApproval) ||
        (moderatorApproval != null && moderatorApproval != item.moderatorApproval) ||
        (unrevealed != null && unrevealed != item.unrevealed) ||
        (anonymous != null && anonymous != item.anonymous)

    /** AO3Client.collectionItemParameters, including iOS's patch fallback. */
    fun parameters(page: AO3CollectionItemsPage): List<Pair<String, String>> = buildList {
        add("authenticity_token" to page.csrfToken)
        add("_method" to (page.methodOverride ?: "patch"))
        val prefix = "collection_items[$itemId]"
        if (remove) {
            add("$prefix[remove]" to "1")
        } else {
            creatorApproval?.let { add("$prefix[user_approval_status]" to it.value) }
            moderatorApproval?.let { add("$prefix[collection_approval_status]" to it.value) }
            unrevealed?.let { add("$prefix[unrevealed]" to if (it) "1" else "0") }
            anonymous?.let { add("$prefix[anonymous]" to if (it) "1" else "0") }
        }
    }
}

/** Immutable staging keeps off-page drafts, but only visible, editable changes are submitted. */
data class AO3CollectionItemStaging(val drafts: Map<Int, AO3CollectionItemDraft> = emptyMap()) {
    fun shown(item: AO3CollectionItem) = (drafts[item.id] ?: AO3CollectionItemDraft(item.id)).forItem(item)
    fun pending(items: List<AO3CollectionItem>) = items.mapNotNull { item ->
        drafts[item.id]?.forItem(item)?.takeIf { it.changes(item) }
    }.sortedBy { it.itemId }
    fun set(item: AO3CollectionItem, change: (AO3CollectionItemDraft) -> AO3CollectionItemDraft) =
        copy(drafts = drafts + (item.id to change(shown(item))))
    fun remove(item: AO3CollectionItem, removed: Boolean) =
        copy(drafts = drafts + (item.id to AO3CollectionItemDraft(item.id, remove = removed)))
    fun clear(ids: List<Int>) = copy(drafts = drafts - ids.toSet())
}

object AO3CollectionItemsUrls {
    fun page(slug: String, tab: AO3CollectionItemTab, page: Int): String =
        AO3Constants.BASE_URL.toHttpUrl().newBuilder().addPathSegment("collections")
            .addPathSegment(slug).addPathSegment("items").apply {
                tab.status?.let { addQueryParameter("status", it) }
                if (page > 1) addQueryParameter("page", page.toString())
            }.build().toString()
}

class AO3CollectionItemsParser {
    fun parse(html: String, slug: String, tab: AO3CollectionItemTab, page: Int): AO3CollectionItemsPage {
        require(!AO3OverloadDetector.isOverloadPage(html)) { "AO3 is busy. Try again shortly." }
        val url = AO3CollectionItemsUrls.page(slug, tab, page)
        val doc = Jsoup.parse(html, url)
        require(doc.selectFirst("form#new_user, form[action='/users/login']") == null) {
            "Log in to AO3 to manage collection items."
        }
        val form = doc.selectFirst("form[action*='/items'], form[action*='collection_items']")
            ?: doc.selectFirst("#main form")
        val nodes = doc.select("li.collection.item, li.item.blurb")
        val items = nodes.mapNotNull { parseItem(it, slug) }.distinctBy { it.id }
        if (items.isEmpty()) {
            val heading = doc.select("h2.heading").text().lowercase()
            require(heading.contains("item") || heading.contains("collection") ||
                doc.selectFirst("ul.navigation.actions, p.note") != null) {
                "Couldn't read AO3's collection items."
            }
        }
        val action = form?.takeIf { it.attr("action").isNotBlank() }?.attr("abs:action")?.takeIf { it.isNotBlank() }
            ?: "${AO3Constants.BASE_URL}/collections/$slug/items/update_multiple"
        require(AO3RedirectCookieRelay.isTrustedUrl(action)) { "AO3 returned an untrusted form address." }
        val csrf = doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.takeIf { it.isNotBlank() }
            ?: form?.selectFirst("input[name=authenticity_token]")?.attr("value").orEmpty()
        val total = doc.select("ol.pagination li").mapNotNull { it.text().toIntOrNull() }
            .fold(page) { count, number -> maxOf(count, number) }
        return AO3CollectionItemsPage(items, tab, page, total, action, csrf,
            form?.selectFirst("input[name=_method]")?.attr("value")?.takeIf { it.isNotBlank() })
    }

    private fun parseItem(li: Element, slug: String): AO3CollectionItem? {
        val id = li.selectFirst("h4.heading")?.id()?.removePrefix("collection_item_")?.toIntOrNull()
            ?: li.select("select, input").firstNotNullOfOrNull {
                Regex("^collection_items\\[(\\d+)]").find(it.attr("name"))?.groupValues?.get(1)?.toIntOrNull()
            } ?: return null
        if (id == 0) return null
        fun select(suffix: String) = li.select("select").firstOrNull { it.attr("name").endsWith("[$suffix]") }
        fun box(suffix: String) = li.select("input[type=checkbox]").firstOrNull { it.attr("name").endsWith("[$suffix]") }
        fun editable(control: Element?) = control?.hasAttr("disabled") != true // iOS's absent-control rule.
        fun approval(control: Element?) = AO3CollectionItemApproval.from(
            (control?.selectFirst("option[selected]") ?: control?.selectFirst("option"))?.attr("value").orEmpty()
        )
        val user = select("user_approval_status")
        val moderator = select("collection_approval_status")
        val unrevealed = box("unrevealed")
        val anonymous = box("anonymous")
        val byline = li.selectFirst("h5.heading")?.text().orEmpty()
        val role = listOf("Member", "Owner", "Moderator").lastOrNull { byline.contains("($it)", true) }.orEmpty()
        return AO3CollectionItem(id,
            li.selectFirst("span.collection a, h5.heading a[href*='/collections/']")?.text()?.ifBlank { slug } ?: slug,
            li.selectFirst("h4.heading a")?.text().orEmpty(), role, byline,
            li.selectFirst("p.datetime")?.text().orEmpty(), approval(user), approval(moderator),
            unrevealed?.hasAttr("checked") == true, anonymous?.hasAttr("checked") == true,
            editable(user), editable(moderator), editable(unrevealed), editable(anonymous), editable(box("remove")))
    }
}
