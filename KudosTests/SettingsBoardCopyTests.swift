import Foundation
import Testing
@testable import Kudos

/// Pins the Settings board copy produced by models and pure helpers across
/// `.design-ref/Settings*.dc.html` so future edits do not drift from the boards.
struct SettingsBoardCopyTests {
    // MARK: - Settings hub (`Settings`)

    @Test func hubTitlesPageTitlesAndSymbolsMatchSettingsBoard() {
        #expect(SettingsRoute.downloads.title == "Downloads")
        #expect(SettingsRoute.downloads.pageTitle == "Storage")
        #expect(SettingsRoute.about.title == "About Kudos")
        #expect(SettingsRoute.about.pageTitle == "About")
        #expect(SettingsRoute.privacy.title == "Privacy and Local Data")
        #expect(SettingsRoute.privacy.pageTitle == "Privacy and Local Data")

        #expect(SettingsRoute.syncFolder.iconTileSystemImage == "cloud")
        #expect(SettingsRoute.importFiles.iconTileSystemImage == "arrow.down.doc")
        #expect(SettingsRoute.account.iconTileSystemImage == "person")
        #expect(SettingsRoute.privacySettings.iconTileSystemImage == "eye")
        #expect(SettingsRoute.privacy.iconTileSystemImage == "shield")
    }

    @Test func aboutVersionAndSearchMatchBoardWords() {
        #expect(SettingsHubValue.aboutVersion("1.6") == "Version 1.6")
        #expect(SettingsRoute.downloads.matches(query: "Downloads", currentValue: ""))
        #expect(SettingsRoute.downloads.matches(query: "Storage", currentValue: ""))
        #expect(SettingsRoute.preservation.matches(query: "still on ao3", currentValue: ""))
        #expect(SettingsRoute.library.matches(query: "edit shelves", currentValue: ""))
        #expect(SettingsRoute.account.matches(query: "preferences", currentValue: ""))
        #expect(SettingsRoute.about.matches(query: "feedback", currentValue: ""))
    }

    // MARK: - Storage (`Settings-Storage`)

    @Test func storageBreakdownLabelsAndStoragePageHelpersMatchBoard() {
        let footprint = LocalStorageFootprint(
            downloadedWorkBytes: 1_000,
            readingCopyBytes: 200,
            preservedOriginalBytes: 300,
            importedFontBytes: 50,
            cacheBytes: 50,
            draftRecoveryBytes: 0
        )
        let titles = StorageBreakdown.segments(footprint).map(\.title)
        #expect(titles == ["EPUBs", "Original files", "Fonts, cache"])

        #expect(SettingsDownloadsPage.preserveSeriesValue(autoPreserve: true, seriesLimit: 10) == "Up to 10 works")
        #expect(SettingsDownloadsPage.preserveSeriesValue(autoPreserve: false, seriesLimit: 10) == "Ask first")

        let sample = Date(timeIntervalSince1970: 1_760_961_600)
        let day = sample.formatted(.dateTime.month(.abbreviated).day())
        #expect(SettingsDownloadsPage.lastRunValue(for: sample) == "Last run \(day)")
    }

    // MARK: - Preservation (`Settings-Preservation`)

    @Test func preservationCopyMatchesBoard() {
        #expect(SettingsPreservationPage.sectionHeader == "Works that leave AO3")
        #expect(SettingsPreservationPage.checkAvailabilityTitle == "Check what’s still on AO3")
        #expect(SettingsPreservationPage.footerText == "Kudos never deletes a work because AO3 lost it.")

        let sample = Date(timeIntervalSince1970: 1_760_961_600)
        let day = sample.formatted(.dateTime.month(.abbreviated).day())
        #expect(SettingsPreservationPage.lastCheckedLabel(for: sample) == "Last: \(day)")
    }

    // MARK: - Library (`Settings-Library`)

