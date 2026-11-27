import Foundation
import SwiftSoup

/// Pure logic and copy for the Reader's end-of-chapter card (Reader-ChapterEnd, T-554)
/// and the caught-up line on the end-of-work card (Reader-CaughtUp).
enum ReaderChapterEndFacts {
    /// A chapter whose last page is on screen, and the chapter a swipe turns to.
    struct ChapterEnd: Equatable {
        let spineIndex: Int
        /// 1-based story-chapter numbers (never raw spine positions).
        let storyChapter: Int
        let nextSpineIndex: Int
        let nextStoryChapter: Int
    }

    /// The end-of-chapter state for the spine item whose trailing edge is on screen, or nil.
    /// Only a real story chapter with another story chapter after it qualifies: Preface,
    /// Summary, a lone Afterword, and the publication's final page (the end-of-work card's)
    /// never do.
    static func chapterEnd(endingSpineIndex: Int?, sections: [ReaderSection]) -> ChapterEnd? {
        guard let index = endingSpineIndex,
              sections.indices.contains(index),
              sections[index].kind == .chapter,
              let story = sections[index].storyChapterIndex,
              let next = sections[(index + 1)...].first(where: { $0.kind == .chapter }),
              let nextStory = next.storyChapterIndex
        else { return nil }
        return ChapterEnd(
            spineIndex: index, storyChapter: story,
            nextSpineIndex: next.spineIndex, nextStoryChapter: nextStory
        )
    }

    static func heading(chapter: Int) -> String { "End of Chapter \(chapter)" }

    /// "Chapter 8: The Tide Table"; the section's own title when it already says "Chapter",
    /// "Chapter 8" when the EPUB gave no title.
    static func nextChapterTitle(number: Int, sectionTitle: String) -> String {
        let title = sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return "Chapter \(number)" }
        if title.lowercased().hasPrefix("chapter") { return title }
        return "Chapter \(number): \(title)"
    }

    /// "About 15 min" for the next chapter, from the work's per-chapter word counts. Nil when
    /// the counts are missing or do not line up with the story chapters (never a guess).
    static func nextChapterTime(
        chapterWordCounts: [Int], storyChapterTotal: Int, nextStoryChapter: Int
    ) -> String? {
        guard chapterWordCounts.count == storyChapterTotal,
              chapterWordCounts.indices.contains(nextStoryChapter - 1),
              let estimate = ReadingQueueFacts.readingTimeEstimate(
                  wordCount: chapterWordCounts[nextStoryChapter - 1]
              )
        else { return nil }
        return estimate.prefix(1).uppercased() + estimate.dropFirst()
    }

    /// "Chapter 7 of 20 · 12 posted · or keep swiping to read on". "Posted" appears only for
    /// a work still in progress (total known and larger than the posted count).
    static func footer(chapter: Int, totalChapters: Int?, postedChapters: Int) -> String {
        var parts = [totalChapters.map { "Chapter \(chapter) of \($0)" } ?? "Chapter \(chapter)"]
        if let totalChapters, postedChapters > 0, postedChapters < totalChapters {
            parts.append("\(postedChapters) posted")
        }
        parts.append("or keep swiping to read on")
        return parts.joined(separator: " · ")
    }

    /// "Chapter 15 of 30 is the latest · updated Nov 3, 2026". AO3 gives a date, not a time, so
    /// the line says "updated <date>" and never invents "2 h ago". Nil with no posted count.
    static func latestChapterLine(
        postedChapters: Int, totalChapters: Int?, updated: String, copyBehind: Bool = false
    ) -> String? {
        guard postedChapters > 0 else { return nil }
        var line = totalChapters.map { "Chapter \(postedChapters) of \($0) is the latest" }
            ?? "Chapter \(postedChapters) is the latest"
        if copyBehind { line = "New chapters on AO3 · " + line }
        let date = updated.trimmingCharacters(in: .whitespacesAndNewlines)
        if !date.isEmpty { line += " · updated \(WorkStat.displayDate(date))" }
        return line
    }

    /// True when AO3 has posted more chapters than the downloaded EPUB holds, so the end of
    /// the book is the end of this copy, not "caught up". Unknown counts never claim it.
    static func isCopyBehind(postedChapters: Int, epubStoryChapters: Int) -> Bool {
        epubStoryChapters > 0 && postedChapters > epubStoryChapters
    }

    /// Largest chapter source the optional note preview will parse.
    nonisolated static let maxNoteSourceBytes = 2_000_000

    /// The extracted author's end note plus which markup produced it, so the in-chapter
    /// card hides only the matching block instead of an opening author note.
    nonisolated struct EndNoteMatch: Equatable, Sendable {
        let text: String
        let isConvertedAside: Bool
    }

    /// The author's end note from one chapter's XHTML, or nil when the chapter has none (the
    /// card then leaves the note out). Same AO3 markers the word counter strips as apparatus.
    nonisolated static func endNote(fromChapterXHTML xhtml: String) -> String? {
        endNoteMatch(fromChapterXHTML: xhtml)?.text
    }

    /// Extracts the author's end note and whether it came from a converted work's trailing
    /// `<aside class="author-note">` rather than an AO3 end-notes block.
    nonisolated static func endNoteMatch(fromChapterXHTML xhtml: String) -> EndNoteMatch? {
        guard !xhtml.isEmpty, xhtml.utf8.count <= maxNoteSourceBytes,
              let doc = try? SwiftSoup.parse(xhtml) else { return nil }
        let selector = "[id^=endnotes], div.end.notes, div.endnotes"
        let container: Element
        let isConvertedAside: Bool
        if let ao3 = try? doc.select(selector).first() {
            container = ao3
            isConvertedAside = false
        } else if let converted = convertedTrailingNote(in: doc) {
            container = converted
            isConvertedAside = true
        } else {
            return nil
        }
        let quote = (try? container.select("blockquote.userstuff, blockquote").first()) ?? nil
        let source = quote ?? container
        guard let text = try? source.text() else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare "End Notes:" heading with no body is not a note.
        let heading = cleaned.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        guard !cleaned.isEmpty, !["notes", "end notes", "endnotes"].contains(heading) else {
            return nil
        }
        return EndNoteMatch(text: cleaned, isConvertedAside: isConvertedAside)
    }

    /// A converted (imported) work's author note sits in `<aside class="author-note">`. Only one
    /// that trails the text counts as an end note: a leading note is the chapter's opening note.
    nonisolated private static func convertedTrailingNote(in doc: Document) -> Element? {
        guard let last = (try? doc.select("aside.author-note"))?.last(),
              let parent = last.parent(), parent.children().count > 1 else { return nil }
        let next: Element? = (try? last.nextElementSibling()) ?? nil
        return next == nil ? last : nil
    }
}
