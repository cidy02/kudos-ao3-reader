import Foundation
import SwiftData
import Testing
@testable import Kudos

struct FollowedTagFeedParserTests {
    private func fixtureData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ao3_tag_feed.atom")
        return try Data(contentsOf: url)
    }

    @Test func parsesAtomFixtureEntriesIDsAndSummaryMetadata() throws {
        let feed = try AO3Client.parseTagFeed(try fixtureData())
        #expect(feed.feedID == "tag:archiveofourown.org,2005:/tags/27785/feed")
        #expect(feed.title == "AO3 works tagged 'Doctor Who (2005)'")
        #expect(feed.updatedAt != nil)
        #expect(feed.entries.count == 2)

        let first = feed.entries[0]
        #expect(first.id == "tag:archiveofourown.org,2005:Work/9123456")
        #expect(first.workID == 9123456)
        #expect(first.title == "Tea at the End of the Universe")
        #expect(first.authors == ["riverpond"])
        #expect(first.authorIdentities.count == 1)
        #expect(first.authorIdentities[0].username == "riverpond")
        #expect(first.url?.absoluteString == "https://archiveofourown.org/works/9123456")
        #expect(first.summary == "A quiet cup of tea after everything goes sideways.")
        #expect(first.words == 2345)
        #expect(first.chapters == "1/1")
        #expect(first.isComplete)
        #expect(!first.isExplicit)
        #expect(first.language == "English")
        #expect(first.rating == "Teen And Up Audiences")
        #expect(first.warnings == ["No Archive Warnings Apply"])
        #expect(first.categories == ["Gen"])
        #expect(first.fandoms == ["Doctor Who (2005)"])
        #expect(first.characters == ["Tenth Doctor", "Donna Noble"])
        #expect(first.relationships == ["Tenth Doctor & Donna Noble"])
        #expect(first.freeforms == ["Fluff", "Tea"])

        let second = feed.entries[1]
        #expect(second.workID == 9123400)
        #expect(second.authors == ["moonbeam (starlight)", "Anonymous"])
        #expect(second.authorIdentities.count == 2)
        #expect(second.authorIdentities[0].username == "starlight")
        #expect(second.authorIdentities[1].kind == .anonymous)
        #expect(!second.isComplete)
        #expect(second.chapters == "3/?")
        #expect(second.isExplicit)
    }

    @Test func emptyValidAtomFeedReturnsZeroEntries() throws {
        let emptyXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xml:lang="en-US" xmlns="http://www.w3.org/2005/Atom">
          <id>tag:archiveofourown.org,2005:/tags/100/feed</id>
          <link rel="alternate" type="text/html" href="https://archiveofourown.org"/>
          <title>AO3 works tagged 'Empty Tag'</title>
        </feed>
        """
        let feed = try AO3Client.parseTagFeed(Data(emptyXML.utf8))
        #expect(feed.feedID == "tag:archiveofourown.org,2005:/tags/100/feed")
        #expect(feed.entries.isEmpty)
    }

    @Test func malformedFeedOrHTMLRedirectThrowsParseError() {
        let htmlRedirect = Data(
            """
            <!DOCTYPE html>
            <html><head><title>Redirected</title></head><body><h1>Works</h1></body></html>
            """.utf8
        )
        let brokenXML = Data("<feed xmlns=\"http://www.w3.org/2005/Atom\"><entry><title>Broken".utf8)
        let missingWorkID = Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
              <id>tag:archiveofourown.org,2005:/tags/1/feed</id>
              <entry>
                <id>tag:archiveofourown.org,2005:NotAWork</id>
                <published>2026-11-16T12:00:00Z</published>
                <title>Missing Link</title>
              </entry>
            </feed>
            """.utf8
        )

        #expect(throws: AO3Error.parse) { try AO3Client.parseTagFeed(Data()) }
        #expect(throws: AO3Error.parse) { try AO3Client.parseTagFeed(htmlRedirect) }
        #expect(throws: AO3Error.parse) { try AO3Client.parseTagFeed(brokenXML) }
        #expect(throws: AO3Error.parse) { try AO3Client.parseTagFeed(missingWorkID) }
    }

    @Test func feedTagIDReadsOfficialFeedControlOnly() throws {
        let fandomHTML = """
        <html>
          <head>
            <link rel="alternate" type="application/atom+xml" href="/tags/27785/feed.atom" />
          </head>
          <body><div id="main"></div></body>
        </html>
        """
        let freeformWithSpoofedSummaryLink = """
        <html>
          <head><title>Slow Burn - Works</title></head>
          <body>
            <div id="main">
              <ol class="work index group">
                <li id="work_1" class="work blurb">
                  <blockquote class="userstuff summary">
                    <a href="/tags/999999/feed.atom">spoof</a>
                  </blockquote>
                </li>
              </ol>
            </div>
          </body>
        </html>
        """
        let canonicalPage = try AO3Client.parseSearchPage(fandomHTML, page: 1)
        #expect(canonicalPage.feedTagID == 27785)
        #expect(AO3FandomUnion.feedTagID(fromTagWorksPage: freeformWithSpoofedSummaryLink) == nil)
    }

    @Test func ao3SubscriptionsScopeNeverIncludesLocalTagsTab() {
        #expect(AO3SubscriptionsScope.allCases == [.works, .series, .users])
        #expect(AO3SubscriptionsTab.allCases.contains(.tags))
    }
}
