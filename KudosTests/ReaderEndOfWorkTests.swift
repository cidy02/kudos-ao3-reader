import Foundation
import Testing
@testable import Kudos

@MainActor
struct ReaderEndOfWorkTests {
    @Test func headingMatchesCompletionState() {
        #expect(ReaderEndOfWorkFacts.heading(isComplete: true) == "The End")
        #expect(ReaderEndOfWorkFacts.heading(isComplete: false) == "You're caught up")
    }

    @Test func durationFormattingHandlesVariousIntervals() {
        #expect(ReaderEndOfWorkFacts.durationString(seconds: 4800) == "1 h 20 min")
        #expect(ReaderEndOfWorkFacts.durationString(seconds: 3600) == "1 h")
        #expect(ReaderEndOfWorkFacts.durationString(seconds: 7200) == "2 h")
        #expect(ReaderEndOfWorkFacts.durationString(seconds: 1500) == "25 min")
        // Logged time under a minute rounds up to 1 min.
        #expect(ReaderEndOfWorkFacts.durationString(seconds: 45) == "1 min")
        // No logged time: nothing is invented.
        #expect(ReaderEndOfWorkFacts.durationString(seconds: 0) == nil)
    }

    @Test func subtitleOmitsReadInWithoutLoggedTimeAndNeedsFinishedForMoved() {
        #expect(
            ReaderEndOfWorkFacts.subtitle(durationSeconds: 4800, isFinished: true)
            == "Read in 1 h 20 min · moved to Finished"
        )
        #expect(ReaderEndOfWorkFacts.subtitle(durationSeconds: 4800, isFinished: false) == "Read in 1 h 20 min")
        #expect(ReaderEndOfWorkFacts.subtitle(durationSeconds: 0, isFinished: true) == "Moved to Finished")
        #expect(ReaderEndOfWorkFacts.subtitle(durationSeconds: 0, isFinished: false) == nil)
    }

    @Test func readingTimeEstimateCalculatesEstimatedTime() {
        // 10,000 words / 200 = 50 min
        #expect(ReaderEndOfWorkFacts.readingTimeEstimate(wordCount: 10000) == "about 50 min")
        // 12,400 words / 200 = 62 min -> rounded to 5-min step is 60 min = 1 h
        #expect(ReaderEndOfWorkFacts.readingTimeEstimate(wordCount: 12400) == "about 1 h")
        // 0 words
        #expect(ReaderEndOfWorkFacts.readingTimeEstimate(wordCount: 0) == "about 1 min")
    }

    @Test func nextWorkMetaFormatsAuthorAndStats() {
        let meta = ReaderEndOfWorkFacts.nextWorkMeta(author: "hearthwitch", wordCount: 12400)
        #expect(meta.contains("hearthwitch"))
        #expect(meta.contains("words"))
        #expect(meta.contains("about 1 h"))

        let authorOnly = ReaderEndOfWorkFacts.nextWorkMeta(author: "hearthwitch", wordCount: 0)
        #expect(authorOnly == "hearthwitch")

        let wordsOnly = ReaderEndOfWorkFacts.nextWorkMeta(author: "", wordCount: 10000)
        #expect(wordsOnly.contains("words"))
        #expect(wordsOnly.contains("about 50 min"))
    }

    @Test func nextWorkInQueueSelectsSubsequentUnfinishedWork() {
        let work1 = SavedWork(title: "Work 1", author: "Author 1")
        let work2 = SavedWork(title: "Work 2", author: "Author 2")
        let work3 = SavedWork(title: "Work 3", author: "Author 3")
        work1.isFinished = true
        work2.isFinished = false
        work3.isFinished = false

        let queue = [work1, work2, work3]

        // When finishing work 1, work 2 is next
        let next = ReaderEndOfWorkFacts.nextWorkInQueue(orderedWorks: queue, currentWorkID: work1.id)
        #expect(next?.id == work2.id)

        // When finishing work 2, work 3 is next
        let nextAfter2 = ReaderEndOfWorkFacts.nextWorkInQueue(orderedWorks: queue, currentWorkID: work2.id)
        #expect(nextAfter2?.id == work3.id)
    }

    @Test func nextWorkInQueueWrapsToEarlierUnfinishedWorkIfSubsequentAllFinished() {
        let work1 = SavedWork(title: "Work 1", author: "Author 1")
        let work2 = SavedWork(title: "Work 2", author: "Author 2")
        let work3 = SavedWork(title: "Work 3", author: "Author 3")
        work1.isFinished = false
        work2.isFinished = true
        work3.isFinished = true

        let queue = [work1, work2, work3]

        // Work 3 is finished, so it wraps to work 1 (which is unfinished)
        let next = ReaderEndOfWorkFacts.nextWorkInQueue(orderedWorks: queue, currentWorkID: work2.id)
        #expect(next?.id == work1.id)
    }

    @Test func nextWorkInQueueIsNilWhenEveryOtherWorkIsFinished() {
        let work1 = SavedWork(title: "Work 1", author: "Author 1")
        let work2 = SavedWork(title: "Work 2", author: "Author 2")
        work1.isFinished = false
        work2.isFinished = true

        #expect(ReaderEndOfWorkFacts.nextWorkInQueue(orderedWorks: [work1, work2], currentWorkID: work1.id) == nil)
    }

    @Test func nextWorkInQueueReturnsNilWhenSingleWorkOrNotFound() {
        let work1 = SavedWork(title: "Work 1", author: "Author 1")
        let unknownWork = SavedWork(title: "Other", author: "Other")

        #expect(ReaderEndOfWorkFacts.nextWorkInQueue(orderedWorks: [work1], currentWorkID: work1.id) == nil)
        #expect(ReaderEndOfWorkFacts.nextWorkInQueue(orderedWorks: [work1], currentWorkID: unknownWork.id) == nil)
    }

    @Test func nextWorkInQueueSkipsPendingDeletionWorks() {
        let work1 = SavedWork(title: "Work 1", author: "Author 1")
        let work2 = SavedWork(title: "Work 2", author: "Author 2")
        let work3 = SavedWork(title: "Work 3", author: "Author 3")
        work1.isFinished = true
        work2.isPendingDeletion = true
        work3.isFinished = false

        let queue = [work1, work2, work3]
        let next = ReaderEndOfWorkFacts.nextWorkInQueue(orderedWorks: queue, currentWorkID: work1.id)
        #expect(next?.id == work3.id)
    }

    @Test func nextWorkInQueueRespectsEligibilityFilter() {
        let work1 = SavedWork(title: "Work 1", author: "Author 1")
        let work2 = SavedWork(title: "Work 2", author: "Author 2")
        let work3 = SavedWork(title: "Work 3", author: "Author 3")
        work1.isFinished = true
        work2.isFinished = false
        work3.isFinished = false

        let queue = [work1, work2, work3]
        // Filter out work2 (e.g. concealed mature work)
        let next = ReaderEndOfWorkFacts.nextWorkInQueue(
            orderedWorks: queue,
            currentWorkID: work1.id,
            isEligible: { $0.id != work2.id }
        )
        #expect(next?.id == work3.id)
    }
}
