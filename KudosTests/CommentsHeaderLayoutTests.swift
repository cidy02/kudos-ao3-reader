import Foundation
import Testing
@testable import Kudos

struct CommentsHeaderLayoutTests {
    @Test func metaLineWithAllFieldsLoggedIn() {
        let data = CommentsHeaderLayout.metaLineData(
            totalComments: 286,
            threads: 12,
            mine: 1,
            isLoggedIn: true,
            latestRelativeText: "20h ago"
        )
        #expect(data.commentsText == "286 comments")
        #expect(data.threadsText == "12 threads")
        #expect(data.yoursText == "1 yours")
        #expect(data.isYoursHighlighted == true)
        #expect(data.latestText == "latest 20h ago")
        #expect(data.fullFormattedLine == "286 comments · 12 threads · 1 yours · latest 20h ago")
    }

    @Test func metaLineZeroYoursLoggedIn() {
        let data = CommentsHeaderLayout.metaLineData(
            totalComments: 10,
            threads: 3,
            mine: 0,
            isLoggedIn: true,
            latestRelativeText: "2d ago"
        )
        #expect(data.yoursText == "0 yours")
        #expect(data.isYoursHighlighted == false)
        #expect(data.fullFormattedLine == "10 comments · 3 threads · 0 yours · latest 2d ago")
    }

    @Test func metaLineSignedOutOmitYours() {
        let data = CommentsHeaderLayout.metaLineData(
            totalComments: 50,
            threads: 5,
            mine: 2,
            isLoggedIn: false,
            latestRelativeText: "1h ago"
        )
        #expect(data.yoursText == nil)
        #expect(data.isYoursHighlighted == false)
        #expect(data.fullFormattedLine == "50 comments · 5 threads · latest 1h ago")
    }

    @Test func metaLineSingularCounts() {
        let data = CommentsHeaderLayout.metaLineData(
            totalComments: 1,
            threads: 1,
            mine: 1,
            isLoggedIn: true,
            latestRelativeText: nil
        )
        #expect(data.commentsText == "1 comment")
        #expect(data.threadsText == "1 thread")
        #expect(data.yoursText == "1 yours")
        #expect(data.latestText == nil)
        #expect(data.fullFormattedLine == "1 comment · 1 thread · 1 yours")
    }

    @Test func totalChaptersFromRawString() {
        #expect(CommentsHeaderLayout.totalChaptersCount(chapters: [], chaptersLoaded: false, rawChapters: "7/20") == 20)
        #expect(CommentsHeaderLayout.totalChaptersCount(chapters: [], chaptersLoaded: false, rawChapters: " 12/24 ") == 24)
        #expect(CommentsHeaderLayout.totalChaptersCount(chapters: [], chaptersLoaded: false, rawChapters: "15") == 15)
        #expect(CommentsHeaderLayout.totalChaptersCount(chapters: [], chaptersLoaded: false, rawChapters: "3/?") == nil)
        #expect(CommentsHeaderLayout.totalChaptersCount(chapters: [], chaptersLoaded: false, rawChapters: "") == nil)
    }

    @Test func totalChaptersFromRawTakesPrecedenceOverLoadedList() {
        let list = [
            AO3ChapterRef(id: 101, position: 1, title: "Ch 1"),
            AO3ChapterRef(id: 102, position: 2, title: "Ch 2")
        ]
        #expect(CommentsHeaderLayout.totalChaptersCount(chapters: list, chaptersLoaded: true, rawChapters: "2/10") == 10)
    }

    @Test func totalChaptersFallbackToLoadedListWhenRawEmpty() {
        let list = [
            AO3ChapterRef(id: 101, position: 1, title: "Ch 1"),
            AO3ChapterRef(id: 102, position: 2, title: "Ch 2")
        ]
        #expect(CommentsHeaderLayout.totalChaptersCount(chapters: list, chaptersLoaded: true, rawChapters: "") == 2)
    }

    @Test func chapterSubtitleByChapter() {
        let chapter = AO3ChapterRef(id: 700, position: 7, title: "Seven")
        let subWithTotal = CommentsHeaderLayout.chapterSubtitle(
            scope: .byChapter,
            selectedChapter: chapter,
            totalChapters: 20
        )
        #expect(subWithTotal == "Chapter 7 of 20")

        let subWithoutTotal = CommentsHeaderLayout.chapterSubtitle(
            scope: .byChapter,
            selectedChapter: chapter,
            totalChapters: nil
        )
        #expect(subWithoutTotal == "Chapter 7")

        let subMalformedTotal = CommentsHeaderLayout.chapterSubtitle(
            scope: .byChapter,
            selectedChapter: chapter,
            totalChapters: 3
        )
        #expect(subMalformedTotal == "Chapter 7")
    }

    @Test func chapterSubtitleAllScopeReturnsNil() {
        let chapter = AO3ChapterRef(id: 700, position: 7, title: "Seven")
        let sub = CommentsHeaderLayout.chapterSubtitle(
            scope: .all,
            selectedChapter: chapter,
            totalChapters: 20
        )
        #expect(sub == nil)
    }

    @Test func matureWorkConcealment() {
        #expect(CommentsHeaderLayout.isWorkConcealed(rating: "Mature", hideMature: true, isRevealed: false) == true)
        #expect(CommentsHeaderLayout.isWorkConcealed(rating: "Explicit", hideMature: true, isRevealed: false) == true)
        #expect(CommentsHeaderLayout.isWorkConcealed(rating: "General", hideMature: true, isRevealed: false) == false)
        #expect(CommentsHeaderLayout.isWorkConcealed(rating: "Teen", hideMature: true, isRevealed: false) == false)
        #expect(CommentsHeaderLayout.isWorkConcealed(rating: "Mature", hideMature: false, isRevealed: false) == false)
        #expect(CommentsHeaderLayout.isWorkConcealed(rating: "Mature", hideMature: true, isRevealed: true) == false)
        #expect(CommentsHeaderLayout.isWorkConcealed(rating: "", hideMature: true, isRevealed: false) == false)
    }
}
