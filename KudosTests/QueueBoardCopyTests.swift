import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Locks the board-matched copy introduced in T-507 (Queues detail sweep) so
/// helper-generated labels, counts, subtitles, and sheet actions don't drift
/// from `.design-ref/Queue*.dc.html`.
@MainActor
struct QueueBoardCopyTests {
    @Test func newQueuePreviewSubtitleOmitsOfflineAndFormatsCounts() {
        #expect(ReadingQueueFacts.previewSubtitle(for: []) == "No works yet")

        let one = SavedWork(title: "One", author: "Author")
        one.wordCount = 6_700
        one.hasEPUB = true
        let expectedOne = ReadingQueueFacts.readingTimeEstimate(wordCount: 6_700) ?? ""
        #expect(ReadingQueueFacts.previewSubtitle(for: [one]) == "1 work · \(expectedOne)")

        let two = SavedWork(title: "Two", author: "Author")
        two.wordCount = 39_300
        let expectedTwo = ReadingQueueFacts.readingTimeEstimate(wordCount: 46_000) ?? ""
        #expect(ReadingQueueFacts.previewSubtitle(for: [one, two]) == "2 works · \(expectedTwo)")

        let missingWords = SavedWork(title: "No Words", author: "Author")
        missingWords.wordCount = 0
        #expect(ReadingQueueFacts.previewSubtitle(for: [one, missingWords]) == "2 works")
    }

