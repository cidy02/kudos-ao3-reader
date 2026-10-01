import Foundation
import SwiftData
import Testing
@testable import Kudos

/// A custom "+" colour is stored as picked (`colorHex`, owner call 2026-10-01)
/// and must survive backup, restore and folder sync — including a trip through
/// a build that does not know the field.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ExactColourBackupTests {
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
        let name = "ExactColourBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func chosenColorKeepsAnExactColourAnOlderArchiveDropped() {
        let local: (hue: Double?, hex: String?) = (0.58, "#1E90FF")
        // Same hue, no hex: written by a build without `colorHex`.
        let dropped = SyncMerge.chosenColor(local: local, incoming: (0.58, nil), incomingWins: true)
        #expect(dropped.hue == 0.58 && dropped.hex == "#1E90FF")
        // A different hue that wins is a real recolour, to a preset.
        let preset = SyncMerge.chosenColor(local: local, incoming: (0.0663, nil), incomingWins: true)
        #expect(preset.hue == 0.0663 && preset.hex == nil)
        // An exact colour that wins replaces the local one.
        let picked = SyncMerge.chosenColor(local: local, incoming: (0.95, "#E0457B"), incomingWins: true)
        #expect(picked.hue == 0.95 && picked.hex == "#E0457B")
        // Losing, or carrying no hue at all, changes nothing.
        let lost = SyncMerge.chosenColor(local: local, incoming: (0.95, "#E0457B"), incomingWins: false)
        #expect(lost.hue == 0.58 && lost.hex == "#1E90FF")
        let silent = SyncMerge.chosenColor(local: local, incoming: (nil, nil), incomingWins: true)
        #expect(silent.hue == 0.58 && silent.hex == "#1E90FF")
        // A colourless local queue takes the archive's, exact or not.
        let filled = SyncMerge.chosenColor(local: (nil, nil), incoming: (0.95, "#E0457B"), incomingWins: false)
        #expect(filled.hue == 0.95 && filled.hex == "#E0457B")
    }

    /// The archived record writes the key, and an archive without it (older
    /// build, Android) still decodes, as no exact colour.
    @Test func archivedQueueCarriesColorHexAndOlderArchivesDecode() throws {
        let context = try makeContext()
        let queue = ReadingQueue(name: "Picked")
        queue.hue = 0.58
        queue.colorHex = "#1E90FF"
        context.insert(queue)

        let data = try JSONEncoder().encode(KudosBackupReadingQueue(queue: queue))
        #expect(try JSONDecoder().decode(KudosBackupReadingQueue.self, from: data).colorHex == "#1E90FF")

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "colorHex")
        let older = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(KudosBackupReadingQueue.self, from: older)
        #expect(decoded.colorHex == nil && decoded.hue == 0.58)
    }

    @Test func restoreBringsBackExactQueueAndCollectionColours() throws {
        let source = try makeContext()
        let queue = ReadingQueue(name: "Picked queue")
        queue.hue = 0.58
        queue.colorHex = "#1E90FF"
        let collection = WorkCollection(name: "Picked shelf")
        collection.hue = 0.95
        collection.colorHex = "#E0457B"
        source.insert(queue)
        source.insert(collection)
        try source.save()
        let contents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [],
            collections: [collection], readingQueues: [queue], defaults: try testDefaults()
        )

        let target = try makeContext()
        _ = try KudosBackupService.restore(contents, into: target, defaults: try testDefaults(), mode: .merge)

        let restoredQueue = try #require(try target.fetch(FetchDescriptor<ReadingQueue>()).first { $0.id == queue.id })
        #expect(restoredQueue.colorHex == "#1E90FF" && restoredQueue.hue == 0.58)
        let restoredShelf = try #require(
            try target.fetch(FetchDescriptor<WorkCollection>()).first { $0.id == collection.id }
        )
        #expect(restoredShelf.colorHex == "#E0457B" && restoredShelf.hue == 0.95)
    }
}
}
