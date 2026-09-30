import Foundation
import Testing
@testable import Kudos

/// The design-review harness must never reach AO3 (owner rule).
@Suite(.serialized) struct DemoNetworkBlockTests {
    @Test func blocksOnlyAO3AndOnlyInDemoRuns() {
        let key = "KudosDemoLibrary"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        let ao3 = URLRequest(url: URL(string: "https://archiveofourown.org/works/1")!)
        let ao3Sub = URLRequest(url: URL(string: "https://download.archiveofourown.org/x.epub")!)
        let other = URLRequest(url: URL(string: "https://example.com/")!)

        UserDefaults.standard.set(true, forKey: key)
        #expect(DemoNetworkBlock.canInit(with: ao3))
        #expect(DemoNetworkBlock.canInit(with: ao3Sub))
        #expect(!DemoNetworkBlock.canInit(with: other))

        UserDefaults.standard.set(false, forKey: key)
        #expect(!DemoNetworkBlock.canInit(with: ao3))
    }

    final class BundleAnchor {}

    /// Browse's fixtures route by path and parse with the real parsers.
    @Test func browseFixturesRouteAndParse() throws {
        func route(_ path: String) -> String? {
            DemoNetworkBlock.fixture(for: URL(string: "https://archiveofourown.org\(path)")!)
        }
        #expect(route("/media") == "ao3_media")
        #expect(route("/media/TV%20Shows/fandoms") == "ao3_media_fandoms")
        #expect(route("/tags/Doctor%20Who/works") == "ao3_tag_works")

        let url = try #require(Bundle(for: BundleAnchor.self).url(forResource: "ao3_media_fandoms", withExtension: "html"))
        let fandoms = AO3Client.parseFandomIndex(try String(contentsOf: url, encoding: .utf8))
        #expect(fandoms.count == 5)

        let tag = try #require(Bundle(for: BundleAnchor.self).url(forResource: "ao3_tag_works", withExtension: "html"))
        let page = try AO3Client.parseSearchPage(try String(contentsOf: tag, encoding: .utf8), page: 1)
        #expect(!page.works.isEmpty)
        #expect(page.summary?.total == 260_114)
    }
}
