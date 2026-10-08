package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.jsoup.Jsoup

/** Remote page values only; never stored in Room or a backup. */
data class AO3PromptMemePrompt(
    val id: Int,
    val title: String,
    val promptText: String,
    val fandoms: List<String>,
    val tags: List<String>,
    val isAnonymous: Boolean,
    val ownerPseud: String?,
    val claimID: Int?,
    val claimantCount: Int,
    val canClaim: Boolean
) {
    val claimedByCurrentUser get() = claimID != null
    val isClaimed get() = claimantCount > 0 || claimedByCurrentUser
    val displayedOwner get() = if (isAnonymous) null else ownerPseud
}

data class AO3PromptMemePage(val prompts: List<AO3PromptMemePrompt>, val currentPage: Int, val totalPages: Int)

enum class AO3PromptMemeFilter(val label: String) {
    All("All"), Unclaimed("Unclaimed"), Yours("Yours");

    fun includes(prompt: AO3PromptMemePrompt, login: String): Boolean = when (this) {
        All -> true
        Unclaimed -> !prompt.isClaimed
        Yours -> {
            val name = login.trim().lowercase()
            val byline = prompt.displayedOwner.orEmpty().trim().lowercase()
            prompt.claimedByCurrentUser || (name.isNotEmpty() && (byline == name || byline.endsWith("($name)")))
        }
    }
}

object AO3PromptMemeUrls {
    fun requests(slug: String, page: Int = 1): String = ChallengeSettingsDestinations.promptMemeView(slug).toHttpUrl()
        .newBuilder().apply { if (page > 1) addQueryParameter("page", page.toString()) }.build().toString()
    fun meme(slug: String) = "${AO3CollectionFormUrls.show(slug)}/prompt_meme"
}

/** iOS parsePromptMemePage / parsePromptMemeCard, including negative identity fallbacks. */
class AO3PromptMemeParser {
    fun parse(html: String, page: Int = 1): AO3PromptMemePage {
        require(!AO3OverloadDetector.isOverloadPage(html)) { "AO3 is busy. Try again shortly." }
        val doc = Jsoup.parse(html)
        require(doc.selectFirst("form#new_user, form[action='/users/login']") == null) { "Log in to AO3 first." }
        fun resourceID(href: String, resource: String) = Regex("/$resource/(\\d+)(?:/|$|[?#])")
            .find(href)?.groupValues?.get(1)?.toIntOrNull()
        val prompts = doc.select("ul.prompt.index > li.blurb").mapIndexed { index, li ->
            val claimAction = li.selectFirst("form[action*='/claims']")?.attr("action").orEmpty()
            val promptID = runCatching {
                AO3Constants.BASE_URL.toHttpUrl().resolve(claimAction)?.queryParameter("prompt_id")?.toIntOrNull()
            }.getOrNull()
            val promptLink = li.selectFirst("a[href*='/prompts/']")?.attr("href").orEmpty()
            val dropClaim = li.selectFirst("a[href*='/claims/'][data-method=delete]")?.attr("href").orEmpty()
            var heading = li.selectFirst("div.header h4.heading")?.text().orEmpty()
            var owner: String? = null
            val by = heading.lastIndexOf(" by ")
            if (by >= 0) {
                owner = heading.substring(by + 4).trim()
                heading = heading.substring(0, by)
            } else if (heading.startsWith("by ")) {
                owner = heading.substring(3)
                heading = ""
            }
            val anonymous = owner == "Anonymous"
            heading = heading.trim()
            val anonymousClaims = Regex("(\\d+) anonymous claimant")
                .find(li.selectFirst("div.claims ul")?.ownText().orEmpty())?.groupValues?.get(1)?.toIntOrNull() ?: 0
            AO3PromptMemePrompt(
                id = promptID ?: resourceID(promptLink, "prompts") ?: -(index + 1),
                title = if (heading == "Request") "" else heading,
                promptText = li.select("blockquote.userstuff.summary").text(),
                fandoms = li.select("h5.fandoms a.tag").map { it.text() },
                tags = li.select("ul.tags:not(.optional) a.tag, ul.tags:not(.optional) li.tag").map { it.text() },
                isAnonymous = anonymous, ownerPseud = if (anonymous) null else owner,
                claimID = resourceID(dropClaim, "claims"),
                claimantCount = maxOf(li.select("div.claims li").size, anonymousClaims),
                canClaim = promptID != null
            )
        }
        if (prompts.isEmpty()) {
            val heading = doc.selectFirst("h2.heading")?.text().orEmpty().lowercase()
            require(listOf("prompt", "request", "meme").any { it in heading } || doc.selectFirst("p.note, p.message") != null) {
                "Unrecognized prompts page"
            }
        }
        val total = doc.select("ol.pagination li").mapNotNull { it.text().trim().toIntOrNull() }.fold(page, ::maxOf)
        return AO3PromptMemePage(prompts, page, total)
    }
}
