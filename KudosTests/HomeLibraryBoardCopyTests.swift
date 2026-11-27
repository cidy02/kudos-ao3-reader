import Foundation
import Testing
@testable import Kudos

/// Board-copy regression tests for the T-507 Home & Library detail sweep:
/// Home section headings and "more" rows, Resume card updated caption,
/// Library Favourites card footers, Shelf List/Grid/Select subtitles,
/// Library Filters active word-range chip, and WorkRow ledger stats separator.
@MainActor
@Suite("Home & Library board copy (T-507)")
struct HomeLibraryBoardCopyTests {
    @Test func homeLaunchpadSectionTitlesLimitsAndMoreLabels() {
        #expect(HomeBoardCopy.alsoReadingTitle == "Also Reading")
        #expect(HomeBoardCopy.queuesTitle == "Queues")
        #expect(HomeBoardCopy.queuesActionTitle == "Organise")
        #expect(HomeBoardCopy.pinnedCollectionCardLimit == 4)
        #expect(HomeBoardCopy.subscriptionVisibleRowLimit == 4)

        #expect(HomeBoardCopy.subscriptionsNewCountText(9) == "9 new")
        #expect(HomeBoardCopy.subscriptionsNewCountText(1) == "1 new")
        #expect(HomeBoardCopy.moreUpdatesLabel(1) == "1 more update")
        #expect(HomeBoardCopy.moreUpdatesLabel(5) == "5 more updates")
        #expect(HomeBoardCopy.moreQueuesLabel(1) == "1 more queue")
        #expect(HomeBoardCopy.moreQueuesLabel(2) == "2 more queues")
    }

    @Test func resumeCardFormatsISOUpdatedDateAndPreservesShortDates() {
        let isoModel = makeResumeModel(updated: "2026-10-21")
        #expect(isoModel.updatedCaption == "Updated \(WorkStat.displayDate("2026-10-21"))")
        #expect(isoModel.updatedCaption != "Updated 2026-10-21")

        let shortModel = makeResumeModel(updated: "Oct 21")
        #expect(shortModel.updatedCaption == "Updated Oct 21")

        let blankModel = makeResumeModel(updated: "   ")
        #expect(blankModel.updatedCaption == nil)
    }

