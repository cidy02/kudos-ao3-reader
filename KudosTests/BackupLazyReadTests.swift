import Foundation
import SwiftData
import Testing
@testable import Kudos

// Nested under the existing KudosBackupTests suite so the RC iOS gate
// (`KudosTests/PersistenceGateSuites/KudosBackupTests`) actually runs them.
// A sibling suite named BackupLazyReadTests would match zero cases under
// that filter and still exit 0.
extension PersistenceGateSuites.KudosBackupTests {
    @Test @MainActor func zipReadDoesNotExtractWorksUntilAccessed() throws {
        let defaults = try backupLazyDefaults()
        let workA = SavedWork(title: "A", author: "Auth")
        let workB = SavedWork(title: "B", author: "Auth")
        let bytesA = Data("epub-a".utf8)
        let bytesB = Data("epub-b".utf8)
        try bytesA.write(to: workA.fileURL)
        try bytesB.write(to: workB.fileURL)
        defer {
            try? FileManager.default.removeItem(at: workA.fileURL)
            try? FileManager.default.removeItem(at: workB.fileURL)
        }
        let exported = try KudosBackupService.makeContents(
            works: [workA, workB],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).kudosbackup")
        try exported.zipData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Production entry Settings uses at execute: `read(from:)`.
        let contents = try KudosBackupContents.read(from: url)
        #expect(contents.epubFiles.isEmpty)
        #expect(contents.fontFiles.isEmpty)
        #expect(
            contents.extractedZipEntryNames == ["manifest.json"],
            "read(from:) must not extract Works/* or Fonts/* before an accessor"
        )
        #expect(contents.epubData(for: workA.id) == bytesA)
        #expect(contents.epubFiles.isEmpty, "epubData must not write epubFiles")
        #expect(
            contents.extractedZipEntryNames.contains("Works/\(workA.id.uuidString).epub"),
            "first accessor is the first extract of that work"
        )
        #expect(
            !contents.extractedZipEntryNames.contains("Works/\(workB.id.uuidString).epub"),
            "unread sibling work must not be extracted"
        )

        let context = try backupLazyContext()
        _ = try KudosBackupService.restore(contents, into: context, defaults: defaults)
        #expect(contents.epubFiles.isEmpty)
        let restored = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(restored.count == 2)
    }

    @Test @MainActor func directoryReadDoesNotMaterializeEPUBs() throws {
        let defaults = try backupLazyDefaults()
        let work = SavedWork(title: "Dir Work", author: "Auth")
        let epub = Data("dir-epub".utf8)
        let dirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let worksDir = dirURL.appendingPathComponent("Works", isDirectory: true)
        try FileManager.default.createDirectory(at: worksDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: worksDir.path
            )
            try? FileManager.default.removeItem(at: dirURL)
        }
        let manifest = KudosBackupManifest(
            works: [KudosBackupWork(work: work)],
            bookmarks: [],
            fonts: [],
            settings: .capture(defaults: defaults)
        )
        try KudosBackupContents(manifest: manifest).manifestData()
            .write(to: dirURL.appendingPathComponent("manifest.json"))
        try epub.write(to: worksDir.appendingPathComponent("\(work.id.uuidString).epub"))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: worksDir.path
        )

        // Production entry. Eager FileWrapper / Data(contentsOf:) of Works/
        // would throw here. Success means the tree was not read.
        let contents = try KudosBackupContents.read(from: dirURL)
        #expect(contents.epubFiles.isEmpty)
        #expect(contents.directoryURL != nil)
        #expect(contents.epubData(for: work.id) == nil)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: worksDir.path
        )
        #expect(contents.epubData(for: work.id) == epub)
        #expect(contents.epubFiles.isEmpty)

        let context = try backupLazyContext()
        _ = try KudosBackupService.restore(contents, into: context, defaults: defaults)
        let restored = try context.fetch(FetchDescriptor<SavedWork>())
        #expect(restored.count == 1)
        #expect(restored.first?.title == "Dir Work")
    }

    @Test @MainActor func zipReadDoesNotExtractFontsUntilAccessed() throws {
        let defaults = try backupLazyDefaults()
        let fontName = "lazy-\(UUID().uuidString).ttf"
        let fontBytes = Data("font-payload".utf8)
        let font = CustomFont(name: "Lazy Font", fileName: fontName)
        let work = SavedWork(title: "Font Work", author: "Auth")
        let base = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [font],
            readingQueues: [],
            defaults: defaults
        )
        let exported = KudosBackupContents(
            manifest: base.manifest,
            fontFiles: [fontName: fontBytes]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).kudosbackup")
        try exported.zipData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let contents = try KudosBackupContents.read(from: url)
        #expect(contents.fontFiles.isEmpty)
        #expect(
            contents.extractedZipEntryNames.filter { $0.hasPrefix("Fonts/") }.isEmpty,
            "read(from:) must not extract Fonts/* until fontData is called"
        )
        #expect(contents.fontData(for: fontName) == fontBytes)
        #expect(contents.fontFiles.isEmpty, "fontData must not write fontFiles")
        #expect(contents.extractedZipEntryNames.contains("Fonts/\(fontName)"))
    }

    @Test @MainActor func directoryReadDoesNotMaterializeFonts() throws {
        let defaults = try backupLazyDefaults()
        let fontName = "dir-\(UUID().uuidString).ttf"
        let fontBytes = Data("dir-font".utf8)
        let font = CustomFont(name: "Dir Font", fileName: fontName)
        let dirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fontsDir = dirURL.appendingPathComponent("Fonts", isDirectory: true)
        try FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: fontsDir.path
            )
            try? FileManager.default.removeItem(at: dirURL)
        }
        let manifest = KudosBackupManifest(
            works: [],
            bookmarks: [],
            fonts: [KudosBackupFont(font: font)],
            settings: .capture(defaults: defaults)
        )
        try KudosBackupContents(manifest: manifest).manifestData()
            .write(to: dirURL.appendingPathComponent("manifest.json"))
        try fontBytes.write(to: fontsDir.appendingPathComponent(fontName))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: fontsDir.path
        )
        let contents = try KudosBackupContents.read(from: dirURL)
        #expect(contents.fontFiles.isEmpty)
        #expect(contents.fontData(for: fontName) == nil)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fontsDir.path
        )
        #expect(contents.fontData(for: fontName) == fontBytes)
        #expect(contents.fontFiles.isEmpty)
    }

    @Test @MainActor func swappedZipIsRejectedAtConfirmedImport() throws {
        let defaults = try backupLazyDefaults()
        let small = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).kudosbackup")
        try small.zipData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let manifest = try KudosBackupContents.preConfirmManifest(from: url)
        let identity = try KudosBackupContents.sourceIdentity(of: url, manifest: manifest)

        // Same path, different size: the confirm-time TOCTOU the split read
        // introduced. Settings execute must refuse this.
        let work = SavedWork(title: "Swap", author: "Auth")
        let epub = Data(repeating: 0x41, count: 64 * 1024)
        try epub.write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }
        let large = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )
        try large.zipData().write(to: url)

        #expect(throws: KudosBackupError.sourceChanged) {
            _ = try KudosBackupContents.readForConfirmedImport(
                from: url,
                expectedIdentity: identity,
                manifest: manifest
            )
        }
    }

    @Test @MainActor func unchangedZipConfirmedImportReadsLazily() throws {
        let defaults = try backupLazyDefaults()
        let work = SavedWork(title: "Stable", author: "Auth")
        let epub = Data("stable-epub".utf8)
        try epub.write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }
        let exported = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: defaults
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).kudosbackup")
        try exported.zipData().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let manifest = try KudosBackupContents.preConfirmManifest(from: url)
        let identity = try KudosBackupContents.sourceIdentity(of: url, manifest: manifest)
        let contents = try KudosBackupContents.readForConfirmedImport(
            from: url,
            expectedIdentity: identity,
            manifest: manifest
        )
        #expect(contents.epubFiles.isEmpty)
        #expect(contents.extractedZipEntryNames == ["manifest.json"])
        #expect(contents.epubData(for: work.id) == epub)
    }

    @Test @MainActor func swappedDirectoryAssetIsRejectedAtConfirmedImport() throws {
        let defaults = try backupLazyDefaults()
        let work = SavedWork(title: "Dir Swap", author: "Auth")
        let dirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let worksDir = dirURL.appendingPathComponent("Works", isDirectory: true)
        try FileManager.default.createDirectory(at: worksDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }
        let manifest = KudosBackupManifest(
            works: [KudosBackupWork(work: work)],
            bookmarks: [],
            fonts: [],
            settings: .capture(defaults: defaults)
        )
        try KudosBackupContents(manifest: manifest).manifestData()
            .write(to: dirURL.appendingPathComponent("manifest.json"))
        let epubURL = worksDir.appendingPathComponent("\(work.id.uuidString).epub")
        try Data("small".utf8).write(to: epubURL)

        let identity = try KudosBackupContents.sourceIdentity(of: dirURL, manifest: manifest)
        try Data(repeating: 0x42, count: 4096).write(to: epubURL)

        #expect(throws: KudosBackupError.sourceChanged) {
            _ = try KudosBackupContents.readForConfirmedImport(
                from: dirURL,
                expectedIdentity: identity,
                manifest: manifest
            )
        }
    }

    private func backupLazyDefaults() throws -> UserDefaults {
        let name = "BackupLazy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func backupLazyContext() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SyncTombstone.self, ReadingAnnotation.self, SavedSearch.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
