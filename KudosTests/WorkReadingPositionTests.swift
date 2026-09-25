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

    /// Cards print Readium's percent or nothing — never "Ch N" from a spine index.
    @Test func cardProgressLabelIsReadiumPercentOrNothing() {
        #expect(WorkReadingPosition.cardProgressLabel(readiumProgress: nil) == nil)
        #expect(WorkReadingPosition.cardProgressLabel(readiumProgress: 0.42) == "42%")
        #expect(WorkReadingPosition.cardProgressLabel(readiumProgress: 0) == "0%")
    }
}
