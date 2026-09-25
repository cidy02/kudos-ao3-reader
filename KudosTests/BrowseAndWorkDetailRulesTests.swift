import Foundation
import Testing
@testable import Kudos

/// Wave-3 audit, browse-workdetail-comments: Jump Back In's ranking (1g.6, 1g.7),
/// the comment budget (1ba.2), the fandom list tally (1al.3) and Work Details'
/// figures (1a.5).
@MainActor
struct BrowseAndWorkDetailRulesTests {
    // MARK: Jump Back In

    /// Ranked by when you last read, across categories — not by date added, and
    /// not in category order.
    @Test func jumpBackInIsMostRecentlyReadFirst() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 9_000)
        // Added later, read earlier, in category A.
        let addedLate = snapshot(["Fandom A"], added: late, read: early)
        // Added earlier, read later, in category B.
        let readLate = snapshot(["Fandom B"], added: early, read: late)
        // Read again: its fandom must not appear twice.
        let again = snapshot(["Fandom B"], added: early, read: early)

        let picks = MediaBrowserView.jumpBackInFandoms(
            works: [addedLate, readLate, again],
            categoryFor: { ["fandom a": "A", "fandom b": "B"][$0] },
            workCountFor: { _ in nil },
            limit: 3
        )
        #expect(picks.map(\.fandom) == ["Fandom B", "Fandom A"])
        #expect(picks.map(\.categoryID) == ["B", "A"])
    }

    @Test func jumpBackInSkipsUnreadAndUncategorisedAndStopsAtTheLimit() {
        let unread = MediaBrowserView.LibraryWorkSnapshot(
            fandomsLower: ["fandom a"], fandomsDisplay: ["Fandom A"],
            hasBeenRead: false, dateAdded: Date(timeIntervalSince1970: 5_000), lastReadDate: nil
        )
        let read = snapshot(["Unknown", "Fandom B", "Fandom C"], added: .distantPast, read: nil)
        let picks = MediaBrowserView.jumpBackInFandoms(
            works: [unread, read],
            categoryFor: { ["fandom a": "A", "fandom b": "B", "fandom c": "C"][$0] },
            workCountFor: { _ in nil },
            limit: 1
        )
        #expect(picks.map(\.fandom) == ["Fandom B"])
    }

    /// The count comes from the category's whole list, so a fandom outside the
    /// twelve cluster chips still has one (1g.7).
    @Test func jumpBackInCarriesTheWorkCount() {
        let picks = MediaBrowserView.jumpBackInFandoms(
            works: [snapshot(["Small Fandom"], added: .distantPast, read: .now)],
            categoryFor: { _ in "A" },
            workCountFor: { ["small fandom": 42][$0] },
            limit: 3
        )
        #expect(picks.first?.workCount == 42)
    }

    // MARK: Comment budget

    /// AO3 counts code points (Ruby `String#length`), not graphemes.
    @Test func commentBudgetCountsCodePoints() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" // one Character, five scalars
        #expect(family.count == 1)
        #expect(CommentComposerSheet.remainingCharacters(for: "a" + family) == 10_000 - 6)
        #expect(CommentComposerSheet.remainingCharacters(for: String(repeating: "x", count: 10_000)) == 0)
        #expect(CommentComposerSheet.remainingCharacters(for: "") == 10_000)
    }

    // MARK: Fandom list tally

    @Test func fandomListTallyNamesSizeAndOrder() {
        #expect(FandomListTally.text(
            totalTags: 9_412, families: 8_106, shownTags: 9_412, isFiltered: false, sort: .alphabetical
        ) == "\(9_412.formatted()) tags in \(8_106.formatted()) fandoms · A–Z")
        #expect(FandomListTally.text(
            totalTags: 9_412, families: 8_106, shownTags: 1_204, isFiltered: true, sort: .familyTotal
        ) == "\(1_204.formatted()) of \(9_412.formatted()) tags · most works")
    }

    // MARK: Work Details figures

    @Test func workDetailPrefersTheFresherRemoteFigure() {
        #expect(WorkDetailFigures.preferred(local: 412, remote: 500) == 500)
        #expect(WorkDetailFigures.preferred(local: 412, remote: nil) == 412)
        #expect(WorkDetailFigures.preferred(local: 0, remote: nil) == nil)
        #expect(WorkDetailFigures.preferred(local: nil, remote: nil) == nil)
        // A printed zero from AO3 is a fact, not an absence.
        #expect(WorkDetailFigures.preferred(local: 0, remote: 0) == 0)
    }

    // MARK: Helpers

    private func snapshot(_ fandoms: [String], added: Date, read: Date?) -> MediaBrowserView.LibraryWorkSnapshot {
        MediaBrowserView.LibraryWorkSnapshot(
            fandomsLower: fandoms.map { $0.lowercased() },
            fandomsDisplay: fandoms,
            hasBeenRead: true,
            dateAdded: added,
            lastReadDate: read
        )
    }
}
