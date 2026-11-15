import Foundation
import Testing
@testable import Kudos

/// T-541: a sync may replace a setting only with a newer one. Before it, every sync-down
/// assigned the folder's settings over whatever had been changed on this device since.
@MainActor
struct SyncedSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let name = "SyncedSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// The folder's copy as another device would have written it: this device's values at
    /// `fontPt`, with no stamps unless the test adds them.
    private func folderCopy(of defaults: UserDefaults, fontPt: Double) -> KudosBackupSettings {
        var copy = KudosBackupSettings.capture(defaults: defaults)
        copy.readerFontPt = fontPt
        copy.modifiedAt = nil
        copy.extras = nil
        return copy
    }

    @Test func aSettingChangedHereSurvivesAnOlderCopyFromTheFolder() {
        let defaults = freshDefaults()
        defaults.set(18.0, forKey: "readerFontPt")
        let stale = folderCopy(of: defaults, fontPt: 18)   // also records the baseline, as a sync-up does
        defaults.set(22.0, forKey: "readerFontPt")          // the reader changes it afterwards

        stale.apply(to: defaults, fromSync: true)

        #expect(defaults.double(forKey: "readerFontPt") == 22)
    }

    @Test func aSettingNobodyChangedHereTakesTheFoldersValue() {
        let defaults = freshDefaults()
        defaults.set(18.0, forKey: "readerFontPt")
        let other = folderCopy(of: defaults, fontPt: 20)

        other.apply(to: defaults, fromSync: true)

        #expect(defaults.double(forKey: "readerFontPt") == 20)
    }

    @Test func theNewerStampWinsAndTheOlderLoses() {
        let defaults = freshDefaults()
        // In the past: an archive date in the future is clamped to now, as every archive date is.
        let changedHere = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(18.0, forKey: "readerFontPt")
        SyncedSettingsClock.noteLocalChanges(keys: ["readerFontPt"], in: defaults, now: changedHere.addingTimeInterval(-600))
        defaults.set(22.0, forKey: "readerFontPt")
        SyncedSettingsClock.noteLocalChanges(keys: ["readerFontPt"], in: defaults, now: changedHere)

        var older = folderCopy(of: defaults, fontPt: 16)
        older.modifiedAt = ["readerFontPt": changedHere.addingTimeInterval(-60)]
        older.apply(to: defaults, fromSync: true)
        #expect(defaults.double(forKey: "readerFontPt") == 22)

        var newer = folderCopy(of: defaults, fontPt: 24)
        newer.modifiedAt = ["readerFontPt": changedHere.addingTimeInterval(60)]
        newer.apply(to: defaults, fromSync: true)
        #expect(defaults.double(forKey: "readerFontPt") == 24)
        // The value that arrived keeps the stamp it came with; it is not a change made here.
        #expect(KudosBackupSettings.capture(defaults: defaults).modifiedAt?["readerFontPt"]
            == changedHere.addingTimeInterval(60))
    }

    @Test func aRestoreTheReaderAskedForStillTakesTheFilesSettings() {
        let defaults = freshDefaults()
        defaults.set(18.0, forKey: "readerFontPt")
        let file = folderCopy(of: defaults, fontPt: 18)
        defaults.set(22.0, forKey: "readerFontPt")

        file.apply(to: defaults)

        #expect(defaults.double(forKey: "readerFontPt") == 18)
    }

    @Test func aSyncStillCannotLoosenAPrivacyGate() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hideMatureContent")
        var incoming = KudosBackupSettings.capture(defaults: defaults)
        incoming.hideMatureContent = false
        incoming.modifiedAt = ["hideMatureContent": Date().addingTimeInterval(-1)]

        incoming.apply(to: defaults, fromSync: true)

        #expect(defaults.bool(forKey: "hideMatureContent"))
    }

    @Test func extrasCarryOnlyStoredChoicesAndOnlyKnownKeys() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "keepScreenAwake")
        let captured = KudosBackupSettings.capture(defaults: defaults)
        #expect(captured.extras?["keepScreenAwake"] == .bool(true))
        #expect(captured.extras?["showsZeroStats"] == nil)   // never chosen here: not exported

        let target = freshDefaults()
        var incoming = KudosBackupSettings.capture(defaults: target)
        incoming.extras = [
            "keepScreenAwake": .bool(true),
            "readerSpeechRate": .string("fast"),           // wrong kind
            "not.a.kudos.setting": .string("xx")           // not on the allowlist
        ]
        incoming.apply(to: target, fromSync: true)

        #expect(target.bool(forKey: "keepScreenAwake"))
        #expect(target.object(forKey: "readerSpeechRate") == nil)
        #expect(target.object(forKey: "not.a.kudos.setting") == nil)
    }

    @Test func theKeysWrittenByNameAreTheKeysTheirOwnersUse() {
        #expect(WorkLifecycle.keepsWorksYouReadKey == "keepsWorksYouRead")
        #expect(WorkListKeys.searchShowSummaries == "search.showSummaries")
        #expect(WorkListKeys.fandomWorksShowSummaries == "browse.fandomWorks.showSummaries")
        #expect(WorkListKeys.tagWorksShowSummaries == "browse.tagWorks.showSummaries")
        #expect(WorkListKeys.authorListsShowSummaries == "author.lists.showSummaries")
        #expect(WorkListKeys.seriesShowSummaries == "series.showSummaries")
        #expect(WorkListKeys.yourWorksArrangement == "account.yourWorks.arrangement")
        #expect(WorkListKeys.markedForLaterArrangement == "account.markedForLater.arrangement")
        #expect(WorkListKeys.bookmarksArrangement == "account.bookmarks.arrangement")
        #expect(WorkListKeys.ao3HistoryArrangement == "account.ao3History.arrangement")
        #expect(WorkListKeys.allWorksArrangement == "library.allWorks.arrangement")
        #expect(WorkListKeys.importedArrangement == "library.imported.arrangement")
        #expect(WorkListKeys.accountDisplayMode == "account.displayMode")
        #expect(WorkListKeys.authorProfileDisplayMode == "authorProfile.displayMode")
        #expect(WorkListKeys.collectionDisplayMode == "collection.displayMode")
        #expect(ThemeManager.paperKey == "readerCustomPaperHex")
        #expect(ReaderSpeechPreferences.rateKey == "readerSpeechRate")
        #expect(ReaderSpeechPreferences.pitchKey == "readerSpeechPitch")
        #expect(ReaderSpeechPreferences.readAuthorNotesKey == "readerSpeechReadAuthorNotes")
        #expect(LibraryPageArrangement.storageKey == "library.page.arrangement")
        #expect(KudosBackupSettings.recencyKeys.contains(LibraryPageArrangement.storageKey))
        #expect(KudosBackupSettings.recencyKeys.contains(WorkSymbolPlacement.storageKey))
        #expect(WorkSymbolPlacement.storageKey == "workSymbolPlacement")
    }

    @Test func stampsAndExtrasSurviveARoundTripAndAnOlderArchiveStillDecodes() throws {
        let defaults = freshDefaults()
        defaults.set(false, forKey: "showsZeroStats")
        var settings = KudosBackupSettings.capture(defaults: defaults)
        settings.modifiedAt = ["readerFontPt": Date(timeIntervalSince1970: 1_800_000_000)]
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(KudosBackupSettings.self, from: data) == settings)

        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy["modifiedAt"] = nil
        legacy["extras"] = nil
        let decoded = try JSONDecoder().decode(
            KudosBackupSettings.self, from: JSONSerialization.data(withJSONObject: legacy)
        )
        #expect(decoded.modifiedAt == nil)
        #expect(decoded.extras == nil)
    }

    private func pronunciationStore() -> KokoroPronunciationStore {
        KokoroPronunciationStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncedSettingsTests-\(UUID().uuidString).json"))
    }

    @Test func aCorrectionEditedHereSurvivesAnOlderCopyFromTheFolder() throws {
        let store = pronunciationStore()
        try store.setOverride("old", for: "Wren")
        var stale = KudosBackupPronunciations.capture(store: store)   // what the folder holds
        stale.global["Maren"] = "added elsewhere"
        try store.setOverride("new", for: "Wren")                     // edited here afterwards
        stale.modifiedAt = store.load().modifiedAt?.addingTimeInterval(-60)

        try stale.apply(to: store, fromSync: true)

        #expect(store.load().global["Wren"] == "new")
        #expect(store.load().global["Maren"] == "added elsewhere")   // an entry only the folder had still arrives
    }

    @Test func aNewerCorrectionFromTheFolderReplacesTheOneHere() throws {
        let store = pronunciationStore()
        try store.setOverride("mine", for: "Wren")
        var newer = KudosBackupPronunciations.capture(store: store)
        newer.global["Wren"] = "theirs"
        newer.modifiedAt = store.load().modifiedAt?.addingTimeInterval(60)

        try newer.apply(to: store, fromSync: true)

        #expect(store.load().global["Wren"] == "theirs")
    }

    @Test func aRestoreTheReaderAskedForStillTakesTheFilesCorrections() throws {
        let store = pronunciationStore()
        try store.setOverride("mine", for: "Wren")
        var file = KudosBackupPronunciations.capture(store: store)
        file.global["Wren"] = "from the backup"
        file.modifiedAt = nil

        try file.apply(to: store)

        #expect(store.load().global["Wren"] == "from the backup")
    }
}
