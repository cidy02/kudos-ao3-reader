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
}
