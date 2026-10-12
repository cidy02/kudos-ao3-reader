package io.github.cidy02.kudos.network.ao3.work

import io.github.cidy02.kudos.network.ao3.AO3OverloadDetector
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

sealed class AO3WorkMetadataParseException(message: String) : Exception(message) {
    class Overloaded : AO3WorkMetadataParseException("AO3 returned an overload or capacity page.")
}

class AO3WorkMetadataParser {
    fun parse(html: String, currentUsername: String? = null): AO3WorkMetadata {
        if (AO3OverloadDetector.isOverloadPage(html)) {
            throw AO3WorkMetadataParseException.Overloaded()
        }

        val document = Jsoup.parse(html)
        return AO3WorkMetadata(
            rating = document.selectFirst("dd.rating.tags")?.normalizedText().orEmpty(),
            fandoms = tags(document, "fandom"),
            relationships = tags(document, "relationship"),
            characters = tags(document, "character"),
            freeforms = tags(document, "freeform"),
            warnings = tags(document, "warning"),
            categories = tags(document, "category"),
            language = document.selectFirst("dd.language")?.normalizedText().orEmpty(),
            words = statInt(document, "words"),
            chapters = stat(document, "chapters"),
            kudos = statInt(document, "kudos"),
            comments = statInt(document, "comments"),
            hits = statInt(document, "hits"),
            kudosGivenByCurrentUser = currentUsername?.let { username ->
                document.selectFirst("#kudos a[href=\"/users/$username\"]") != null
            } ?: false,
            // The first byline is the work's; a chapter can carry one of its own further down.
            authorIdentitiesJSON = io.github.cidy02.kudos.network.ao3.author.AO3AuthorIdentities.json(
                document.selectFirst("h3.byline")?.select("a[rel=author]").orEmpty()
            ),
            title = document.selectFirst("h2.title.heading")?.normalizedText().orEmpty(),
            authors = document.selectFirst("h3.byline")?.select("a[rel=author]").orEmpty()
                .map { it.normalizedText() }.dedupeFirstSeen(),
            // The work's own: a chapter's summary sits in a preface of its own, without the title.
            summary = document.selectFirst("div.preface:has(h2.title) div.summary blockquote.userstuff")
                ?.normalizedText().orEmpty()
        )
    }

    private fun tags(root: Element, kind: String): List<String> {
        return root.select("dd.$kind.tags a.tag")
            .map { it.normalizedText() }
            .dedupeFirstSeen()
    }

    private fun stat(root: Element, kind: String): String {
        return root.selectFirst("dd.$kind")?.normalizedText().orEmpty()
    }

    private fun statInt(root: Element, kind: String): Int? {
        val digits = stat(root, kind).filter(Char::isDigit)
        return digits.takeIf { it.isNotEmpty() }?.toIntOrNull()
    }
}

private fun Element.normalizedText(): String {
    return text().replace(Regex("\\s+"), " ").trim()
}
