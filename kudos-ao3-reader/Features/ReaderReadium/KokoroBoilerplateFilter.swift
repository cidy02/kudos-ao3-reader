import Foundation

/// Strips AO3 export scaffolding before it reaches the packer: fixed
/// structural labels the site injects around every work/chapter, and bare
/// URLs, which Kokoro's G2P has no pronunciation for and reads out character
/// by character.
///
/// Evidence: 19 real works / ~127k blocks, `tag<TAB>text` corpora extracted
/// straight from AO3 EPUB exports (`Scripts/epub-to-corpus.py`). See
/// `KokoroBoilerplateFilterTests` for the exact false-positive traps this
/// was checked against.
nonisolated enum KokoroBoilerplateFilter {
    /// AO3's own section headings, as they arrive once tags are stripped: a
    /// standalone block with nothing else in it, always immediately after a
    /// chapter heading or at the very top of the work. Corpus counts:
    /// "Summary" 19, "Notes" 10, "End Notes" 4, "Chapter Summary" 397,
    /// "Chapter Notes" 479 -- 909 blocks total, always exactly this text and
    /// nothing else. "Author's Note"/"Author's Note:" had zero hits in this
    /// particular corpus (AO3 doesn't generate that label itself -- authors
    /// type it by hand) but it's common enough elsewhere to keep, with the
    /// same whole-block anchoring so it costs nothing when absent.
    ///
    /// This is whole-block equality against normalized text, never a
    /// substring test: a real note that merely *starts* with one of these
    /// words -- e.g. "Author's End NoteThank you to everyone who's been
    /// with me..." (an actual block in the corpus, tags glued the label to
    /// the next sentence with no space) -- does not match and is spoken in
    /// full.
    private static let labels: Set<String> = [
        "Summary", "Notes", "End Notes",
        "Chapter Summary", "Chapter Notes",
        "Author's Note", "Author's Note:",
    ]

    /// AO3's fixed closing plug, appended verbatim to every downloaded work
    /// (19/19 works in the corpus, exactly once each, byte-for-byte
    /// identical).
    private static let kudosPlug =
        "Please drop by the Archive and comment to let the creator know if you enjoyed their work!"

    /// True for a block that is nothing but AO3 scaffolding and should be
    /// dropped rather than spoken.
    /// A section heading that introduces an author's note, as opposed to the
    /// archive's closing plug. Only these open a suppressible note span.
    static func isNoteLabel(_ text: String) -> Bool {
        labels.contains(KokoroSpeechNormalizer.normalize(text))
    }

    static func isBoilerplate(_ text: String) -> Bool {
        let normalized = KokoroSpeechNormalizer.normalize(text)
        return labels.contains(normalized) || normalized == kudosPlug
    }

    private static let urlPattern = try? NSRegularExpression(pattern: #"(?:https?://|www\.)\S+"#)

    /// Replaces every `scheme://host/path?query` run with its bare host, so
    /// Kokoro says "tumblr.com" instead of spelling out a path and query
    /// string letter by letter and digit by digit -- the single worst
    /// offender for read-aloud quality found in the corpus (48 of ~127k
    /// blocks contain a URL). Deletion isn't an option here: nearly every
    /// hit sits mid-sentence ("...posted originally...at
    /// https://archiveofourown.org/works/407062.", "...updates:
    /// http://wittyy-name.tumblr.com/") and dropping the link would leave a
    /// dangling "at ." or "updates:".
    ///
    /// A run ends at whitespace. A few source blocks glue the very next word
    /// onto the link with no space at all (an AO3 authoring/HTML quirk --
    /// the anchor text was the bare URL, immediately followed by more prose
    /// with no space in the markup); that one glued word is absorbed into
    /// the replacement along with the path. Every instance found in the
    /// corpus lost at most one word this way, never a full sentence, since
    /// real prose has spaces between its own words and stops the match --
    /// so a real word-boundary parse isn't worth the added complexity.
    static func sanitizingURLs(in text: String) -> String {
        guard let urlPattern else { return text }
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = urlPattern.matches(in: text, range: full)
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text), range.lowerBound >= cursor else { continue }
            result += text[cursor..<range.lowerBound]
            result += host(of: text[range])
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    private static func host(of run: Substring) -> String {
        var rest = run
        if let schemeEnd = rest.range(of: "://") { rest = rest[schemeEnd.upperBound...] }
        if rest.hasPrefix("www.") { rest = rest.dropFirst(4) }
        let hostEnd = rest.firstIndex(where: { "/?#".contains($0) }) ?? rest.endIndex
        let host = rest[rest.startIndex..<hostEnd]
        guard !host.isEmpty else { return "a link" }
        // Keep genuine sentence punctuation the match swallowed off its own
        // end, e.g. the "." in "...works/407062."
        if let last = run.last, ".,;:!?".contains(last) {
            return String(host) + String(last)
        }
        return String(host)
    }
}
