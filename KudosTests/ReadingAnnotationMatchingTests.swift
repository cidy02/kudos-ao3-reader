import Foundation
import Testing
@testable import Kudos

@Suite("Reading annotation matching")
struct ReadingAnnotationMatchingTests {
    @Test func exactLocatorMatchIsSamePassage() {
        let loc = #"{"href":"/ch1","locations":{"position":3},"text":{"highlight":"hello"}}"#
        #expect(ReadingAnnotationMatching.isSamePassage(
            existingLocator: loc,
            selectionLocator: loc
        ))
    }

    @Test func differentLocatorIsNotSameEvenWithSameText() {
        // Same words, different locator encoding/range → two marks allowed.
        #expect(!ReadingAnnotationMatching.isSamePassage(
            existingLocator: #"{"href":"/a","locations":{"position":10}}"#,
            selectionLocator: #"{"href":"/a","locations":{"position":10},"text":{"highlight":"the lantern guttered"}}"#
        ))
    }

    @Test func emptyLocatorsDoNotMatch() {
        #expect(!ReadingAnnotationMatching.isSamePassage(
            existingLocator: "",
            selectionLocator: ""
        ))
        #expect(!ReadingAnnotationMatching.isSamePassage(
            existingLocator: "a",
            selectionLocator: ""
        ))
    }

    @Test func toggleOffRequiresIdenticalLocatorString() {
        let loc = "same-locator"
        #expect(ReadingAnnotationMatching.isSamePassage(
            existingLocator: loc,
            selectionLocator: loc
        ))
        #expect(!ReadingAnnotationMatching.isSamePassage(
            existingLocator: loc,
            selectionLocator: loc + "-other"
        ))
    }
}
