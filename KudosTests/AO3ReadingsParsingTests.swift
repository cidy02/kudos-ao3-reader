import Foundation
import Testing
@testable import Kudos

/// 1t's per-row reading metadata, pinned to otwarchive's
/// `readings/_reading_blurb`. The fixture mirrors that partial: a work module
/// followed by the `div.user.module` that only this page has.
struct AO3ReadingsParsingTests {
    private func fixture(_ name: String) throws -> String {
        let url = try #require(Bundle(for: ReadingsBundleAnchor.self)
            .url(forResource: name, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func readsEveryRowInPageOrder() throws {
        let entries = try AO3Client.parseReadingEntries(from: fixture("ao3_readings"))
        #expect(entries.count == 4)
        #expect(entries.map(\.workID) == [11, 22, 33, nil])
    }

    /// The figure that made 1t look unbuildable. AO3 writes "Visited once" for
    /// one and "Visited N times" otherwise.
    @Test func readsVisitCounts() throws {
        let entries = try AO3Client.parseReadingEntries(from: fixture("ao3_readings"))
        #expect(entries.map(\.visitCount) == [7, 2, 1, nil])
    }

    /// 1t draws "Visited twice", which AO3 itself never writes — it says
    /// "Visited 2 times". The tree is what the screen follows.
    @Test func visitCountReadsTheWayTheBoardDraws() throws {
        let entries = try AO3Client.parseReadingEntries(from: fixture("ao3_readings"))
        #expect(entries[0].visitCountDisplay == "Visited 7 times")
        #expect(entries[1].visitCountDisplay == "Visited twice")
        #expect(entries[2].visitCountDisplay == "Visited once")
        #expect(entries[3].visitCountDisplay == nil)
    }

    @Test func readsTheVersionNote() throws {
        let entries = try AO3Client.parseReadingEntries(from: fixture("ao3_readings"))
        #expect(entries.map(\.versionStatus) == [
            .updateAvailable, .minorEdits, .latestVersion, .unknown
        ])
        #expect(entries[0].versionDisplay == "Update available")
        // A row that says none of the three must not be guessed into one.
        #expect(entries[3].versionDisplay == nil)
    }

    /// `set_format_for_date` gives a duration within 30 days and an rfc822 date
    /// beyond it. "2 days" needs "ago"; "04 Mar 2024" must not get it.
    @Test func lastVisitedKeepsAO3sOwnWordingAndOnlyAgoesADuration() throws {
        let entries = try AO3Client.parseReadingEntries(from: fixture("ao3_readings"))
        #expect(entries[0].lastVisited == "2 days")
        #expect(entries[0].lastVisitedDisplay == "Last visited 2 days ago")

        #expect(entries[1].lastVisited == "04 Mar 2024")
        #expect(entries[1].lastVisitedIsRelative == false)
        #expect(entries[1].lastVisitedDisplay == "Last visited 04 Mar 2024")

        #expect(entries[2].lastVisited == "about 1 month")
        #expect(entries[2].lastVisitedDisplay == "Last visited about 1 month ago")
    }

    @Test func readsMarkedForLaterAndFlaggedToSkip() throws {
        let entries = try AO3Client.parseReadingEntries(from: fixture("ao3_readings"))
        #expect(entries.map(\.isMarkedForLater) == [false, true, false, false])
        #expect(entries.map(\.isFlaggedToSkip) == [false, false, true, false])
    }

    /// AO3 keeps the reading after the work is gone: no id, no work module,
    /// only "(Deleted work, last visited …)".
    @Test func readsADeletedWorkRow() throws {
        let entries = try AO3Client.parseReadingEntries(from: fixture("ao3_readings"))
        let deleted = entries[3]
        #expect(deleted.isDeletedWork)
        #expect(deleted.workID == nil)
        #expect(deleted.lastVisited == "12 Jan 2023")
        #expect(entries.prefix(3).allSatisfy { !$0.isDeletedWork })
    }

    @Test func aPageWithNoReadingsIsEmptyNotAFailure() throws {
        #expect(try AO3Client.parseReadingEntries(from: "<html><body></body></html>").isEmpty)
    }
}

private final class ReadingsBundleAnchor {}
