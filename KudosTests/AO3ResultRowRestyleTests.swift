import Testing
@testable import Kudos

struct AO3ResultRowRestyleTests {
    @Test func resultRangeUsesTheSharedPageSizeAndStopsAtTheTotal() {
        let first = AO3ResultSummary(total: 260_114, scope: nil, range: nil)
            .completing(subject: nil, page: 1, onPageCount: AO3ResultSummary.worksPerPage)
        let last = AO3ResultSummary(total: 45, scope: nil, range: nil)
            .completing(subject: nil, page: 3, onPageCount: 5)
        #expect(
            AO3ResultListPaging.rangeSubtitle(total: first.total, range: first.range)
                == "1–20 of 260,114 works on AO3"
        )
        #expect(AO3ResultListPaging.rangeSubtitle(total: last.total, range: last.range)
            == "41–45 of 45 works on AO3")
        #expect(AO3ResultListPaging.rangeSubtitle(
            total: 260_114,
            range: 41 ... 60,
            rankedCount: 100
        ) == "1–100 of 260,114 works on AO3")
    }

    @Test func resultPagesStopAtAO3sSearchCap() {
        #expect(AO3ResultListPaging.clampedTotalPages(8_000) == 5_000)
        #expect(AO3ResultListPaging.clampedTotalPages(42) == 42)
        #expect(AO3ResultListPaging.clampedTotalPages(0) == 1)
    }

    @Test func crossoverLabelNamesOnlyTheOtherFandoms() {
        #expect(AO3WorkRow.crossoverAccessibilityLabel(fandoms: ["Star Wars"]) == nil)
        #expect(
            AO3WorkRow.crossoverAccessibilityLabel(
                fandoms: ["Star Wars", "The Mandalorian", "Ahsoka"]
            ) == "Crossover with The Mandalorian, Ahsoka"
        )
    }

    @Test func localStatusUsesTheMostSpecificKnownState() {
        let text = AO3WorkRow.statusText
        #expect(text(.finished, "Ch 7", true, 2, true) == "Finished")
        #expect(text(.inProgress, "Ch 7", true, 2, true) == "Reading · Ch 7")
        #expect(text(.inProgress, nil, false, 0, true) == "Reading")
        #expect(text(.unread, nil, true, 2, true) == "Want to Read")
        #expect(text(.unread, nil, false, 2, false) == "In a queue")
        #expect(text(.unread, nil, false, 0, true) == "In Library")
        #expect(text(.freedHistory, nil, false, 0, false) == nil)
    }

    @Test func labelledStatsCellsMatchTheBoardOrderAndFormatting() {
        let cells = WorkListStatsGrid.cells(
            words: 48_210,
            chapters: "12/12",
            kudos: 3_104,
            hits: 41_200,
            comments: 214,
            bookmarks: 412,
            language: "English",
            dateUpdated: "2026-07-09"
        )
        #expect(cells.map(\.label) == ["Words", "Ch", "Kudos", "Hits", "Comments", "Bookmarks", nil, nil])
        #expect(Array(cells.map(\.value).prefix(7)) == [
            48_210.formatted(), "12/12", 3_104.formatted(), 41_200.compactCount,
            214.formatted(), 412.formatted(), "English",
        ])
        #expect(cells[7].value == WorkStat.displayDate("2026-07-09"))
    }

    @Test func statsCellsKeepKnownZeroAndReserveUnknownForSparseRows() {
        let full = WorkListStatsGrid.cells(
            words: 0, chapters: "1/1", kudos: 0, hits: 0, comments: 0,
            bookmarks: 0, language: "English", dateUpdated: "2026-07-09"
        )
        #expect(full[2].value == "0")
        #expect(full[2].accessibilityText == "0 kudos")

        let sparse = WorkListStatsGrid.cells(
            words: nil, chapters: "", kudos: nil, hits: nil, comments: nil,
            bookmarks: nil, language: "", dateUpdated: ""
        )
        #expect(sparse[2].value == "—")
        #expect(sparse[2].accessibilityText == "Kudos unknown")
    }
}
