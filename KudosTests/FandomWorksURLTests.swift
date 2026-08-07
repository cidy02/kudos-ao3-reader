import Foundation
import Testing
@testable import Kudos

/// Pins Browse's endpoint. Browse asks AO3 for a tag's own works list; the Search
/// tab asks `/works/search`. Both are the same `WorkSearchForm` server-side, which
/// is why one query-item builder serves both — every parameter below was verified
/// live on `/tags/Naruto (Anime *a* Manga)/works` on 2026-08-06 and measurably
/// changed the result count there.
struct FandomWorksURLTests {
    private func url(_ fandom: String, _ filters: AO3SearchFilters = AO3SearchFilters(), page: Int = 1) throws -> URL {
        try #require(AO3Client.fandomWorksURL(fandom: fandom, filters: filters, page: page))
    }

    private func params(_ url: URL) throws -> [String: [String]] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return (components.queryItems ?? []).reduce(into: [:]) { result, item in
            result[item.name, default: []].append(item.value ?? "")
        }
    }

    @Test func aFandomBecomesAO3sOwnTagPath() throws {
        // `&` is written `*a*` in an AO3 tag path, not percent-encoded — this is
        // AO3's own convention and the reason a naive URL builder 404s here.
        let url = try url("Naruto (Anime & Manga)")
        #expect(url.absoluteString.hasPrefix("https://archiveofourown.org/tags/Naruto%20(Anime%20*a*%20Manga)/works?"))
    }

    @Test func everyCharacterAO3EscapesIsEscaped() throws {
        #expect(AO3Client.tagPathSegment("a/b") == "a*s*b")
        #expect(AO3Client.tagPathSegment("a&b") == "a*a*b")
        #expect(AO3Client.tagPathSegment("a.b") == "a*d*b")
        #expect(AO3Client.tagPathSegment("a?b") == "a*q*b")
        #expect(AO3Client.tagPathSegment("a#b") == "a*h*b")
        // Spaces still percent-encode; only those five take the `*x*` form.
        #expect(AO3Client.tagPathSegment("a b") == "a%20b")
    }

    @Test func browseSendsTheSameFiltersAsSearch() throws {
        // The tag page's visible sidebar offers fewer fields than this, but the
        // endpoint honours all of them — the whole reason Browse can move here
        // without losing a single filter the panel offers.
        var filters = AO3SearchFilters()
        filters.title = "Chunin Exams"
        filters.creators = "someauthor"
        filters.characters = "Sasuke Uchiha"
        filters.rating = .teen
        filters.includeNotRated = false
        filters.chapterCount = .singleChapter
        filters.updated = .week
        filters.hitsFrom = "1000"
        filters.wordsFrom = "1000"
        filters.wordsTo = "5000"
        filters.excludedAdditionalTags = "Time Travel"
        filters.sort = .kudos

        let values = try params(try url("Naruto (Anime & Manga)", filters))
        #expect(values["work_search[title]"] == ["Chunin Exams"])
        #expect(values["work_search[creators]"] == ["someauthor"])
        #expect(values["work_search[character_names]"] == ["Sasuke Uchiha"])
        #expect(values["work_search[rating_ids]"] == ["11"])
        #expect(values["work_search[single_chapter]"] == ["1"])
        #expect(values["work_search[revised_at]"] == ["< 1 week ago"])
        #expect(values["work_search[hits]"] == ["> 1000"])
        #expect(values["work_search[word_count]"] == ["1000-5000"])
        #expect(values["work_search[excluded_tag_names]"] == ["Time Travel"])
        #expect(values["work_search[sort_column]"] == ["kudos_count"])
    }

    @Test func browseAndSearchEmitIdenticalFilterParameters() throws {
        // One builder, two paths. If these ever diverge, the two screens silently
        // answer different questions about the same fandom.
        var filters = AO3SearchFilters()
        filters.query = "found family"
        filters.rating = .explicit
        filters.warnings = [.violence]
        filters.excludedFandoms = "Bleach"
        filters.sort = .kudos

        let browse = try params(try url("Naruto (Anime & Manga)", filters, page: 3))
        let search = try params(try #require(AO3Client.searchURL(filters: filters, page: 3)))
        #expect(browse == search)
    }

    @Test func theFandomStaysInTheQueryAsWellAsThePath() throws {
        // Redundant but never wrong: the path already scopes to this tag, so
        // `fandom_names` re-selects the same works (measured — the count is
        // unchanged). Stripping it would *widen* results if the field ever held
        // more than the fandom the screen was opened for.
        var filters = AO3SearchFilters()
        filters.fandom = "Naruto (Anime & Manga)"
        let values = try params(try url("Naruto (Anime & Manga)", filters))
        #expect(values["work_search[fandom_names]"] == ["Naruto (Anime & Manga)"])
    }

    @Test func pagingIsSentTheSameWayItIsForSearch() throws {
        #expect(try params(try url("Naruto", page: 1))["page"] == ["1"])
        #expect(try params(try url("Naruto", page: 7))["page"] == ["7"])
    }

    @Test func browseNeverSendsViewAdult() throws {
        // Same reasoning as search: it is a work-page parameter, listing pages have
        // no interstitial, and it changes no results.
        var filters = AO3SearchFilters()
        filters.rating = .explicit
        #expect(try params(try url("Naruto", filters))["view_adult"] == nil)
    }
}
