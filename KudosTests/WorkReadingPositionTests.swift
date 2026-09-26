import Testing
@testable import Kudos

@MainActor
struct WorkReadingPositionTests {
    @Test func usesPersistedPublicationLabelsIncludingFrontMatter() {
        #expect(WorkReadingPosition.title(
            from: #"{"title":"Chapter 3: Begin Again","locations":{"totalProgression":0.42}}"#
        ) == "Chapter 3: Begin Again")
        #expect(WorkReadingPosition.title(from: #"{"title":"Preface"}"#) == "Preface")
        #expect(WorkReadingPosition.title(from: #"{"title":" Afterword "}"#) == "Afterword")
    }

    @Test(arguments: ["", "not JSON", "[]", "{}", #"{"title":"  "}"#, #"{"title":3}"#])
    func missingOrInvalidLocatorLabelUsesTheFallback(locatorJSON: String) {
        #expect(WorkReadingPosition.title(from: locatorJSON) == nil)
    }

    /// Cards print the publication percent or nothing — never "Ch N" from a spine index.
    @Test func cardProgressLabelIsPublicationPercentOrNothing() {
        #expect(WorkReadingPosition.cardProgressLabel(progress: nil) == nil)
        #expect(WorkReadingPosition.cardProgressLabel(progress: 0.42) == "42%")
        #expect(WorkReadingPosition.cardProgressLabel(progress: 0) == "0%")
    }

    // MARK: publicationProgress — Readium's totalProgression, rebuilt for the Mac

    /// Positions [2, 1, 10, 10], 23 in all: a preface and a summary ahead of two chapters.
    private static let lengths: [Int?] = [2048, 1024, 10240, 10240]

    private func progress(_ spine: Int, _ fraction: Double, _ lengths: [Int?] = Self.lengths) -> Double? {
        WorkReadingPosition.publicationProgress(
            spineIndex: spine, chapterFraction: fraction, resourceLengths: lengths)
    }

    @Test func publicationProgressWeighsFrontMatterLikeReadium() {
        #expect(progress(0, 0) == 0)
        // The top of Chapter 1 is past the front matter, not 0% — and not the
        // legacy (lastSpineIndex + 1) / 2 = 100% a "2/2" work would claim.
        #expect(progress(2, 0) == 3.0 / 23)
        #expect(WorkReadingPosition.cardProgressLabel(progress: progress(2, 0)) == "13%")
        #expect(progress(2, 0.5) == 8.0 / 23)
        // The last page of a 10-page final chapter.
        #expect(progress(3, 0.9) == 22.0 / 23)
        #expect(WorkReadingPosition.cardProgressLabel(progress: progress(3, 0.9)) == "96%")
        #expect(progress(3, 1) == 1)
    }

    @Test func publicationProgressGivesEveryResourceAtLeastOnePosition() {
        // [0, 1, 1024, 1025] → positions [1, 1, 1, 2], 5 in all.
        #expect(progress(3, 0.5, [0, 1, 1024, 1025]) == 4.0 / 5)
    }

    /// nil = outside Readium's reading order (a `linear="no"` cover): no weight, and
    /// no percent while it is on screen.
    @Test func publicationProgressSkipsItemsReadiumLeavesOut() {
        #expect(progress(1, 0, [51200, 1024, 1024]) == 50.0 / 52)
        #expect(progress(1, 0, [nil, 1024, 1024]) == 0)
        #expect(progress(2, 0.5, [nil, 1024, 1024]) == 0.75)
        #expect(progress(0, 0.5, [nil, 1024, 1024]) == nil)
    }

    @Test func publicationProgressRejectsUnknownSpinesAndClampsTheFraction() {
        #expect(progress(4, 0) == nil)
        #expect(progress(-1, 0) == nil)
        #expect(progress(0, 0, []) == nil)
        #expect(progress(2, -1) == 3.0 / 23)
        #expect(progress(2, 2) == 13.0 / 23)
    }
}