    @Test func libraryCopyMatchesBoard() {
        #expect(SettingsLibraryPage.shelvesShownLabel(count: 6) == "6 shown")
        #expect(SettingsLibraryPage.shelvesShownLabel(count: 0) == "0 shown")
        #expect(
            SettingsLibraryPage.workListsFooter
                == "Row puts the four symbols under the title. Grid keeps them in a square beside it."
        )
        #expect(PreservedWorkService.recoveryWindowText == "90 days")
    }

    // MARK: - Backup & Sync (`Settings-Backup-Sync`)

    @Test func syncFolderDisplayCopyCoversHeadingStatusPendingAndFooter() {
        let base = Date(timeIntervalSince1970: 1_760_961_600)
        let twoMinutesEarlier = base.addingTimeInterval(-120)
        let twoHoursEarlier = base.addingTimeInterval(-7_200)
        let oneHourEarlier = base.addingTimeInterval(-3_600)
        let twoDaysEarlier = base.addingTimeInterval(-172_800)

        let icloudSync = FolderSyncSnapshot(
            isConnected: true,
            folderDisplayName: "Kudos",
            folderPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Kudos",
            lastSyncAt: twoMinutesEarlier,
            lastError: "",
            isDirty: false,
            autoSyncEnabled: true
        )
        #expect(SyncFolderDisplayCopy.folderHeading(icloudSync) == "iCloud Drive › Kudos")
        #expect(SyncFolderDisplayCopy.isUpToDate(icloudSync))
        #expect(!SyncFolderDisplayCopy.isUpToDate(icloudSync, isSyncing: true))
        #expect(
            SyncFolderDisplayCopy.statusLine(icloudSync, now: base)
                == "Up to date · synced 2 min ago"
        )
        #expect(
            SyncFolderDisplayCopy.statusLine(icloudSync, isSyncing: true, now: base)
                == "Syncing library…"
        )

        var localSync = icloudSync
        localSync.folderPath = "/Users/reader/Documents/Kudos"
        localSync.isDirty = true
        #expect(SyncFolderDisplayCopy.folderHeading(localSync) == "Kudos")
        #expect(!SyncFolderDisplayCopy.isUpToDate(localSync))
        #expect(
            SyncFolderDisplayCopy.statusLine(localSync, now: base)
                == "Changes pending · synced 2 min ago"
        )

        var erroredSync = icloudSync
        erroredSync.lastError = "No access"
        #expect(!SyncFolderDisplayCopy.isUpToDate(erroredSync))
        #expect(SyncFolderDisplayCopy.statusLine(erroredSync, now: base) == "No access")

        var neverSynced = icloudSync
        neverSynced.folderDisplayName = "   "
        neverSynced.lastSyncAt = nil
        #expect(SyncFolderDisplayCopy.folderHeading(neverSynced) == "Sync Folder")
        #expect(SyncFolderDisplayCopy.statusLine(neverSynced, now: base) == "Not synced yet")

        #expect(SyncFolderDisplayCopy.relativeSyncAge(from: base.addingTimeInterval(-10), to: base) == "just now")
        #expect(SyncFolderDisplayCopy.relativeSyncAge(from: oneHourEarlier, to: base) == "1 hr ago")
        #expect(SyncFolderDisplayCopy.relativeSyncAge(from: twoHoursEarlier, to: base) == "2 hrs ago")
        #expect(
            SyncFolderDisplayCopy.relativeSyncAge(from: twoDaysEarlier, to: base)
                == WorkStat.displayDate(twoDaysEarlier, time: .shortened)
        )

        #expect(SyncFolderDisplayCopy.pendingLabel(isDirty: false) == "0 pending")
        #expect(SyncFolderDisplayCopy.pendingLabel(isDirty: true) == "Pending")
        #expect(
            SyncFolderDisplayCopy.footerText
                == "Kudos keeps a copy of your library in this folder. "
                + "Other devices that use the same folder stay in step."
        )
    }

    @Test func devicesBackupAndImportCopyMatchBoard() {
        let sample = Date(timeIntervalSince1970: 1_760_961_600)
        let day = sample.formatted(.dateTime.month(.abbreviated).day())

        #expect(TrustedDeviceCopy.thisDeviceTitle(deviceName: "iPhone") == "This iPhone")
        #expect(TrustedDeviceCopy.thisDeviceTitle(deviceName: "iPad") == "This iPad")
        #expect(TrustedDeviceCopy.thisDeviceTitle(deviceName: "Mac") == "This Mac")
        #expect(TrustedDeviceCopy.thisDeviceDetail == "Signs deletions with its own key")
        #expect(TrustedDeviceCopy.thisDeviceSymbol(deviceName: "iPhone") == "iphone")
        #expect(TrustedDeviceCopy.thisDeviceSymbol(deviceName: "iPad") == "ipad")
        #expect(TrustedDeviceCopy.thisDeviceSymbol(deviceName: "Mac") == "desktopcomputer")
        #expect(TrustedDeviceCopy.trustedSince(sample) == "Trusted since \(day)")
        #expect(TrustedDeviceCopy.emptyState == "No other devices paired yet.")

        #expect(
            BackupSettingsSection.footerText
                == "A .kudosbackup holds your works, progress, tags, queues, collections and fonts. "
                + "Importing merges by default; you can replace your library instead, after a preview "
                + "and an undo copy. Your AO3 sign-in is never included."
        )
        #expect(EPUBImportSettingsSection.buttonTitle == "Import Files…")
        #expect(
            EPUBImportSettingsSection.footerText
                == "Add EPUBs and other books from Files. They join your library like any work."
        )
    }

    // MARK: - Account & Privacy (`Settings-Account`)

    @Test func accountCopyMatchesBoard() {
        #expect(SettingsAccountCopy.loggedInTitle(username: "saltwindow") == "Logged in as saltwindow")
        #expect(SettingsAccountCopy.sessionSubtitle(deviceName: "iPhone") == "Session stored on this iPhone only")
        #expect(SettingsAccountCopy.sessionSubtitle(deviceName: "iPad") == "Session stored on this iPad only")
        #expect(SettingsAccountCopy.sessionSubtitle(deviceName: "Mac") == "Session stored on this Mac only")
    }
}
