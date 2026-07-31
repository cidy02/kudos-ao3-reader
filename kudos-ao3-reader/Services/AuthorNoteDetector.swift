import Foundation

/// Identifies author's notes among a work's paragraphs, so the reader can present
/// them as apparatus rather than as prose.
///
/// An author's note is the bit before the story where the writer apologises for the
/// delay, thanks their beta, or explains that they are mid-"Frozen" obsession. In an
/// AO3 HTML download it is marked up (`div.notes`) and can be identified with
/// certainty. In a PDF or a `.txt` there is no markup at all, so it has to be
/// recognised from the text — which is what this type does.
///
/// ## Adding an indicator
///
/// Everything this knows lives in `indicators`, one `Indicator` per line. To teach
/// it a phrase from a source it has not seen:
///
/// 1. Add an `Indicator` to the table below. Give it a `name` (it appears in
///    `diagnostics(for:)` and in test failures, so make it searchable), the
///    narrowest `scope` that can work, and a matcher.
/// 2. Add a case to `AuthorNoteDetectorTests` using a real line from the file that
///    prompted it — a fixture that names its source is worth more than a synthetic one.
/// 3. Run `AuthorNoteDetector.diagnostics(for:)` over the new document and check
///    nothing in the *story* now matches. That is the failure mode that matters: a
///    missed note is a cosmetic loss, while a false positive demotes real prose.
///
/// **Scope is the safety mechanism.** Phrases that read like ordinary narration
/// ("I'll finish it, I swear") are only trusted at the very start or end of a work,
/// where notes actually live. Only unambiguous markers (`A/N:`, `Disclaimer:`) are
/// trusted anywhere.
nonisolated enum AuthorNoteDetector {
    /// Where in the work a given indicator may be believed.
    enum Scope {
        /// Trusted anywhere — the phrase is never plausible narration.
        case anywhere
        /// Only in the opening blocks, where a pre-chapter note sits.
        case opening
        /// Only in the closing blocks, where a sign-off sits.
        case closing
        /// Either end, but not the middle.
        case edges
    }

    struct Indicator {
        let name: String
        let scope: Scope
        let matches: (String) -> Bool

        init(_ name: String, _ scope: Scope, matches: @escaping (String) -> Bool) {
            self.name = name
            self.scope = scope
            self.matches = matches
        }

        /// Convenience for the common case: a case-insensitive prefix.
        static func prefix(_ name: String, _ scope: Scope, _ prefixes: [String]) -> Indicator {
            Indicator(name, scope) { text in
                prefixes.contains { text.lowercased().hasPrefix($0.lowercased()) }
            }
        }

        /// Convenience for a phrase appearing anywhere in the block.
        static func phrase(_ name: String, _ scope: Scope, _ phrases: [String]) -> Indicator {
            Indicator(name, scope) { text in
                let lowered = text.lowercased()
                return phrases.contains { lowered.contains($0.lowercased()) }
            }
        }
    }

    /// How many blocks at each end count as "the edges". Notes cluster in the first
    /// or last couple of paragraphs; anything deeper is prose that happens to sound
    /// chatty.
    static let edgeBlockCount = 3

    /// Every indicator this knows about. Ordered loosely by confidence, though order
    /// does not affect the result — a block is a note if *any* in-scope indicator
    /// matches it.
    static let indicators: [Indicator] = [
        // MARK: Unambiguous markers — safe anywhere in the work.
        .prefix("an-abbreviation", .anywhere, [
            "a/n:", "a/n ", "a/n-", "an:", "a.n.", "author's note", "authors note",
            "author note", "author’s note"
        ]),
        .prefix("note-label", .anywhere, ["note:", "notes:", "end note", "end notes"]),
        .prefix("disclaimer", .anywhere, ["disclaimer:", "disclaimer -"]),
        .prefix("beta-credit", .anywhere, ["beta:", "beta'd by", "beta’d by", "betaed by", "unbeta"]),
        .phrase("ownership-disclaimer", .anywhere, [
            "i don't own", "i do not own", "i don’t own", "belongs to disney",
            "not my characters", "no copyright infringement"
        ]),

        // MARK: Sign-offs — the pen name that closes a note.
        //
        // The strongest marker in the FanFiction.net PDFs seen so far, and the one whose
        // absence prompted this section: every chapter of "In the Service of the Queen"
        // ends `~Malthazar LOS`, 29 times, and the whole 8,000-line document contains no
        // other line that opens with a tilde. Trusted `.anywhere` on that evidence —
        // a tilde never opens a paragraph of prose — and because PDF chapter splitting
        // glues the sign-off to the next chapter's marker, so it can land at the top of
        // a chapter as easily as the bottom.
        //
        // A `~~~~` scene divider is wrapped as a note by this, which is a cosmetic loss
        // and the reason the letter requirement is here rather than a bare prefix check.
        Indicator("tilde-signature", .anywhere) { text in
            guard text.hasPrefix("~") else { return false }
            let name = text.dropFirst().trimmingCharacters(in: .whitespaces)
            return name.count <= 60 && name.contains(where: \.isLetter)
        },
        // Same shape with a dash, which other sources use. Kept to the edges and to a
        // shorter name: an em dash *does* open lines of prose in some typesetting.
        Indicator("dash-signature", .edges) { text in
            guard let first = text.first, first == "—" || first == "–" else { return false }
            let name = text.dropFirst().trimmingCharacters(in: .whitespaces)
            return name.count <= 40 && name.contains(where: \.isLetter)
        },

        // MARK: Review/engagement asks — fanfic apparatus, never narration.
        .phrase("review-ask", .edges, [
            "please review", "read and review", "r&r", "leave a review", "leave a comment",
            "thanks for the reviews", "thanks for reading", "thank you for reading",
            "kudos and comments", "comments and kudos", "let me know what you think",
            "and review!", "appreciate the reviews"
        ]),

        // A short question aimed at the reader. Trusted `.anywhere` *because* of the
        // length limit: "So..thoughts?" is a note wherever it appears, while the word
        // "thoughts?" inside a paragraph of narration is not.
        Indicator("reader-question", .anywhere) { text in
            guard text.count <= 60, text.hasSuffix("?") else { return false }
            let lowered = text.lowercased()
            return ["thoughts?", "opinions?", "what do you think", "any guesses"]
                .contains { lowered.contains($0) }
        },
        .phrase("reader-question-long", .edges, [
            "how many of you", "would you be interested", "anyone out there know"
        ]),

        // MARK: Talking to the readership rather than about the story.
        // Leading spaces are deliberate: bare "yall" is a substring of "royally".
        .phrase("direct-reader-address", .edges, [
            " you guys", " yall", " y'all", " ya go", "my readers", "great readers",
            "hope you all", "you all enjoyed"
        ]),
        .phrase("more-to-come", .edges, [
            "more to come", "more soon", "till next time", "till next chapter"
        ]),
        .phrase("stopping-point", .edges, [
            "good place to end", "good place to stop", "seemed like a good place"
        ]),

        // MARK: Meta talk about the writing itself — plausible narration, so edges only.
        .phrase("update-apology", .edges, [
            "sorry for the wait", "sorry for the delay", "sorry it took", "long time no update",
            "hiatus", "writer's block", "writer’s block"
        ]),
        .phrase("next-chapter-talk", .edges, [
            "next chapter", "this chapter", "last chapter", "the next update", "new chapter",
            "short chapter"
        ]),
        .phrase("other-work-talk", .edges, [
            "my other story", "my other fic", "should be working on", "i will finish it",
            "i'll finish it", "i’ll finish it", "obsession"
        ]),
        .phrase("enjoy-signoff", .edges, ["so enjoy this", "enjoy!", "hope you enjoy", "happy reading"]),

        // MARK: Structural leftovers from converted downloads.
        .prefix("chapter-summary-label", .opening, ["summary:", "chapter summary"])
    ]

    /// Indices of `blocks` that look like author's notes.
    static func noteIndices(in blocks: [String]) -> Set<Int> {
        var result: Set<Int> = []
        for (index, block) in blocks.enumerated() {
            let text = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if firstMatch(for: text, at: index, of: blocks.count) != nil {
                result.insert(index)
            }
        }
        return result
    }

    /// Which indicator claimed each block, keyed by block index.
    ///
    /// This exists for the workflow in the type comment: point it at a new document,
    /// read what matched, and judge whether an indicator is too eager before it ships.
    /// Tests use it so a failure names the rule rather than only the index.
    static func diagnostics(for blocks: [String]) -> [Int: String] {
        var result: [Int: String] = [:]
        for (index, block) in blocks.enumerated() {
            let text = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let name = firstMatch(for: text, at: index, of: blocks.count) {
                result[index] = name
            }
        }
        return result
    }

    // MARK: - Internals

    private static func firstMatch(for text: String, at index: Int, of total: Int) -> String? {
        indicators.first { indicator in
            isInScope(indicator.scope, index: index, total: total) && indicator.matches(text)
        }?.name
    }

    private static func isInScope(_ scope: Scope, index: Int, total: Int) -> Bool {
        let isOpening = index < edgeBlockCount
        let isClosing = index >= max(0, total - edgeBlockCount)
        switch scope {
        case .anywhere: return true
        case .opening: return isOpening
        case .closing: return isClosing
        case .edges: return isOpening || isClosing
        }
    }
}
