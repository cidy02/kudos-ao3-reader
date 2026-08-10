package io.github.cidy02.kudos.works.converters

/**
 * Identifies author's notes among a work's paragraphs, so the reader can present
 * them as apparatus rather than as prose.
 *
 * Faithful port of iOS `AuthorNoteDetector`. In an AO3 HTML download notes are
 * marked up (`div.notes`) and rewritten structurally. In a PDF or `.txt` there is
 * no markup, so notes are recognised from the text — which is what this type does.
 *
 * **Scope is the safety mechanism.** Phrases that read like ordinary narration
 * are only trusted at the start or end of a work. Only unambiguous markers
 * (`A/N:`, `Disclaimer:`) are trusted anywhere. A false positive that demotes
 * real prose is worse than a missed note.
 *
 * Do not invent simpler heuristics or retune the phrase list — iOS's list has
 * already been thought about. To add a phrase, mirror iOS + add a real-fixture
 * test case.
 */
object AuthorNoteDetector {
    /** Where in the work a given indicator may be believed. */
    enum class Scope {
        /** Trusted anywhere — the phrase is never plausible narration. */
        ANYWHERE,
        /** Only in the opening blocks, where a pre-chapter note sits. */
        OPENING,
        /** Only in the closing blocks, where a sign-off sits. */
        CLOSING,
        /** Either end, but not the middle. */
        EDGES
    }

    data class Indicator(
        val name: String,
        val scope: Scope,
        val matches: (String) -> Boolean
    ) {
        companion object {
            /** Case-insensitive prefix match (any of [prefixes]). */
            fun prefix(name: String, scope: Scope, prefixes: List<String>): Indicator =
                Indicator(name, scope) { text ->
                    val lowered = text.lowercase()
                    prefixes.any { lowered.startsWith(it.lowercase()) }
                }

            /** Case-insensitive substring match (any of [phrases]). */
            fun phrase(name: String, scope: Scope, phrases: List<String>): Indicator =
                Indicator(name, scope) { text ->
                    val lowered = text.lowercase()
                    phrases.any { lowered.contains(it.lowercase()) }
                }
        }
    }

    /**
     * How many blocks at each end count as "the edges". Notes cluster in the first
     * or last couple of paragraphs; anything deeper is prose that happens to sound
     * chatty.
     */
    const val EDGE_BLOCK_COUNT = 3

    /**
     * Every indicator this knows about. Order does not affect the result — a block
     * is a note if *any* in-scope indicator matches it.
     */
    val indicators: List<Indicator> = listOf(
        // Unambiguous markers — safe anywhere in the work.
        Indicator.prefix(
            "an-abbreviation",
            Scope.ANYWHERE,
            listOf(
                "a/n:", "a/n ", "a/n-", "an:", "a.n.", "author's note", "authors note",
                "author note", "author’s note"
            )
        ),
        Indicator.prefix(
            "note-label",
            Scope.ANYWHERE,
            listOf("note:", "notes:", "end note", "end notes")
        ),
        Indicator.prefix(
            "disclaimer",
            Scope.ANYWHERE,
            listOf("disclaimer:", "disclaimer -")
        ),
        Indicator.prefix(
            "beta-credit",
            Scope.ANYWHERE,
            listOf("beta:", "beta'd by", "beta’d by", "betaed by", "unbeta")
        ),
        Indicator.phrase(
            "ownership-disclaimer",
            Scope.ANYWHERE,
            listOf(
                "i don't own", "i do not own", "i don’t own", "belongs to disney",
                "not my characters", "no copyright infringement"
            )
        ),

        // Sign-offs — the pen name that closes a note.
        //
        // Trusted ANYWHERE: a tilde never opens a paragraph of prose. A `~~~~`
        // scene divider is wrapped as a note by this, which is a cosmetic loss and
        // the reason the letter requirement is here rather than a bare prefix check.
        Indicator("tilde-signature", Scope.ANYWHERE) { text ->
            if (!text.startsWith("~")) return@Indicator false
            val name = text.drop(1).trimStart()
            name.length <= 60 && name.any { it.isLetter() }
        },
        // Same shape with a dash, which other sources use. Kept to the edges and to a
        // shorter name: an em dash *does* open lines of prose in some typesetting.
        Indicator("dash-signature", Scope.EDGES) { text ->
            val first = text.firstOrNull() ?: return@Indicator false
            if (first != '—' && first != '–') return@Indicator false
            val name = text.drop(1).trimStart()
            name.length <= 40 && name.any { it.isLetter() }
        },

        // Review/engagement asks — fanfic apparatus, never narration.
        Indicator.phrase(
            "review-ask",
            Scope.EDGES,
            listOf(
                "please review", "read and review", "r&r", "leave a review", "leave a comment",
                "thanks for the reviews", "thanks for reading", "thank you for reading",
                "kudos and comments", "comments and kudos", "let me know what you think",
                "and review!", "appreciate the reviews"
            )
        ),

        // A short question aimed at the reader. Trusted ANYWHERE because of the
        // length limit: "So..thoughts?" is a note wherever it appears, while the word
        // "thoughts?" inside a paragraph of narration is not.
        Indicator("reader-question", Scope.ANYWHERE) { text ->
            if (text.length > 60 || !text.endsWith("?")) return@Indicator false
            val lowered = text.lowercase()
            listOf("thoughts?", "opinions?", "what do you think", "any guesses")
                .any { lowered.contains(it) }
        },
        Indicator.phrase(
            "reader-question-long",
            Scope.EDGES,
            listOf("how many of you", "would you be interested", "anyone out there know")
        ),

        // Talking to the readership rather than about the story.
        // Leading spaces are deliberate: bare "yall" is a substring of "royally".
        Indicator.phrase(
            "direct-reader-address",
            Scope.EDGES,
            listOf(
                " you guys", " yall", " y'all", " ya go", "my readers", "great readers",
                "hope you all", "you all enjoyed"
            )
        ),
        Indicator.phrase(
            "more-to-come",
            Scope.EDGES,
            listOf("more to come", "more soon", "till next time", "till next chapter")
        ),
        Indicator.phrase(
            "stopping-point",
            Scope.EDGES,
            listOf("good place to end", "good place to stop", "seemed like a good place")
        ),

        // Meta talk about the writing itself — plausible narration, so edges only.
        Indicator.phrase(
            "update-apology",
            Scope.EDGES,
            listOf(
                "sorry for the wait", "sorry for the delay", "sorry it took", "long time no update",
                "hiatus", "writer's block", "writer’s block"
            )
        ),
        Indicator.phrase(
            "next-chapter-talk",
            Scope.EDGES,
            listOf(
                "next chapter", "this chapter", "last chapter", "the next update", "new chapter",
                "short chapter"
            )
        ),
        Indicator.phrase(
            "other-work-talk",
            Scope.EDGES,
            listOf(
                "my other story", "my other fic", "should be working on", "i will finish it",
                "i'll finish it", "i’ll finish it", "obsession"
            )
        ),
        Indicator.phrase(
            "enjoy-signoff",
            Scope.EDGES,
            listOf("so enjoy this", "enjoy!", "hope you enjoy", "happy reading")
        ),

        // Structural leftovers from converted downloads.
        Indicator.prefix(
            "chapter-summary-label",
            Scope.OPENING,
            listOf("summary:", "chapter summary")
        )
    )

