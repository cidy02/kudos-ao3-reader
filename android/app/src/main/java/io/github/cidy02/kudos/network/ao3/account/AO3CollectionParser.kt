package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

class AO3CollectionParser {
    fun parseCollectionShow(html: String, slug: String): AO3CollectionShow {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3AccountParseException.Overloaded()
        val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
        val title = doc.selectFirst("div.primary.header.module h2.heading")?.normalizedText().orEmpty()
        val typeText = doc.selectFirst("p.type")?.normalizedText().orEmpty().lowercase()
        val isClosed = typeText.contains("closed")
        val isModerated = typeText.contains("moderated") && !typeText.contains("unmoderated")
        val isUnrevealed = typeText.contains("unrevealed")
        val isAnonymous = typeText.contains("anonymous")
        val challengeKind = when {
            typeText.contains("gift exchange") -> AO3ChallengeKind.GiftExchange
            typeText.contains("prompt meme") -> AO3ChallengeKind.PromptMeme
            else -> null
        }
        val iconUrl = doc.selectFirst("div.primary.header.module .icon img, .collection .icon img")?.attr("abs:src")
        val headerImageUrl = doc.selectFirst("img.collection-header, .header img[src*=header]")?.attr("abs:src")
        val description = doc.selectFirst("div.primary.header.module > blockquote.userstuff")?.normalizedText().orEmpty()
        
        val intro = doc.selectFirst("#intro, div#intro")?.normalizedText().orEmpty()
        val faq = doc.selectFirst("#faq, div#faq")?.normalizedText().orEmpty()
        val rules = doc.selectFirst("#rules, div#rules")?.normalizedText().orEmpty()
        
        val maintainerLinks = doc.select("a.owner, a.mod, h4.heading a[href*=/users/]")
        val maintainerIdentities = maintainerLinks.map { link ->
            AO3AuthorIdentity(displayName = link.normalizedText(), href = link.attr("href"))
        }
        
        val editPath = "/collections/$slug/edit"
        val viewerIsOwner = doc.select("a[href]").any { it.attr("href").endsWith(editPath) }
        
        val header = doc.selectFirst("div.primary.header.module")
        val worksCount = header?.let { intStat("works", it) } ?: navCount(doc, "/collections/$slug/works") ?: 0
        val bookmarksCount = header?.let { intStat("bookmarks", it) } ?: navCount(doc, "/collections/$slug/bookmarks") ?: 0
        
        val nav = doc.select("ul.navigation.actions").map { it.normalizedText() }.joinToString(" ")
        val hasJoin = doc.selectFirst("form[action*=/participants/join]") != null || nav.contains("Join", ignoreCase = true)
        val leaveLink = doc.selectFirst("a[href*=/participants/][data-method=delete], a[href*=/participants/]")
        val leaveId = leaveLink?.attr("href")?.let { pathId(it, "participants") }
        val canLeave = leaveId != null && leaveLink.normalizedText().contains("Leave", ignoreCase = true)
        val isMaintainer = nav.contains("Manage Items", ignoreCase = true) || nav.contains("Membership", ignoreCase = true)
        
        val dashboard = parseDashboard(doc, slug)
        
        val collection = AO3Collection(
            name = slug,
            title = title.ifEmpty { slug },
            byline = maintainerIdentities.joinToString(", ") { it.displayName },
            maintainerNames = maintainerIdentities.map { it.displayName },
            maintainerIdentities = maintainerIdentities,
            isClosed = isClosed,
            isModerated = isModerated,
            isUnrevealed = isUnrevealed,
            isAnonymous = isAnonymous,
            worksCount = worksCount,
            bookmarksCount = bookmarksCount,
            iconURL = iconUrl,
            summary = description,
            challengeKind = challengeKind,
            viewerIsOwner = viewerIsOwner
        )
        
        return AO3CollectionShow(
            collection = collection,
            headerImageUrl = headerImageUrl,
            introduction = intro,
            faq = faq,
            rules = rules,
            canJoin = hasJoin,
            canLeave = canLeave,
            leaveParticipantId = leaveId,
            canPostWork = dashboard.postToCollectionUrl != null,
            isMaintainer = isMaintainer,
            dashboard = dashboard
        )
    }
    
    fun parseCollectionPeoplePage(html: String, page: Int): AO3CollectionPeoplePage {
        if (AO3OverloadDetector.isOverloadPage(html)) throw AO3AccountParseException.Overloaded()
        val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
        val blurbs = doc.select("ul.participant.pseud.index li, li.user.pseud.blurb, li.pseud.blurb")
        val people = blurbs.mapNotNull { li ->
            val link = li.selectFirst("h4.heading a[href*=/users/], h5.heading a[href*=/users/], a[href*=/users/]") ?: return@mapNotNull null
            val name = link.normalizedText()
            val href = link.attr("href")
            val identity = AO3AuthorIdentity(name, href)
            val works = intStat("works", li)
            AO3CollectionPerson(id = href, identity = identity, workCount = works)
        }
        val totalPages = doc.select("ol.pagination li")
            .mapNotNull { it.normalizedText().toIntOrNull() }
            .fold(page) { acc, p -> maxOf(acc, p) }
        return AO3CollectionPeoplePage(people, page, totalPages)
    }

    private fun parseDashboard(doc: Document, slug: String): AO3CollectionDashboard {
        val nodes = doc.select("#dashboard a, ul.navigation.actions a")
        fun link(containing: String): String? {
            return nodes.firstOrNull { it.attr("href").contains(containing) }?.attr("abs:href")
        }
        return AO3CollectionDashboard(
            profileUrl = link("/profile") ?: AO3Constants.BASE_URL + "/collections/$slug/profile",
            worksUrl = link("/works") ?: AO3Constants.BASE_URL + "/collections/$slug/works",
            bookmarksUrl = link("/bookmarks") ?: AO3Constants.BASE_URL + "/collections/$slug/bookmarks",
            peopleUrl = link("/people") ?: AO3Constants.BASE_URL + "/collections/$slug/people",
            itemsUrl = link("/items"),
            participantsUrl = link("/participants"),
            signUpsUrl = link("/signups"),
            assignmentsUrl = link("/assignments"),
            promptsUrl = link("/requests"),
            challengeSettingsUrl = link("/gift_exchange") ?: link("/prompt_meme"),
            postToCollectionUrl = link("/works/new")
        )
    }

    private fun intStat(kind: String, element: Element): Int? {
        val text = element.selectFirst("dl.stats dd.$kind")?.normalizedText().orEmpty()
        val digits = text.filter { it.isDigit() }
        return digits.toIntOrNull()
    }

    private fun navCount(doc: Document, path: String): Int? {
        val link = doc.select("ul.navigation a[href]").firstOrNull { it.attr("href").endsWith(path) }
        val text = link?.normalizedText().orEmpty()
        if (text.endsWith(")")) {
            val open = text.lastIndexOf("(")
            if (open != -1) {
                return text.substring(open).filter { it.isDigit() }.toIntOrNull()
            }
        }
        return null
    }

    private fun pathId(href: String, segment: String): Int? {
        val parts = href.split("/")
        val index = parts.indexOf(segment)
        if (index != -1 && index + 1 < parts.size) {
            val raw = parts[index + 1].substringBefore("?")
            return raw.toIntOrNull()
        }
        return null
    }
}

private fun Element.normalizedText(): String {
    return text().replace(Regex("\\s+"), " ").trim()
}
