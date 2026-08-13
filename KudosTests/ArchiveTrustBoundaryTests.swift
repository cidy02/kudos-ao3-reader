import Foundation
import SwiftData
import Testing
@testable import Kudos

/// The WP-A trust-boundary fixes that had shipped without tests: M1a (timestamp clamp),
/// M1b + D7 (EPUB replacement gate), M1d (monotonic preservation), M2 (tombstone types) and
/// M3 (privacy gates). One case per rule, each written so it fails if the rule is removed.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ArchiveTrustBoundaryTests {

    // MARK: - M1a — decode clamp

    /// Drives the REAL decoder with a year-3000 manifest rather than calling
    /// `clampedArchiveDate` directly. The earlier version of this test invoked the
    /// helper and proved only that `min()` works — it stayed green with the clamp
    /// deleted from `makeDecoder()`, which is the only place that makes it a
    /// security control. Revert-check: remove `clampedArchiveDate(...)` from the
    /// decoder's `dateDecodingStrategy` and this must go red.
    @Test func futureDatedArchiveTimestampsAreClampedAtDecode() throws {
        // Build a REAL, schema-complete manifest, then rewrite every timestamp in the
        // encoded JSON to the year 3000 — which is exactly what an adversary does to a
        // legitimate backup. Hand-writing the JSON is not viable here: KudosBackupWork
        // has ~30 non-optional fields, and an incomplete fixture throws in the decoder
        // and "fails" for the wrong reason (it did, on the first run of this rewrite).
        let container = try container()
        let context = container.mainContext
        let donor = SavedWork(title: "Year 3000", author: "Adversary")
        donor.isSaved = true
        // makeContents reads EPUB bytes for any work with hasEPUB (defaults true).
        donor.hasEPUB = false
        context.insert(donor)

        let honest = try KudosBackupService.makeContents(
            works: [donor], bookmarks: [], fonts: [], readingQueues: [],
            defaults: try testDefaults()
        )
        var json = String(decoding: try honest.manifestData(), as: UTF8.self)
        json = json.replacingOccurrences(
            of: #""(\d{4})-\d{2}-\d{2}T[^"]+Z""#,
            with: #""3000-01-01T00:00:00.000Z""#,
            options: .regularExpression
        )
        #expect(json.contains("3000-01-01"), "fixture did not actually carry a future date")

        let manifest = try KudosBackupContents.decodeManifest(Data(json.utf8))
        // Ceiling captured AFTER the decode, deliberately. The clamp calls `Date()`
        // itself, so a ceiling taken beforehand is stale by the microseconds between
        // the two calls and the comparison fails by a hair — which is exactly what
        // happened on the first run of this rewrite. Taking it after guarantees
        // `ceiling >= ` the clamp's own now, with no tolerance fudge.
        let ceiling = Date().addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew)

        #expect(manifest.exportedAt <= ceiling, "exportedAt escaped the decode clamp")
        let work = try #require(manifest.works.first)
        #expect(work.dateAdded <= ceiling, "dateAdded escaped the clamp")
        #expect(work.lastModifiedAt.map { $0 <= ceiling } ?? true, "lastModifiedAt escaped the clamp")
    }

    /// An honest past date must survive the clamp untouched — otherwise the fix
    /// would "pass" by flattening every timestamp, destroying merge ordering.
    @Test func honestPastTimestampsAreNotAlteredByTheDecodeClamp() throws {
        let json = """
        {
          "version": 8,
          "exportedAt": "2023-11-14T09:30:00.000Z",
          "works": [], "bookmarks": [], "fonts": [], "settings": {}
        }
        """
        let manifest = try KudosBackupContents.decodeManifest(Data(json.utf8))
        let expected = ISO8601DateFormatter().date(from: "2023-11-14T09:30:00Z")
        #expect(manifest.exportedAt == expected, "a past date must pass through unchanged")
    }

    // MARK: - M1b + D7 — EPUB replacement gate

    /// Drives the REAL `restore()` and asserts on the BYTES ON DISK. The earlier
    /// version called `mayReplaceEPUB` directly, so deleting the gate's call site
    /// from the works loop — the actual vulnerability — left it green.
    ///
    /// D7: same-id is not an escape hatch. An A4 adversary reads record UUIDs out of
    /// the sync folder's own manifest, so a matching id was never evidence of
    /// provenance. The donor here deliberately uses the victim's own id.
    ///
    /// Revert-check: delete `Self.mayReplaceEPUB(...)` from the `if let epub =`
    /// condition in the works loop and this must go red.
    @Test func preservedWorkWithAFileIsNeverByteReplacedByARestore() throws {
        let container = try container()
        let context = container.mainContext
        let workID = UUID()

        let local = SavedWork(id: workID, title: "Preserved", author: "Writer")
        local.isSaved = true
        local.hasEPUB = true
        context.insert(local)
        let genuine = try Data(contentsOf: EPUBTests.sampleEPUB)
        try genuine.write(to: local.fileURL)
        defer { try? FileManager.default.removeItem(at: local.fileURL) }
        // `.preserved` only survives `ReadingQueueService.normalize` with queue
        // membership and a real file (see the M1d test's note).
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        ReadingQueueService.add(local, to: queue, in: context)
        local.epubPreservationStatus = .preserved
        try context.save()

        // The attacker ships different, structurally valid EPUB bytes under the
        // victim's own record id.
        let attacker = try Data(contentsOf: EPUBTests.sampleEPUB) + Data("<!-- ATTACKER -->".utf8)
        let donor = SavedWork(id: workID, title: "Preserved", author: "Writer")
        donor.lastModifiedAt = Date().addingTimeInterval(60 * 60)
        let contents = KudosBackupContents(
            manifest: KudosBackupManifest(
                works: [KudosBackupWork(work: donor)], bookmarks: [], fonts: [],
                settings: .capture(defaults: try testDefaults())
            ),
            epubFiles: [workID: attacker]
        )

        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let onDisk = try Data(contentsOf: local.fileURL)
        #expect(onDisk == genuine, "a preserved work's bytes were replaced by a restore")
        #expect(onDisk != attacker, "attacker bytes reached a preserved work's file")
    }

    @Test func replacementIsAllowedWhereThereIsNothingToDestroy() {
        let newRecord = SavedWork(title: "Fresh", author: "Writer")
        newRecord.hasEPUB = true
        newRecord.epubPreservationStatusRaw = EPUBPreservationStatus.preserved.rawValue
        #expect(KudosBackupService.mayReplaceEPUB(local: newRecord, isNewRecord: true))

        let fileless = SavedWork(title: "No File", author: "Writer")
        fileless.hasEPUB = false
        fileless.epubPreservationStatusRaw = EPUBPreservationStatus.preserved.rawValue
        #expect(KudosBackupService.mayReplaceEPUB(local: fileless, isNewRecord: false))

        let ordinary = SavedWork(title: "Ordinary", author: "Writer")
        ordinary.hasEPUB = true
        ordinary.epubPreservationStatusRaw = EPUBPreservationStatus.notPreserved.rawValue
        #expect(KudosBackupService.mayReplaceEPUB(local: ordinary, isNewRecord: false))
    }

    // MARK: - M1d — preservation is monotonic

    @Test func aRestoreCannotDemoteAPreservedWork() throws {
        let container = try container()
        let context = container.mainContext
        let workID = UUID()
        let local = SavedWork(id: workID, title: "Preserved", author: "Writer")
        local.isSaved = true
        local.hasEPUB = true
        context.insert(local)
        // `.preserved` is only stable alongside queue membership and a file that actually
        // exists: `ReadingQueueService.normalize` runs as part of every restore and downgrades
        // an un-queued or file-less work to `.notPreserved`. Without this scaffolding the
        // fixture demotes itself and the test passes or fails for reasons unrelated to M1d.
        let validEPUB = try Data(contentsOf: EPUBTests.sampleEPUB)
        try validEPUB.write(to: local.fileURL)
        defer { try? FileManager.default.removeItem(at: local.fileURL) }
        // Deliberately NOT queued, and `isQueuedForLater` left false.
        //
        // The earlier fixture put the work in a queue so `.preserved` would survive
        // `ReadingQueueService.normalize` — and that scaffolding is exactly what made
        // this test worthless: `normalizeAllQueuedWorks` then RE-UPGRADED the work to
        // `.preserved` after the archive demoted it, so the test passed with M1d fully
        // reverted (verified: it did).
        //
        // `normalizeAllQueuedWorks` (ReadingQueueService.swift:167-192) only visits works
        // that hold a queue membership or still carry a stale `isQueuedForLater` flag.
        // An un-queued, unflagged work is never normalized at all, so whatever the merge
        // leaves is what we observe — no masking in either direction.
        local.isQueuedForLater = false
        local.epubPreservationStatus = .preserved
        try context.save()

        // A newer archive claiming the work is not preserved. Without M1d this wins via
        // incomingWins and then re-opens the byte-replacement path M1b closes.
        let donor = SavedWork(id: workID, title: "Preserved", author: "Writer")
        donor.epubPreservationStatusRaw = EPUBPreservationStatus.notPreserved.rawValue
        donor.lastModifiedAt = Date().addingTimeInterval(60 * 60)
        let contents = KudosBackupContents(manifest: KudosBackupManifest(
            works: [KudosBackupWork(work: donor)], bookmarks: [], fonts: [],
            settings: .capture(defaults: try testDefaults())
        ))
        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let merged = try #require(
            try context.fetch(FetchDescriptor<SavedWork>()).first { $0.id == workID }
        )
        #expect(merged.epubPreservationStatus == .preserved)
    }

    // MARK: - M2 — unknown tombstone record types

    @Test func aTombstoneWithAnUnknownRecordTypeIsSkippedNotCoercedToSavedWork() throws {
        let container = try container()
        let context = container.mainContext
        let victimID = UUID()

        // Forge a tombstone carrying a type string the app does not know. Before M2 this fell
        // back to `.savedWork` — and work tombstones are what suppress a later restore.
        let donor = SyncTombstone(
            recordID: victimID,
            recordType: .savedWork,
            sourceURL: "",
            ao3WorkID: nil,
            deletedOnDeviceID: "attacker",
            deletionReason: "forged"
        )
        donor.recordTypeRaw = "not-a-real-record-type"
        let contents = KudosBackupContents(manifest: KudosBackupManifest(
            works: [], bookmarks: [], fonts: [],
            settings: .capture(defaults: try testDefaults()),
            tombstones: [KudosBackupTombstone(tombstone: donor)]
        ))
        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let landed = try context.fetch(FetchDescriptor<SyncTombstone>())
        #expect(
            !landed.contains { $0.recordID == victimID },
            "an unknown record type was coerced into a work tombstone"
        )
    }

    // MARK: - M3 — privacy gates tighten only

    @Test func aRestoreCannotRelaxPrivacyGates() throws {
        let loose = try namedDefaults("loose")
        loose.set(false, forKey: "hideMatureContent")
        loose.set(false, forKey: "requireBiometricToReveal")
        loose.set(false, forKey: "confirmBeforeDelete")
        loose.set(MaturePrivacyMode.obscure.rawValue, forKey: "matureContentMode")
        let permissiveArchive = KudosBackupSettings.capture(defaults: loose)

        let strict = try namedDefaults("strict")
        strict.set(true, forKey: "hideMatureContent")
        strict.set(true, forKey: "requireBiometricToReveal")
        strict.set(true, forKey: "confirmBeforeDelete")
        strict.set(MaturePrivacyMode.hide.rawValue, forKey: "matureContentMode")

        permissiveArchive.apply(to: strict)

        #expect(strict.bool(forKey: "hideMatureContent"))
        #expect(strict.bool(forKey: "requireBiometricToReveal"))
        #expect(strict.bool(forKey: "confirmBeforeDelete"))
        #expect(strict.string(forKey: "matureContentMode") == MaturePrivacyMode.hide.rawValue)
    }

    @Test func aRestoreMayStillTightenPrivacyGates() throws {
        let strictSource = try namedDefaults("strict-source")
        strictSource.set(true, forKey: "hideMatureContent")
        strictSource.set(true, forKey: "requireBiometricToReveal")
        strictSource.set(MaturePrivacyMode.hide.rawValue, forKey: "matureContentMode")
        let strictArchive = KudosBackupSettings.capture(defaults: strictSource)

        let target = try namedDefaults("target")
        target.set(false, forKey: "hideMatureContent")
        target.set(false, forKey: "requireBiometricToReveal")
        target.set(MaturePrivacyMode.obscure.rawValue, forKey: "matureContentMode")

        strictArchive.apply(to: target)

        #expect(target.bool(forKey: "hideMatureContent"))
        #expect(target.bool(forKey: "requireBiometricToReveal"))
        #expect(target.string(forKey: "matureContentMode") == MaturePrivacyMode.hide.rawValue)
    }

    // MARK: - Helpers

    private func container() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func namedDefaults(_ label: String) throws -> UserDefaults {
        let name = "ArchiveTrustBoundaryTests.\(label).\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func testDefaults() throws -> UserDefaults {
        try namedDefaults("run")
    }
}
}
