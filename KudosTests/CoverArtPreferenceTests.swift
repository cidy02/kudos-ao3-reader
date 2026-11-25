import Foundation
import SwiftData
import Testing
@testable import Kudos

/// T-573: a work's own choice between the generated cover and the art inside its EPUB.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct CoverArtPreferenceTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "CoverArtPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func work(id: UUID, raw: String?, at changed: TimeInterval? = nil, modifiedAt: TimeInterval = 1_000,
                       in context: ModelContext) -> SavedWork {
        let work = SavedWork(id: id, title: "Covered", author: "Writer")
        work.hasEPUB = false
        work.coverArtPreferenceRaw = raw
        work.coverArtPreferenceChangedAt = changed.map { Date(timeIntervalSince1970: $0) }
        work.markModified(Date(timeIntervalSince1970: modifiedAt))
        context.insert(work)
        return work
    }

    /// Through real JSON, so a decoder that drops a key cannot hide behind an in-memory manifest.
    private func contents(_ work: SavedWork) throws -> KudosBackupContents {
        let raw = try KudosBackupService.makeContents(works: [work], bookmarks: [], fonts: [], readingQueues: [],
                                                      defaults: try testDefaults())
        return KudosBackupContents(manifest: try KudosBackupContents.decodeManifest(try raw.manifestData()))
    }

    private func stripped(_ contents: KudosBackupContents, key: String = "coverArtPreference") throws -> KudosBackupContents {
        var root = try #require(try JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any])
        var works = try #require(root["works"] as? [[String: Any]])
        for index in works.indices { works[index].removeValue(forKey: key) }
        root["works"] = works
        return KudosBackupContents(manifest: try KudosBackupContents.decodeManifest(
            try JSONSerialization.data(withJSONObject: root)))
    }

    // MARK: Resolution

    @Test func resolutionIsOverrideThenGlobalThenHasArt() {
        for global in [true, false] {
            for hasArt in [true, false] {
                #expect(CoverArtPreference.showsEmbeddedArt(override: "generated", global: global, hasArt: hasArt) == false)
                #expect(CoverArtPreference.showsEmbeddedArt(override: "embedded", global: global, hasArt: hasArt) == hasArt)
                for follows in [nil, CoverArtPreference.followRaw, "sepia-photo"] {
                    #expect(CoverArtPreference.showsEmbeddedArt(override: follows, global: global, hasArt: hasArt)
                        == (global && hasArt))
                }
            }
        }
    }

    @Test func anUnknownValueIsKeptThroughBackupAndUntouchedBySelectingFollow() throws {
        let context = try makeContext()
        let id = UUID()
        let archive = try contents(work(id: id, raw: "sepia-photo", at: 5_000, in: context))
        let fresh = try makeContext()
        _ = try KudosBackupService.restore(archive, into: fresh, defaults: try testDefaults(), mode: .replaceLibrary)
        let restored = try #require(try fresh.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.coverArtPreferenceRaw == "sepia-photo")

        restored.setCoverArtPreference(nil) // the already-selected "Follow Settings"
        #expect(restored.coverArtPreferenceRaw == "sepia-photo")
        #expect(restored.coverArtPreferenceChangedAt == Date(timeIntervalSince1970: 5_000))
    }

    @Test func aReadersEditStampsItsOwnClockMonotonically() {
        let work = SavedWork(title: "Edit", author: "Writer")
        let ahead = Date().addingTimeInterval(600) // a clock that ran fast on an earlier edit
        work.coverArtPreferenceChangedAt = ahead
        work.setCoverArtPreference(.generated)
        #expect(work.coverArtPreferenceRaw == "generated")
        #expect(work.coverArtPreferenceChangedAt! >= ahead.addingTimeInterval(0.001))
        let first = work.coverArtPreferenceChangedAt!
        work.setCoverArtPreference(.generated) // same option: no write
        #expect(work.coverArtPreferenceChangedAt == first)
        work.setCoverArtPreference(nil)
        #expect(work.coverArtPreferenceRaw == CoverArtPreference.followRaw)
        #expect(work.coverArtPreferenceChangedAt! > first)
        let untouched = SavedWork(title: "Never chosen", author: "Writer")
        untouched.setCoverArtPreference(nil)
        #expect(untouched.coverArtPreferenceRaw == nil && untouched.coverArtPreferenceChangedAt == nil)
    }

    // MARK: Backup and merge

    @Test func bothKeysDecodeFromJSONAndAreOmittedForAWorkWithoutAChoice() throws {
        let context = try makeContext()
        let chosen = work(id: UUID(), raw: "embedded", at: 5_000, in: context)
        let json = try #require(try JSONSerialization.jsonObject(with: try contents(chosen).manifestData())
            as? [String: Any])
        let entry = try #require((json["works"] as? [[String: Any]])?.first)
        #expect(entry["coverArtPreference"] as? String == "embedded")
        #expect(entry["coverArtPreferenceChangedAt"] != nil)
        let decoded = try #require(try contents(chosen).manifest.works.first)
        #expect(decoded.coverArtPreference == "embedded")
        #expect(decoded.coverArtPreferenceChangedAt == Date(timeIntervalSince1970: 5_000))

        let following = work(id: UUID(), raw: nil, in: context)
        let followJSON = try #require(try JSONSerialization.jsonObject(with: try contents(following).manifestData())
            as? [String: Any])
        let followEntry = try #require((followJSON["works"] as? [[String: Any]])?.first)
        #expect(followEntry["coverArtPreference"] == nil && followEntry["coverArtPreferenceChangedAt"] == nil)

        let fresh = try makeContext()
        _ = try KudosBackupService.restore(try contents(chosen), into: fresh, defaults: try testDefaults(),
                                           mode: .replaceLibrary)
        let restored = try #require(try fresh.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.coverArtPreferenceRaw == "embedded")
        #expect(restored.coverArtPreferenceChangedAt == Date(timeIntervalSince1970: 5_000))
    }

    @Test func anArchiveWithoutTheKeyNeverClearsALocalChoice() throws {
        let id = UUID()
        let remote = try makeContext()
        let archive = try stripped(try contents(work(id: id, raw: "generated", at: 9_000, modifiedAt: 9_000, in: remote)))
        #expect(try #require(archive.manifest.works.first).coverArtPreference == nil)
        for mode in [BackupImportMode.reconcile, .replaceLibrary] {
            let local = try makeContext()
            let mine = work(id: id, raw: "embedded", at: 1_000, in: local)
            try local.save()
            _ = try KudosBackupService.restore(archive, into: local, defaults: try testDefaults(), mode: mode)
            #expect(mine.coverArtPreferenceRaw == "embedded")
        }
    }

    /// The review's scenario: this copy was only read (newer lastModifiedAt, no choice).
    @Test func aPeersChoiceSurvivesALocalCopyWithANewerWorkClockButNoChoice() throws {
        let id = UUID()
        let remote = try makeContext()
        let archive = try contents(work(id: id, raw: "generated", at: 500, modifiedAt: 500, in: remote))
        let local = try makeContext()
        let read = work(id: id, raw: nil, modifiedAt: 9_000, in: local)
        try local.save()
        _ = try KudosBackupService.restore(archive, into: local, defaults: try testDefaults(), mode: .reconcile)
        #expect(read.coverArtPreferenceRaw == "generated")
        #expect(read.coverArtPreferenceChangedAt == Date(timeIntervalSince1970: 500))
    }

    @Test func theNewerStampWinsEitherWayRound() throws {
        let id = UUID()
        let remote = try makeContext()
        let newer = try contents(work(id: id, raw: "generated", at: 9_000, modifiedAt: 1, in: remote))
        let stale = try makeContext()
        let old = work(id: id, raw: "embedded", at: 1_000, modifiedAt: 9_999, in: stale)
        try stale.save()
        _ = try KudosBackupService.restore(newer, into: stale, defaults: try testDefaults(), mode: .reconcile)
        #expect(old.coverArtPreferenceRaw == "generated")

        let remoteOlder = try makeContext()
        let older = try contents(work(id: id, raw: "generated", at: 1_000, modifiedAt: 9_999, in: remoteOlder))
        let fresher = try makeContext()
        let mine = work(id: id, raw: "embedded", at: 9_000, modifiedAt: 1, in: fresher)
        try fresher.save()
        _ = try KudosBackupService.restore(older, into: fresher, defaults: try testDefaults(), mode: .reconcile)
        #expect(mine.coverArtPreferenceRaw == "embedded")
    }

    @Test func aResetToFollowWithANewerStampReachesOtherDevices() throws {
        let id = UUID()
        let remote = try makeContext()
        let reset = try contents(work(id: id, raw: CoverArtPreference.followRaw, at: 9_000, in: remote))
        let other = try makeContext()
        let theirs = work(id: id, raw: "generated", at: 1_000, modifiedAt: 9_999, in: other)
        try other.save()
        _ = try KudosBackupService.restore(reset, into: other, defaults: try testDefaults(), mode: .reconcile)
        #expect(theirs.coverArtPreferenceRaw == CoverArtPreference.followRaw)
        #expect(CoverArtPreference.wantsEmbeddedArt(override: theirs.coverArtPreferenceRaw, global: true))
    }

    /// A device whose clock ran 10 minutes fast edited first; the later edit on a correct clock
    /// still gets a newer stamp locally (monotonic) and so wins there and after sync.
    @Test func clockSkewWithinTheAllowedWindowStillLetsTheLatestEditWin() throws {
        let id = UUID()
        let fastDevice = try makeContext()
        let fast = work(id: id, raw: nil, in: fastDevice)
        fast.coverArtPreferenceChangedAt = Date().addingTimeInterval(600)
        fast.coverArtPreferenceRaw = "generated"
        let archive = try contents(fast)

        let phone = try makeContext()
        let theirs = work(id: id, raw: nil, in: phone)
        try phone.save()
        _ = try KudosBackupService.restore(archive, into: phone, defaults: try testDefaults(), mode: .reconcile)
        #expect(theirs.coverArtPreferenceRaw == "generated")
        theirs.setCoverArtPreference(.embedded) // later in real time, but the stamp still moves forward
        #expect(theirs.coverArtPreferenceChangedAt! > fast.coverArtPreferenceChangedAt!)

        let back = try contents(theirs)
        _ = try KudosBackupService.restore(back, into: fastDevice, defaults: try testDefaults(), mode: .reconcile)
        #expect(fast.coverArtPreferenceRaw == "embedded")
    }

    // MARK: Contract update 2

    /// Every row of the merge table (Merge / Reconcile / Folder Sync), both directions where it matters.
    @Test func theMergeTableDecidesEveryRow() {
        let now = Date(timeIntervalSince1970: 100_000)
        let t1 = Date(timeIntervalSince1970: 1_000), t2 = Date(timeIntervalSince1970: 2_000)
        func wins(_ lr: String?, _ ls: Date?, _ ir: String, _ istamp: Date?) -> Bool {
            CoverArtPreference.incomingWins(localRaw: lr, localStamp: ls, incomingRaw: ir, incomingStamp: istamp, now: now)
        }
        #expect(wins("generated", t1, "embedded", t2))            // stamped vs stamped: newer wins
        #expect(wins("generated", t2, "embedded", t1) == false)
        #expect(wins("embedded", t1, "generated", t1))             // equal stamps: greater value wins, on both devices
        #expect(wins("generated", t1, "embedded", t1) == false)
        #expect(wins("generated", t1, "embedded", nil) == false)   // stamped local beats unstamped incoming
        #expect(wins("generated", nil, "embedded", t1))            // unstamped local loses to stamped incoming
        #expect(wins("embedded", nil, "generated", nil))           // unstamped vs unstamped: greater value
        #expect(wins("generated", nil, "embedded", nil) == false)
        #expect(wins("embedded", nil, "follow", nil))              // an older unstamped archive can only
        #expect(wins("follow", nil, "embedded", nil) == false)     // win by value, so both devices agree
        #expect(wins(nil, nil, "follow", nil))                     // nil local takes any present value
        #expect(wins(nil, nil, "embedded", t1))
        // a far-future stamp is clamped to now + skew on both sides
        let far = now.addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew * 3)
        #expect(wins("generated", far, "embedded", far.addingTimeInterval(500)) == false) // equal once clamped: "embedded" < "generated"
        #expect(wins("embedded", far, "generated", far.addingTimeInterval(500)))
    }

    @Test func aCoverEditLeavesTheWorkClockAloneAndHealsAFarFutureStamp() {
        let work = SavedWork(title: "Edit", author: "Writer")
        let clock = Date(timeIntervalSince1970: 1_234)
        work.markModified(clock)
        work.setCoverArtPreference(.generated)
        #expect(work.lastModifiedAt == clock, "a cover edit must not override concurrent edits elsewhere")

        let first = work.coverArtPreferenceChangedAt!
        work.setCoverArtPreference(.embedded)
        #expect(work.coverArtPreferenceChangedAt! >= first.addingTimeInterval(0.002))

        work.coverArtPreferenceChangedAt = Date().addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew * 3)
        work.setCoverArtPreference(.generated) // a fast clock's stamp counts as now on the next edit
        let ceiling = Date().addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew)
        #expect(work.coverArtPreferenceChangedAt! <= ceiling)
        #expect(work.coverArtPreferenceChangedAt! < Date().addingTimeInterval(60))
    }

    @Test func replaceLibraryAdoptsAnyPresentValueSoARestoreRollsBack() throws {
        let id = UUID()
        let snapshotSource = try makeContext()
        let snapshot = try contents(work(id: id, raw: "embedded", at: 1_000, in: snapshotSource))
        let local = try makeContext()
        let mine = work(id: id, raw: "generated", at: 2_000, in: local) // edited after the backup
        try local.save()
        _ = try KudosBackupService.restore(snapshot, into: local, defaults: try testDefaults(), mode: .replaceLibrary)
        #expect(mine.coverArtPreferenceRaw == "embedded")

        // An unstamped (Android) export replaces a stamped local choice too.
        let androidSource = try makeContext()
        let android = try stripped(try contents(work(id: id, raw: "generated", at: 1, in: androidSource)),
                                   key: "coverArtPreferenceChangedAt")
        #expect(try #require(android.manifest.works.first).coverArtPreferenceChangedAt == nil)
        let other = try makeContext()
        let theirs = work(id: id, raw: "embedded", at: 5_000, in: other)
        try other.save()
        _ = try KudosBackupService.restore(android, into: other, defaults: try testDefaults(), mode: .replaceLibrary)
        #expect(theirs.coverArtPreferenceRaw == "generated")
        #expect(theirs.coverArtPreferenceChangedAt == nil)
    }

    @Test func anUnstampedAndroidExportNeverBeatsAStampedLocalChoiceInEveryMergeMode() throws {
        let id = UUID()
        let source = try makeContext()
        let android = try stripped(try contents(work(id: id, raw: "generated", at: 1, in: source)),
                                   key: "coverArtPreferenceChangedAt")
        for mode in [BackupImportMode.reconcile, .merge] {
            let local = try makeContext()
            let mine = work(id: id, raw: "embedded", at: 1_000, in: local)
            try local.save()
            _ = try KudosBackupService.restore(android, into: local, defaults: try testDefaults(), mode: mode)
            #expect(mine.coverArtPreferenceRaw == "embedded")
        }
        // Reconcile fills a work that has no choice at all; Merge leaves an existing work entirely alone
        // but gives a work it adds the archived value.
        let bare = try makeContext()
        let empty = work(id: id, raw: nil, in: bare)
        try bare.save()
        _ = try KudosBackupService.restore(android, into: bare, defaults: try testDefaults(), mode: .merge)
        #expect(empty.coverArtPreferenceRaw == nil)
        _ = try KudosBackupService.restore(android, into: bare, defaults: try testDefaults(), mode: .reconcile)
        #expect(empty.coverArtPreferenceRaw == "generated")
        let added = try makeContext()
        _ = try KudosBackupService.restore(android, into: added, defaults: try testDefaults(), mode: .merge)
        #expect(try added.fetch(FetchDescriptor<SavedWork>()).first?.coverArtPreferenceRaw == "generated")
    }

    @Test func aFutureStampIsClampedWhenItArrives() throws {
        let id = UUID()
        let source = try makeContext()
        let far = Date().addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew * 10)
        let archive = try contents(work(id: id, raw: "generated", at: far.timeIntervalSince1970, in: source))
        let local = try makeContext()
        let mine = work(id: id, raw: nil, in: local)
        try local.save()
        _ = try KudosBackupService.restore(archive, into: local, defaults: try testDefaults(), mode: .reconcile)
        #expect(mine.coverArtPreferenceRaw == "generated")
        #expect(mine.coverArtPreferenceChangedAt! <= Date().addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew + 5))
    }

    @Test func malformedValuesDecodeAsAbsentAndNeverClear() throws {
        let id = UUID()
        let source = try makeContext()
        var root = try #require(try JSONSerialization.jsonObject(
            with: try contents(work(id: id, raw: "generated", at: 9_000, in: source)).manifestData()) as? [String: Any])
        var works = try #require(root["works"] as? [[String: Any]])
        works[0]["coverArtPreference"] = 42            // not a string
        works[0]["coverArtPreferenceChangedAt"] = "yesterday-ish" // not a date
        root["works"] = works
        let archive = KudosBackupContents(manifest: try KudosBackupContents.decodeManifest(
            try JSONSerialization.data(withJSONObject: root)))
        let decoded = try #require(archive.manifest.works.first)
        #expect(decoded.coverArtPreference == nil && decoded.coverArtPreferenceChangedAt == nil)

        let local = try makeContext()
        let mine = work(id: id, raw: "embedded", at: 1_000, in: local)
        try local.save()
        _ = try KudosBackupService.restore(archive, into: local, defaults: try testDefaults(), mode: .reconcile)
        #expect(mine.coverArtPreferenceRaw == "embedded")
    }

    @Test func aMergeThatAdoptsTheChoiceLeavesTheWorkClockToTheUsualRule() throws {
        let id = UUID()
        let remote = try makeContext()
        let archive = try contents(work(id: id, raw: "generated", at: 500, modifiedAt: 500, in: remote))
        let local = try makeContext()
        let read = work(id: id, raw: nil, modifiedAt: 9_000, in: local)
        try local.save()
        _ = try KudosBackupService.restore(archive, into: local, defaults: try testDefaults(), mode: .reconcile)
        #expect(read.coverArtPreferenceRaw == "generated")
        #expect(read.lastModifiedAt == Date(timeIntervalSince1970: 9_000))
    }

    /// Export ("Include Cover") and drawing read the same resolved choice.
    @Test func exportFollowsTheResolvedChoice() throws {
        let defaults = try testDefaults()
        let work = SavedWork(title: "Export", author: "Writer")
        #expect(CoverArtPreference.wantsEmbeddedArt(for: work, defaults: defaults))      // global default on
        defaults.set(false, forKey: "useEmbeddedCoverArt")
        #expect(CoverArtPreference.wantsEmbeddedArt(for: work, defaults: defaults) == false)
        work.coverArtPreferenceRaw = "embedded"
        #expect(CoverArtPreference.wantsEmbeddedArt(for: work, defaults: defaults))
        defaults.set(true, forKey: "useEmbeddedCoverArt")
        work.coverArtPreferenceRaw = "generated"
        #expect(CoverArtPreference.wantsEmbeddedArt(for: work, defaults: defaults) == false)
    }
}
}
