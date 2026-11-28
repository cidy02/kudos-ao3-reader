import Foundation
import Testing
@testable import Kudos

/// Board copy regressions for the Subscriptions and Collection detail sweeps
/// (`Subscriptions`, `Subscriptions-Plan`, `Subscriptions-Tags`, `Collection`,
/// `Collection-New`, `Collection-Reorder`).
@MainActor
struct SubscriptionsBoardCopyTests {
    private let sampleDate = Date(timeIntervalSince1970: 1_760_918_400)

    // MARK: - Subscriptions top rail

    @Test func tagsPillShowsCountOnlyWhenFollowedTagsExist() {
        #expect(SubscriptionsBoardCopy.tabTitle(for: .tags, tagCount: 3) == "Tags 3")
        #expect(SubscriptionsBoardCopy.tabTitle(for: .tags, tagCount: 0) == "Tags")
        #expect(SubscriptionsBoardCopy.tabTitle(for: .waiting, tagCount: 3) == "Waiting")
        #expect(SubscriptionsBoardCopy.tabTitle(for: .following, tagCount: 3) == "Following")
        #expect(SubscriptionsBoardCopy.tabTitle(for: .tidyUp, tagCount: 3) == "Tidy up")
    }

    // MARK: - Waiting / Updates rows

    @Test func waitingSourceLineMatchesBoardBySourceKind() {
        let workUpdate = makeUpdate(source: .work, author: "wrenfield")
        #expect(WaitingRowBoardCopy.sourceLine(for: workUpdate) == "wrenfield")
        #expect(!WaitingRowBoardCopy.showsAuthorInMetadata(for: workUpdate))

        let contestedWork = makeUpdate(source: .work, author: "wrenfield", isContested: true)
        #expect(WaitingRowBoardCopy.sourceLine(for: contestedWork) == "Following this work")
        #expect(!WaitingRowBoardCopy.showsAuthorInMetadata(for: contestedWork))

        let seriesUpdate = makeUpdate(
            source: .series("Bath & Barouche"),
            author: "quietharbor",
            isAnchoredToWork: false
        )
        #expect(WaitingRowBoardCopy.sourceLine(for: seriesUpdate) == "Bath & Barouche · quietharbor")
        #expect(!WaitingRowBoardCopy.showsAuthorInMetadata(for: seriesUpdate))

        let seriesWithoutAuthor = makeUpdate(
            source: .series("Series #4021"),
            author: "",
            isAnchoredToWork: false
        )
        #expect(WaitingRowBoardCopy.sourceLine(for: seriesWithoutAuthor) == "Series #4021")

        let authorSameName = makeUpdate(
            source: .author("fogandlamplight"),
            author: "fogandlamplight",
            isAnchoredToWork: false
        )
        #expect(WaitingRowBoardCopy.sourceLine(for: authorSameName) == "fogandlamplight")
        #expect(!WaitingRowBoardCopy.showsAuthorInMetadata(for: authorSameName))

        let authorWithPseud = makeUpdate(
            source: .author("fogandlamplight"),
            author: "Baker Street Pseud",
            isAnchoredToWork: false
        )
        #expect(WaitingRowBoardCopy.showsAuthorInMetadata(for: authorWithPseud))

        let tagSource = SubscriptionUpdate.FollowedTagUpdateSource(
            tagID: 10,
            name: "Pride and Prejudice",
            category: "Fandom",
            tagURLString: nil,
            count: 6,
            isBusy: false,
            showOnHome: true
        )
        let tagUpdate = makeUpdate(source: .tag(tagSource), author: "wrenfield")
        #expect(WaitingRowBoardCopy.sourceLine(for: tagUpdate) == "Pride and Prejudice · fandom")
        #expect(WaitingRowBoardCopy.showsAuthorInMetadata(for: tagUpdate))

        let unknownUpdate = makeUpdate(source: .unknown, author: "", isAnchoredToWork: false)
        #expect(WaitingRowBoardCopy.sourceLine(for: unknownUpdate) == "From a subscription")
    }

    @Test func waitingWhatChangedIncludesKnownChapterWordsAndPreservesHonesty() {
        let chapterWithWords = makeUpdate(
            source: .work,
            chapterNumber: 9,
            words: 5_020
        )
        let expectedWords = UInt64(5_020).formatted()
        #expect(
            WaitingRowBoardCopy.whatChanged(for: chapterWithWords, chapter: 9)
                == "Chapter 9 · \(expectedWords) words"
        )

        let chapterWithoutWords = makeUpdate(source: .work, chapterNumber: 9, words: nil)
        #expect(WaitingRowBoardCopy.whatChanged(for: chapterWithoutWords, chapter: 9) == "Chapter 9 posted")

