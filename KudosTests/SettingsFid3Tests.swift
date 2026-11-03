import Foundation
import Testing
@testable import Kudos

/// Boards 49-51: the pure pieces behind the Backup summary row and the storage bar.
struct SettingsFid3Tests {
    @Test func storageSegmentsAddUpToTheTotalAndDropEmptyOnes() {
        let footprint = LocalStorageFootprint(
            downloadedWorkBytes: 100, readingCopyBytes: 20, preservedOriginalBytes: 0,
            importedFontBytes: 5, cacheBytes: 10, draftRecoveryBytes: 1
        )
        let segments = StorageBreakdown.segments(footprint)
        #expect(segments.map(\.kind) == [.works, .other])
        #expect(segments.map(\.bytes) == [120, 16])
        #expect(segments.reduce(Int64(0)) { $0 + $1.bytes } == footprint.totalBytes)
    }

    @Test func emptyFootprintHasNoSegments() {
        #expect(StorageBreakdown.segments(LocalStorageFootprint()).isEmpty)
    }

    @Test func syncDetailReadsTheSnapshot() {
        var sync = FolderSyncSnapshot(
            isConnected: false, folderDisplayName: "", folderPath: "", lastSyncAt: nil,
            lastError: "", isDirty: false, autoSyncEnabled: true
        )
        #expect(BackupSyncSummary.detail(sync) == "No folder connected")
        sync.isConnected = true
        sync.folderDisplayName = "Kudos"
        #expect(BackupSyncSummary.detail(sync) == "Kudos · Not synced yet")
        sync.lastSyncAt = Date(timeIntervalSince1970: 0)
        #expect(BackupSyncSummary.detail(sync).hasPrefix("Kudos · Synced "))
    }

    @Test func workCountPluralises() {
        #expect(SettingsPrivacyPage.workCount(1) == "1 work")
        #expect(SettingsPrivacyPage.workCount(0) == "0 works")
    }
}
