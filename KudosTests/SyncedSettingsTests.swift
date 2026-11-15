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

    // MARK: Review round (Codex, 2026-11-15)

    @Test func anOlderConflictCopyCannotReplaceWhatANewerManifestJustSet() {
        let defaults = freshDefaults()
        defaults.set(18.0, forKey: "readerFontPt")
        let live = folderCopy(of: defaults, fontPt: 20)      // no stamps: Android or an older build
        let conflict = folderCopy(of: defaults, fontPt: 14)
        let liveExported = Date(timeIntervalSince1970: 1_700_000_600)

        live.apply(to: defaults, fromSync: true, archiveDate: liveExported)
        conflict.apply(to: defaults, fromSync: true, archiveDate: liveExported.addingTimeInterval(-600))

        #expect(defaults.double(forKey: "readerFontPt") == 20)
    }

    @Test func aChoiceResetOnAnotherDeviceIsRemovedHere() {
        let defaults = freshDefaults()
        defaults.set("#F4ECD8", forKey: "readerCustomPaperHex")
        var incoming = KudosBackupSettings.capture(defaults: defaults)
        incoming.extras?["readerCustomPaperHex"] = nil
        incoming.modifiedAt = ["readerCustomPaperHex": Date().addingTimeInterval(-5)]

        incoming.apply(to: defaults, fromSync: true, archiveDate: Date().addingTimeInterval(-5))
        #expect(defaults.object(forKey: "readerCustomPaperHex") == nil)

        // A copy that does not know the key carries no stamp for it: that is not a reset.
        defaults.set("#F4ECD8", forKey: "readerCustomPaperHex")
        var unaware = KudosBackupSettings.capture(defaults: defaults)
        unaware.extras = nil
        unaware.modifiedAt = nil
        unaware.apply(to: defaults, fromSync: true, archiveDate: Date())
        #expect(defaults.string(forKey: "readerCustomPaperHex") == "#F4ECD8")
    }

    @Test func checkingForChangesWritesNothingWhenNothingChanged() {
        let defaults = freshDefaults()
        defaults.set(18.0, forKey: "readerFontPt")
        #expect(!SyncedSettingsClock.stampChanges(keys: KudosBackupSettings.syncedKeys, in: defaults))
        #expect(!SyncedSettingsClock.stampChanges(keys: KudosBackupSettings.syncedKeys, in: defaults))
        defaults.set(22.0, forKey: "readerFontPt")
        #expect(SyncedSettingsClock.stampChanges(keys: KudosBackupSettings.syncedKeys, in: defaults))
        #expect(SyncedSettingsClock.stamps(in: defaults)["readerFontPt"] != nil)
    }

    private func pronunciationStore() -> KokoroPronunciationStore {
        KokoroPronunciationStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncedSettingsTests-\(UUID().uuidString).json"))
    }

    /// Through JSON, as a manifest travels: the first version of T-541 never decoded the stamps.
    private func throughJSON(_ value: KudosBackupPronunciations) throws -> KudosBackupPronunciations {
        try JSONDecoder().decode(KudosBackupPronunciations.self, from: JSONEncoder().encode(value))
    }

    private func id(_ word: String) -> String { KokoroPronunciationStore.entryID(.global, word) }

    @Test func aCorrectionEditedHereSurvivesAnOlderCopyFromTheFolder() throws {
        let store = pronunciationStore()
        try store.setOverride("old", for: "Wren")
        var stale = KudosBackupPronunciations.capture(store: store)   // what the folder holds
        stale.global["Maren"] = "added elsewhere"
        try store.setOverride("new", for: "Wren")                     // edited here afterwards
        let editedHere = try #require(store.load().stamps?[id("Wren")])
        stale.stamps = [id("Wren"): editedHere.addingTimeInterval(-60)]

        try throughJSON(stale).apply(to: store, fromSync: true, archiveDate: editedHere.addingTimeInterval(-30))

        #expect(store.load().global["Wren"] == "new")
        #expect(store.load().global["Maren"] == "added elsewhere")   // an entry only the folder had still arrives
    }

    @Test func aNewerCorrectionFromTheFolderReplacesTheOneHere() throws {
        let store = pronunciationStore()
        try store.setOverride("mine", for: "Wren")
        let editedHere = try #require(store.load().stamps?[id("Wren")])
        var newer = KudosBackupPronunciations.capture(store: store)
        newer.global["Wren"] = "theirs"
        newer.stamps = [id("Wren"): editedHere.addingTimeInterval(-1)]
        try throughJSON(newer).apply(to: store, fromSync: true)
        #expect(store.load().global["Wren"] == "mine")               // older by a second: stays

        // Set here a minute ago; the folder's is from just now.
        var file = store.load()
        file.stamp(["Wren"], in: .global, at: Date().addingTimeInterval(-60))
        try store.save(file)
        newer.stamps = [id("Wren"): Date().addingTimeInterval(-1)]
        try throughJSON(newer).apply(to: store, fromSync: true)
        #expect(store.load().global["Wren"] == "theirs")
    }

    @Test func twoDevicesEditingDifferentWordsBothKeepTheirEdit() throws {
        let start = Date().addingTimeInterval(-600)
        let here = pronunciationStore()
        var file = KokoroPronunciationStore.empty
        file.global = ["Wren": "old", "Maren": "old"]
        try here.save(file)
        // This device corrects Wren. The other, which still has the old Wren, corrects Maren later.
        var mine = here.load()
        mine.global["Wren"] = "fixed here"
        mine.stamp(["Wren"], in: .global, at: start.addingTimeInterval(60))
        try here.save(mine)
        var theirs = KudosBackupPronunciations(global: ["Wren": "old", "Maren": "fixed there"], fandoms: [:], works: [:])
        theirs.stamps = [id("Maren"): start.addingTimeInterval(120)]

        try throughJSON(theirs).apply(to: here, fromSync: true, archiveDate: start)

        #expect(here.load().global["Wren"] == "fixed here")
        #expect(here.load().global["Maren"] == "fixed there")
    }

    @Test func aCorrectionRemovedElsewhereIsRemovedHereAndOneRemovedHereStaysRemoved() throws {
        let store = pronunciationStore()
        try store.setOverride("x", for: "Wren")
        var file = store.load()
        file.stamp(["Wren"], in: .global, at: Date().addingTimeInterval(-600))
        try store.save(file)
        var removedThere = KudosBackupPronunciations(global: [:], fandoms: [:], works: [:])
        removedThere.stamps = [id("Wren"): Date().addingTimeInterval(-60)]
        try throughJSON(removedThere).apply(to: store, fromSync: true)
        #expect(store.load().global["Wren"] == nil)

        try store.setOverride("y", for: "Maren")
        try store.removeOverride(for: "Maren")                        // removed here, just now
        var stale = KudosBackupPronunciations(global: ["Maren": "y"], fandoms: [:], works: [:])
        stale.stamps = [id("Maren"): Date().addingTimeInterval(-300)]
        try throughJSON(stale).apply(to: store, fromSync: true)
        #expect(store.load().global["Maren"] == nil)
    }

    @Test func aRestoreTheReaderAskedForStillTakesTheFilesCorrections() throws {
        let store = pronunciationStore()
        try store.setOverride("mine", for: "Wren")
        var file = KudosBackupPronunciations.capture(store: store)
        file.global["Wren"] = "from the backup"
        file.stamps = nil

        try throughJSON(file).apply(to: store)

        #expect(store.load().global["Wren"] == "from the backup")
    }
}
