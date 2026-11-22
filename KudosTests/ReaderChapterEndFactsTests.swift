import Foundation
import Testing
@testable import Kudos

@MainActor
struct ReaderChapterEndFactsTests {
    private func section(_ index: Int, _ kind: ReaderSectionKind, story: Int? = nil) -> ReaderSection {
        ReaderSection(
            href: "s\(index).xhtml", title: "T\(index)", kind: kind,
            spineIndex: index, storyChapterIndex: story
        )
    }

    private var sections: [ReaderSection] {
        [section(0, .preface), section(1, .chapter, story: 1), section(2, .chapter, story: 2),
         section(3, .afterword)]
    }

    @Test func chapterEndNeedsAStoryChapterWithAnotherAfterIt() {
        let first = ReaderChapterEndFacts.chapterEnd(endingSpineIndex: 1, sections: sections)
        #expect(first == .init(spineIndex: 1, storyChapter: 1, nextSpineIndex: 2, nextStoryChapter: 2))
        // The last story chapter (an Afterword follows, not a chapter), front matter and
        // back matter never get the card.
        #expect(ReaderChapterEndFacts.chapterEnd(endingSpineIndex: 2, sections: sections) == nil)
        #expect(ReaderChapterEndFacts.chapterEnd(endingSpineIndex: 0, sections: sections) == nil)
        #expect(ReaderChapterEndFacts.chapterEnd(endingSpineIndex: 3, sections: sections) == nil)
        #expect(ReaderChapterEndFacts.chapterEnd(endingSpineIndex: nil, sections: sections) == nil)
        #expect(ReaderChapterEndFacts.chapterEnd(endingSpineIndex: 9, sections: sections) == nil)
    }

    @Test func chapterEndSkipsNonChapterSectionsBetweenChapters() {
        let spine = [section(0, .chapter, story: 1), section(1, .other), section(2, .chapter, story: 2)]
        #expect(ReaderChapterEndFacts.chapterEnd(endingSpineIndex: 0, sections: spine)?.nextSpineIndex == 2)
    }

    @Test func nextChapterTitleKeepsAnExistingChapterPrefix() {
        #expect(ReaderChapterEndFacts.nextChapterTitle(number: 8, sectionTitle: "The Tide Table")
            == "Chapter 8: The Tide Table")
        #expect(ReaderChapterEndFacts.nextChapterTitle(number: 8, sectionTitle: "Chapter 8: The Tide Table")
            == "Chapter 8: The Tide Table")
        #expect(ReaderChapterEndFacts.nextChapterTitle(number: 8, sectionTitle: "  ") == "Chapter 8")
    }

    @Test func nextChapterTimeNeedsCountsThatLineUpWithTheChapters() {
        #expect(ReaderChapterEndFacts.nextChapterTime(
            chapterWordCounts: [1000, 3000, 3000], storyChapterTotal: 3, nextStoryChapter: 2) == "About 15 min")
        // Counts for a different number of chapters are never guessed from.
        #expect(ReaderChapterEndFacts.nextChapterTime(
            chapterWordCounts: [1000, 3000], storyChapterTotal: 3, nextStoryChapter: 2) == nil)
        #expect(ReaderChapterEndFacts.nextChapterTime(
            chapterWordCounts: [], storyChapterTotal: 0, nextStoryChapter: 1) == nil)
    }

    @Test func footerShowsPostedOnlyForAWorkInProgress() {
        #expect(ReaderChapterEndFacts.footer(chapter: 7, totalChapters: 20, postedChapters: 12)
            == "Chapter 7 of 20 · 12 posted · or keep swiping to read on")
        #expect(ReaderChapterEndFacts.footer(chapter: 7, totalChapters: 12, postedChapters: 12)
            == "Chapter 7 of 12 · or keep swiping to read on")
        #expect(ReaderChapterEndFacts.footer(chapter: 7, totalChapters: nil, postedChapters: 0)
            == "Chapter 7 · or keep swiping to read on")
    }

    @Test func latestChapterLineNeverInventsATime() {
        #expect(ReaderChapterEndFacts.latestChapterLine(postedChapters: 15, totalChapters: 30, updated: "")
            == "Chapter 15 of 30 is the latest")
        #expect(ReaderChapterEndFacts.latestChapterLine(postedChapters: 15, totalChapters: nil, updated: "")
            == "Chapter 15 is the latest")
        #expect(ReaderChapterEndFacts.latestChapterLine(postedChapters: 0, totalChapters: 30, updated: "2026-11-03")
            == nil)
        let dated = ReaderChapterEndFacts.latestChapterLine(
            postedChapters: 15, totalChapters: 30, updated: "2026-11-03"
        )
        #expect(dated?.hasPrefix("Chapter 15 of 30 is the latest · updated ") == true)
        #expect(dated?.contains(" ago") == false)
    }

    @Test func endNoteIsReadFromAO3EndNotesMarkup() {
        let xhtml = """
        <html><body><div class="userstuff"><p>Story text.</p></div>
        <div class="end notes module" id="endnotes"><h3 class="heading">End Notes:</h3>
        <blockquote class="userstuff"><p>Thank you for every comment.</p></blockquote></div></body></html>
        """
        #expect(ReaderChapterEndFacts.endNote(fromChapterXHTML: xhtml) == "Thank you for every comment.")
        #expect(ReaderChapterEndFacts.endNote(fromChapterXHTML: "<html><body><p>Story</p></body></html>") == nil)
        #expect(ReaderChapterEndFacts.endNote(fromChapterXHTML: "") == nil)
        #expect(ReaderChapterEndFacts.endNote(
            fromChapterXHTML: "<div id=\"endnotes\"><h3>End Notes:</h3></div>") == nil)
    }
}
