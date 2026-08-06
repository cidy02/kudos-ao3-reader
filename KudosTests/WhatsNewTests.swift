import Foundation
import Testing
@testable import Kudos

struct WhatsNewTests {
    @Test func freshInstallShowsNothingAndEstablishesBaseline() throws {
        let defaults = try testDefaults()

        let entries = Changelog.unseenEntries(defaults: defaults)

        #expect(entries.isEmpty)
        #expect(defaults.string(forKey: "lastSeenChangelogVersion") == Changelog.currentVersion)
    }

    @Test func alreadySeenCurrentVersionShowsNothing() throws {
        let defaults = try testDefaults()
        defaults.set(Changelog.currentVersion, forKey: "lastSeenChangelogVersion")

        #expect(Changelog.unseenEntries(defaults: defaults).isEmpty)
    }

    @Test func unrecognizedLastSeenVersionShowsEverythingRatherThanLosingNotes() throws {
        let defaults = try testDefaults()
        defaults.set("0.0-predates-this-feature", forKey: "lastSeenChangelogVersion")

        #expect(Changelog.unseenEntries(defaults: defaults) == Changelog.entries)
    }

    @Test func markSeenRecordsTheCurrentVersion() throws {
        let defaults = try testDefaults()

        Changelog.markSeen(defaults: defaults)

        #expect(defaults.string(forKey: "lastSeenChangelogVersion") == Changelog.currentVersion)
        #expect(Changelog.unseenEntries(defaults: defaults).isEmpty)
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "WhatsNewTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
