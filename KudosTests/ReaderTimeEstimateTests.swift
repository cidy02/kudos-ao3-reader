import CoreGraphics
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

    @Test func secondsScaleWithTheDocumentedConstant() {
        #expect(ReaderTimeEstimate.seconds(forPositions: 0) == 0)
        #expect(ReaderTimeEstimate.seconds(forPositions: 1) == 55)
        #expect(ReaderTimeEstimate.seconds(forPositions: 12) == 660)
        #expect(ReaderTimeEstimate.seconds(forPositions: -3) == 0)
    }

    @Test func nowPlayingTimingExposesDurationAndElapsed() throws {
        // 100 positions total, 25 remaining → 75 elapsed.
        // Unwrap via #require first rather than chaining `timing?.duration ==`:
        // comparing through optional-member-access read as a genuine formula
        // bug under Swift Testing's macro-captured diagnostics (both sides
        // *displayed* as equal — "5500.0 == 5500" — yet the expectation still
        // failed); isolating the arithmetic in a standalone script confirmed
        // the formula itself is exactly correct, so this was the macro
        // expansion, not `nowPlayingTiming`.
        let timing = try #require(ReaderTimeEstimate.nowPlayingTiming(
            totalPositions: 100,
            remainingPositions: 25
        ))
        #expect(timing.duration == 100 * 55)
        #expect(timing.elapsed == 75 * 55)
    }

    @Test func nowPlayingTimingNilWhenTotalUnknown() {
        #expect(ReaderTimeEstimate.nowPlayingTiming(totalPositions: 0, remainingPositions: 0) == nil)
    }

    @Test func nowPlayingTimingClampsOverRemaining() throws {
        let timing = try #require(ReaderTimeEstimate.nowPlayingTiming(
            totalPositions: 10,
            remainingPositions: 50
        ))
        #expect(timing.duration == 10 * 55)
        #expect(timing.elapsed == 0)
    }

    // MARK: - TTS-paced timing (distinct from the silent-reading model above)

    // 200 wpm silent-reading calibration × 55 s ÷ 60, then ÷160 wpm × 60 — the
    // intermediate 11000/60 isn't exactly representable in binary floating
    // point, so comparisons below use a tight epsilon rather than `==`
    // (matches the existing tolerance pattern for the page-box snap tests).
    private func expectApproximatelyEqual(
        _ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(lhs - rhs) < tolerance, "\(lhs) is not within \(tolerance) of \(rhs)", sourceLocation: sourceLocation)
    }

    @Test func ttsSecondsPerPositionAtDefaultRateIsSlowerThanSilentReading() {
        // Spoken word is slower than the app's ~200 wpm silent-reading pace, so
        // the default (1.0x) TTS rate must take *longer* per position, not the
        // same 55 s the position card's silent estimate uses.
        expectApproximatelyEqual(ReaderTimeEstimate.ttsSecondsPerPosition(rate: 1.0), 68.75)
        #expect(
            ReaderTimeEstimate.ttsSecondsPerPosition(rate: 1.0) > ReaderTimeEstimate.secondsPerPosition
        )
    }

    @Test func ttsSecondsPerPositionScalesInverselyWithRate() {
        // Faster read-aloud rate → fewer seconds per position, and vice versa.
        expectApproximatelyEqual(ReaderTimeEstimate.ttsSecondsPerPosition(rate: 1.5), 68.75 / 1.5)
        expectApproximatelyEqual(ReaderTimeEstimate.ttsSecondsPerPosition(rate: 0.5), 137.5)
    }

    @Test func ttsNowPlayingTimingExposesDurationAndElapsedAtDefaultRate() throws {
        let timing = try #require(ReaderTimeEstimate.ttsNowPlayingTiming(
            totalPositions: 100, remainingPositions: 25, rate: 1.0
        ))
        expectApproximatelyEqual(timing.duration, 100 * 68.75)
        expectApproximatelyEqual(timing.elapsed, 75 * 68.75)
    }

    @Test func ttsNowPlayingTimingNilWhenTotalUnknown() {
        #expect(
            ReaderTimeEstimate.ttsNowPlayingTiming(totalPositions: 0, remainingPositions: 0, rate: 1.0) == nil
        )
    }

    @Test func ttsNowPlayingTimingClampsOverRemaining() throws {
        let timing = try #require(ReaderTimeEstimate.ttsNowPlayingTiming(
            totalPositions: 10, remainingPositions: 50, rate: 1.0
        ))
        expectApproximatelyEqual(timing.duration, 10 * 68.75)
        #expect(timing.elapsed == 0)
    }

    @Test func ttsNowPlayingTimingFasterRateShortensDuration() throws {
        // Same book, same progress — only the read-aloud speed changed, so the
        // estimated total time must shrink, not stay pinned to the silent model.
        let normal = try #require(ReaderTimeEstimate.ttsNowPlayingTiming(
            totalPositions: 100, remainingPositions: 0, rate: 1.0
        ))
        let faster = try #require(ReaderTimeEstimate.ttsNowPlayingTiming(
            totalPositions: 100, remainingPositions: 0, rate: 1.5
        ))
        #expect(faster.duration < normal.duration)
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

    // MARK: - Paged page-box snapping

    #if os(iOS)
    /// The two properties that keep paged mode from slicing its last line: the
    /// inset never drops below the minimum clearance, and the height it leaves
    /// behind is always an exact multiple of the line height (so a line box can
    /// never straddle the bottom edge).
    @Test(arguments: [
        // viewHeight, safeTop, lineHeight
        (956.0, 59.0, 29.7), (956.0, 59.0, 19.8), (956.0, 59.0, 56.1),
        (874.0, 47.0, 29.7), (667.0, 20.0, 22.0), (1366.0, 24.0, 39.6)
    ])
    func snappedInsetLeavesAWholeNumberOfLines(_ input: (Double, Double, Double)) {
        let (viewHeight, safeTop, lineHeight) = input
        let minimum: CGFloat = 8
        let inset = ReadiumBook.snappedBottomInset(
            viewHeight: CGFloat(viewHeight), safeTop: CGFloat(safeTop),
            lineHeight: CGFloat(lineHeight), minimum: minimum
        )

        #expect(inset >= minimum)
        // Never eats more than the minimum plus one line's worth of slack.
        #expect(inset < minimum + CGFloat(lineHeight))

        let remainingHeight = CGFloat(viewHeight) - CGFloat(safeTop) - inset
        let lines = remainingHeight / CGFloat(lineHeight)
        #expect(abs(lines - lines.rounded()) < 0.0001,
                "remaining height \(remainingHeight) is not a whole number of \(lineHeight)pt lines")
    }

    @Test func snappedInsetFallsBackToTheMinimumOnDegenerateInput() {
        // A zero/unknown line height, or a view too short to hold even one line,
        // must not divide by zero or return something nonsensical.
        #expect(ReadiumBook.snappedBottomInset(viewHeight: 956, safeTop: 59, lineHeight: 0) == 8)
        #expect(ReadiumBook.snappedBottomInset(viewHeight: 0, safeTop: 0, lineHeight: 29.7) == 8)
        // 20 - 0 - 8 = 12 pt available, less than one 29.7 pt line.
        #expect(ReadiumBook.snappedBottomInset(viewHeight: 20, safeTop: 0, lineHeight: 29.7) == 8)
        // Not degenerate: a view with room for exactly one line keeps that line
        // rather than collapsing to the bare minimum (40 - 10.3 == 29.7 == 1 line).
        #expect(ReadiumBook.snappedBottomInset(viewHeight: 40, safeTop: 0, lineHeight: 29.7) > 8)
    }

    /// C2: vertical page box uses full safe area (Readium pageMargins are
    /// horizontal-only) and snaps the real text band to whole line heights.
    @Test func pageBoxInsetsUseFullSafeAreaAndSnapTextBand() {
        let viewH: CGFloat = 956
        let safeTop: CGFloat = 59
        let safeBottom: CGFloat = 34
        let lineH: CGFloat = 29.7

        let insets = ReadiumBook.pageBoxContentInsets(
            viewHeight: viewH, safeTop: safeTop, safeBottom: safeBottom,
            lineHeight: lineH
        )

        // First ink at content inset = full island clearance (not safe − margin).
        #expect(insets.top == safeTop)
        #expect(insets.bottom >= safeBottom)

        let textBand = viewH - insets.top - insets.bottom
        let lines = textBand / lineH
        #expect(abs(lines - lines.rounded()) < 0.0001,
                "text band \(textBand) is not a whole number of \(lineH)pt lines")
        #expect(insets.bottom < safeBottom + lineH)

        // Larger text size → different remainder (snap follows line height).
        let largeType = ReadiumBook.pageBoxContentInsets(
            viewHeight: viewH, safeTop: safeTop, safeBottom: safeBottom,
            lineHeight: 56.1
        )
        #expect(largeType.top == safeTop)
        let largeBand = viewH - largeType.top - largeType.bottom
        #expect(abs(largeBand / 56.1 - (largeBand / 56.1).rounded()) < 0.0001)
    }

    @Test func pageBoxInsetsMatchLegacySnapShape() {
        let viewH: CGFloat = 874
        let safeTop: CGFloat = 47
        let safeBottom: CGFloat = 34
        let lineH: CGFloat = 22
        let box = ReadiumBook.pageBoxContentInsets(
            viewHeight: viewH, safeTop: safeTop, safeBottom: safeBottom,
            lineHeight: lineH
        )
        #expect(box.top == safeTop)
        let legacy = ReadiumBook.snappedBottomInset(
            viewHeight: viewH, safeTop: safeTop, lineHeight: lineH,
            minimum: max(8, safeBottom)
        )
        #expect(box.bottom == legacy)
    }
    #endif

    @Test func chapterSectionMissingItsIndexFallsBackToOne() {
        // `.chapter` always carries a storyChapterIndex from the builder; the
        // fallback exists so a malformed section can't crash the card.
        #expect(
            ReaderPositionSummary.Place(section: section(.chapter), storyChapterTotal: 10)
                == .chapter(index: 1, total: 10)
        )
    }
}
