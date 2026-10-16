package io.github.cidy02.kudos.network.ao3.author

import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.writes.normalizedText
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

class AO3AuthorParseException(message: String) : Exception(message)

/**
 * Parses AO3 author dashboard / profile / series / bookmarks HTML.
 * Port of iOS `AO3Client+Authors` parsers.
 */
class AO3AuthorParser(
    private val searchParser: AO3SearchParser = AO3SearchParser()
) {
    fun parseDashboard(html: String, route: AO3AuthorRoute): AO3AuthorHeader {
        val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
        if (doc.selectFirst("div.user.home, div.user.pseud.home") == null ||
            doc.selectFirst("div.primary.header.module") == null
        ) {
            throw AO3AuthorParseException("Not an AO3 author dashboard page.")
        }
        val avatarUrl = absoluteUrl(
            doc.selectFirst("div.primary.header.module .icon img")?.attr("src")
        )
        var pseuds = parsePseuds(
            doc.select("#dashboard a[href*=/pseuds/], dd.pseuds a[href*=/pseuds/]"),
            route.username
        )
        val selected = route.pseud
        if (selected != null && pseuds.none { it.route.pseud.equals(selected, true) }) {
            pseuds = pseuds + AO3AuthorPseud(
                name = selected,
                route = AO3AuthorRoute(route.username, selected),
                avatarUrl = avatarUrl
            )
        }
        if (selected != null) {
            pseuds = pseuds.map {
                if (it.route.pseud.equals(selected, true)) it.copy(avatarUrl = avatarUrl) else it
            }
        }
        pseuds = pseuds.distinctBy { it.route.id }.sortedBy { it.name.lowercase() }

        val fandoms = doc.select("#user-fandoms li").mapNotNull { item ->
            val link = item.selectFirst("a") ?: return@mapNotNull null
            val name = link.normalizedText()
            if (name.isBlank()) return@mapNotNull null
            val url = absoluteUrl(link.attr("href")) ?: return@mapNotNull null
            val count = trailingCount(item.normalizedText())
            AO3AuthorFandom(name = name, workCount = count, url = url)
        }

        val subscription = parseSubscriptionForm(doc, route.dashboardUrl)
        val actions = parseActions(
            doc.select("div.primary.header.module ul.navigation.actions a, #dashboard a"),
            route.username
        )
        return AO3AuthorHeader(
            username = route.username,
            displayName = route.displayName,
            avatarUrl = avatarUrl,
            userId = parseUserId(doc),
            pseuds = pseuds,
            fandoms = fandoms,
            subscriptionForm = subscription,
            actions = actions,
            recentWorks = parseDashboardGroup(doc, "#user-works li.work.blurb") {
                runCatching { searchParser.parseWorkSummary(it) }.getOrNull()
            },
            recentSeries = parseDashboardGroup(doc, "#user-series li.series.blurb", ::parseSeriesBlurb),
            recentBookmarks = parseDashboardGroup(doc, "#user-bookmarks li.bookmark.blurb", ::parseBookmark)
        )
    }

    /**
     * As iOS: a missing group is AO3's empty state (an empty list); one blurb that will not
     * parse makes that group unreadable (null), never a shorter list, and its siblings stand.
     */
    private fun <T> parseDashboardGroup(doc: Document, selector: String, parse: (Element) -> T?): List<T>? =
        doc.select(selector).map { parse(it) ?: return null }

    fun parseAbout(html: String, route: AO3AuthorRoute): AO3AuthorAbout {
        val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
        if (doc.selectFirst("div.user.home.profile") == null) {
            throw AO3AuthorParseException("Not an AO3 author profile page.")
        }
        val title = doc.selectFirst("div.user.home.profile > h3.heading")
            ?.normalizedText().orEmpty()
        val bioElement = doc.selectFirst("div.bio blockquote.userstuff")
        val bio = bioElement?.normalizedText().orEmpty()
        val pseuds = parsePseuds(
            doc.select("dl.meta dd.pseuds a[href*=/pseuds/]"),
            route.username
        ).distinctBy { it.route.id }
        val actions = parseActions(
            doc.select("div.user.home.profile ul.navigation.actions a"),
            route.username
        )
        return AO3AuthorAbout(
            profileTitle = title,
            bioText = bio,
            pseuds = pseuds,
            joinedDate = metadataValue(doc, "joined"),
            userId = parseUserId(doc),
            actions = actions,
            bioHtml = bioElement?.html()?.takeIf { bio.isNotEmpty() }.orEmpty()
        )
    }

    fun parseSeriesPage(html: String, page: Int): AO3AuthorSeriesPage {
        val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
        val blurbs = doc.select("li.series")
        val series = blurbs.mapNotNull { parseSeriesBlurb(it) }
        if (blurbs.isEmpty()) {
            val recognized = doc.selectFirst("ul.series.index, h2.heading, p.message, .flash") != null
            if (!recognized) throw AO3AuthorParseException("Not an AO3 author series page.")
        }
        return AO3AuthorSeriesPage(
            series = series,
            currentPage = page.coerceAtLeast(1),
            totalPages = paginationTotal(doc, page)
        )
    }

    fun parseBookmarksPage(html: String, page: Int): AO3AuthorBookmarksPage {
        val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
        val blurbs = doc.select("li.bookmark.blurb")
        val bookmarks = blurbs.mapNotNull { parseBookmark(it) }
        if (blurbs.isEmpty()) {
            val recognized = doc.selectFirst("ol.bookmark.index, h2.heading, p.message, .flash") != null
            if (!recognized) throw AO3AuthorParseException("Not an AO3 author bookmarks page.")
        }
        return AO3AuthorBookmarksPage(
            bookmarks = bookmarks,
            currentPage = page.coerceAtLeast(1),
            totalPages = paginationTotal(doc, page)
        )
    }

    /**
     * The Totals block of the stats page. Only that block: every work listed under it has a
     * `dd.kudos` of its own. A figure is found by its whole set of class names, because "user
     * subscriptions" also carries the class "subscriptions". No block is an account with no
     * works, not a page that could not be read.
     */
    fun parseUserStats(html: String): AO3UserStats {
        val totals = Jsoup.parse(html).selectFirst("dl.statistics.meta") ?: return AO3UserStats()
        val figures = totals.select("dd").mapNotNull { dd ->
            dd.text().filter(Char::isDigit).toIntOrNull()?.let { dd.classNames().sorted().joinToString(" ") to it }
        }.toMap()
        return AO3UserStats(
            wordCount = figures["words"], kudos = figures["kudos"], hits = figures["hits"],
            bookmarks = figures["bookmarks"], commentThreads = figures["comment count thread"],
            subscriptions = figures["subscriptions"], userSubscriptions = figures["subscriptions user"]
        )
    }

    fun parseWorksPage(html: String, page: Int): io.github.cidy02.kudos.network.ao3.search.AO3SearchPage {
        val result = searchParser.parseSearchPage(html, page)
        val doc = Jsoup.parse(html, AO3Constants.BASE_URL)
        val blurbs = doc.select("li.work.blurb")
        if ((blurbs.isEmpty() && doc.selectFirst("ol.work.index, h2.heading, p.message, .flash") == null) ||
            (blurbs.isNotEmpty() && result.works.isEmpty())
        ) throw AO3AuthorParseException("AO3 author works markup was not recognized.")
        return result
    }

    private fun parseSeriesBlurb(element: Element): AO3AuthorSeriesSummary? {
        val titleLink = element.selectFirst("h4.heading a[href*=/series/]") ?: return null
        val url = absoluteUrl(titleLink.attr("href")) ?: return null
        val id = Regex("""/series/(\d+)""").find(url)?.groupValues?.getOrNull(1)?.toLongOrNull()
            ?: return null
        val creators = element.select("h4.heading a[rel=author], h4.heading a[href*=/pseuds/]")
            .map { it.normalizedText() }
            .filter { it.isNotBlank() }
            .ifEmpty {
                if (element.normalizedText().contains("Anonymous", ignoreCase = true)) {
                    listOf("Anonymous")
                } else emptyList()
            }
        val status = element.selectFirst("ul.required-tags .iswip .text")?.normalizedText().orEmpty()
        return AO3AuthorSeriesSummary(
            id = id,
            title = titleLink.normalizedText(),
            creators = creators,
            fandoms = element.select("h5.fandoms a.tag").map { it.normalizedText() },
            summary = element.selectFirst("blockquote.userstuff.summary")?.normalizedText().orEmpty(),
            words = statInt(element, "words"),
            workCount = statInt(element, "works"),
            dateUpdated = element.selectFirst("p.datetime")?.normalizedText().orEmpty(),
            isComplete = seriesCompletion(status),
            url = url,
            creatorUsernames = ao3CreatorUsernames(element.select("h4.heading a[rel=author], h4.heading a[href*=/pseuds/]")
                .mapNotNull { absoluteUrl(it.attr("href")) }),
            bookmarkCount = statInt(element, "bookmarks"),
            // The heading's image only, as iOS: a summary that says "restricted" is not a lock.
            isRestricted = element.select("h4.heading img").any {
                it.attr("src").contains("lockblue", true) || it.attr("title").equals("Restricted", true) ||
                    it.attr("alt").contains("restricted", true)
            }
        )
    }

    private fun parseBookmark(element: Element): AO3AuthorBookmark? {
        val idRaw = element.id().removePrefix("bookmark_")
        val id = idRaw.toLongOrNull() ?: return null
        val work = runCatching {
            // Reuse search parser on a single-blurb fragment when possible.
            val page = searchParser.parseSearchPage(
                "<ol class=\"work index group\">${element.outerHtml()}</ol>",
                page = 1
            )
            page.works.firstOrNull()
        }.getOrNull() ?: extractWorkSummaryFallback(element)
        val notes = element.selectFirst("div.user.module blockquote.userstuff.notes")
            ?.normalizedText().orEmpty()
        val status = element.selectFirst("p.status")?.outerHtml()?.lowercase().orEmpty()
        return AO3AuthorBookmark(
            id = id,
            work = work,
            notes = notes,
            tags = element.select("div.user.module ul.meta.tags a.tag").map { it.normalizedText() },
            isRecommendation = element.hasClass("rec") || status.contains("recommend"),
            isPrivate = element.hasClass("private") || status.contains("private"),
            date = element.selectFirst("div.user.module p.datetime")?.normalizedText().orEmpty()
        )
    }

    private fun extractWorkSummaryFallback(element: Element): AO3WorkSummary? {
        val link = element.selectFirst("h4.heading a[href*=/works/]") ?: return null
        val href = absoluteUrl(link.attr("href")) ?: return null
        val workId = Regex("""/works/(\d+)""").find(href)?.groupValues?.getOrNull(1)?.toLongOrNull()
            ?: return null
        val authors = element.select("h4.heading a[rel=author]").map { it.normalizedText() }
        return AO3WorkSummary(
            id = workId,
            title = link.normalizedText(),
            authors = authors,
            fandoms = element.select("h5.fandoms a.tag").map { it.normalizedText() },
            rating = element.selectFirst("ul.required-tags .rating .text")?.normalizedText().orEmpty(),
            warnings = emptyList(),
            categories = emptyList()
        )
    }

    private fun parsePseuds(elements: org.jsoup.select.Elements, username: String): List<AO3AuthorPseud> {
        return elements.mapNotNull { link ->
            val name = link.normalizedText()
            val href = link.attr("href")
            val route = routeFromPath(href) ?: return@mapNotNull null
            if (!route.username.equals(username, true) || route.pseud.isNullOrBlank() || name.isBlank()) {
                return@mapNotNull null
            }
            AO3AuthorPseud(name = name, route = route)
        }
    }

    private fun parseSubscriptionForm(doc: Document, referer: String): AO3AuthorSubscriptionForm? {
        val csrf = doc.selectFirst("input[name=authenticity_token]")?.attr("value")?.trim()
            ?: doc.selectFirst("meta[name=csrf-token]")?.attr("content")?.trim()
            ?: return null
        for (form in doc.select("form")) {
            val type = form.selectFirst("input[name=subscription\\[subscribable_type\\]]")
                ?.attr("value")
                ?: form.selectFirst("input[name=\"subscription[subscribable_type]\"]")
                    ?.attr("value")
                ?: continue
            if (!type.equals("User", ignoreCase = true)) continue
            val action = absoluteUrl(form.attr("action")) ?: continue
            val submit = form.selectFirst("input[type=submit], button[type=submit]")
            val label = submit?.attr("value")?.takeIf { it.isNotBlank() }
                ?: submit?.normalizedText().orEmpty()
            val fields = form.select("input[name]").map {
                it.attr("name") to it.attr("value")
            }
            return AO3AuthorSubscriptionForm(
                label = label,
                actionUrl = action,
                fields = fields,
                csrfToken = csrf,
                referer = referer
            )
        }
        return null
    }

    private fun parseActions(
        links: org.jsoup.select.Elements,
        username: String
    ): List<AO3AuthorWebAction> {
        val seen = mutableSetOf<String>()
        return links.mapNotNull { link ->
            val label = link.normalizedText()
            val url = absoluteUrl(link.attr("href")) ?: return@mapNotNull null
            if (label.isBlank() || !seen.add(url)) return@mapNotNull null
            val lower = label.lowercase()
            val path = url.lowercase()
            val usernamePath = "/users/${username.lowercase()}"
            val kind = when {
                lower.contains("block") || path.contains("blocked") ->
                    AO3AuthorWebAction.Kind.Block
                lower.contains("mute") || path.contains("muted") ->
                    AO3AuthorWebAction.Kind.Mute
                path.endsWith("$usernamePath/profile") || path.endsWith("$usernamePath/profile/edit") ->
                    AO3AuthorWebAction.Kind.Profile
                path.contains("/works") -> AO3AuthorWebAction.Kind.Works
                path.contains("/preferences") -> AO3AuthorWebAction.Kind.Preferences
                path.endsWith(usernamePath) || path.endsWith("$usernamePath/") ->
                    AO3AuthorWebAction.Kind.Dashboard
                else -> AO3AuthorWebAction.Kind.Other
            }
            AO3AuthorWebAction(label = label, url = url, kind = kind)
        }
    }

    private fun metadataValue(doc: Document, needle: String): String {
        for (label in doc.select("dl.meta dt")) {
            if (label.normalizedText().lowercase().contains(needle)) {
                return label.nextElementSibling()?.normalizedText().orEmpty()
            }
        }
        return ""
    }

    private fun parseUserId(doc: Document): Long? {
        val value = metadataValue(doc, "user id")
        return value.filter { it.isDigit() }.toLongOrNull()
    }

    private fun paginationTotal(doc: Document, currentPage: Int): Int {
        return doc.select("ol.pagination li")
            .mapNotNull { it.normalizedText().toIntOrNull() }
            .fold(currentPage.coerceAtLeast(1)) { acc, n -> maxOf(acc, n) }
    }

    /**
     * iOS `seriesCompletion`. AO3 writes "Series Complete: Yes" or "Series Complete: No", and
     * both say "complete": every unfinished series was read as finished.
     */
    private fun seriesCompletion(text: String): Boolean? {
        val value = text.lowercase()
        return when {
            Regex("""\byes\b""").containsMatchIn(value) -> true
            Regex("""\bno\b""").containsMatchIn(value) -> false
            "in progress" in value || "incomplete" in value -> false
            "complete" in value -> true
            else -> null
        }
    }

    private fun statInt(element: Element, cssClass: String): Int? {
        // Never the label: where a "Words:" <dt> carries the class too it comes first, and the
        // figure after it was read as nothing.
        val text = element.select("dl.stats dd.$cssClass, .stats .$cssClass").firstOrNull { it.tagName() != "dt" }
            ?.normalizedText()
            ?: return null
        return text.filter { it.isDigit() }.toIntOrNull()
    }

    private fun trailingCount(text: String): Int? {
        val match = Regex("""\((\d[\d,]*)\)\s*$""").find(text) ?: return null
        return match.groupValues[1].replace(",", "").toIntOrNull()
    }

    /**
     * Resolved, so the names are decoded. A pseud of two words was kept as "Avery%20Writes":
     * it matched no chosen pseud (listed twice, never ticked), and choosing it asked AO3 for
     * "Avery%2520Writes", which is nobody.
     */
    private fun routeFromPath(href: String): AO3AuthorRoute? {
        val path = AO3Constants.baseHttpUrl.resolve(href.trim())?.pathSegments ?: return null
        val at = path.indexOf("users")
        val user = path.getOrNull(at + 1)?.takeIf { at >= 0 && it.isNotBlank() } ?: return null
        val pseud = path.getOrNull(at + 3)?.takeIf { path.getOrNull(at + 2) == "pseuds" && it.isNotBlank() }
        return AO3AuthorRoute(user, pseud)
    }

    private fun absoluteUrl(href: String?): String? {
        val raw = href?.trim().orEmpty()
        if (raw.isEmpty()) return null
        if (raw.startsWith("http://") || raw.startsWith("https://")) return raw
        return try {
            AO3Constants.baseHttpUrl.resolve(raw)?.toString()
        } catch (_: Exception) {
            null
        }
    }
}
