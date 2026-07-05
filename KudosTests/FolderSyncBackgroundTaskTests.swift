#if os(iOS)
import Foundation
import Testing
@testable import Kudos

@Suite(.serialized)
struct FolderSyncBackgroundTaskTests {
    @MainActor
    @Test func scheduleRequiresConnectedFolderAndAutoSyncEnabled() {
        #expect(FolderSyncBackgroundTask.shouldSchedule(snapshot: snapshot(isConnected: true, autoSyncEnabled: true)))
        #expect(!FolderSyncBackgroundTask.shouldSchedule(snapshot: snapshot(isConnected: false, autoSyncEnabled: true)))
        #expect(!FolderSyncBackgroundTask.shouldSchedule(snapshot: snapshot(isConnected: true, autoSyncEnabled: false)))
        #expect(!FolderSyncBackgroundTask.shouldSchedule(snapshot: snapshot(isConnected: false, autoSyncEnabled: false)))
    }

    private func snapshot(isConnected: Bool, autoSyncEnabled: Bool) -> FolderSyncSnapshot {
        FolderSyncSnapshot(
            isConnected: isConnected,
            folderDisplayName: "Test Folder",
            folderPath: "/tmp/test",
            lastSyncAt: nil,
            lastError: "",
            isDirty: false,
            autoSyncEnabled: autoSyncEnabled
        )
    }
}
#endif
