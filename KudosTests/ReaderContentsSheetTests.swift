#if os(iOS)
import Testing
@testable import Kudos

struct ReaderContentsSheetTests {
    @Test func annotationCountsAppearOnlyWhenNonzero() {
        #expect(ReaderContentsLabels.segmentTitle(.chapters, count: 8) == "Contents")
        #expect(ReaderContentsLabels.segmentTitle(.bookmarks, count: 3) == "Bookmarks · 3")
        #expect(ReaderContentsLabels.segmentTitle(.notes, count: 2) == "Highlights · 2")
        #expect(ReaderContentsLabels.segmentTitle(.bookmarks, count: 0) == "Bookmarks")
        #expect(ReaderContentsLabels.segmentTitle(.notes, count: 0) == "Highlights")
    }

    @Test func progressIncludesExistingWorkEstimateWhenAvailable() {
        #expect(
            ReaderContentsLabels.progress(percent: 22, remainingPositions: 273)
                == "22% of the work · about 4 hr 10 min left"
        )
    }

    @Test func progressKeepsThePercentWhenNoEstimateIsAvailable() {
        #expect(ReaderContentsLabels.progress(percent: 22, remainingPositions: nil) == "22% of the work")
        #expect(ReaderContentsLabels.progress(percent: 99, remainingPositions: 0) == "99% of the work")
    }

    @Test func chapterRowPresentationMatchesBoard28() {
        let preface = ReaderSection(href: "preface.xhtml", title: "Preface and summary", kind: .preface, spineIndex: 0, storyChapterIndex: nil)
        let ch1 = ReaderSection(href: "ch1.xhtml", title: "Instruments", kind: .chapter, spineIndex: 1, storyChapterIndex: 1)
        let ch7 = ReaderSection(href: "ch7.xhtml", title: "The Salt Road", kind: .chapter, spineIndex: 7, storyChapterIndex: 7)
        let ch8 = ReaderSection(href: "ch8.xhtml", title: "White Ground", kind: .chapter, spineIndex: 8, storyChapterIndex: 8)
        let ch9 = ReaderSection(href: "ch9.xhtml", title: "Copper Light", kind: .chapter, spineIndex: 9, storyChapterIndex: 9)

        // 9 story chapters: indices 0..8.
        // ch8 is storyIndex 8 -> words[7] = 3600 (18 min).
        // ch9 is storyIndex 9 -> words[8] = 4200 (21 min).
        let words = [1000, 1000, 1000, 1000, 1000, 1000, 1000, 3600, 4200]

        // 1. Preface before current chapter: no number, no state
        let prefaceRow = ReaderContentsLabels.chapterRow(
            section: preface,
            currentSpineIndex: 7,
            currentChapterProgression: 0.22,
            storyChapterWords: words
        )
        #expect(prefaceRow.number == "")
        #expect(prefaceRow.isCurrent == false)
        #expect(prefaceRow.state == "")
        #expect(prefaceRow.accessibilityLabel == "Preface and summary")

        // 2. Earlier chapter: number, title, "read"
        let ch1Row = ReaderContentsLabels.chapterRow(
            section: ch1,
            currentSpineIndex: 7,
            currentChapterProgression: 0.22,
            storyChapterWords: words
        )
        #expect(ch1Row.number == "1")
        #expect(ch1Row.isCurrent == false)
        #expect(ch1Row.state == "read")
        #expect(ch1Row.accessibilityLabel == "1, Instruments, read")

        // 3. Current chapter: number, title, progress "22% · reading", highlighted
        let ch7Row = ReaderContentsLabels.chapterRow(
            section: ch7,
            currentSpineIndex: 7,
            currentChapterProgression: 0.22,
            storyChapterWords: words
        )
        #expect(ch7Row.number == "7")
        #expect(ch7Row.isCurrent == true)
        #expect(ch7Row.state == "22% · reading")
        #expect(ch7Row.accessibilityLabel == "7, The Salt Road, 22% · reading")

        // 4. Later chapter with word counts: "18 min"
        let ch8Row = ReaderContentsLabels.chapterRow(
            section: ch8,
            currentSpineIndex: 7,
            currentChapterProgression: 0.22,
            storyChapterWords: words
        )
        #expect(ch8Row.number == "8")
        #expect(ch8Row.isCurrent == false)
        #expect(ch8Row.state == "18 min")
        #expect(ch8Row.accessibilityLabel == "8, White Ground, 18 min")

        // 5. Later chapter with word counts: "21 min"
        let ch9Row = ReaderContentsLabels.chapterRow(
            section: ch9,
            currentSpineIndex: 7,
            currentChapterProgression: 0.22,
            storyChapterWords: words
        )
        #expect(ch9Row.number == "9")
        #expect(ch9Row.isCurrent == false)
        #expect(ch9Row.state == "21 min")
        #expect(ch9Row.accessibilityLabel == "9, Copper Light, 21 min")

        // 6. Later chapter without word counts: omits minutes
        let ch8NoWords = ReaderContentsLabels.chapterRow(
            section: ch8,
            currentSpineIndex: 7,
            currentChapterProgression: 0.22,
            storyChapterWords: nil
        )
        #expect(ch8NoWords.number == "8")
        #expect(ch8NoWords.isCurrent == false)
        #expect(ch8NoWords.state == "")
        #expect(ch8NoWords.accessibilityLabel == "8, White Ground")
    }
}
#endif
