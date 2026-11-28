import Foundation
import Testing
@testable import Kudos

struct SystemBoardCopyTests {
    @Test func welcomeDescribesTheRunningPlatform() {
        #if os(iOS)
        #expect(WelcomeBoardCopy.readAnywhere == "Download works and read them offline, with themes, fonts and Read Aloud.")
        #else
        #expect(WelcomeBoardCopy.readAnywhere == "Download works and read them offline, with themes and custom fonts.")
        #endif
        #expect(WelcomeBoardCopy.localLibrary(deviceName: "iPhone")
            == "Your library, queues and history stay on your iPhone. Mature works can hide behind Face ID.")
        #expect(WelcomeBoardCopy.localLibrary(deviceName: "Mac")
            == "Your library, queues and history stay on your Mac.")
    }

    @Test func legalDocumentUsesTheBundledLicencesName() {
        #expect(LegalNoticesView.Document.gpl.title == "GNU AGPL v3.0")
    }

    @Test func restoreFormatsManifestDateCountsAndOptionalArchiveSize() {
        let date = Date(timeIntervalSince1970: 1_760_961_600)
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        #expect(SystemBackupBoardCopy.title(exportedAt: date) == "Kudos backup, \(day)")
        #expect(SystemBackupBoardCopy.summary(works: 1, queues: 1, collections: 0, byteCount: nil)
            == "1 work · 1 queue · 0 collections")

        let bytes = 31_000_000
        let size = LocalStorageFootprint.formatted(bytes: Int64(bytes))
        #expect(SystemBackupBoardCopy.summary(works: 214, queues: 6, collections: 4, byteCount: bytes)
            == "214 works · 6 queues · 4 collections · \(size)")
    }

    @Test func privacyNamesBothModesAndUsesTheSizeOfEligibleDownloads() {
        #if os(iOS)
        #expect(SystemPrivacyBoardCopy.authenticationTitle == "Require Face ID to reveal")
        #else
        #expect(SystemPrivacyBoardCopy.authenticationTitle == "Require authentication to reveal")
        #endif
        #expect(SystemPrivacyBoardCopy.modeTitle(.obscure) == "Blur")
        #expect(SystemPrivacyBoardCopy.modeTitle(.hide) == "Hide Completely")
        #expect(SystemPrivacyBoardCopy.downloadDetail(count: 0, bytes: 0) == "0 works")
        #expect(SystemPrivacyBoardCopy.downloadDetail(count: 1, bytes: nil) == "1 work")
        let bytes: Int64 = 1_200_000_000
        let size = LocalStorageFootprint.formatted(bytes: bytes)
        #expect(SystemPrivacyBoardCopy.downloadDetail(count: 74, bytes: bytes) == "74 works · \(size)")
    }

    @Test func syncActionsUseTheCurrentDeviceName() {
        let now = Date(timeIntervalSince1970: 1_760_961_600)
        let lastSync = now.addingTimeInterval(-10)
        let age = SyncFolderDisplayCopy.relativeSyncAge(from: lastSync, to: now)
        #expect(TrustedDeviceCopy.thisDeviceStatus(lastSyncAt: nil, now: now) == "Signs deletions with its own key")
        #expect(TrustedDeviceCopy.thisDeviceStatus(lastSyncAt: lastSync, now: now)
            == "Signs deletions with its own key · synced \(age)")
        #expect(TrustedDeviceCopy.addDevice == "Add a Device…")
        #expect(TrustedDeviceCopy.showCodeTitle(deviceName: "iPhone") == "Show a Code on This iPhone")
        #expect(TrustedDeviceCopy.showCodeTitle(deviceName: "iPad") == "Show a Code on This iPad")
        #expect(SyncFolderDisplayCopy.removeDeviceTitle(deviceName: "iPhone") == "Remove This iPhone from Sync")
        #expect(SyncFolderDisplayCopy.removeDeviceDetail(deviceName: "Mac")
            == "Your library stays on this Mac; it just stops syncing.")
    }

    @Test func preferenceCopyPreservesLabelsForOptOutAndUnknownFields() {
        let adult = AO3PreferenceToggle(
            name: "preference[adult]", label: "Show me adult content without checking.", isOn: false, help: nil
        )
        let kudos = AO3PreferenceToggle(
            name: "preference[kudos_emails_off]", label: "Turn off emails about kudos.", isOn: true, help: nil
        )
        let display = AO3PreferenceSection(title: "Display", help: nil, toggles: [adult])
        let comments = AO3PreferenceSection(title: "Comments", help: nil, toggles: [kudos])
        let mixed = AO3PreferenceSection(title: "Other", help: nil, toggles: [adult, kudos])
        #expect(AO3PreferencesBoardCopy.sectionTitle(display) == "Reading on AO3")
        #expect(AO3PreferencesBoardCopy.sectionTitle(comments) == "Notifications by email")
        #expect(AO3PreferencesBoardCopy.sectionTitle(mixed) == "Other")
        #expect(AO3PreferencesBoardCopy.toggleTitle(adult) == "Show adult content without asking")
        #expect(AO3PreferencesBoardCopy.toggleTitle(kudos) == "Turn off emails about kudos.")
        #expect(AO3PreferencesBoardCopy.profileTitle(key: "time_zone", fallback: "Your time zone") == "Time zone")
        #expect(AO3PreferencesBoardCopy.profileTitle(key: "skin_id", fallback: "Your site skin") == "Skin")
        #expect(AO3PreferencesBoardCopy.profileTitle(key: "work_title_format", fallback: "Format") == "Browser title")
        #expect(AO3PreferencesBoardCopy.profileTitle(key: "locale", fallback: "Language") == "Language")
    }

    @Test func playerSubtitleUsesKnownPositionComponents() {
        let duration = ReaderTimeEstimate.durationLabel(minutes: 12)
        #expect(SystemReadAloudBoardCopy.subtitle(chapter: 16, minutes: 12) == "Chapter 16 · \(duration) left")
        #expect(SystemReadAloudBoardCopy.subtitle(chapter: nil, minutes: 12) == "\(duration) left")
        #expect(SystemReadAloudBoardCopy.subtitle(chapter: 16, minutes: nil) == "Chapter 16")
        #expect(SystemReadAloudBoardCopy.subtitle(chapter: nil, minutes: nil) == nil)
        #expect(SystemReadAloudBoardCopy.readerLabel(title: "Salt & Starlight", subtitle: "Chapter 16")
            == "Now reading aloud: Salt & Starlight, Chapter 16")
        #expect(SystemReadAloudBoardCopy.readerLabel(title: "Reading Aloud", subtitle: nil) == "Reading Aloud")
    }
}
