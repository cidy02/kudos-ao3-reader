import Foundation
import Testing
@testable import Kudos

/// Editor autocomplete wraps the existing search endpoints. Suggestions are
/// not a whitelist — a free-typed name still posts.
struct AO3TagAutocompleteTests {
    @Test func suggestionsAreCanonicalWhenJSONHasOnlyNames() throws {
        let body = Data("""
        [{"id":"Hurt/Comfort","name":"Hurt/Comfort"},
         {"id":"Time Travel","name":"Time Travel"}]
        """.utf8)
        let tags = try AO3TagAutocomplete.parseEditorAutocomplete(body)
        #expect(tags.map(\.name) == ["Hurt/Comfort", "Time Travel"])
        #expect(tags.allSatisfy { $0.isCanonical })
        #expect(tags.allSatisfy { $0.workCount == nil })
    }

    @Test func canonicalAndCountAreParsedWhenPresent() throws {
        let body = Data("""
        [{"id":"Hurt/Comfort","name":"Hurt/Comfort","canonical":true,"work_count":9001},
         {"id":"not a tag","name":"not a tag","canonical":false}]
        """.utf8)
        let tags = try AO3TagAutocomplete.parseEditorAutocomplete(body)
        #expect(tags[0].isCanonical)
        #expect(tags[0].workCount == 9001)
        #expect(!tags[1].isCanonical)
    }

    @Test func wrapperDoesNotWhitelistFreeTypedTags() {
        let suggestions = AO3TagAutocomplete.editorTags(
            fromCanonicalNames: ["Hurt/Comfort", "Time Travel"]
        )
        let canonical = AO3TagAutocomplete.accept(
            name: "hurt/comfort", suggestions: suggestions
        )
        #expect(canonical.name == "Hurt/Comfort")
        #expect(canonical.isCanonical)

        let free = AO3TagAutocomplete.accept(
            name: "My Original Tag", suggestions: suggestions
        )
        #expect(free.name == "My Original Tag")
        #expect(!free.isCanonical)
        #expect(free.workCount == nil)
    }

    @Test func blankTermMakesNoSuggestList() async throws {
        let tags = try await AO3TagAutocomplete.suggest(
            kind: .freeform, term: "   ", debounceNanoseconds: 0
        )
        #expect(tags.isEmpty)
    }

    @Test func usesTheExistingAutocompleteURLBuilder() throws {
        let url = try #require(AO3Client.autocompleteURL(kind: .fandom, term: "time"))
        #expect(url.path == "/autocomplete/fandom")
        #expect(url.host == "archiveofourown.org")
    }

    @Test func debounceConstantMatchesSearchPicker() {
        #expect(AO3TagAutocomplete.debounceMilliseconds == 300)
    }
}