    @Test func favouritesFooterOmitsMultiplierForSingleFinishAndIncludesItForRereads() throws {
        let locale = Locale(identifier: "en_US")
        let gmt = try #require(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = gmt

        let aug2 = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 12)))
        let oct24 = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12)))

        #expect(
            LibraryFavouriteCardCopy.footer(finishCount: 0, lastFinishedAt: aug2, locale: locale, timeZone: gmt) == nil
        )
        #expect(
            LibraryFavouriteCardCopy.footer(finishCount: 1, lastFinishedAt: nil, locale: locale, timeZone: gmt) == nil
        )
        #expect(
            LibraryFavouriteCardCopy.footer(finishCount: 1, lastFinishedAt: aug2, locale: locale, timeZone: gmt)
                == "Read Aug 2"
        )
        #expect(
            LibraryFavouriteCardCopy.footer(finishCount: 2, lastFinishedAt: oct24, locale: locale, timeZone: gmt)
                == "Read ×2 · Oct 24"
        )
    }

    @Test func finishedShelfOrderAndShelfHeaderTalliesMatchBoards() {
        #expect(LibrarySectionKind.finished.orderDescription == "most recently finished first")

        #expect(LibraryShelfHeaderCopy.tallyLine(
            visibleCount: 74,
            totalCount: 74,
            orderDescription: LibrarySectionKind.finished.orderDescription,
            arrangement: .list,
            hasActiveFilters: false,
            isSelecting: false,
            selectedCount: 0
        ) == "74 works · most recently finished first")

        #expect(LibraryShelfHeaderCopy.tallyLine(
            visibleCount: 1,
            totalCount: 1,
            orderDescription: LibrarySectionKind.readingNow.orderDescription,
            arrangement: .list,
            hasActiveFilters: false,
            isSelecting: false,
            selectedCount: 0
        ) == "1 work · most recently read first")

        #expect(LibraryShelfHeaderCopy.tallyLine(
            visibleCount: 74,
            totalCount: 74,
            orderDescription: LibrarySectionKind.finished.orderDescription,
            arrangement: .grid,
            hasActiveFilters: false,
            isSelecting: false,
            selectedCount: 0
        ) == "74 works · Grid")

        #expect(LibraryShelfHeaderCopy.tallyLine(
            visibleCount: 6,
            totalCount: 6,
            orderDescription: LibrarySectionKind.readingNow.orderDescription,
            arrangement: .list,
            hasActiveFilters: false,
            isSelecting: true,
            selectedCount: 2
        ) == "2 of 6 selected · most recently read first")

        #expect(LibraryShelfHeaderCopy.tallyLine(
            visibleCount: 0,
            totalCount: 12,
            orderDescription: LibrarySectionKind.finished.orderDescription,
            arrangement: .list,
            hasActiveFilters: true,
            isSelecting: false,
            selectedCount: 0
        ) == "12 works · none match the current filters")

        #expect(LibraryShelfHeaderCopy.tallyLine(
            visibleCount: 4,
            totalCount: 12,
            orderDescription: LibrarySectionKind.finished.orderDescription,
            arrangement: .list,
            hasActiveFilters: true,
            isSelecting: false,
            selectedCount: 0
        ) == "4 works")
    }

    @Test func libraryFilterWordRangeActiveChipFormatsCompactBounds() {
        #expect(LibraryFilterPanel.wordRangeActiveLabel(from: "", to: "") == nil)
        #expect(LibraryFilterPanel.wordRangeActiveLabel(from: "  ", to: "") == nil)

        let ten = 10_000.compactCount.lowercased()
        let oneFifty = 150_000.compactCount.lowercased()
        let oneK = 1_000.compactCount.lowercased()

        #expect(LibraryFilterPanel.wordRangeActiveLabel(from: "10000", to: "150000") == "\(ten)–\(oneFifty) words")
        #expect(LibraryFilterPanel.wordRangeActiveLabel(from: "10000", to: "") == "≥ \(ten) words")
        #expect(LibraryFilterPanel.wordRangeActiveLabel(from: "", to: "1000") == "≤ \(oneK) words")
    }

    @Test func workLedgerStatsLineUsesSingleSpaceSeparator() {
        let figures = WorkStat.ledgerFigures(
            language: "English",
            wordCount: 84_210,
            chapters: "12/20",
            comments: nil,
            kudos: 3_104,
            bookmarks: nil,
            hits: nil,
            dateUpdated: "",
            showsZeroStats: false
        )
        let line = WorkLedgerStatsLine.formattedText(figures)
        #expect(WorkLedgerStatsLine.separator == " · ")
        #expect(line == "English · \(84_210.formatted()) words · 12/20 ch · ♥ \(3_104.formatted())")
        #expect(!line.contains("  ·  "))
    }

    // MARK: - Helpers

    private func makeResumeModel(updated: String) -> ResumeCardModel {
        ResumeCardModel(
            coverRecipe: GeneratedCoverRecipe(id: nil, title: "The Salt Road", author: "", fandoms: []),
            title: "The Salt Road",
            authors: ["wren"],
            authorIdentities: [],
            fandoms: ["Original Work"],
            rating: "T",
            categories: ["F/M"],
            warnings: [],
            completion: .inProgress,
            words: 84_210,
            kudos: 3_104,
            chapters: "12/20",
            progress: 0.58,
            chapterProgress: 0.22,
            chapterName: "Ch 7, The Salt Road",
            published: "Mar 3",
            updated: updated,
            newChapterCount: 0
        )
    }
}
