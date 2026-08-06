import Foundation
import Testing
@testable import Kudos

/// Pins AO3's tag-autocomplete contract, which is what keeps the tag names this
/// app sends in AO3's own casing.
///
/// That is not cosmetic. otwarchive looks a tag name up in the DB
/// case-insensitively but computes its "missing" set with a case-*sensitive* Ruby
/// array difference (`taggable_query.rb`), so a wrongly-cased name is treated as
/// both found *and* missing and picks up two filters instead of one — measured on
/// a 92,495-work corpus, `Time Travel` excludes to 89,855 while `time travel`
/// excludes to 89,741. The app never hits that path because every tag in the filter
/// panel comes from these endpoints (`TagSelectField` has no free-text entry), so
/// these constants are load-bearing: a wrong path segment 404s into an empty
/// suggestion list, which looks like "AO3 has no such tag" rather than a failure.
///
/// Every endpoint below was verified live against archiveofourown.org on
/// 2026-08-06.
struct TagAutocompleteTests {
    private func query(_ url: URL) throws -> [String: String] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return (components.queryItems ?? []).reduce(into: [:]) { $0[$1.name] = $1.value }
    }

    @Test func everyTagKindHitsItsOwnLiveAO3Endpoint() throws {
        let expected: [(AO3TagKind, String)] = [
            (.fandom, "/autocomplete/fandom"),
            (.character, "/autocomplete/character"),
            (.relationship, "/autocomplete/relationship"),
            (.freeform, "/autocomplete/freeform"),
            (.tag, "/autocomplete/tag")
        ]
        for (kind, path) in expected {
            let url = try #require(AO3Client.autocompleteURL(kind: kind, term: "time"))
            #expect(url.path == path)
            #expect(url.host == "archiveofourown.org")
            #expect(url.scheme == "https")
        }
    }

    @Test func theSearchTermUsesAO3sOwnParameterName() throws {
        let url = try #require(AO3Client.autocompleteURL(kind: .freeform, term: "time travel"))
        // `term`, not `q`/`query`: AO3 ignores an unknown parameter and answers with
        // an unfiltered list, so this typo would not error, it would just suggest
        // the wrong tags.
        #expect(try query(url) == ["term": "time travel"])
    }

    @Test func aBlankTermMakesNoRequest() {
        // nil rather than a URL: the picker calls this on every keystroke, and a
        // request per empty field would spend paced AO3 slots for nothing.
        #expect(AO3Client.autocompleteURL(kind: .fandom, term: "") == nil)
        #expect(AO3Client.autocompleteURL(kind: .fandom, term: "   ") == nil)
        #expect(AO3Client.autocompleteURL(kind: .fandom, term: "\n\t") == nil)
    }

    @Test func surroundingWhitespaceIsTrimmedRatherThanSent() throws {
        let url = try #require(AO3Client.autocompleteURL(kind: .character, term: "  naruto  "))
        #expect(try query(url) == ["term": "naruto"])
    }

    @Test func autocompleteResponsesYieldAO3sCanonicalTagNames() throws {
        // A real response body, copied verbatim from
        // /autocomplete/fandom?term=time on 2026-08-06.
        let body = Data("""
        [{"id":"Once Upon a Time (TV)","name":"Once Upon a Time (TV)"},
         {"id":"Wheel of Time - Robert Jordan","name":"Wheel of Time - Robert Jordan"}]
        """.utf8)
        #expect(try AO3Client.parseAutocomplete(body) == [
            "Once Upon a Time (TV)", "Wheel of Time - Robert Jordan"
        ])
    }

    @Test func theNameFieldIsTakenNotTheID() throws {
        // AO3 sends the same string in both fields today. If that ever diverges,
        // `name` is the label a user picked and the one the search must send back —
        // this pins which field we read rather than relying on them matching.
        let body = Data(#"[{"id":"12345","name":"Time Travel"}]"#.utf8)
        #expect(try AO3Client.parseAutocomplete(body) == ["Time Travel"])
    }

    @Test func anEmptyAutocompleteResponseIsNotAnError() throws {
        // AO3 answers an unmatched term with `[]`. The picker shows "No tags found",
        // which is a different state from a failed request.
        #expect(try AO3Client.parseAutocomplete(Data("[]".utf8)).isEmpty)
    }

    @Test func aMalformedAutocompleteResponseThrows() {
        // Maintenance pages and Cloudflare interstitials are HTML, not JSON. This
        // must surface as an error the picker can show, never as "no tags found".
        #expect(throws: (any Error).self) {
            try AO3Client.parseAutocomplete(Data("<html>maintenance</html>".utf8))
        }
    }

    @Test func tagNamesNeedingEscapingSurviveTheRoundTrip() throws {
        // Real AO3 tags carry slashes, ampersands and quotes ("Rape/Non-Con",
        // "Steve Rogers & Tony Stark"). URLComponents must percent-encode them into
        // the query rather than letting them split it.
        let url = try #require(AO3Client.autocompleteURL(kind: .relationship, term: "Steve & Tony/Bucky"))
        #expect(try query(url) == ["term": "Steve & Tony/Bucky"])
    }
}
