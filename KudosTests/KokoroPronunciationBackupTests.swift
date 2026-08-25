#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// Corrections are hand-made and unreconstructible, so they have to travel
/// with the reader rather than being stranded on one device.
@Suite("Kokoro pronunciation backup")
struct KokoroPronunciationBackupTests {
    private func temporaryStore() -> KokoroPronunciationStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kokoro-backup-\(UUID().uuidString).json")
        return KokoroPronunciationStore(url: url)
    }

    @Test func captureReadsEveryLayer() throws {
        let store = temporaryStore()
        try store.setOverride("g", for: "Sam")
        try store.setOverride("f", for: "Sam", in: .fandom("LOTR"))
        try store.setOverride("w", for: "Sam", in: .work("42"))
        let captured = KudosBackupPronunciations.capture(store: store)
        #expect(captured.global == ["Sam": "g"])
        #expect(captured.fandoms == ["LOTR": ["Sam": "f"]])
        #expect(captured.works == ["42": ["Sam": "w"]])
    }

    /// Restoring must not wipe corrections the archive never knew about —
    /// that would silently delete hand-made work.
    @Test func applyMergesRatherThanReplacing() throws {
        let store = temporaryStore()
        try store.setOverride("local", for: "OnlyHere")
        let archive = KudosBackupPronunciations(
            global: ["FromBackup": "restored"], fandoms: [:], works: [:]
        )
        try archive.apply(to: store)
        #expect(store.overrides() == ["OnlyHere": "local", "FromBackup": "restored"])
    }

    /// Restoring is an explicit act: the reader asked for the archive's
    /// contents, so on a conflict the archive wins.
    @Test func theArchiveWinsOnAConflict() throws {
        let store = temporaryStore()
        try store.setOverride("old", for: "Draco")
        try KudosBackupPronunciations(
            global: ["Draco": "new"], fandoms: [:], works: [:]
        ).apply(to: store)
        #expect(store.overrides()["Draco"] == "new")
    }

    @Test func anEmptyArchiveChangesNothing() throws {
        let store = temporaryStore()
        try store.setOverride("keep", for: "Liv")
        try KudosBackupPronunciations.empty.apply(to: store)
        #expect(store.overrides() == ["Liv": "keep"])
    }

    /// Archives written before this feature have no key at all and must still
    /// decode — the field is additive-optional precisely so old backups and
    /// Android's 1…8 version range keep working.
    @Test func archivesWithoutTheKeyStillDecode() throws {
        let json = """
        {"global": {"Liv": "lˈɪv"}}
        """
        let decoded = try JSONDecoder().decode(
            KudosBackupPronunciations.self, from: Data(json.utf8)
        )
        #expect(decoded.global == ["Liv": "lˈɪv"])
        #expect(decoded.fandoms.isEmpty)
        #expect(decoded.works.isEmpty)
    }

    /// The manifest must round-trip with the new field present.
    @Test func manifestRoundTripsWithPronunciations() throws {
        let manifest = KudosBackupManifest(
            works: [], bookmarks: [], fonts: [], collections: [],
            readingQueues: [], readingQueueMemberships: [], annotations: [],
            savedSearches: [], settings: .capture(defaults: UserDefaults()),
            pronunciations: .init(global: ["Nico": "nˈikoʊ"], fandoms: [:], works: [:])
        )
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(KudosBackupManifest.self, from: data)
        #expect(decoded.pronunciations.global == ["Nico": "nˈikoʊ"])
    }

    /// The version must not move for an additive field. Android's
    /// `BackupVersion.isSupported` accepts only 1…8, so a bump would make every
    /// archive this app writes fail import there outright.
    ///
    /// **This is compatibility, not parity, and the distinction matters.** Not
    /// bumping keeps Android *reading* our archives; it does not teach Android
    /// the field. Android's DTO has no `pronunciations` and its decoder sets
    /// `ignoreUnknownKeys`, so a sync down-and-up through an Android device
    /// strips corrections out of the shared archive. iOS survives that locally
    /// — `apply` merges and returns early on empty, so nothing here is
    /// destroyed — but the corrections stop travelling, and a fresh iOS device
    /// would receive none. Tracked as T-210(a); the fix is a passthrough field
    /// on the Android DTO, which need not understand it, only carry it.
    @Test func addingPronunciationsDidNotBumpTheSchemaVersion() {
        #expect(KudosBackupManifest.currentVersion == 8)
        #expect(KudosBackupManifest.supportedVersions.contains(8))
    }

    /// The property that keeps an Android round-trip from destroying anything:
    /// a manifest with no pronunciations must leave local corrections intact.
    @Test func aManifestWithoutPronunciationsLeavesLocalCorrectionsAlone() throws {
        let store = temporaryStore()
        try store.setOverride("hɜɹmˈIəni", for: "Hermione")
        // Exactly what an Android-written manifest decodes to: the key absent.
        let androidWritten = try JSONDecoder().decode(
            KudosBackupPronunciations.self, from: Data("{}".utf8)
        )
        try androidWritten.apply(to: store)
        #expect(store.overrides() == ["Hermione": "hɜɹmˈIəni"])
    }
}
#endif