    /** Indices of [blocks] that look like author's notes. */
    fun noteIndices(blocks: List<String>): Set<Int> {
        val result = mutableSetOf<Int>()
        blocks.forEachIndexed { index, block ->
            val text = block.trim()
            if (text.isEmpty()) return@forEachIndexed
            if (firstMatch(text, index, blocks.size) != null) {
                result += index
            }
        }
        return result
    }

    /**
     * Which indicator claimed each block, keyed by block index.
     * Used by tests and diagnostics so a failure names the rule.
     */
    fun diagnostics(blocks: List<String>): Map<Int, String> {
        val result = linkedMapOf<Int, String>()
        blocks.forEachIndexed { index, block ->
            val text = block.trim()
            if (text.isEmpty()) return@forEachIndexed
            firstMatch(text, index, blocks.size)?.let { result[index] = it }
        }
        return result
    }

    private fun firstMatch(text: String, index: Int, total: Int): String? =
        indicators.firstOrNull { indicator ->
            isInScope(indicator.scope, index, total) && indicator.matches(text)
        }?.name

    private fun isInScope(scope: Scope, index: Int, total: Int): Boolean {
        val isOpening = index < EDGE_BLOCK_COUNT
        val isClosing = index >= maxOf(0, total - EDGE_BLOCK_COUNT)
        return when (scope) {
            Scope.ANYWHERE -> true
            Scope.OPENING -> isOpening
            Scope.CLOSING -> isClosing
            Scope.EDGES -> isOpening || isClosing
        }
    }
}

/**
 * Wraps plain-text / PDF paragraph blocks into XHTML body fragment, grouping
 * consecutive author's notes into one `<aside class="author-note">` (iOS
 * `HTMLWorkSanitizer.paragraphs(from:)`). Class matches the HTML import path and
 * [EpubBuilder.AUTHOR_NOTE_STYLESHEET].
 */
fun paragraphsWithAuthorNotes(blocks: List<String>): String {
    val noteIndices = AuthorNoteDetector.noteIndices(blocks)
    val lines = mutableListOf<String>()
    var index = 0
    while (index < blocks.size) {
        if (index !in noteIndices) {
            lines += "<p>${escapeXml(blocks[index])}</p>"
            index += 1
            continue
        }
        val run = mutableListOf<String>()
        while (index < blocks.size && index in noteIndices) {
            run += blocks[index]
            index += 1
        }
        lines += """<aside class="author-note">"""
        lines += run.map { "<p>${escapeXml(it)}</p>" }
        lines += "</aside>"
    }
    return lines.joinToString("\n")
}

private fun escapeXml(value: String): String =
    value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
