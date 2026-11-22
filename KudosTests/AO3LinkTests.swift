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
        ("https://archiveofourown.org/tags/Fluff", .tag("Fluff")),
        ("https://archiveofourown.org/tags/Kara%20Danvers*s*Lena%20Luthor/works",
         .tag("Kara Danvers/Lena Luthor")),
        ("https://archiveofourown.org/tags/Literal%2520Name", .tag("Literal%20Name")),
        ("https://archiveofourown.org/tags/A%2FB", .tag("A/B")),
        ("https://archiveofourown.org/users/Literal%2520Name", .user(username: "Literal%20Name", pseud: nil)),
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
        "file://archiveofourown.org/works/123",
        "https://archiveofourown.org:8443/works/123"
    ])
    func rejectsOtherOrigins(urlString: String) {
        #expect(AO3Link(URL(string: urlString)!).kind == .notAO3)
    }

    @Test(arguments: [
        "https://archiveofourown.org/works/nope",
        "https://archiveofourown.org/works/0",
        "https://archiveofourown.org/works/+123",
        "https://archiveofourown.org/users/login",
        "https://archiveofourown.org/users/logout",
        "https://archiveofourown.org/users/new",
        "https://archiveofourown.org/users/password",
        "https://archiveofourown.org/series/77/extra",
        "https://archiveofourown.org/tags/Fluff/bookmarks",
        "https://archiveofourown.org/chapters/456"
    ])
    func unsupportedPathsStayOnAO3(urlString: String) {
        #expect(AO3Link(URL(string: urlString)!).kind == .otherAO3)
    }

    @Test func relativeSeriesURLKeepsItsID() {
        #expect(ReadingQueueService.ao3SeriesID(from: "/series/77") == 77)
        #expect(ReadingQueueService.ao3SeriesID(from: "https://archiveofourown.org/series/77") == 77)
        #expect(ReadingQueueService.ao3SeriesID(from: "https://example.org/series/77") == nil)
    }

    @Test func linkedChapterMapsThroughStoryPositionNotRawSpine() {
        let chapters = [
            AO3ChapterRef(id: 456, position: 1, title: "First"),
            AO3ChapterRef(id: 789, position: 2, title: "Second")
        ]
        let sections = [
            ReaderSection(href: "preface", title: "Preface", kind: .preface,
                          spineIndex: 0, storyChapterIndex: nil),
            ReaderSection(href: "ch1", title: "First", kind: .chapter,
                          spineIndex: 1, storyChapterIndex: 1),
            ReaderSection(href: "ch2", title: "Second", kind: .chapter,
                          spineIndex: 2, storyChapterIndex: 2)
        ]
        #expect(LinkedChapterTarget.spineIndex(chapterID: 789, chapters: chapters, sections: sections) == 2)
        #expect(LinkedChapterTarget.spineIndex(chapterID: 999, chapters: chapters, sections: sections) == nil)
    }

    @Test func landingWaitsForRestoreAndOnlyLoginFailuresPrompt() {
        #expect(!LinkedWorkLandingView.canFetchRemote(status: .restoring))
        #expect(LinkedWorkLandingView.canFetchRemote(status: .signedOut))
        #expect(LinkedWorkLandingView.requiresLogin(.authenticationRequired, isLoggedIn: true))
        #expect(LinkedWorkLandingView.requiresLogin(.parse, isLoggedIn: false))
        #expect(!LinkedWorkLandingView.requiresLogin(.notFound, isLoggedIn: false))
        #expect(!LinkedWorkLandingView.requiresLogin(.parse, isLoggedIn: true))
    }
}