    @Test func contextCardKickerAndMetaMatchEditAndSourcesBoards() {
        #expect(ReadingQueueFacts.contextCardKicker(workCount: 0) == "Queue · 0 works")
        #expect(ReadingQueueFacts.contextCardKicker(workCount: 1) == "Queue · 1 work")
        #expect(ReadingQueueFacts.contextCardKicker(workCount: 8) == "Queue · 8 works")

        #expect(
            ReadingQueueFacts.contextCardMeta(
                workCount: 0, totalWordCount: 0, finishedCount: 0, offlineCount: 0
            ) == "No works yet"
        )
        let eightWorks = ReadingQueueFacts.readingTimeEstimate(wordCount: 116_000) ?? ""
        #expect(
            ReadingQueueFacts.contextCardMeta(
                workCount: 8, totalWordCount: 116_000, finishedCount: 2, offlineCount: 6
            ) == ReadingQueueFacts.capitalizedSentenceStart("\(eightWorks) · 2 finished · 6 offline")
        )
        let fiveWorks = ReadingQueueFacts.readingTimeEstimate(wordCount: 49_000) ?? ""
        #expect(
            ReadingQueueFacts.contextCardMeta(
                workCount: 5, totalWordCount: 49_000, finishedCount: 0, offlineCount: 5
            ) == ReadingQueueFacts.capitalizedSentenceStart("\(fiveWorks) · all offline")
        )
        #expect(
            ReadingQueueFacts.contextCardMeta(
                workCount: 3, totalWordCount: 0, finishedCount: 0, offlineCount: 3
            ) == "All offline"
        )
        #expect(
            ReadingQueueFacts.contextCardMeta(
                workCount: 2, totalWordCount: 0, finishedCount: 0, offlineCount: 0
            ) == "0 offline"
        )
    }

    @Test func findMoreSubtitleBadgeAndAccessibilityMatchQueueBoards() {
        #expect(ReadingQueueFacts.findMoreSubtitle(sourceNames: []) == "")
        #expect(
            ReadingQueueFacts.findMoreSubtitle(sourceNames: ["Holmes casefic under 20k"])
                == "Holmes casefic under 20k"
        )
        #expect(
            ReadingQueueFacts.findMoreSubtitle(
                sourceNames: ["Holmes casefic under 20k", "Lighthouses", "fogandlamplight", "Series", "Tag"]
            ) == "Holmes casefic under 20k + 4 more"
        )

        #expect(ReadingQueueFacts.findMoreBadge(counts: []) == nil)
        #expect(ReadingQueueFacts.findMoreBadge(counts: [0, 0]) == nil)
        #expect(ReadingQueueFacts.findMoreBadge(counts: [3]) == "3 new")
        #expect(ReadingQueueFacts.findMoreBadge(counts: [20]) == "20+ new")
        #expect(ReadingQueueFacts.findMoreBadge(counts: [3, 1, 5]) == "9 new")
        #expect(ReadingQueueFacts.findMoreBadge(counts: [20, 3]) == "23+ new")

        #expect(
            ReadingQueueFacts.findMoreAccessibilityLabel(
                sourceNames: ["Holmes casefic under 20k"], newCounts: [3]
            ) == "Find more works: Holmes casefic under 20k, 3 new on AO3"
        )
        #expect(
            ReadingQueueFacts.findMoreAccessibilityLabel(
                sourceNames: ["Holmes casefic under 20k"], newCounts: []
            ) == "Find more works: Holmes casefic under 20k on AO3"
        )
        #expect(
            ReadingQueueFacts.findMoreAccessibilityLabel(
                sourceNames: ["A", "B", "C"], newCounts: [3, 1, 5]
            ) == "Find more works: 3 sources, 9 new on AO3"
        )
        #expect(
            ReadingQueueFacts.findMoreAccessibilityLabel(
                sourceNames: ["A", "B"], newCounts: []
            ) == "Find more works: 2 sources on AO3"
        )
    }

    @Test func newSectionBannerAndFinishedDisclosureMatchSectionsBoard() {
        #expect(ReadingQueueFacts.newBannerTitle == "New, not sorted yet")
        #expect(
            ReadingQueueFacts.newBannerSubtitle(count: 7, allAddedToday: true, fromFindMore: true)
                == "Added today from Find More"
        )
        #expect(
            ReadingQueueFacts.newBannerSubtitle(count: 3, allAddedToday: true, fromFindMore: false)
                == "Added today"
        )
        #expect(
            ReadingQueueFacts.newBannerSubtitle(count: 4, allAddedToday: false, fromFindMore: true)
                == "Added from Find More"
        )
        #expect(
            ReadingQueueFacts.newBannerSubtitle(count: 1, allAddedToday: false, fromFindMore: false)
                == "1 work waiting to sort"
        )
        #expect(
            ReadingQueueFacts.newBannerSubtitle(count: 5, allAddedToday: false, fromFindMore: false)
                == "5 works waiting to sort"
        )

        #expect(ReadingQueueFacts.finishedSectionCount(1) == "1 work")
        #expect(ReadingQueueFacts.finishedSectionCount(2) == "2 works")
    }

    @Test func newBannerDoesNotClaimFindMoreUnlessEveryWorkCameFromIt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = now.addingTimeInterval(-3 * 24 * 60 * 60)
        #expect(
            ReadingQueueFacts.newBannerSubtitle(
                for: [bannerEntry(kind: .search, queuedAt: now), bannerEntry(kind: .manual, queuedAt: now)],
                now: now
            ) == "Added today"
        )
        #expect(
            ReadingQueueFacts.newBannerSubtitle(
                for: [bannerEntry(kind: .search, queuedAt: earlier), bannerEntry(kind: .source, queuedAt: earlier)],
                now: now
            ) == "Added from Find More"
        )
        #expect(
            ReadingQueueFacts.newBannerSubtitle(
                for: [bannerEntry(kind: .search, queuedAt: now), bannerEntry(kind: .source, queuedAt: now)],
                now: now
            ) == "Added today from Find More"
        )
    }

    private func bannerEntry(
        kind: ReadingQueueMembershipOriginKind,
        queuedAt: Date
    ) -> ReadingQueueSectionEntry {
        let work = SavedWork(title: "Work", author: "Author")
        let membership = ReadingQueueMembership(
            queue: nil,
            work: work,
            queuedAt: queuedAt,
            origin: ReadingQueueMembershipOrigin(kind: kind)
        )
        return ReadingQueueSectionEntry(
            membership: membership,
            work: work,
            section: .new,
            hasNewChapter: false
        )
    }

    @Test func seriesSourceAndEditOfflineSubtitlesMatchBoards() {
        #expect(ReadingQueueFacts.seriesSourceSubtitle(partCount: 0, isComplete: false) == "Series")
        #expect(
            ReadingQueueFacts.seriesSourceSubtitle(partCount: 1, isComplete: false)
                == "Series · 1 part, not finished"
        )
        #expect(
            ReadingQueueFacts.seriesSourceSubtitle(partCount: 2, isComplete: false)
                == "Series · 2 parts, not finished"
        )
        #expect(
            ReadingQueueFacts.seriesSourceSubtitle(partCount: 2, isComplete: true)
                == "Series · 2 parts"
        )

        #expect(ReadingQueueFacts.offlineDownloadSubtitle(offlineCount: 0, totalCount: 0, byteCount: 0) == nil)
        let formatted = queueByteCountString(41_000_000)
        #expect(
            ReadingQueueFacts.offlineDownloadSubtitle(offlineCount: 6, totalCount: 8, byteCount: 41_000_000)
                == "6 of 8 downloaded · \(formatted)"
        )
    }

    @Test func newAndSmartQueueSheetCopyMatchesBoards() {
        #expect(NewReadingQueueSheet.confirmButtonTitle(isEditing: false, isSmart: false) == "Add")
        #expect(NewReadingQueueSheet.confirmButtonTitle(isEditing: true, isSmart: false) == "Save")
        #expect(NewReadingQueueSheet.confirmButtonTitle(isEditing: false, isSmart: true) == "Save")
        #expect(NewReadingQueueSheet.confirmButtonTitle(isEditing: true, isSmart: true) == "Save")

        #expect(
            NewReadingQueueSheet.offlineFootnote
                == "Kudos downloads each work you add and keeps it while it's in this queue."
        )
        #expect(NewReadingQueueSheet.offlineFootnote(keepsWorksOffline: true) == NewReadingQueueSheet.offlineFootnote)
        #expect(
            NewReadingQueueSheet.offlineFootnote(keepsWorksOffline: false)
                == "When this is off, the queue keeps only your list and uses no extra storage."
        )
        #expect(
            NewReadingQueueSheet.smartFootnote
                == "A smart queue updates itself as your library changes. "
                + "A work leaves when it stops matching, for example when you finish it."
        )

        let emptyPreview = NewReadingQueueSheet.smartPreviewCopy(for: [], fileExists: { _ in true })
        #expect(emptyPreview.count == "0 works")
        #expect(emptyPreview.detail.isEmpty)

        let works: [SavedWork] = (1 ... 12).map { index in
            let work = SavedWork(title: "Work \(index)", author: "Author")
            work.wordCount = 3_167 // 12 * 3,167 = 38,004 -> 190 min = 3 h 10 min
            work.hasEPUB = index <= 9
            return work
        }
        let expectedTime = ReadingQueueFacts.capitalizedSentenceStart(
            ReadingQueueFacts.readingTimeEstimate(wordCount: 12 * 3_167) ?? ""
        )
        let populated = NewReadingQueueSheet.smartPreviewCopy(for: works, fileExists: { _ in true })
        #expect(populated.count == "12 works")
        #expect(populated.detail == "\(expectedTime) · 9 offline")
    }
}
