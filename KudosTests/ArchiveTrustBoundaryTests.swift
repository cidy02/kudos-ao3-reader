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

    @Test func futureDatedArchiveTimestampsAreClampedAtDecode() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let far = Date(timeIntervalSince1970: 32_503_680_000)  // year 3000
        let clamped = KudosBackupContents.clampedArchiveDate(far, now: now)
        #expect(clamped == now.addingTimeInterval(KudosBackupContents.maxFutureTimestampSkew))
        // An honest past date is untouched.
        let past = Date(timeIntervalSince1970: 500_000)
        #expect(KudosBackupContents.clampedArchiveDate(past, now: now) == past)
    }

    // MARK: - M1b + D7 — EPUB replacement gate

    @Test func preservedWorkWithAFileIsNeverByteReplacedByARestore() {
        let work = SavedWork(title: "Preserved", author: "Writer")
        work.hasEPUB = true
        work.epubPreservationStatusRaw = EPUBPreservationStatus.preserved.rawValue
        // D7: same-id is no longer an escape hatch — an A4 adversary reads record UUIDs out
        // of the sync folder's own manifest, so it was never evidence of provenance.
        #expect(!KudosBackupService.mayReplaceEPUB(local: work, isNewRecord: false))
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
        let queue = ReadingQueueService.ensureSavedForLaterQueue(in: context)
        ReadingQueueService.add(local, to: queue, in: context)
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
