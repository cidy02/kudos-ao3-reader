import Foundation
import Testing
@testable import Kudos

/// URL fixtures follow otwcode/otwarchive config/routes.rb (master, read 2026-11-16).
struct AO3LinkTests {
    @Test(arguments: [
        ("https://archiveofourown.org/works/123", AO3Link.Kind.work(id: 123, chapterID: nil)),
        ("https://archiveofourown.org/works/123/chapters/456", .work(id: 123, chapterID: 456)),
        ("https://archiveofourown.org/collections/Summer/works/123", .work(id: 123, chapterID: nil)),
        ("https://archiveofourown.org/series/77", .series(77)),
        ("https://archiveofourown.org/users/Avery", .user(username: "Avery", pseud: nil)),
        ("https://archiveofourown.org/users/Avery/pseuds/Avery%20Writes",
         .user(username: "Avery", pseud: "Avery Writes")),
        ("https://archiveofourown.org/tags/Fluff/works", .tag("Fluff")),
        ("https://archiveofourown.org/works/search?work_search%5Bquery%5D=Fluff", .search),
        ("https://archiveofourown.org/collections/Summer", .collection("Summer")),
        ("https://archiveofourown.org/works/123/bookmarks", .otherAO3),
        ("http://ao3.org/works/123", .work(id: 123, chapterID: nil)),
        ("https://www.archiveofourown.org/works/123", .work(id: 123, chapterID: nil))
    ])
    func recognizedRoutes(urlString: String, expected: AO3Link.Kind) {
        #expect(AO3Link(URL(string: urlString)!).kind == expected)
    }

    @Test(arguments: [
        "https://archiveofourown.org.evil.example/works/123",
        "https://fakearchiveofourown.org/works/123",
        "https://ao3.org.evil.example/works/123",
        "https://example.org/works/123",
        "javascript://archiveofourown.org/works/123",
        "file://archiveofourown.org/works/123"
    ])
    func rejectsOtherOrigins(urlString: String) {
        #expect(AO3Link(URL(string: urlString)!).kind == .notAO3)
    }

    @Test(arguments: [
        "https://archiveofourown.org/works/nope",
        "https://archiveofourown.org/works/0",
        "https://archiveofourown.org/series/77/extra",
        "https://archiveofourown.org/tags/Fluff"
    ])
    func unsupportedPathsStayOnAO3(urlString: String) {
        #expect(AO3Link(URL(string: urlString)!).kind == .otherAO3)
    }
}
