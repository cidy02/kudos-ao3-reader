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

    private func work(id: UUID, raw: String?, modifiedAt: TimeInterval, in context: ModelContext) -> SavedWork {
        let work = SavedWork(id: id, title: "Covered", author: "Writer")
        work.hasEPUB = false
        work.coverArtPreferenceRaw = raw
        work.markModified(Date(timeIntervalSince1970: modifiedAt))
        context.insert(work)
        return work
    }

    private func contents(_ work: SavedWork) throws -> KudosBackupContents {
        try KudosBackupService.makeContents(works: [work], bookmarks: [], fonts: [], readingQueues: [],
                                            defaults: try testDefaults())
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
                #expect(CoverArtPreference.showsEmbeddedArt(override: nil, global: global, hasArt: hasArt) == (global && hasArt))
            }
        }
    }

    @Test func anUnknownValueIsKeptButReadAsFollowSettings() throws {
        #expect(CoverArtPreference.resolved("sepia-photo") == nil)
        #expect(CoverArtPreference.wantsEmbeddedArt(override: "sepia-photo", global: true))
        #expect(CoverArtPreference.wantsEmbeddedArt(override: "sepia-photo", global: false) == false)

        let context = try makeContext()
        let id = UUID()
        let archive = try contents(work(id: id, raw: "sepia-photo", modifiedAt: 9_000, in: context))
        let fresh = try makeContext()
        _ = try KudosBackupService.restore(archive, into: fresh, defaults: try testDefaults(), mode: .replaceLibrary)
        #expect(try fresh.fetch(FetchDescriptor<SavedWork>()).first?.coverArtPreferenceRaw == "sepia-photo")
    }

    @Test func aReadersEditIsStampedAndFollowSettingsClearsIt() {
        let work = SavedWork(title: "Edit", author: "Writer")
        work.markModified(Date(timeIntervalSince1970: 1_000))
        work.setCoverArtPreference(.generated)
        #expect(work.coverArtPreferenceRaw == "generated")
        #expect(work.lastModifiedAt > Date(timeIntervalSince1970: 1_000))
        work.setCoverArtPreference(nil)
        #expect(work.coverArtPreferenceRaw == CoverArtPreference.followRaw)
        #expect(CoverArtPreference.resolved(work.coverArtPreferenceRaw) == nil)
        let untouched = SavedWork(title: "Never chosen", author: "Writer")
        untouched.setCoverArtPreference(nil)
        #expect(untouched.coverArtPreferenceRaw == nil, "a work that never had a choice stays unset")
    }

    /// A reset to Follow Settings must reach a device that still holds the old choice.
    @Test func aResetToFollowSettingsReachesOtherDevices() throws {
        let id = UUID()
        let remote = try makeContext()
        let reset = try contents(work(id: id, raw: CoverArtPreference.followRaw, modifiedAt: 9_000, in: remote))
        let other = try makeContext()
        let theirs = work(id: id, raw: "generated", modifiedAt: 1_000, in: other)
        try other.save()
        _ = try KudosBackupService.restore(reset, into: other, defaults: try testDefaults(), mode: .reconcile)
        #expect(theirs.coverArtPreferenceRaw == CoverArtPreference.followRaw)
        #expect(CoverArtPreference.wantsEmbeddedArt(override: theirs.coverArtPreferenceRaw, global: true))
    }

    // MARK: Backup and merge

    @Test func theKeyRoundTripsAndIsOmittedWhenTheWorkFollowsSettings() throws {
        let context = try makeContext()
        let chosen = work(id: UUID(), raw: "embedded", modifiedAt: 9_000, in: context)
        let json = try #require(try JSONSerialization.jsonObject(with: try contents(chosen).manifestData())
            as? [String: Any])
        let entry = try #require((json["works"] as? [[String: Any]])?.first)
        #expect(entry["coverArtPreference"] as? String == "embedded")

        let following = work(id: UUID(), raw: nil, modifiedAt: 9_000, in: context)
        let followJSON = try #require(try JSONSerialization.jsonObject(with: try contents(following).manifestData())
            as? [String: Any])
        #expect((followJSON["works"] as? [[String: Any]])?.first?["coverArtPreference"] == nil)

        let fresh = try makeContext()
        _ = try KudosBackupService.restore(try contents(chosen), into: fresh, defaults: try testDefaults(),
                                           mode: .replaceLibrary)
        #expect(try fresh.fetch(FetchDescriptor<SavedWork>()).first?.coverArtPreferenceRaw == "embedded")
    }

    @Test func anArchiveWithoutTheKeyNeverClearsALocalChoice() throws {
        let id = UUID()
        let remote = try makeContext()
        let archive = try stripped(try contents(work(id: id, raw: "generated", modifiedAt: 9_000, in: remote)))
        #expect(try #require(archive.manifest.works.first).coverArtPreference == nil)

        let local = try makeContext()
        let mine = work(id: id, raw: "embedded", modifiedAt: 1_000, in: local)
        try local.save()
        _ = try KudosBackupService.restore(archive, into: local, defaults: try testDefaults(), mode: .reconcile)
        #expect(mine.coverArtPreferenceRaw == "embedded")
    }

    @Test func aNewerEditWinsAndAnOlderOneDoesNot() throws {
        let id = UUID()
        let remote = try makeContext()
        let newer = try contents(work(id: id, raw: "generated", modifiedAt: 9_000, in: remote))

        let stale = try makeContext()
        let old = work(id: id, raw: "embedded", modifiedAt: 1_000, in: stale)
        try stale.save()
        _ = try KudosBackupService.restore(newer, into: stale, defaults: try testDefaults(), mode: .reconcile)
        #expect(old.coverArtPreferenceRaw == "generated")

        let remoteOlder = try makeContext()
        let older = try contents(work(id: id, raw: "generated", modifiedAt: 1_000, in: remoteOlder))
        let fresher = try makeContext()
        let mine = work(id: id, raw: "embedded", modifiedAt: 9_000, in: fresher)
        try fresher.save()
        _ = try KudosBackupService.restore(older, into: fresher, defaults: try testDefaults(), mode: .reconcile)
        #expect(mine.coverArtPreferenceRaw == "embedded")
    }
}
}
