import Foundation
import SwiftData
import Testing
@testable import Kudos

/// An archive that says nothing about a preference must not clear it.
///
/// `keepInProgressOverride` decoded with `?? false`, which made "this archive
/// predates the field" indistinguishable from "the reader turned it off". An
/// older client that had never heard of the override could update a work, win
/// the timestamp comparison, and silently switch off a choice it had no opinion
/// about. The transport field is optional now, and absent is left alone.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct OmittedFieldKeepsPreferenceTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self, ReadingAnnotation.self
        ])
        return ModelContext(try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "OmittedFieldKeepsPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A newer archive for `id`, with `keepInProgressOverride` either carrying
    /// `value` or removed from the JSON entirely — the shape an older client
    /// that never knew the field would write.
    private func archive(
        for id: UUID, carrying value: Bool?, modifiedAt: Date
    ) throws -> KudosBackupContents {
        let staging = try makeContext()
        let archived = SavedWork(id: id, title: "Shared", author: "Writer")
        archived.keepInProgressOverride = value ?? false
        archived.markModified(modifiedAt)
        staging.insert(archived)
        try staging.save()

        let base = try KudosBackupService.makeContents(
            works: [archived], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        guard value == nil else { return base }

        var root = try #require(
            try JSONSerialization.jsonObject(with: base.manifestData()) as? [String: Any]
        )
        var works = try #require(root["works"] as? [[String: Any]])
        works[0].removeValue(forKey: "keepInProgressOverride")
        root["works"] = works
        let stripped = try JSONSerialization.data(withJSONObject: root)
        return KudosBackupContents(manifest: try KudosBackupContents.decodeManifest(stripped))
    }

    private func localWork(in context: ModelContext) throws -> SavedWork {
        let work = SavedWork(id: UUID(), title: "Shared", author: "Writer")
        work.keepInProgressOverride = true
        work.markModified(Date(timeIntervalSince1970: 1_000))
        context.insert(work)
        try context.save()
        return work
    }

    @Test func anArchiveWithoutTheFieldLeavesTheOverrideOn() throws {
        let context = try makeContext()
        let work = try localWork(in: context)

        _ = try KudosBackupService.restore(
            try archive(for: work.id, carrying: nil, modifiedAt: Date(timeIntervalSince1970: 9_000)),
            into: context, defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(work.keepInProgressOverride)
    }

    /// The counterpart: an archive that really does say "off" still turns it off,
    /// or the field could never be synced at all.
    @Test func anArchiveThatSaysOffStillTurnsItOff() throws {
        let context = try makeContext()
        let work = try localWork(in: context)

        _ = try KudosBackupService.restore(
            try archive(for: work.id, carrying: false, modifiedAt: Date(timeIntervalSince1970: 9_000)),
            into: context, defaults: try testDefaults(), mode: .replaceLibrary
        )

        #expect(!work.keepInProgressOverride)
    }
}
}
