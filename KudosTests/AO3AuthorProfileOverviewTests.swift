import Foundation
import Testing
@testable import Kudos

struct AuthorProfileSeeAllTests {
    @Test func seeAllOnlyWhenSomethingIsHidden() {
        #expect(AuthorProfileSeeAll.isShown(visibleCount: 3, totalCount: 42, hasMore: false))
        #expect(AuthorProfileSeeAll.isShown(visibleCount: 3, totalCount: 3, hasMore: true))
        #expect(AuthorProfileSeeAll.isShown(visibleCount: 2, totalCount: nil, hasMore: true))
        #expect(!AuthorProfileSeeAll.isShown(visibleCount: 3, totalCount: 3, hasMore: false))
        #expect(!AuthorProfileSeeAll.isShown(visibleCount: 2, totalCount: 2, hasMore: false))
        #expect(!AuthorProfileSeeAll.isShown(visibleCount: 0, totalCount: 0, hasMore: false))
        #expect(!AuthorProfileSeeAll.isShown(visibleCount: 2, totalCount: nil, hasMore: false))
        #expect(!AuthorProfileSeeAll.isShown(visibleCount: 3, totalCount: 1, hasMore: false))
    }
}

@MainActor
struct AO3AuthorProfileOverviewTests {
    final class BundleAnchor {}

    private func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html")
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesGiftsIndexAndRecognizesEmptyGiftsList() throws {
        let page = try AO3Client.parseAuthorWorksPage(fixture("ao3_author_gifts"), page: 1)
        #expect(page.works.count == 1)
        #expect(page.works.first?.id == 1001)
        #expect(page.works.first?.title == "Two Voices at Dawn")
        #expect(page.totalPages == 2)
        #expect(page.works.first?.giftRecipients == ["Avery_Archive"])

        let empty = try AO3Client.parseAuthorWorksPage(
            "<html><body><ul class='gift work index group'></ul></body></html>",
            page: 1
        )
        #expect(empty.works.isEmpty)
    }

    @Test func dashboardSidebarCountsMatchExactListPaths() throws {
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let html = try fixture("ao3_author_dashboard").replacingOccurrences(
            of: "<div id=\"dashboard\">",
            with: """
            <div id="dashboard"><ul class="navigation actions">\
            <li><a href="/users/Avery_Archive/works">Works (42)</a></li>\
            <li><a href="/users/Avery_Archive/works/collected">Works in Collections (3)</a></li>\
            <li><a href="/users/Avery_Archive/series">Series (6)</a></li>\
            <li><a href="/users/Avery_Archive/bookmarks">Bookmarks (128)</a></li>\
            <li><a href="/users/Avery_Archive/gifts">Gifts (9)</a></li>\
            </ul>
            """
        )
        let header = try AO3Client.parseAuthorDashboard(html, route: route)
        #expect(header.listCount(for: .works, route: route) == 42)
        #expect(header.listCount(for: .collectedWorks, route: route) == 3)
        #expect(header.listCount(for: .series, route: route) == 6)
        #expect(header.listCount(for: .bookmarks, route: route) == 128)
        #expect(header.listCount(for: .gifts, route: route) == 9)
        #expect(header.actions.contains { $0.kind == .gifts })
    }

    @Test func aboutIgnoresLocationMetadata() throws {
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let html = try fixture("ao3_author_profile").replacingOccurrences(
            of: "<dt>Joined</dt>",
            with: "<dt>Location</dt><dd>London</dd><dt>Joined</dt>"
        )
        let about = try AO3Client.parseAuthorAbout(html, route: route)
        #expect(about.joinedDate == "12 March 2014")
        #expect(!about.bio.plainText.contains("London"))
    }

    @Test func overviewActivateLoadsDashboardAndAboutOnly() async throws {
        let dashboard = try fixture("ao3_author_dashboard")
        let works = try fixture("ao3_author_works")
        let about = try fixture("ao3_author_profile")
        var requests: [URL] = []
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let model = AO3AuthorProfileModel(route: route, overviewMode: true) { url, _, _ in
            requests.append(url)
            if url.path.hasSuffix("/profile") {
                return .init(html: about, isStale: false)
            }
            if url.path.hasSuffix("/works") {
                return .init(html: works, isStale: false)
            }
            return .init(html: dashboard, isStale: false)
        }
        let auth = AO3AuthService()
        model.activate(auth: auth)
        await model.waitForActiveLoad()
        #expect(requests.map(\.path) == [
            "/users/Avery_Archive",
            "/users/Avery_Archive/profile"
        ])
        #expect(model.about?.joinedDate == "12 March 2014")
        #expect(model.works.isEmpty)
        #expect(model.popularWorks.isEmpty)
        #expect(model.series.isEmpty)
        #expect(model.bookmarks.isEmpty)
    }

    @Test func overviewPopularSectionFetchesKudosSortWithoutClobberingWorks() async throws {
        let dashboard = try fixture("ao3_author_dashboard")
        let works = try fixture("ao3_author_works")
        let about = try fixture("ao3_author_profile")
        var requests: [URL] = []
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let model = AO3AuthorProfileModel(route: route, overviewMode: true) { url, _, _ in
            requests.append(url)
            if url.path.hasSuffix("/profile") {
                return .init(html: about, isStale: false)
            }
            if url.path.hasSuffix("/works") {
                return .init(html: works, isStale: false)
            }
            return .init(html: dashboard, isStale: false)
        }
        let auth = AO3AuthService()
        model.activate(auth: auth)
        await model.waitForActiveLoad()
        model.ensureSectionVisible(.popular, auth: auth)
        await model.waitForActiveLoad()
        let popular = try #require(requests.last)
        #expect(popular.path == "/users/Avery_Archive/works")
        let items = URLComponents(url: popular, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains { $0.name == "work_search[sort_column]" && $0.value == "kudos_count" })
        #expect(model.popularWorks.count == 3)
        #expect(model.works.isEmpty)
        #expect(model.popularPhase == .loaded)
    }

    @Test func overviewCancelDropsInFlightSectionLoad() async throws {
        let dashboard = try fixture("ao3_author_dashboard")
        let works = try fixture("ao3_author_works")
        let about = try fixture("ao3_author_profile")
        var popularStarted = false
        var popularCancelled = false
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let model = AO3AuthorProfileModel(route: route, overviewMode: true) { url, _, _ in
            if url.path.hasSuffix("/works") {
                popularStarted = true
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    popularCancelled = true
                    throw error
                }
                return .init(html: works, isStale: false)
            }
            if url.path.hasSuffix("/profile") {
                return .init(html: about, isStale: false)
            }
            return .init(html: dashboard, isStale: false)
        }
        let auth = AO3AuthService()
        model.activate(auth: auth)
        await model.waitForActiveLoad()
        model.ensureSectionVisible(.popular, auth: auth)
        while !popularStarted { await Task.yield() }
        model.cancel()
        for _ in 0..<200 where !popularCancelled { await Task.yield() }
        #expect(popularCancelled)
        #expect(model.popularWorks.isEmpty)
        #expect(model.popularPhase == .idle)
    }
}
