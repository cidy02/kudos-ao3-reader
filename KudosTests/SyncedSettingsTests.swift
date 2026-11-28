import Foundation
import SwiftData
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

    // Privacy gates (owner, 2026-11-27: "i just turned off blur mature works, and when i opened the app again it was
    // back on"): a sync may still tighten a gate and never loosen one, but not over a newer change made here.

    @Test func aPrivacyGateTurnedOffHereStaysOffAfterAnOlderCopyFromTheFolder() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hideMatureContent")
        var stale = folderCopy(of: defaults, fontPt: 18)   // also records the baseline, as a sync-up does
        stale.hideMatureContent = true
        defaults.set(false, forKey: "hideMatureContent")    // the reader turns it off afterwards

        stale.apply(to: defaults, fromSync: true)

        #expect(defaults.bool(forKey: "hideMatureContent") == false)
    }

    @Test func aPrivacyGateNobodyChangedHereIsStillTightenedByTheFolder() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: "hideMatureContent")
        var other = folderCopy(of: defaults, fontPt: 18)
        other.hideMatureContent = true

        other.apply(to: defaults, fromSync: true)

        #expect(defaults.bool(forKey: "hideMatureContent") == true)
    }

    @Test func aPrivacyGateIsNeverLoosenedByACopy() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hideMatureContent")
        var other = folderCopy(of: defaults, fontPt: 18)
        other.hideMatureContent = false

        other.apply(to: defaults, fromSync: true)
        other.apply(to: defaults)

        #expect(defaults.bool(forKey: "hideMatureContent") == true)
    }

    @Test func anExplicitRestoreStillTightensAGateChangedHere() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hideMatureContent")
        var backup = folderCopy(of: defaults, fontPt: 18)
        backup.hideMatureContent = true
        defaults.set(false, forKey: "hideMatureContent")

        backup.apply(to: defaults)

        #expect(defaults.bool(forKey: "hideMatureContent") == true)
    }

    @Test func blurChosenHereIsNotTurnedBackIntoHideByAnOlderCopy() {
        let defaults = freshDefaults()
        defaults.set(MaturePrivacyMode.hide.rawValue, forKey: "matureContentMode")
        var stale = folderCopy(of: defaults, fontPt: 18)
        stale.matureContentMode = MaturePrivacyMode.hide.rawValue
        defaults.set(MaturePrivacyMode.obscure.rawValue, forKey: "matureContentMode")

        stale.apply(to: defaults, fromSync: true)

        #expect(defaults.string(forKey: "matureContentMode") == MaturePrivacyMode.obscure.rawValue)
    }

    @Test func privacyGatesAreWatchedSoAChangeIsStampedAndUploaded() {
        let keys = KudosBackupSettings.observedKeys(in: freshDefaults()).keys
        for key in KudosBackupSettings.privacyGateKeys {
            #expect(keys.contains(key))
        }
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

        // Settings the integration branch added after T-541 forked (named fields, stamped here).
        for key in [
            "useEmbeddedCoverArt", SavedSeriesWeeklyCheck.enabledKey, ReaderPageTurnStyle.storageKey,
            ReaderSpeechPreferences.voiceIDKey, ReaderSpeechPreferences.voiceNameKey,
            "lastAddedReadingQueueID", InsightsOptions.Keys.discreetMode, InsightsOptions.Keys.hideReadingTime,
            InsightsOptions.Keys.countRereads, InsightsOptions.Keys.countReadAloud,
            InsightsOptions.Keys.askAboutUntouched, InsightsOptions.Keys.untouchedDays,
            InsightsOptions.Keys.excludedFandoms, InsightsOptions.Keys.excludedTags,
            InsightsOptions.Keys.excludedWorkIDs
        ] {
            #expect(KudosBackupSettings.recencyKeys.contains(key), "\(key)")
            #expect(KudosBackupSettings.extraKeys[key] == nil, "\(key) must not travel twice")
        }
        #expect(KudosBackupSettings.extraKeys["workExportIncludesCover"] == .bool)
    }

    @Test func aRemovedPatternedLayoutKeyStillGetsItsRemovalStamped() {
        let defaults = freshDefaults()
        let key = "collection.0F0F0F0F.arrangement"
        _ = KudosBackupSettings.capture(defaults: defaults)
        defaults.set("grid", forKey: key)
        _ = KudosBackupSettings.capture(defaults: defaults)
        #expect(SyncedSettingsClock.stamps(in: defaults)[key] != nil)
        defaults.removeObject(forKey: key)
        #expect(KudosBackupSettings.observedKeys(in: defaults).keys.contains(key))
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

    /// Codex's third review: an explicit restore reproduces the snapshot, resets included.
    @Test func anExplicitRestoreAlsoAppliesAReset() {
        let defaults = freshDefaults()
        defaults.set("#F4ECD8", forKey: "readerCustomPaperHex")
        var snapshot = KudosBackupSettings.capture(defaults: defaults)
        snapshot.extras?["readerCustomPaperHex"] = nil
        snapshot.modifiedAt = ["readerCustomPaperHex": Date().addingTimeInterval(-5)]
        snapshot.apply(to: defaults, fromSync: false)
        #expect(defaults.object(forKey: "readerCustomPaperHex") == nil)
    }

    /// Codex's fourth review: the named settings that may be absent honour a reset too, on a sync
    /// and on an explicit restore; absent without a stamp still leaves the local choice.
    @Test func aResetOfANamedOptionalSettingTravels() {
        for fromSync in [true, false] {
            let defaults = freshDefaults()
            defaults.set("#2468AC", forKey: "accentColorHex")
            defaults.set(WorkSymbolPlacement.beside.rawValue, forKey: WorkSymbolPlacement.storageKey)
            var reset = KudosBackupSettings.capture(defaults: defaults)
            reset.accentColorHex = nil
            reset.workSymbolPlacement = nil
            reset.modifiedAt = ["accentColorHex": Date().addingTimeInterval(-5)]
            reset.apply(to: defaults, fromSync: fromSync, archiveDate: Date().addingTimeInterval(-5))
            #expect(defaults.object(forKey: "accentColorHex") == nil, "fromSync: \(fromSync)")
            // No stamp for the symbol placement: an unaware writer, not a reset.
            #expect(defaults.string(forKey: WorkSymbolPlacement.storageKey) == WorkSymbolPlacement.beside.rawValue)
        }
    }

    /// Fifth review: a device that never held a value still keeps the reset's stamp, so its own
    /// next export carries the reset on and an offline device's older value cannot come back.
    @Test func aDeviceThatNeverHadTheValueStillPassesTheResetOn() throws {
        let removedAt = Date().addingTimeInterval(-5)
        let paperEntry = SyncedSettingsClock.entryID("ao3CommentDrafts", "me|w1-c0-p0")
        var reset = KudosBackupSettings.capture(defaults: freshDefaults())
        reset.accentColorHex = nil
        reset.modifiedAt = [
            "readerCustomPaperHex": removedAt, "accentColorHex": removedAt, paperEntry: removedAt
        ]
        let untouched = freshDefaults()
        try throughJSON(reset).apply(to: untouched, fromSync: true, archiveDate: removedAt)
        #expect(untouched.object(forKey: "readerCustomPaperHex") == nil)
        #expect(untouched.object(forKey: "ao3CommentDrafts") == nil)    // nothing invented

        let passedOn = KudosBackupSettings.capture(defaults: untouched)
        for id in ["readerCustomPaperHex", "accentColorHex", paperEntry] {
            #expect(passedOn.modifiedAt?[id] != nil, "\(id) stamp dropped")
        }

        // The offline device's older value then loses to the passed-on reset.
        let offline = freshDefaults()
        offline.set("#F4ECD8", forKey: "readerCustomPaperHex")
        offline.set(["me|w1-c0-p0": "old"], forKey: "ao3CommentDrafts")
        SyncedSettingsClock.adopt(key: "readerCustomPaperHex", stamp: .init(date: removedAt.addingTimeInterval(-100), inferred: false), in: offline)
        SyncedSettingsClock.adopt(key: "ao3CommentDrafts", entry: "me|w1-c0-p0", value: "old", stamp: .init(date: removedAt.addingTimeInterval(-100), inferred: false), in: offline)
        try throughJSON(passedOn).apply(to: offline, fromSync: true, archiveDate: Date())
        #expect(offline.object(forKey: "readerCustomPaperHex") == nil)
        #expect((offline.dictionary(forKey: "ao3CommentDrafts") as? [String: String])?["me|w1-c0-p0"] == nil)
    }

    /// Codex's third review: the reader font is part of the snapshot, but never a custom font
    /// whose file is not on this device.
    @Test func theReaderFontTravelsUnlessItsFileIsMissing() {
        let defaults = freshDefaults()
        defaults.set("system", forKey: "readerFontID")
        var incoming = KudosBackupSettings.capture(defaults: defaults)
        incoming.readerFontID = "georgia"
        incoming.modifiedAt = ["readerFontID": Date().addingTimeInterval(-5)]
        incoming.apply(to: defaults, fromSync: true, archiveDate: Date().addingTimeInterval(-5))
        #expect(defaults.string(forKey: "readerFontID") == "georgia")

        var missing = KudosBackupSettings.capture(defaults: defaults)
        missing.readerFontID = "custom:not-here.ttf"
        missing.modifiedAt = ["readerFontID": Date()]
        missing.skipsReaderFont = true
        missing.apply(to: defaults, fromSync: true, archiveDate: Date())
        #expect(defaults.string(forKey: "readerFontID") == "georgia")
    }

    @Test func aFirstChoiceForAnUntouchedSettingIsStampedAndAnnounced() {
        let defaults = freshDefaults()
        let keys = ["readerFontPt", "readerLineSpacing"]
        let maps: Set<String> = ["commentDrafts"]
        defaults.set(1.4, forKey: "readerLineSpacing")
        // First look: nothing is stamped, an existing value included.
        #expect(!SyncedSettingsClock.stampChanges(keys: keys + ["commentDrafts"], mapKeys: maps, in: defaults))
        #expect(SyncedSettingsClock.stamps(in: defaults).isEmpty)
        // The reader then sets a setting that was absent: an edit, stamped, so the observer uploads it.
        let when = Date(timeIntervalSince1970: 2_000_000_000)
        defaults.set(20.0, forKey: "readerFontPt")
        #expect(SyncedSettingsClock.stampChanges(keys: keys + ["commentDrafts"], mapKeys: maps, in: defaults, now: when))
        #expect(SyncedSettingsClock.stamps(in: defaults)["readerFontPt"] == when)
        #expect(SyncedSettingsClock.stamps(in: defaults)["readerLineSpacing"] == nil)
        // A new entry in a map setting is an edit too.
        defaults.set(["work-1": "draft"], forKey: "commentDrafts")
        #expect(SyncedSettingsClock.stampChanges(keys: keys + ["commentDrafts"], mapKeys: maps, in: defaults, now: when))
        #expect(SyncedSettingsClock.stamps(in: defaults)[SyncedSettingsClock.entryID("commentDrafts", "work-1")] == when)
        // An older stamped copy from elsewhere then loses to that first choice.
        let older = SyncedSettingsClock.Stamp(date: when.addingTimeInterval(-60), inferred: false)
        let local = SyncedSettingsClock.localStamps(in: defaults)["readerFontPt"]
        #expect(!SyncedSettingsClock.incomingWins(local: local, incoming: older, fromSync: true))
    }

    @Test func checkingForChangesWritesNothingWhenNothingChanged() {
        let defaults = freshDefaults()
        defaults.set(18.0, forKey: "readerFontPt")
        let keys = KudosBackupSettings.observedKeys(in: defaults)
        #expect(!SyncedSettingsClock.stampChanges(keys: keys.keys, mapKeys: keys.maps, in: defaults))
        #expect(!SyncedSettingsClock.stampChanges(keys: keys.keys, mapKeys: keys.maps, in: defaults))
        defaults.set(22.0, forKey: "readerFontPt")
        #expect(SyncedSettingsClock.stampChanges(keys: keys.keys, mapKeys: keys.maps, in: defaults))
        #expect(SyncedSettingsClock.stamps(in: defaults)["readerFontPt"] != nil)
    }

    // MARK: Second review round (Codex, 2026-11-15) and the complete snapshot (owner, 2026-11-16)

    /// Through JSON, as a manifest travels.
    private func throughJSON(_ settings: KudosBackupSettings) throws -> KudosBackupSettings {
        try JSONDecoder().decode(KudosBackupSettings.self, from: JSONEncoder().encode(settings))
    }

    @Test func anExportDateNeverBeatsARealEditMadeHere() throws {
        let defaults = freshDefaults()
        defaults.set(18.0, forKey: "readerFontPt")
        let stale = folderCopy(of: defaults, fontPt: 18)        // Android or an older build: no stamps
        defaults.set(22.0, forKey: "readerFontPt")
        _ = KudosBackupSettings.capture(defaults: defaults)      // the edit is stamped

        // Exported after the edit, but the value in it is the old one.
        try throughJSON(stale).apply(to: defaults, fromSync: true, archiveDate: Date())

        #expect(defaults.double(forKey: "readerFontPt") == 22)
    }

    @Test func commentDraftsTypedOnTwoDevicesBothSurviveAndAClearedOneStaysCleared() throws {
        let key = "ao3CommentDrafts"
        let here = freshDefaults()
        here.set(["me|w1-c0-p0": "old draft"], forKey: key)
        let start = KudosBackupSettings.capture(defaults: here)          // both devices start here
        let there = freshDefaults()
        try throughJSON(start).apply(to: there, fromSync: true, archiveDate: Date())
        #expect(there.dictionary(forKey: key) as? [String: String] == ["me|w1-c0-p0": "old draft"])

        // Here: the draft is posted and cleared. There: a new draft for another work.
        here.set([String: String](), forKey: key)
        _ = KudosBackupSettings.capture(defaults: here)
        var drafts = there.dictionary(forKey: key) as? [String: String] ?? [:]
        drafts["me|w2-c0-p0"] = "typed there"
        there.set(drafts, forKey: key)
        let fromThere = try throughJSON(KudosBackupSettings.capture(defaults: there))

        try fromThere.apply(to: here, fromSync: true, archiveDate: Date())

        let result = here.dictionary(forKey: key) as? [String: String] ?? [:]
        #expect(result["me|w2-c0-p0"] == "typed there")
        #expect(result["me|w1-c0-p0"] == nil)        // posted here after the other copy last saw it
    }

    @Test func oneUnreadableExtraKeepsTheRestAndRemovesNothing() throws {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "keepScreenAwake")
        defaults.set("#F4ECD8", forKey: "readerCustomPaperHex")
        var settings = KudosBackupSettings.capture(defaults: defaults)
        settings.extras = ["keepScreenAwake": .bool(false)]
        settings.modifiedAt = ["readerCustomPaperHex": Date(), "keepScreenAwake": Date()]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        var extras = try #require(json["extras"] as? [String: Any])
        extras["showsZeroStats"] = ["unexpected": [1, 2]]   // an entry this build cannot read
        json["extras"] = extras
        let decoded = try JSONDecoder().decode(
            KudosBackupSettings.self, from: JSONSerialization.data(withJSONObject: json)
        )
        #expect(decoded.extras?["keepScreenAwake"] == .bool(false))
        #expect(decoded.extrasIncomplete)

        decoded.apply(to: defaults, fromSync: true, archiveDate: Date())

        #expect(defaults.bool(forKey: "keepScreenAwake") == false)
        #expect(defaults.string(forKey: "readerCustomPaperHex") == "#F4ECD8")   // not taken as a reset
    }

    @Test func perListLayoutsAndStoredBytesTravel() throws {
        let source = freshDefaults()
        source.set("grid", forKey: "library.someShelf.arrangement")
        source.set(Data([1, 2, 3]), forKey: "writing.recentTags.v1")
        source.set(["alice": "pseud"], forKey: "ao3PostingPseudByUsername")
        let captured = try throughJSON(KudosBackupSettings.capture(defaults: source))
        #expect(captured.extras?["library.someShelf.arrangement"] == .string("grid"))
        #expect(KudosBackupSettings.extraKind(for: "library.page.arrangement") == nil)   // a named field
        #expect(KudosBackupSettings.extraKind(for: "AO3AuthenticatedUsername") == nil)  // sign-in stays

        let target = freshDefaults()
        captured.apply(to: target, fromSync: true, archiveDate: Date())

        #expect(target.string(forKey: "library.someShelf.arrangement") == "grid")
        #expect(target.data(forKey: "writing.recentTags.v1") == Data([1, 2, 3]))
        #expect(target.dictionary(forKey: "ao3PostingPseudByUsername") as? [String: String] == ["alice": "pseud"])
    }

    @Test func aStoredByteValueIsNotMistakenForAnotherOfTheSameLength() {
        let defaults = freshDefaults()
        defaults.set(Data([1, 2, 3]), forKey: "writing.recentTags.v1")
        let keys = KudosBackupSettings.observedKeys(in: defaults)
        SyncedSettingsClock.noteLocalChanges(keys: keys.keys, mapKeys: keys.maps, in: defaults)
        defaults.set(Data([9, 9, 9]), forKey: "writing.recentTags.v1")
        #expect(SyncedSettingsClock.stampChanges(keys: keys.keys, mapKeys: keys.maps, in: defaults))
    }

    @Test func correctionNamesReadBackWhateverTheyHold() {
        let word = "odd\u{1F}word"
        let id = KokoroPronunciationStore.entryID(.fandom("A\u{1F}B"), word)
        let parsed = KokoroPronunciationStore.entry(from: id)
        #expect(parsed?.0 == .fandom("A\u{1F}B"))
        #expect(parsed?.1 == word)
        // The first version's identifiers still read.
        let legacy = ["g", "Wren"].joined(separator: "\u{1F}")
        #expect(KokoroPronunciationStore.entry(from: legacy)?.1 == "Wren")
    }

    // MARK: Writing drafts and data files

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SyncedSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func writingDraftsArriveAndANewerOneHereIsKept() throws {
        let source = try temporaryFolder()
        let target = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: target) }
        let name = String(repeating: "a", count: 64) + ".SESSION-1.json"
        let older = WritingTextRecovery.Entry(text: "first", originalDigest: "x", savedAt: Date(timeIntervalSince1970: 1_700_000_000), accountDigest: nil)
        try JSONEncoder().encode(older).write(to: source.appendingPathComponent(name))
        try Data("{}".utf8).write(to: source.appendingPathComponent("notes.json"))   // not a recovery copy

        let copies = KudosBackupRecoveryCopy.capture(directory: source)
        #expect(copies.map(\.fileName) == [name])
        KudosBackupRecoveryCopy.apply(copies, directory: target)
        #expect(try WritingTextRecovery(directory: target).load(from: target.appendingPathComponent(name))?.text == "first")

        let newer = WritingTextRecovery.Entry(text: "kept", originalDigest: "x", savedAt: Date(timeIntervalSince1970: 1_700_000_500), accountDigest: nil)
        try JSONEncoder().encode(newer).write(to: target.appendingPathComponent(name))
        KudosBackupRecoveryCopy.apply(copies, directory: target)
        #expect(try WritingTextRecovery(directory: target).load(from: target.appendingPathComponent(name))?.text == "kept")

        let hostile = KudosBackupRecoveryCopy(fileName: "../../outside.json", entry: older)
        KudosBackupRecoveryCopy.apply([hostile], directory: target)
        #expect(!FileManager.default.fileExists(atPath: target.deletingLastPathComponent().appendingPathComponent("outside.json").path))
    }

    @Test func dataFilesTravelOnlyUnderKnownNames() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(KudosBackupDocument.location(for: "mail/updates.json", root: root) != nil)
        #expect(KudosBackupDocument.location(for: "subscriptionScan/user%3Aalice.json", root: root) != nil)
        #expect(KudosBackupDocument.location(for: "mail/cursor.json", root: root) == nil)
        #expect(KudosBackupDocument.location(for: "subscriptionScan/../../x.json", root: root) == nil)

        let json = Data(#"{"items":[]}"#.utf8)
        let scan = "subscriptionScan/user%3Aalice.json"
        KudosBackupDocument.apply([.init(name: scan, data: json, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))], root: root)
        let url = try #require(KudosBackupDocument.location(for: scan, root: root))
        #expect(try Data(contentsOf: url) == json)
        // An older copy does not replace it.
        KudosBackupDocument.apply([.init(name: scan, data: Data("{}".utf8), modifiedAt: Date(timeIntervalSince1970: 1_600_000_000))], root: root)
        #expect(try Data(contentsOf: url) == json)
        #expect(KudosBackupDocument.capture(root: root).map(\.name) == [scan])
    }

    /// Codex's third review: a stale device that refreshed its mail (so its file is newer) must
    /// not erase a choice made later on another device.
    @Test func aStaleMailRefreshKeepsTheOtherDevicesLaterChoice() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSubscriptionUpdateStore(directoryURL: root.appendingPathComponent("KudosMail", isDirectory: true))
        // This device decided "Not for me" on work 7 at 1,000; work 9 was saved here at 1,000.
        try store.saveState(SubscriptionUpdateState(decisions: [
            SubscriptionDecision(workID: 7, action: .notForMe, decidedAt: Date(timeIntervalSince1970: 1_000)),
            SubscriptionDecision(workID: 9, action: .saved, decidedAt: Date(timeIntervalSince1970: 1_000))
        ]))
        // The stale device's copy: refreshed later, an older choice on work 7, a newer one on 9,
        // an undated one (an older build) on 7 too, and a choice for a new work 11.
        let stale = SubscriptionUpdateState(
            lastRefreshAt: Date(timeIntervalSince1970: 5_000),
            decisions: [
                SubscriptionDecision(workID: 7, action: .saved, decidedAt: Date(timeIntervalSince1970: 500)),
                SubscriptionDecision(workID: 9, action: .notForMe, decidedAt: Date(timeIntervalSince1970: 2_000)),
                SubscriptionDecision(workID: 11, action: .saved)
            ]
        )
        KudosBackupDocument.apply([.init(name: "mail/updates.json", data: try JSONEncoder().encode(stale),
                                         modifiedAt: Date(timeIntervalSince1970: 5_000))], root: root)
        let merged = try store.loadState()
        let actions = Dictionary(uniqueKeysWithValues: merged.decisions.map { ($0.workID, $0.action) })
        #expect(actions[7] == .notForMe)
        #expect(actions[9] == .notForMe)
        #expect(actions[11] == .saved)
        #expect(merged.lastRefreshAt == Date(timeIntervalSince1970: 5_000))
        // An undated choice never beats a dated one.
        let undated = SubscriptionUpdateState(decisions: [SubscriptionDecision(workID: 7, action: .saved)])
        #expect(SubscriptionUpdateState.merged(local: merged, incoming: undated).decisions.first { $0.workID == 7 }?.action == .notForMe)
    }

    /// Codex's third review: one malformed entry used to drop every writing draft in the archive.
    @Test func oneMalformedEntryLosesOnlyItself() throws {
        let json = Data(#"[{"name":"subscriptionScan/a.json","data":"e30=","modifiedAt":0},{"name":7},"x",{"name":"subscriptionScan/b.json","data":"e30=","modifiedAt":0}]"#.utf8)
        let decoded = try JSONDecoder().decode(LossyArray<KudosBackupDocument>.self, from: json)
        #expect(decoded.values.map(\.name) == ["subscriptionScan/a.json", "subscriptionScan/b.json"])
        #expect(decoded.skipped == 2)
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

    // MARK: Review 7 (merge with the integration branch's named settings)

    private func settingsThroughJSON(_ settings: KudosBackupSettings, tweak: (inout [String: Any]) -> Void = { _ in })
        throws -> KudosBackupSettings {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        tweak(&object)
        return try JSONDecoder().decode(KudosBackupSettings.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func anOlderNamedValueLosesAndANewerIndependentOneWinsThroughAManifest() throws {
        let key = InsightsOptions.Keys.countReadAloud
        let other = InsightsOptions.Keys.discreetMode
        let defaults = freshDefaults()
        defaults.set(true, forKey: key)
        defaults.set(false, forKey: other)
        _ = KudosBackupSettings.capture(defaults: defaults)           // baseline
        defaults.set(false, forKey: key)
        SyncedSettingsClock.noteLocalChanges(keys: [key], in: defaults, now: t0)
        defaults.set(true, forKey: key)
        SyncedSettingsClock.noteLocalChanges(keys: [key], in: defaults, now: t0)

        var incoming = KudosBackupSettings.capture(defaults: freshDefaults())
        incoming.countReadAloud = false
        incoming.discreetMode = true
        incoming.modifiedAt = [key: t0.addingTimeInterval(-600), other: t0.addingTimeInterval(300)]
        try settingsThroughJSON(incoming).apply(to: defaults, fromSync: true)
        #expect(defaults.bool(forKey: key))                 // older: kept here
        #expect(defaults.bool(forKey: other))               // newer, independent: taken

        // The reader's own restore takes the file's value whatever its date.
        try settingsThroughJSON(incoming).apply(to: defaults)
        #expect(!defaults.bool(forKey: key))

        // A stampless copy still fills a device that never touched the setting.
        let fresh = freshDefaults()
        incoming.modifiedAt = nil
        try settingsThroughJSON(incoming).apply(to: fresh, fromSync: true)
        #expect(fresh.object(forKey: key) != nil && !fresh.bool(forKey: key))
    }

    @Test func aMalformedNamedSettingNeverErasesTheOneHere() throws {
        let key = InsightsOptions.Keys.excludedTags
        let defaults = freshDefaults()
        defaults.set(["Slow Burn"], forKey: key)
        _ = KudosBackupSettings.capture(defaults: defaults)
        var incoming = KudosBackupSettings.capture(defaults: freshDefaults())
        incoming.modifiedAt = [key: t0.addingTimeInterval(300)]
        let broken = try settingsThroughJSON(incoming) { $0["excludedTags"] = "Slow Burn" }

        broken.apply(to: defaults, fromSync: true)
        #expect(defaults.stringArray(forKey: key) == ["Slow Burn"])
        broken.apply(to: defaults)                           // manual restore, whatever the stamp
        #expect(defaults.stringArray(forKey: key) == ["Slow Burn"])

        // A real omission with its own stamp is still a reset.
        try settingsThroughJSON(incoming).apply(to: defaults, fromSync: true)
        #expect(defaults.object(forKey: key) == nil)
    }

    @Test func theVoiceIDAndNameTravelAsOneSetting() throws {
        let id = ReaderSpeechPreferences.voiceIDKey
        let name = ReaderSpeechPreferences.voiceNameKey
        func local(nameStampedAt: Date) -> UserDefaults {
            let defaults = freshDefaults()
            defaults.set("af_bella", forKey: id)
            defaults.set("Bella", forKey: name)
            _ = KudosBackupSettings.capture(defaults: defaults)
            defaults.set("Bella ", forKey: id)
            defaults.set("Bella!", forKey: name)
            SyncedSettingsClock.noteLocalChanges(keys: [id, name], in: defaults, now: t0)
            defaults.set("af_bella", forKey: id)
            defaults.set("Bella", forKey: name)
            SyncedSettingsClock.noteLocalChanges(keys: [id], in: defaults, now: t0)
            SyncedSettingsClock.noteLocalChanges(keys: [name], in: defaults, now: nameStampedAt)
            return defaults
        }
        var incoming = KudosBackupSettings.capture(defaults: freshDefaults())

        // The same voice, its label refreshed on another device: the newer label arrives.
        let refreshed = local(nameStampedAt: t0)
        incoming.readerSpeechVoiceID = "af_bella"
        incoming.readerSpeechVoiceName = "Bella (US)"
        incoming.modifiedAt = [id: t0, name: t0.addingTimeInterval(300)]
        try settingsThroughJSON(incoming).apply(to: refreshed, fromSync: true)
        #expect(refreshed.string(forKey: name) == "Bella (US)")

        // A different voice wins without a name: the old label goes, and that is no local edit.
        let swapped = local(nameStampedAt: t0)
        incoming.readerSpeechVoiceID = "bm_lewis"
        incoming.readerSpeechVoiceName = nil
        incoming.modifiedAt = [id: t0.addingTimeInterval(300), name: t0.addingTimeInterval(300)]
        try settingsThroughJSON(incoming).apply(to: swapped, fromSync: true)
        #expect(swapped.string(forKey: id) == "bm_lewis")
        #expect(swapped.object(forKey: name) == nil)
        #expect(!SyncedSettingsClock.stampChanges(keys: [id, name], in: swapped))
        #expect(KudosBackupSettings.capture(defaults: swapped).modifiedAt?[name] == t0.addingTimeInterval(300))

        // This device's own newer label keeps the whole pair: no new ID with the old device's label.
        let newerHere = local(nameStampedAt: t0.addingTimeInterval(600))
        incoming.readerSpeechVoiceID = "bm_lewis"
        incoming.readerSpeechVoiceName = "Lewis"
        try settingsThroughJSON(incoming).apply(to: newerHere, fromSync: true)
        #expect(newerHere.string(forKey: id) == "af_bella")
        #expect(newerHere.string(forKey: name) == "Bella")
    }

    private func bellaHere() -> UserDefaults {
        let defaults = freshDefaults()
        defaults.set("af_bella", forKey: ReaderSpeechPreferences.voiceIDKey)
        defaults.set("Bella", forKey: ReaderSpeechPreferences.voiceNameKey)
        _ = KudosBackupSettings.capture(defaults: defaults)
        defaults.set("af_bella ", forKey: ReaderSpeechPreferences.voiceIDKey)
        SyncedSettingsClock.noteLocalChanges(
            keys: [ReaderSpeechPreferences.voiceIDKey, ReaderSpeechPreferences.voiceNameKey],
            in: defaults, now: t0
        )
        defaults.set("af_bella", forKey: ReaderSpeechPreferences.voiceIDKey)
        SyncedSettingsClock.noteLocalChanges(
            keys: [ReaderSpeechPreferences.voiceIDKey, ReaderSpeechPreferences.voiceNameKey],
            in: defaults, now: t0
        )
        return defaults
    }

    @Test func aMalformedVoiceNameMakesTheWholeIncomingPairInvalid() throws {
        let id = ReaderSpeechPreferences.voiceIDKey
        let name = ReaderSpeechPreferences.voiceNameKey
        var incoming = KudosBackupSettings.capture(defaults: freshDefaults())
        incoming.readerSpeechVoiceID = "bm_lewis"
        incoming.modifiedAt = [id: t0.addingTimeInterval(-100), name: t0.addingTimeInterval(300)]
        let broken = try settingsThroughJSON(incoming) { $0["readerSpeechVoiceName"] = 42 }
        for fromSync in [true, false] {
            let defaults = bellaHere()
            broken.apply(to: defaults, fromSync: fromSync)
            #expect(defaults.string(forKey: id) == "af_bella")
            #expect(defaults.string(forKey: name) == "Bella")
            #expect(!SyncedSettingsClock.stampChanges(keys: [id, name], in: defaults))
        }
    }

    @Test func aNewerVoiceResetClearsBothAndAnOlderOneClearsNeither() throws {
        let id = ReaderSpeechPreferences.voiceIDKey
        let name = ReaderSpeechPreferences.voiceNameKey
        var reset = KudosBackupSettings.capture(defaults: freshDefaults())
        reset.modifiedAt = [id: t0.addingTimeInterval(-1), name: t0.addingTimeInterval(300)]
        for fromSync in [true, false] {
            let defaults = bellaHere()
            try settingsThroughJSON(reset).apply(to: defaults, fromSync: fromSync)
            #expect(defaults.object(forKey: id) == nil)
            #expect(defaults.object(forKey: name) == nil)
            #expect(!SyncedSettingsClock.stampChanges(keys: [id, name], in: defaults))
        }
        reset.modifiedAt = [id: t0.addingTimeInterval(-1), name: t0.addingTimeInterval(-5)]
        let kept = bellaHere()
        try settingsThroughJSON(reset).apply(to: kept, fromSync: true)
        #expect(kept.string(forKey: id) == "af_bella")
        #expect(kept.string(forKey: name) == "Bella")
    }

    @Test func aStampedLabelOmissionClearsTheLabelOfARetainedVoiceButAnUnstampedOneDoesNot() throws {
        let name = ReaderSpeechPreferences.voiceNameKey
        var incoming = KudosBackupSettings.capture(defaults: freshDefaults())
        incoming.readerSpeechVoiceID = "af_bella"
        incoming.modifiedAt = [ReaderSpeechPreferences.voiceIDKey: t0, name: t0.addingTimeInterval(300)]
        let cleared = bellaHere()
        try settingsThroughJSON(incoming).apply(to: cleared, fromSync: true)
        #expect(cleared.object(forKey: name) == nil)

        incoming.modifiedAt = nil
        let kept = bellaHere()
        try settingsThroughJSON(incoming).apply(to: kept, fromSync: true)
        #expect(kept.string(forKey: name) == "Bella")
    }

    @Test func anArchiveWithoutBylinesLeavesALocalWorksBylinesAlone() throws {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let id = UUID()
        let local = SavedWork(id: id, title: "Bylines", author: "Someone")
        local.authorIdentitiesJSON = #"[{"username":"someone","pseud":"Someone"}]"#
        context.insert(local)
        let older = SavedWork(id: id, title: "Bylines", author: "Someone")
        older.lastModifiedAt = Date().addingTimeInterval(3600)   // newer than the local work, no bylines
        let contents = try KudosBackupService.makeContents(
            works: [older], bookmarks: [], fonts: [], readingQueues: [], defaults: freshDefaults()
        )
        for fromSync in [true, false] {
            _ = try KudosBackupService.restore(contents, into: context, defaults: freshDefaults(), fromSync: fromSync)
            let works = try context.fetch(FetchDescriptor<SavedWork>())
            #expect(works.first?.authorIdentitiesJSON == #"[{"username":"someone","pseud":"Someone"}]"#)
        }
    }

    @Test func aLayoutLearnedWithoutAnEditStampStillGetsItsResetSent() throws {
        let key = "collection.0F0F0F0F.arrangement"
        let defaults = freshDefaults()
        _ = KudosBackupSettings.capture(defaults: defaults)
        var incoming = KudosBackupSettings.capture(defaults: freshDefaults())
        incoming.extras = [key: .string("grid")]
        try settingsThroughJSON(incoming).apply(to: defaults, fromSync: true, archiveDate: t0)
        #expect(defaults.string(forKey: key) == "grid")
        defaults.removeObject(forKey: key)
        #expect(KudosBackupSettings.capture(defaults: defaults).modifiedAt?[key] != nil)
    }

    @Test func aWorksBylinesTravelInAnArchive() throws {
        let work = SavedWork(title: "Bylines", author: "Someone")
        work.authorIdentitiesJSON = #"[{"username":"someone","pseud":"Someone"}]"#
        let data = try JSONEncoder().encode(KudosBackupWork(work: work))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["authorIdentitiesJSON"] as? String == work.authorIdentitiesJSON)
        #expect(try JSONDecoder().decode(KudosBackupWork.self, from: data).authorIdentitiesJSON
            == work.authorIdentitiesJSON)
    }
}
