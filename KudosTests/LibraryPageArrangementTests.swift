import Foundation
import Testing
@testable import Kudos

/// The Library page's section / button split. Default, order, and an older
/// backup that has no field for it.
struct LibraryPageArrangementTests {
    @Test func defaultIsFavouritesCollectionsDownloadedAsCarousels() {
        let arrangement = LibraryPageArrangement.default
        #expect(arrangement.sections == [
            LibraryPageSection(id: .favourites, style: .carousel),
            LibraryPageSection(id: .collections, style: .carousel),
            LibraryPageSection(id: .downloaded, style: .carousel)
        ])
        #expect(arrangement.buttons == [
            .wantToRead, .readingNow, .finished, .queues, .history, .imported
        ])
        expectPartition(arrangement)
    }

    @Test func removingASectionAppendsAButtonAndAddingItReturnsACarousel() {
        let removed = LibraryPageArrangement.default.removingFromPage(.favourites)
        #expect(removed.sections.map(\.id) == [.collections, .downloaded])
        #expect(removed.buttons.last == .favourites)
        expectPartition(removed)

        let added = removed.addingToPage(.favourites)
        #expect(added.sections.last == LibraryPageSection(id: .favourites, style: .carousel))
        #expect(!added.buttons.contains(.favourites))
        expectPartition(added)

        // A shelf that is already on the page is not added twice.
        #expect(added.addingToPage(.collections) == added)
        #expect(LibraryPageArrangement.default.removingFromPage(.queues) == .default)
    }

    @Test func styleAndOrderRoundTripThroughStorage() throws {
        let arranged = LibraryPageArrangement.default
            .removingFromPage(.downloaded)
            .addingToPage(.history)
            .settingStyle(.collections, to: .list)
            .movingSections(from: IndexSet(integer: 0), to: 2)
            .movingButtons(from: IndexSet(integer: 0), to: 3)
        expectPartition(arranged)

        let restored = try #require(LibraryPageArrangement(rawValue: arranged.rawValue))
        #expect(restored == arranged)

        let defaults = try makeDefaults()
        defaults.set(arranged.rawValue, forKey: LibraryPageArrangement.storageKey)
        #expect(LibraryPageArrangement.stored(in: defaults) == arranged)
    }

    @Test func moveMatchesTheListGap() {
        #expect(LibraryPageArrangement.moved(["a", "b", "c", "d"], from: IndexSet(integer: 0), to: 2) == ["b", "a", "c", "d"])
        #expect(LibraryPageArrangement.moved(["a", "b", "c", "d"], from: IndexSet(integer: 3), to: 0) == ["d", "a", "b", "c"])
    }

    @Test func unknownIDsDropAndAMissingShelfBecomesAButton() throws {
        let json = """
        {"sections":[{"id":"favourites","style":"list"},{"id":"nope","style":"carousel"},{"id":"favourites","style":"carousel"}],"buttons":["queues","not-a-shelf","favourites"]}
        """
        let decoded = try #require(LibraryPageArrangement(rawValue: json))
        #expect(decoded.sections == [LibraryPageSection(id: .favourites, style: .list)])
        #expect(decoded.buttons.first == .queues)
        #expect(!decoded.buttons.contains(.favourites))
        expectPartition(decoded)
    }

    @Test func aShelfNamedInBothListsStaysASection() {
        let both = LibraryPageArrangement(
            sections: [LibraryPageSection(id: .readingNow, style: .list)],
            buttons: [.readingNow, .finished]
        )
        #expect(both.style(of: .readingNow) == .list)
        #expect(!both.buttons.contains(.readingNow))
        #expect(both.buttons.contains(.finished))
        expectPartition(both)
    }

    @Test func importedIsEverythingThatDidNotComeFromAO3() {
        #expect(LibraryShelfID.isImported(origin: .importedFile, isQueueOnly: false))
        #expect(LibraryShelfID.isImported(origin: .fanfictionNet, isQueueOnly: false))
        #expect(!LibraryShelfID.isImported(origin: .archiveOfOurOwn, isQueueOnly: false))
        #expect(!LibraryShelfID.isImported(origin: .importedFile, isQueueOnly: true))
    }

    @Test func headerTallyKeepsTheSingular() {
        #expect(LibraryPageArrangement.workCountPhrase(1) == "1 work")
        #expect(LibraryPageArrangement.workCountPhrase(214) == "214 works")
        #expect(
            LibraryPageArrangement.headerTally(works: 214, downloaded: 98, byteText: "2.1 GB")
                == "214 works · 98 downloaded · 2.1 GB"
        )
    }

    @Test func olderSettingsWithoutTheFieldLeaveTheLocalLayout() throws {
        let settings = try JSONDecoder().decode(KudosBackupSettings.self, from: Data(olderSettingsJSON.utf8))
        #expect(settings.libraryPageArrangement == nil)

        let defaults = try makeDefaults()
        let custom = LibraryPageArrangement.default.settingStyle(.downloaded, to: .list)
        defaults.set(custom.rawValue, forKey: LibraryPageArrangement.storageKey)
        settings.apply(to: defaults)
        #expect(LibraryPageArrangement.stored(in: defaults) == custom)
    }

    @Test func aMalformedArrangementDecodesAsNilAndLeavesTheLocalLayout() throws {
        let json = olderSettingsJSON.replacingOccurrences(
            of: "\"autoPreserveSeriesWorkThreshold\": 5",
            with: "\"autoPreserveSeriesWorkThreshold\": 5, \"libraryPageArrangement\": \"nope\""
        )
        let settings = try JSONDecoder().decode(KudosBackupSettings.self, from: Data(json.utf8))
        #expect(settings.libraryPageArrangement == nil)

        let defaults = try makeDefaults()
        let custom = LibraryPageArrangement.default.settingStyle(.favourites, to: .list)
        defaults.set(custom.rawValue, forKey: LibraryPageArrangement.storageKey)
        settings.apply(to: defaults)
        #expect(LibraryPageArrangement.stored(in: defaults) == custom)
    }

    @Test func arrangementRoundTripsThroughBackupSettings() throws {
        let source = try makeDefaults()
        let custom = LibraryPageArrangement.default
            .addingToPage(.queues)
            .settingStyle(.favourites, to: .list)
        source.set(custom.rawValue, forKey: LibraryPageArrangement.storageKey)

        let captured = KudosBackupSettings.capture(defaults: source)
        #expect(captured.libraryPageArrangement == custom)

        let data = try JSONEncoder().encode(captured)
        let decoded = try JSONDecoder().decode(KudosBackupSettings.self, from: data)
        #expect(decoded.libraryPageArrangement == custom)

        let destination = try makeDefaults()
        destination.set(
            LibraryPageArrangement.default.rawValue,
            forKey: LibraryPageArrangement.storageKey
        )
        decoded.apply(to: destination)
        #expect(LibraryPageArrangement.stored(in: destination) == custom)
    }

    private func expectPartition(_ arrangement: LibraryPageArrangement) {
        let sectionIDs = arrangement.sections.map(\.id)
        #expect(Set(sectionIDs).count == sectionIDs.count)
        #expect(Set(arrangement.buttons).count == arrangement.buttons.count)
        #expect(Set(sectionIDs).isDisjoint(with: arrangement.buttons))
        #expect(Set(sectionIDs).union(arrangement.buttons) == Set(LibraryShelfID.allCases))
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "LibraryPageArrangementTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// The settings object older archives carry: every key that existed before
    /// this shelf arrangement, and not the arrangement.
    private var olderSettingsJSON: String {
        """
        {
          "readerFontID": "system",
          "readerMode": "scroll",
          "readerTwoPage": false,
          "readerCustomize": false,
          "readerBoldText": false,
          "readerFontPt": 18,
          "readerLineHeight": 1.65,
          "readerLetterSpacing": 0,
          "readerWordSpacing": 0,
          "readerMargin": 28,
          "readerJustify": false,
          "confirmBeforeDelete": true,
          "hideMatureContent": true,
          "matureContentMode": "obscure",
          "requireBiometricToReveal": false,
          "appTheme": "light",
          "readerTheme": "light",
          "matchAppReaderTheme": true,
          "accentColorHex": "#990000",
          "autoPreserveSmallSeriesOnSaveForLater": false,
          "autoPreserveSeriesWorkThreshold": 5
        }
        """
    }
}