        let newWorkWithMeta = makeUpdate(
            source: .work,
            chapterID: nil,
            chapterNumber: nil,
            isNewWork: true,
            fandoms: ["Sherlock Holmes"],
            words: 3_800
        )
        let expectedNewWorkWords = UInt64(3_800).formatted()
        #expect(
            WaitingRowBoardCopy.whatChanged(for: newWorkWithMeta, chapter: nil)
                == "New work · Sherlock Holmes · \(expectedNewWorkWords) words"
        )

        let bareNewWork = makeUpdate(
            source: .work,
            chapterID: nil,
            chapterNumber: nil,
            isNewWork: true
        )
        #expect(WaitingRowBoardCopy.whatChanged(for: bareNewWork, chapter: nil) == "A new work was posted")

        let contested = makeUpdate(source: .work, isContested: true)
        #expect(
            WaitingRowBoardCopy.whatChanged(for: contested, chapter: nil)
                == "This work updated. Open it to see what changed."
        )

        let unpinned = makeUpdate(source: .author("fogandlamplight"), isAnchoredToWork: false)
        #expect(
            WaitingRowBoardCopy.whatChanged(for: unpinned, chapter: nil)
                == "Something new from this follow. Open it on AO3 to see what."
        )
        #expect(WaitingRowBoardCopy.badge(for: chapterWithWords, chapter: 9) == "+1 · Ch. 9")
        #expect(WaitingRowBoardCopy.badge(for: bareNewWork, chapter: nil) == "New")
        #expect(WaitingRowBoardCopy.badge(for: contested, chapter: nil) == "Updated")
        #expect(WaitingRowBoardCopy.badge(for: unpinned, chapter: nil) == "Check")
    }

    @Test func waitingTagRowsUseBoardCountAndMoreCopy() {
        let pairTag = SubscriptionUpdate.FollowedTagUpdateSource(
            tagID: 11,
            name: "Anne Elliot/Frederick Wentworth",
            category: "Relationship",
            tagURLString: nil,
            count: 2,
            isBusy: false,
            showOnHome: true
        )
        let pairUpdate = makeUpdate(
            source: .tag(pairTag),
            workTitle: "Half Agony, Half Hope (Again)"
        )
        #expect(
            WaitingRowBoardCopy.whatChanged(for: pairUpdate, chapter: nil)
                == "\u{201C}Half Agony, Half Hope (Again)\u{201D} and 1 more"
        )
        #expect(WaitingRowBoardCopy.badge(for: pairUpdate, chapter: nil) == "2")

        let singleTag = SubscriptionUpdate.FollowedTagUpdateSource(
            tagID: 12,
            name: "Lighthouses",
            category: nil,
            tagURLString: nil,
            count: 1,
            isBusy: false,
            showOnHome: false
        )
        let singleUpdate = makeUpdate(source: .tag(singleTag))
        #expect(WaitingRowBoardCopy.badge(for: singleUpdate, chapter: nil) == "New")

        let busyTag = SubscriptionUpdate.FollowedTagUpdateSource(
            tagID: 13,
            name: "Pride and Prejudice",
            category: "Fandom",
            tagURLString: nil,
            count: 25,
            isBusy: true,
            showOnHome: true
        )
        let busyUpdate = makeUpdate(source: .tag(busyTag), workTitle: "Netherfield in Snow")
        #expect(
            WaitingRowBoardCopy.whatChanged(for: busyUpdate, chapter: nil)
                == "\u{201C}Netherfield in Snow\u{201D} and more"
        )
        #expect(
            WaitingRowBoardCopy.badge(for: busyUpdate, chapter: nil)
                == "\(FollowedTagFeedEvaluator.maxFeedEntries)+"
        )
    }

    // MARK: - Follow Tag sheet & Followed Tags list

    @Test func followTagSheetSubtitleLeadsWithCategory() {
        #expect(
            FollowTagSheetCopy.subtitle(
                category: "Fandom",
                followedCount: 3,
                maxCount: 20,
                lastCheckedRelativeText: nil
            ) == "Fandom · 3 of 20 tags followed"
        )
        #expect(
            FollowTagSheetCopy.subtitle(
                category: "Fandom",
                followedCount: 3,
                maxCount: 20,
                lastCheckedRelativeText: "10 min ago"
            ) == "Fandom · Last checked 10 min ago"
        )
        #expect(
            FollowTagSheetCopy.subtitle(
                category: nil,
                followedCount: 0,
                maxCount: 20,
                lastCheckedRelativeText: nil
            ) == "0 of 20 tags followed"
        )
    }

    @Test func followedTagsHeaderAndRowCopyMatchBoard() {
        #expect(
            FollowedTagsBoardCopy.subtitle(count: 3, checkedRelativeText: "10 min ago")
                == "3 tags followed in Kudos · checked 10 min ago"
        )
        #expect(
            FollowedTagsBoardCopy.subtitle(count: 1, checkedRelativeText: nil)
                == "1 tag followed in Kudos"
        )
        #expect(
            FollowedTagsBoardCopy.subtitle(count: 20, checkedRelativeText: nil, isAtLimit: true)
                == "20 tags followed in Kudos · limit reached"
        )

        #expect(
            FollowedTagsBoardCopy.rowSubtitle(
                unreadCount: 6,
                isBusy: false,
                lastSeenDate: nil,
                lastCheckedAt: nil,
                completeOnly: true,
                hideExplicit: false,
                showOnHome: true
            ) == "6 new · Complete only · on Home"
        )
        #expect(
            FollowedTagsBoardCopy.rowSubtitle(
                unreadCount: 2,
                isBusy: false,
                lastSeenDate: nil,
                lastCheckedAt: nil,
                completeOnly: false,
                hideExplicit: false,
                showOnHome: true
            ) == "2 new · on Home"
        )

        let expectedDate = WorkStat.displayDate(sampleDate)
        #expect(
            FollowedTagsBoardCopy.rowSubtitle(
                unreadCount: 0,
                isBusy: false,
                lastSeenDate: sampleDate,
                lastCheckedAt: nil,
                completeOnly: false,
                hideExplicit: true,
                showOnHome: false
            ) == "Nothing new since \(expectedDate) · Hide Explicit"
        )
        #expect(
            FollowedTagsBoardCopy.rowSubtitle(
                unreadCount: 0,
                isBusy: false,
                lastSeenDate: nil,
                lastCheckedAt: nil,
                completeOnly: false,
                hideExplicit: false,
                showOnHome: false
            ) == "Not checked yet"
        )

        #expect(FollowedTagsBoardCopy.badgeLabel(unreadCount: 0, isBusy: false) == nil)
        #expect(FollowedTagsBoardCopy.badgeLabel(unreadCount: 6, isBusy: false) == "6")
        #expect(FollowedTagsBoardCopy.badgeLabel(unreadCount: 25, isBusy: true) == "25+")
    }

    // MARK: - Collections (Detail, New, Reorder)

    @Test func collectionDetailSubtitleIncludesReadingTimeAndCustomOrderOnlyWhenKnown() throws {
        let estimate = try #require(ReadingQueueFacts.readingTimeEstimate(wordCount: 168_000))
        #expect(
            CollectionBoardCopy.subtitle(
                workCount: 12,
                totalWordCount: 168_000,
                hasCustomOrder: true
            ) == "12 works · \(estimate) · custom order"
        )
        #expect(
            CollectionBoardCopy.subtitle(
                workCount: 1,
                totalWordCount: nil,
                hasCustomOrder: false
            ) == "1 work"
        )
        #expect(
            CollectionBoardCopy.subtitle(
                workCount: 3,
                totalWordCount: 0,
                hasCustomOrder: true
            ) == "3 works · custom order"
        )
    }

    @Test func newCollectionAndReorderContextCopyMatchBoards() {
        #expect(NewCollectionBoardCopy.previewKicker == "New collection")
        #expect(NewCollectionBoardCopy.previewMeta == "No works yet · only in Kudos")
        #expect(NewCollectionBoardCopy.previewTitle(for: "   ") == "Untitled collection")
        #expect(NewCollectionBoardCopy.previewTitle(for: " Austen Variations ") == "Austen Variations")
        #expect(NewCollectionBoardCopy.reorderKicker(workCount: 1) == "Collection · 1 work")
        #expect(NewCollectionBoardCopy.reorderKicker(workCount: 12) == "Collection · 12 works")
        #expect(NewCollectionBoardCopy.reorderMeta == "Drag to set the reading order")
    }

    // MARK: - Helpers

    private func makeUpdate(
        source: SubscriptionUpdate.Source,
        workTitle: String = "Salt & Starlight",
        author: String = "wrenfield",
        chapterID: UInt64? = 100,
        chapterNumber: Int? = 9,
        isNewWork: Bool = false,
        isContested: Bool = false,
        isAnchoredToWork: Bool = true,
        fandoms: [String] = [],
        words: UInt64? = nil
    ) -> SubscriptionUpdate {
        SubscriptionUpdate(
            uid: 1,
            workID: 42,
            chapterID: chapterID,
            chapterNumber: chapterNumber,
            isNewWork: isNewWork,
            isContested: isContested,
            isAnchoredToWork: isAnchoredToWork,
            workTitle: workTitle,
            author: author,
            at: sampleDate,
            source: source,
            fandoms: fandoms,
            words: words
        )
    }
}
