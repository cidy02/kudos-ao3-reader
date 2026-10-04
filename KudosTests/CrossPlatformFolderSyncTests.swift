import Foundation
import SwiftData
import Testing
@testable import Kudos

// The sync folder, across the two apps. The backup goldens
// (`CrossPlatformBackupTests`) already prove each side reads the other's
// manifest; what they cannot see is the folder itself: its layout, the names
// of the files in it, and what a sync from the other app leaves in place. An
// EPUB named in the wrong letter case is not found by the other app, and is
// pruned by it as an orphan.
//
// Nested under PersistenceGateSuites: every sync call takes
// PersistenceOperationGate, a process-wide lock.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct CrossPlatformFolderSyncTests {
    /// The folder iOS writes is the fixture Android's `SyncRepositoryTest`
    /// reads, so a change to its layout or names fails here first and there
    /// next. `KUDOS_WRITE_GOLDEN=1` rewrites the fixture.
    @Test func theFolderIOSWritesIsTheFixtureAndroidReads() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        let epub = try Data(contentsOf: try EPUBTests.sampleEPUB)
        var works: [SavedWork] = []
        defer { works.forEach { try? FileManager.default.removeItem(at: $0.fileURL) } }
        for (id, title, ao3WorkID) in [
            (Self.workOneID, "Folder Sync One", 2001),
            (Self.workTwoID, "Folder Sync Two", 2002)
        ] {
            let work = SavedWork(id: id, title: title, author: "Archive Author")
            work.sourceURL = "https://archiveofourown.org/works/\(ao3WorkID)"
            work.ao3WorkID = ao3WorkID
            context.insert(work)
            // Through the app's one EPUB write path, so the manifest carries
            // the digest a real library's does.
            let staged = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).epub")
            try epub.write(to: staged, options: .atomic)
            try ReadingQueueService.replaceEPUB(for: work, with: staged)
            work.hasEPUB = true
            works.append(work)
        }
        try context.save()

        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        let written = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let paths = fixturePaths()
        if writesGolden {
            try? FileManager.default.removeItem(at: paths.iosFolder)
            try FileManager.default.createDirectory(
                at: paths.iosFolder.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: written, to: paths.iosFolder)
        }
        // The names are the contract here. What the manifest holds is the
        // backup goldens' business.
        #expect(try relativeFiles(in: written) == relativeFiles(in: paths.iosFolder))
    }

    /// A folder Android wrote (`SyncRepositoryTest`, run with
    /// `-Dkudos.writeGolden=true`). Every EPUB it lists arrives on this
    /// device, and a full sync from here leaves Android's files in place.
    @Test func aFolderAndroidWroteIsReadAndKept() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let syncDirectory = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        try FileManager.default.copyItem(at: fixturePaths().androidFolder, to: syncDirectory)
        let before = try relativeFiles(in: syncDirectory)

        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: defaults) }
        try FolderSyncService.connect(to: folder, defaults: defaults)

        _ = try await FolderSyncService.syncNow(in: context, defaults: defaults)

        let restored = try context.fetch(FetchDescriptor<SavedWork>())
        defer { restored.forEach { try? FileManager.default.removeItem(at: $0.fileURL) } }
        #expect(restored.count == 2)
        for work in restored {
            #expect(work.hasEPUB)
            let remote = syncDirectory
                .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
                .appendingPathComponent("\(work.id.uuidString).epub")
            #expect(try Data(contentsOf: work.fileURL) == Data(contentsOf: remote))
        }
        #expect(try relativeFiles(in: syncDirectory) == before)
    }

    // xcodebuild injects TEST_RUNNER_* into the test process and strips the
    // prefix. Accept either spelling, as `CrossPlatformBackupTests` does.
    private var writesGolden: Bool {
        ProcessInfo.processInfo.environment["KUDOS_WRITE_GOLDEN"] == "1"
            || ProcessInfo.processInfo.environment["TEST_RUNNER_KUDOS_WRITE_GOLDEN"] == "1"
    }

    /// Every file under `directory`, as a path relative to it. Hidden files
    /// and the manifest's backup copy (Android keeps one, iOS does not) are
    /// not part of what the two apps must agree on.
    private func relativeFiles(in directory: URL) throws -> Set<String> {
        let root = directory.resolvingSymlinksInPath().path
        let enumerator = try #require(FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))
        var files: Set<String> = []
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(root + "/"), !path.hasSuffix(".bak") else { continue }
            files.insert(String(path.dropFirst(root.count + 1)))
        }
        return files
    }

    private func fixturePaths() -> (iosFolder: URL, androidFolder: URL) {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return (
            root.appendingPathComponent(
                "android/app/src/test/resources/cross-platform/ios-sync-folder/KudosLibrary"
            ),
            root.appendingPathComponent(
                "KudosTests/Fixtures/cross-platform/android-sync-folder/KudosLibrary"
            )
        )
    }

    private func container() throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, SyncTombstone.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrossPlatformFolderSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "CrossPlatformFolderSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // Letters in both: an id of digits alone reads the same in either case,
    // and the case of the file name is the thing under test.
    private static let workOneID = UUID(uuidString: "2000ABCD-0000-4000-8000-00000000000A")!
    private static let workTwoID = UUID(uuidString: "2000ABCD-0000-4000-8000-00000000000B")!
}
}
