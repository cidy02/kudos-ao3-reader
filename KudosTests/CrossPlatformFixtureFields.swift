import Foundation
import SwiftData
import Testing
@testable import Kudos

/// Values shared with Android CrossPlatformFixtureFields. Defaults are never sufficient proof.
@MainActor
struct CrossPlatformFixtureFields {
    static let collectionID = UUID(uuidString: "e0000000-0000-4000-8000-000000000001")!
    static let queueID = UUID(uuidString: "e0000000-0000-4000-8000-000000000002")!
    static let annotationID = UUID(uuidString: "e0000000-0000-4000-8000-000000000003")!
    static let tombstoneID = UUID(uuidString: "c0000000-0000-4000-8000-000000000002")!
    static let fontName = "Kudos Fixture Regular"
    static let fontFile = "kudos-cross-platform-fixture.ttf"
    static let deletedAt = Date(timeIntervalSince1970: 1_700_001_080)
    static let fontDate = Date(timeIntervalSince1970: 1_700_000_060)
    static let pronunciations = KudosBackupPronunciations(
        global: ["Nico": "nˈikoʊ"],
        fandoms: ["Portable Fandom": ["Sam": "sæm"]],
        works: ["820002": ["Sam": "sɑm"]]
    )

    // Original two-glyph TrueType font (.notdef and A), accepted by CoreText/CGFont.
    static let fontBytes = Data(base64Encoded:
        "AAEAAAAKAIAAAwAgT1MvMkoJUIsAAACsAAAATmNtYXAADAB0AAAA/AAAACxnbHlmCXMJcgAAASgAAABEaGVhZGEKQ6EAAAFsAAAA" +
        "NmhoZWEFFgH3AAABpAAAACRobXR4BLAAAAAAAcgAAAAIbG9jYQAiABEAAAHQAAAABm1heHAABAAGAAAB2AAAACBuYW1lFAAqxAAA" +
        "AfgAAAEKcG9zdAADAAAAAAMEAAAAIAAAAlgBkAAFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
        "AAAAAABLVURPAEAAQQBBAyD/OAAAAyAAyAAAAAAAAQADAAEAAAAMAAQAIAAAAAQABAABAAAAQf//AAAAQf///8AAAQAAAAAAAQAA" +
        "AAAB9AK8AAMAAAEBAQEAAAH0AAD+DAAAAAACvAAAAAEAAAAAAfQCvAADAAABAQEBAAAB9AAA/gwAAAAAArwAAAABAAAAAQAAAJUE" +
        "p18PPPUAAwPoAAAAAAAAAAAAAAAAAAAAAAAAAAAB9AK8AAAACAACAAAAAAAAAAEAAAMg/zgAAAJYAAAAZAH0AAEAAAAAAAAAAAAA" +
        "AAAAAAACAlgAAAJYAAAAAAARACIAAAABAAAAAgAEAAEAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAABgBOAAMAAQQJAAEAGgAAAAMA" +
        "AQQJAAIADgAaAAMAAQQJAAMALAAoAAMAAQQJAAQAKgBUAAMAAQQJAAUAFgB+AAMAAQQJAAYAKACUAEsAdQBkAG8AcwAgAEYAaQB4" +
        "AHQAdQByAGUAUgBlAGcAdQBsAGEAcgBLAHUAZABvAHMARgBpAHgAdAB1AHIAZQAtAFIAZQBnAHUAbABhAHIALQAxAEsAdQBkAG8A" +
        "cwAgAEYAaQB4AHQAdQByAGUAIABSAGUAZwB1AGwAYQByAFYAZQByAHMAaQBvAG4AIAAxAC4AMABLAHUAZABvAHMARgBpAHgAdAB1" +
        "AHIAZQAtAFIAZQBnAHUAbABhAHIAAAADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    )!

    struct Records {
        let collection: WorkCollection
        let queue: ReadingQueue
        let annotation: ReadingAnnotation
        let font: CustomFont
        let tombstone: SyncTombstone
    }

    static func seed(in context: ModelContext, work: SavedWork) throws -> Records {
        let font = CustomFont(name: fontName, fileName: fontFile)
        font.dateAdded = fontDate
        try fontBytes.write(to: font.fileURL, options: .atomic)
        let collection = WorkCollection(name: "Deleted Portable Collection")
        collection.id = collectionID
        collection.dateAdded = fontDate
        collection.createdAt = fontDate
        collection.lastModifiedAt = deletedAt
        collection.isPendingDeletion = true
        collection.deletedAt = deletedAt
        let queue = ReadingQueue(
            id: queueID, name: "Deleted Portable Queue", dateCreated: fontDate, dateUpdated: deletedAt
        )
        queue.lastMembershipChangedAt = fontDate
        queue.isPendingDeletion = true
        queue.deletedAt = deletedAt
        let annotation = ReadingAnnotation(
            id: annotationID, work: work, kind: .highlight,
            locatorString: #"{"href":"deleted.xhtml","locations":{"totalProgression":0.33}}"#,
            selectedText: "Deleted passage", note: "Deleted reader note", createdAt: fontDate
        )
        annotation.lastModifiedAt = deletedAt
        annotation.deletedAt = deletedAt
        annotation.isPendingDeletion = true
        let tombstone = SyncTombstone(
            recordID: UUID(uuidString: "b0000000-0000-4000-8000-000000000002")!,
            recordType: .savedSearch, sourceURL: "https://archiveofourown.org/works/829998",
            ao3WorkID: 829998, createdAt: deletedAt,
            deletedOnDeviceID: "cross-platform-fixture", deletionReason: "fixture coverage"
        )
        tombstone.id = tombstoneID
        tombstone.signerPublicKey = "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8"
        tombstone.signature =
            "ed5fe7713c031096df77adb16525722bf6c7dd8485bebd596eb9977570d55a5b"
            + "ef8883cb1545e9765d935143b81adf95b2e41f47eabc999a9230621ccc067904"
        #expect(TombstoneSigning.verify(KudosBackupTombstone(tombstone: tombstone)))
        context.insert(font)
        context.insert(collection)
        context.insert(queue)
        context.insert(annotation)
        context.insert(tombstone)
        try KokoroPronunciationStore().save(.init(
            version: 1, global: pronunciations.global, fandoms: pronunciations.fandoms, works: pronunciations.works
        ))
        return Records(collection: collection, queue: queue, annotation: annotation, font: font, tombstone: tombstone)
    }

    /// Remove test state before restore so an already-present file cannot hide a dropped asset.
    static func clearAssets() throws {
        try? FileManager.default.removeItem(at: Storage.fontsDirectory.appendingPathComponent(fontFile))
        try KokoroPronunciationStore().save(KokoroPronunciationStore.empty)
    }

    /// Export/restore use the default pronunciation store; preserve its exact pre-test bytes.
    static func isolateStorage() throws -> () -> Void {
        let oldFonts = Storage.fontsDirectoryOverride
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = KokoroPronunciationStore.defaultURL()
        let original = try? Data(contentsOf: url)
        try KokoroPronunciationStore().save(KokoroPronunciationStore.empty)
        Storage.fontsDirectoryOverride = folder
        return {
            Storage.fontsDirectoryOverride = oldFonts
            try? FileManager.default.removeItem(at: folder)
            if let original {
                try? original.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func assertRestored(in context: ModelContext) throws {
        let fonts = try context.fetch(FetchDescriptor<CustomFont>())
        let font = try #require(fonts.first { $0.fileName == fontFile }, "Brief 3ge: restored font missing")
        #expect(font.name == fontName)
        #expect(font.fileName == fontFile)
        #expect(font.dateAdded == fontDate)
        #expect(try Data(contentsOf: font.fileURL) == fontBytes)
        #expect(KudosBackupPronunciations.capture() == pronunciations)
        let collections = try context.fetch(FetchDescriptor<WorkCollection>())
        let collection = try #require(collections.first { $0.id == collectionID })
        #expect(collection.deletedAt == deletedAt)
        let queues = try context.fetch(FetchDescriptor<ReadingQueue>())
        #expect(queues.first { $0.id == queueID }?.deletedAt == deletedAt)
        #expect(queues.first { $0.id == queueID }?.lastMembershipChangedAt == fontDate)
        let annotations = try context.fetch(FetchDescriptor<ReadingAnnotation>())
        #expect(annotations.first { $0.id == annotationID }?.deletedAt == deletedAt)
        let tombstones = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(tombstones.first { $0.id == tombstoneID }?.ao3WorkID == 829998)
    }

    /// Check raw JSON before a decoder can discard an unsupported key.
    static func assertManifest(_ data: Data) throws {
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        func record(_ key: String, _ id: UUID) throws -> [String: Any] {
            let rows = root[key] as? [[String: Any]] ?? []
            return try #require(rows.first { ($0["id"] as? String)?.lowercased() == id.uuidString.lowercased() },
                "Brief 3ge: fixture predates user-made fields; regenerate iOS goldens first, then Android")
        }
        let corrections = try #require(root["pronunciations"] as? [String: Any],
            "Brief 3ge: pronunciations missing; regenerate iOS then Android goldens")
        #expect(corrections["global"] as? [String: String] == pronunciations.global)
        #expect(corrections["fandoms"] as? [String: [String: String]] == pronunciations.fandoms)
        #expect(corrections["works"] as? [String: [String: String]] == pronunciations.works)
        let fonts = root["fonts"] as? [[String: Any]] ?? []
        let font = try #require(fonts.first { $0["fileName"] as? String == fontFile },
            "Brief 3ge: font missing; regenerate iOS then Android goldens")
        #expect(font["name"] as? String == fontName)
        #expect(font["fileName"] as? String == fontFile)
        #expect(font["dateAdded"] as? String == "2023-11-14T22:14:20.000Z")
        let collection = try record("collections", collectionID)
        #expect(collection["deletedAt"] as? String == "2023-11-14T22:31:20.000Z")
        #expect(try record("readingQueues", queueID)["deletedAt"] as? String == "2023-11-14T22:31:20.000Z")
        let queue = try record("readingQueues", queueID)
        #expect(queue["lastMembershipChangedAt"] as? String == "2023-11-14T22:14:20.000Z")
        #expect(try record("annotations", annotationID)["deletedAt"] as? String == "2023-11-14T22:31:20.000Z")
        #expect(try record("tombstones", tombstoneID)["ao3WorkID"] as? Int == 829998)
    }

    static func assertArchive(_ archive: KudosBackupContents) throws {
        try assertManifest(archive.manifestData())
        #expect(archive.fontData(for: fontFile) == fontBytes)
    }
}
