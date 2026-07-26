import Foundation
import Testing
@testable import Kudos

/// Covers the reader position card's pure formatting layer: the
/// positions→minutes conversion (`ReaderTimeEstimate`) and the three label lines
/// built from an already-resolved reading position (`ReaderPositionSummary`).
/// Both are deliberately navigator-free so the rules are testable without an
/// open EPUB.
struct ReaderTimeEstimateTests {
    // MARK: - minutes(forPositions:)

    @Test func zeroPositionsIsZeroMinutes() {
        #expect(ReaderTimeEstimate.minutes(forPositions: 0) == 0)
    }

    @Test func negativePositionCountClampsToZero() {
        // Remaining counts are derived by subtraction, so a stale locator could
        // momentarily produce a negative — it must never render as "-3 min".
        #expect(ReaderTimeEstimate.minutes(forPositions: -5) == 0)
    }

    @Test func onePositionRoundsToOneMinute() {
        // 1 position ≈ 1 KB ≈ 55 s, which rounds to 1 min.
        #expect(ReaderTimeEstimate.minutes(forPositions: 1) == 1)
    }

    @Test func minutesScaleWithTheDocumentedConstant() {
        // 12 positions × 55 s = 660 s = 11 min exactly.
        #expect(ReaderTimeEstimate.minutes(forPositions: 12) == 11)
        // 60 positions × 55 s = 3300 s = 55 min.
        #expect(ReaderTimeEstimate.minutes(forPositions: 60) == 55)
    }

    // MARK: - durationLabel(minutes:)

    @Test func durationUnderAnHourIsMinutesOnly() {
        #expect(ReaderTimeEstimate.durationLabel(minutes: 0) == "0 min")
        #expect(ReaderTimeEstimate.durationLabel(minutes: 8) == "8 min")
        #expect(ReaderTimeEstimate.durationLabel(minutes: 59) == "59 min")
    }

    @Test func durationAtWholeHoursOmitsTheMinutes() {
        #expect(ReaderTimeEstimate.durationLabel(minutes: 60) == "1 hr")
        #expect(ReaderTimeEstimate.durationLabel(minutes: 120) == "2 hr")
    }

    @Test func durationOverAnHourCombinesBothUnits() {
        #expect(ReaderTimeEstimate.durationLabel(minutes: 65) == "1 hr 5 min")
        #expect(ReaderTimeEstimate.durationLabel(minutes: 195) == "3 hr 15 min")
    }

    @Test func durationClampsNegativeMinutes() {
        #expect(ReaderTimeEstimate.durationLabel(minutes: -10) == "0 min")
    }

    // MARK: - Suffixed labels

    @Test func chapterAndWorkLabelsCarryTheirOwnSuffixes() {
        #expect(ReaderTimeEstimate.chapterRemainingLabel(positions: 12) == "11 min left in chapter")
        #expect(ReaderTimeEstimate.workRemainingLabel(positions: 12) == "11 min left")
    }

    // MARK: - ReaderPositionSummary

    private func summary(
        page: Int = 3, pageCount: Int = 12, percent: Int = 34,
        place: ReaderPositionSummary.Place = .chapter(index: 2, total: 10),
        remainingInChapter: Int? = 9, remainingInWork: Int? = 71
    ) -> ReaderPositionSummary {
        ReaderPositionSummary(
            page: page, pageCount: pageCount, percent: percent, place: place,
            remainingInChapter: remainingInChapter, remainingInWork: remainingInWork
        )
    }

    @Test func pageLabelReadsAsPageOfCount() {
        #expect(summary().pageLabel == "Page 3 of 12")
    }

    @Test func fullyPopulatedSummaryBuildsAllThreeLines() {
        let result = summary()
        #expect(result.chapterTimeLabel == "8 min left in chapter")
        #expect(result.workLine == "Chapter 2 of 10 · 34% of work · 1 hr 5 min left")
    }

    @Test func missingRemainingCountsDropTheTimeEstimates() {
        // Before the navigator reports a position there is no honest estimate to
        // show — the labels must omit it rather than claim "0 min left".
        let result = summary(remainingInChapter: nil, remainingInWork: nil)
        #expect(result.chapterTimeLabel.isEmpty)
        #expect(result.workLine == "Chapter 2 of 10 · 34% of work")
    }

    @Test func chapterTotalIsFlooredAtTheCurrentChapter() {
        // A WIP whose posted total is unknown (or stale) must never render the
        // nonsense "Chapter 7 of 1".
        let result = summary(place: .chapter(index: 7, total: 1))
        #expect(result.workLine.hasPrefix("Chapter 7 of 7 · "))
    }

    @Test func singlePagePositionStillFormats() {
        let result = summary(page: 1, pageCount: 1, percent: 100,
                            place: .chapter(index: 1, total: 1),
                            remainingInChapter: 0, remainingInWork: 0)
        #expect(result.pageLabel == "Page 1 of 1")
        #expect(result.chapterTimeLabel == "0 min left in chapter")
        #expect(result.workLine == "Chapter 1 of 1 · 100% of work · 0 min left")
    }

    // MARK: - Front/back matter is never numbered as a chapter

    @Test func frontAndBackMatterAreNamedNotNumbered() {
        // AO3 wraps the story in a Preface/Summary/Afterword. Rendering those as
        // "Chapter 1 of 66" (the pre-fix behaviour) was simply untrue.
        #expect(summary(place: .preface).workLine.hasPrefix("Preface · "))
        #expect(summary(place: .summary).workLine.hasPrefix("Summary · "))
        #expect(summary(place: .afterword).workLine.hasPrefix("Afterword · "))
        for place in [ReaderPositionSummary.Place.preface, .summary, .afterword] {
            #expect(!summary(place: place).workLine.contains("Chapter"))
        }
    }

    @Test func unrecognizedSectionShowsPercentWithoutADanglingSeparator() {
        let result = summary(place: .other)
        #expect(result.workLine == "34% of work · 1 hr 5 min left")
        #expect(!result.workLine.hasPrefix(" · "))
    }

    // MARK: - Place(section:storyChapterTotal:)

    private func section(_ kind: ReaderSectionKind, storyChapterIndex: Int? = nil) -> ReaderSection {
        ReaderSection(href: "s.xhtml", title: "t", kind: kind,
                      spineIndex: 0, storyChapterIndex: storyChapterIndex)
    }

    @Test func placeMapsEachNormalizedSectionKind() {
        #expect(ReaderPositionSummary.Place(section: section(.preface), storyChapterTotal: 10) == .preface)
        #expect(ReaderPositionSummary.Place(section: section(.summary), storyChapterTotal: 10) == .summary)
        #expect(ReaderPositionSummary.Place(section: section(.afterword), storyChapterTotal: 10) == .afterword)
        #expect(ReaderPositionSummary.Place(section: section(.other), storyChapterTotal: 10) == .other)
        #expect(
            ReaderPositionSummary.Place(section: section(.chapter, storyChapterIndex: 4), storyChapterTotal: 10)
                == .chapter(index: 4, total: 10)
        )
    }

    @Test func chapterSectionMissingItsIndexFallsBackToOne() {
        // `.chapter` always carries a storyChapterIndex from the builder; the
        // fallback exists so a malformed section can't crash the card.
        #expect(
            ReaderPositionSummary.Place(section: section(.chapter), storyChapterTotal: 10)
                == .chapter(index: 1, total: 10)
        )
    }
}
