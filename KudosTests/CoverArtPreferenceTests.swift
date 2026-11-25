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

    private func stripped(_ contents: KudosBackupContents) throws -> KudosBackupContents {
        var root = try #require(try JSONSerialization.jsonObject(with: contents.manifestData()) as? [String: Any])
        var works = try #require(root["works"] as? [[String: Any]])
        for index in works.indices { works[index].removeValue(forKey: "coverArtPreference") }
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
}
}
