import Foundation
import SwiftSoup
import Testing
@testable import Kudos

@MainActor
struct AO3DashboardTests {
    final class BundleAnchor {}

    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle(for: BundleAnchor.self).url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// otwarchive users/_contents.html.erb wraps its ordinary blurbs in these
    /// three IDs. Reuse the existing blurb fixtures to check cross-group leakage.
    private func dashboardWithRecentGroups() throws -> String {
        var html = try fixture("ao3_author_dashboard")
        for (id, name, selector) in [
            ("user-works", "ao3_author_works", "li.work.blurb"),
            ("user-series", "ao3_author_series", "li.series.blurb"),
            ("user-bookmarks", "ao3_author_bookmarks", "li.bookmark.blurb")
        ] {
            let blurbs = try SwiftSoup.parse(fixture(name)).select(selector).array()
                .map { try $0.outerHtml() }.joined()
            html = html.replacingOccurrences(of: "</body>", with: "<div id='\(id)'>\(blurbs)</div></body>")
        }
        return html
    }

    @Test func dashboardSeparatesAllThreeRecentGroupsFromOnePage() throws {
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let header = try AO3Client.parseAuthorDashboard(dashboardWithRecentGroups(), route: route)
        let works = try AO3Client.parseAuthorWorksPage(fixture("ao3_author_works"), page: 1).works
        let series = try AO3Client.parseAuthorSeriesPage(fixture("ao3_author_series"), page: 1).series
        let bookmarks = try AO3Client.parseAuthorBookmarksPage(fixture("ao3_author_bookmarks"), page: 1).bookmarks
        #expect(header.recentWorks == works)
        #expect(header.recentSeries == series)
        #expect(header.recentBookmarks == bookmarks)
        #expect(header.recentWorks?.contains { $0.id == bookmarks.first?.work.id } == false)
    }

    @Test func missingGroupsAreEmptyButMalformedGroupDoesNotEraseItsSiblings() throws {
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let empty = try AO3Client.parseAuthorDashboard(fixture("ao3_author_dashboard"), route: route)
        #expect(empty.recentWorks == [])
        #expect(empty.recentSeries == [])
        #expect(empty.recentBookmarks == [])

        let html = try dashboardWithRecentGroups().replacingOccurrences(
            of: "<div id='user-series'>",
            with: "<div id='user-series'><li class='series blurb'>Unrecognized series</li>"
        )
        let partial = try AO3Client.parseAuthorDashboard(html, route: route)
        #expect(partial.recentSeries == nil)
        #expect(partial.recentWorks?.isEmpty == false)
        #expect(partial.recentBookmarks?.isEmpty == false)
    }

    @Test func dashboardNeverLoadsTheFullListsOrAboutAndScopeSwitchReloadsOnlyDashboard() async throws {
        let html = try dashboardWithRecentGroups()
        let route = try #require(AO3AuthorRoute(username: "Avery_Archive"))
        let pseud = try #require(AO3AuthorRoute(username: route.username, pseud: "NightShift"))
        var requests: [URL] = []
        let model = AO3AuthorProfileModel(route: route, dashboardOnly: true) { url, _, _ in
            requests.append(url)
            return .init(html: html, isStale: false)
        }
        let auth = AO3AuthService()
        model.activate(auth: auth)
        await model.waitForActiveLoad()
        model.activate(auth: auth)
        await model.waitForActiveLoad()
        #expect(requests == [route.dashboardURL])
        #expect(model.header?.recentWorks?.isEmpty == false)
        #expect(model.works.isEmpty)
        #expect(model.series.isEmpty)
        #expect(model.bookmarks.isEmpty)
        #expect(model.about == nil)

        model.selectScope(pseud, auth: auth)
        await model.waitForActiveLoad()
        #expect(requests == [route.dashboardURL, pseud.dashboardURL])
        #expect(model.header?.identity.route == pseud)
    }

    @Test func performancePreservesPrintedZeroAndOmitsUnavailableCounts() throws {
        var work = try #require(AO3Client.parseAuthorWorksPage(fixture("ao3_author_works"), page: 1).works.first)
        work.kudos = 0
        work.comments = nil
        work.hits = 27
        work.bookmarks = nil
        let cells = AO3AuthorPerformanceStrip.cells(for: work)
        #expect(cells.map(\.label) == ["Kudos", "Hits"])
        #expect(cells.map(\.value) == ["0", "27"])
        let metadata = AO3WorkRow.ledgerMetadata(for: work, showsZeroStats: true, includesPerformance: false)
        #expect(!metadata.contains { $0.contains("kudos") || $0.contains("hit") || $0.contains("comment") })
    }
}
