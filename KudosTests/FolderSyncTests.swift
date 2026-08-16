import CoreText
import Foundation
import SwiftData
import Testing
@testable import Kudos

// Nested under PersistenceGateSuites (see its doc comment): every sync call here
// takes PersistenceOperationGate, a process-wide static lock, so this suite must
// serialize against the other gate-taking suites too, not just within itself.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct FolderSyncTests {
    @Test func syncUpWritesReadableSyncDirectory() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        let work = SavedWork(
            title: "Folder Sync Work",
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/1001"
        )
        work.ao3WorkID = 1001
        work.isFavorite = true
        context.insert(work)
        try context.save()

        try FolderSyncService.connect(to: folder, defaults: defaults)
        let result = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        // The live payload is a plain directory (manifest + per-asset files),
        // not an archive — that's what lets iCloud sync per-file deltas. Its
        // layout matches the legacy package's, so the shared reader can verify it.
        let syncDirectoryURL = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: syncDirectoryURL.path,
            isDirectory: &isDirectory
        ))
        #expect(isDirectory.boolValue)
        let contents = try KudosBackupContents.read(from: syncDirectoryURL)
        #expect(result.didWriteRemoteFile)
        #expect(contents.manifest.works.count == 1)
        #expect(contents.manifest.works.first?.title == "Folder Sync Work")
        #expect(contents.manifest.works.first?.isFavorite == true)
        #expect(FolderSyncService.snapshot(defaults: defaults).lastSyncAt != nil)
    }

    @Test func syncDownRestoresWorkQueueAndCollection() async throws {
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let sourceDefaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: sourceDefaults) }

        let seed = try insertLibraryFixture(into: sourceContext)
        try FolderSyncService.connect(to: folder, defaults: sourceDefaults)
        _ = try await FolderSyncService.syncUp(in: sourceContext, defaults: sourceDefaults)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let result = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)

        let restoredWork = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        let restoredQueue = try #require(try targetContext.fetch(FetchDescriptor<ReadingQueue>())
            .first { $0.id == seed.queueID })
        let restoredCollection = try #require(try targetContext.fetch(FetchDescriptor<WorkCollection>())
            .first { $0.id == seed.collectionID })

        #expect(result.didReadRemoteFile)
        #expect(result.restoredWorks == 1)
        #expect(restoredWork.id == seed.workID)
        #expect(restoredQueue.name == "Weekend Reads")
        #expect(restoredQueue.memberships.count == 1)
        #expect(restoredCollection.name == "Comfort Shelf")
        #expect(restoredCollection.works.map(\.id) == [seed.workID])
    }

    /// A5-F3: folder sync's restore path is the same `KudosBackupService.restore`
    /// used by manual backup import, so a corrupt synced EPUB must be rejected the
    /// same way — never overwriting a valid local copy.
    @Test func syncDownRejectsInvalidEPUBWithoutOverwritingLocalCopy() async throws {
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let sourceDefaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: sourceDefaults) }

        let workID = UUID()
        let sourceWork = SavedWork(id: workID, title: "Corrupt Sync Work", author: "Writer")
        sourceWork.hasEPUB = true
        sourceContext.insert(sourceWork)
        try Data("not-an-epub".utf8).write(to: sourceWork.fileURL)
        try sourceContext.save()
        defer { try? FileManager.default.removeItem(at: sourceWork.fileURL) }

        try FolderSyncService.connect(to: folder, defaults: sourceDefaults)
        _ = try await FolderSyncService.syncUp(in: sourceContext, defaults: sourceDefaults)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let targetWork = SavedWork(id: workID, title: "Corrupt Sync Work", author: "Writer")
        targetWork.hasEPUB = true
        targetContext.insert(targetWork)
        let validEPUB = try Data(contentsOf: EPUBTests.sampleEPUB)
        try validEPUB.write(to: targetWork.fileURL)
        try targetContext.save()
        defer { try? FileManager.default.removeItem(at: targetWork.fileURL) }

        _ = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)

        let restored = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        #expect(restored.hasEPUB)
        #expect(try Data(contentsOf: restored.fileURL) == validEPUB)
    }

    @Test func syncDownRejectsInvalidFontWithoutPersistenceOrSelectorChange() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        targetDefaults.set("custom:local-font.ttf", forKey: "readerFontID")
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }

        let fileName = "invalid-\(UUID().uuidString).ttf"
        let installedURL = Storage.fontsDirectory.appendingPathComponent(fileName)
        defer { try? FileManager.default.removeItem(at: installedURL) }
        let manifest = try fontManifest(fileName: fileName, readerFontID: "custom:\(fileName)")
        let invalidBytes = Data([0x00, 0x01, 0x00, 0x00]) + Data("not a font".utf8)
        try writeRemoteFont(manifest: manifest, fileName: fileName, data: invalidBytes, to: folder)
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        do {
            _ = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
            Issue.record("Expected live folder sync to reject the invalid custom font.")
        } catch let error as KudosBackupError {
            guard case .invalidPackage = error else {
                Issue.record("Expected invalidPackage, got \(error).")
                return
            }
            #expect(error.localizedDescription == "This file is not a valid Kudos backup.")
        }

        #expect(try targetContext.fetch(FetchDescriptor<CustomFont>()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: installedURL.path))
        #expect(targetDefaults.string(forKey: "readerFontID") == "custom:local-font.ttf")
    }

    @Test func syncDownSkipsOversizedFontAndRestoresUnrelatedState() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }

        let fileName = "oversized-\(UUID().uuidString).ttf"
        let installedURL = Storage.fontsDirectory.appendingPathComponent(fileName)
        defer { try? FileManager.default.removeItem(at: installedURL) }
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let font = CustomFont(name: "Oversized", fileName: fileName)
        let bookmark = Bookmark(title: "Unrelated Bookmark", urlString: "https://example.com/safe")
        sourceContext.insert(font)
        sourceContext.insert(bookmark)
        try sourceContext.save()
        let manifest = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [bookmark],
            fonts: [font],
            readingQueues: [],
            defaults: try testDefaults()
        ).manifest
        try writeRemoteFont(
            manifest: manifest,
            fileName: fileName,
            data: Data(repeating: 0, count: KudosBackupContents.maxFontEntryBytes + 1),
            to: folder
        )
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let result: FolderSyncResult
        do {
            result = try await FolderSyncService.syncDown(
                in: targetContext,
                defaults: targetDefaults
            )
        } catch {
            #expect(Bool(false), "Oversized font bytes must not abort sync-down.")
            return
        }

        #expect(result.didReadRemoteFile, "Oversized font bytes must not abort sync-down.")
        #expect(
            try targetContext.fetch(FetchDescriptor<CustomFont>()).isEmpty,
            "An oversized font must not persist a CustomFont row."
        )
        #expect(!FileManager.default.fileExists(atPath: installedURL.path))
        let restoredBookmarks = try targetContext.fetch(FetchDescriptor<Bookmark>())
        #expect(
            restoredBookmarks.map(\.title) == ["Unrelated Bookmark"],
            "Sync-down must restore unrelated manifest state after skipping an oversized font."
        )
    }

    @Test func syncDownPreservesCollidingFontBytesAndLocalSelector() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }

        let (fontData, fileExtension) = try validFontData()
        let localData = fontData + Data(repeating: 0, count: 16)
        let incomingData = fontData + Data(repeating: 0, count: 15) + Data([1])
        let fileName = "collision-\(UUID().uuidString).\(fileExtension)"
        let suffixName = (fileName as NSString).deletingPathExtension
            + "-restored-1.\((fileName as NSString).pathExtension)"
        let localURL = Storage.fontsDirectory.appendingPathComponent(fileName)
        let suffixURL = Storage.fontsDirectory.appendingPathComponent(suffixName)
        defer {
            try? FileManager.default.removeItem(at: localURL)
            try? FileManager.default.removeItem(at: suffixURL)
        }
        try FileManager.default.createDirectory(at: Storage.fontsDirectory, withIntermediateDirectories: true)
        try localData.write(to: localURL)
        targetContext.insert(CustomFont(name: "Local", fileName: fileName))
        try targetContext.save()
        targetDefaults.set("custom:\(fileName)", forKey: "readerFontID")

        let manifest = try fontManifest(fileName: fileName, readerFontID: "custom:remote.ttf")
        try writeRemoteFont(manifest: manifest, fileName: fileName, data: incomingData, to: folder)
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let result = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)

        #expect(result.didReadRemoteFile)
        #expect(try Data(contentsOf: localURL) == localData)
        let restoredCollisionData = try? Data(contentsOf: suffixURL)
        #expect(
            restoredCollisionData == incomingData,
            "Equal-size different font bytes must be restored under a collision-safe suffix."
        )
        #expect(Set(try targetContext.fetch(FetchDescriptor<CustomFont>()).map(\.fileName)) == [fileName, suffixName])
        #expect(targetDefaults.string(forKey: "readerFontID") == "custom:\(fileName)")
    }

    @Test func syncDownConvergesWhenFontLibraryExceedsAggregateCap() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }

        let (fontData, fileExtension) = try validFontData()
        let paddedData = fontData + Data(
            repeating: 0,
            count: KudosBackupContents.maxFontEntryBytes - fontData.count
        )
        var fontFiles: [String: Data] = [:]
        var archivedFonts: [CustomFont] = []
        for index in 0..<9 {
            let fileName = "aggregate-\(UUID().uuidString)-\(index).\(fileExtension)"
            archivedFonts.append(CustomFont(name: "Aggregate \(index)", fileName: fileName))
            fontFiles[fileName] = paddedData
        }
        defer {
            for fileName in fontFiles.keys {
                try? FileManager.default.removeItem(
                    at: Storage.fontsDirectory.appendingPathComponent(fileName)
                )
            }
        }
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let work = try insertWork(
            into: sourceContext,
            title: "Aggregate-Safe Work",
            ao3WorkID: 9010
        )
        let bookmark = Bookmark(
            title: "Aggregate-Safe Bookmark",
            urlString: "https://example.com/aggregate-safe"
        )
        sourceContext.insert(bookmark)
        try sourceContext.save()
        let manifest = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [bookmark],
            fonts: archivedFonts,
            readingQueues: [],
            defaults: try testDefaults()
        ).manifest
        try writeRemoteFonts(manifest: manifest, fontFiles: fontFiles, to: folder)
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let first: FolderSyncResult
        do {
            first = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        } catch {
            #expect(Bool(false), "Aggregate exhaustion must not abort sync-down.")
            return
        }
        #expect(first.didReadRemoteFile, "Aggregate exhaustion must not abort sync-down.")
        #expect(try targetContext.fetch(FetchDescriptor<CustomFont>()).count == 8)
        #expect(
            try targetContext.fetch(FetchDescriptor<SavedWork>()).map(\.title)
                == ["Aggregate-Safe Work"],
            "Aggregate exhaustion must not roll back an unrelated work."
        )
        #expect(
            try targetContext.fetch(FetchDescriptor<Bookmark>()).map(\.title)
                == ["Aggregate-Safe Bookmark"],
            "Aggregate exhaustion must not roll back an unrelated bookmark."
        )

        let second = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(
            try targetContext.fetch(FetchDescriptor<CustomFont>()).count == 9,
            "Already-installed identical fonts must cost no aggregate bytes on retry."
        )
        #expect(
            second.didReadRemoteFile,
            "An incomplete aggregate pass must re-read the unchanged manifest."
        )
        #expect(
            second.skippedUnchanged == false,
            "An incomplete aggregate pass must withhold the unchanged stamp and retry."
        )

        let third = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(third.skippedUnchanged, "A converged font library must regain the unchanged stamp.")
    }

    @Test func syncDownPreservesEveryCaseFoldedDatabaseRow() async throws {
        try await CaseSensitiveFontTestVolume.withFontsDirectory {
            let folder = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let targetContainer = try container()
            let targetContext = targetContainer.mainContext
            let targetDefaults = try testDefaults()
            defer { FolderSyncService.disconnect(defaults: targetDefaults) }

            let (incomingData, fileExtension) = try validFontData()
            let baseName = "sync-case-\(UUID().uuidString)"
            let archivedFileName = "\(baseName.uppercased()).\(fileExtension.uppercased())"
            let localFileName = "\(baseName.lowercased()).\(fileExtension.uppercased())"
            let incomingFileName = "\(baseName.lowercased()).\(fileExtension.lowercased())"
            let suffixName = (incomingFileName as NSString).deletingPathExtension
                + "-restored-1.\((incomingFileName as NSString).pathExtension)"
            let localURL = Storage.fontsDirectory.appendingPathComponent(localFileName)
            let archivedURL = Storage.fontsDirectory.appendingPathComponent(archivedFileName)
            let suffixURL = Storage.fontsDirectory.appendingPathComponent(suffixName)
            defer {
                try? FileManager.default.removeItem(at: localURL)
                try? FileManager.default.removeItem(at: archivedURL)
                try? FileManager.default.removeItem(at: suffixURL)
            }
            try FileManager.default.createDirectory(
                at: Storage.fontsDirectory,
                withIntermediateDirectories: true
            )
            try incomingData.write(to: localURL)
            try incomingData.write(to: archivedURL)
            let archivedCaseRow = CustomFont(name: "Archived Case", fileName: archivedFileName)
            let localCaseRow = CustomFont(name: "Local Case", fileName: localFileName)
            targetContext.insert(archivedCaseRow)
            targetContext.insert(localCaseRow)
            try targetContext.save()
            targetDefaults.set("custom:\(archivedFileName)", forKey: "readerFontID")

            let manifest = try fontManifest(
                fileName: incomingFileName,
                readerFontID: "custom:\(archivedFileName)"
            )
            try writeRemoteFont(
                manifest: manifest,
                fileName: incomingFileName,
                data: incomingData,
                to: folder
            )
            try FolderSyncService.connect(to: folder, defaults: targetDefaults)

            let result = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)

            #expect(result.didReadRemoteFile)
            let rows = try targetContext.fetch(FetchDescriptor<CustomFont>())
            #expect(
                Set(rows.map(\.fileName)) == [archivedFileName, localFileName, suffixName],
                "Ambiguous case-fold matches must preserve every DB row and install a suffixed font."
            )
            #expect(try Data(contentsOf: localURL) == incomingData)
            #expect(try Data(contentsOf: archivedURL) == incomingData)
            #expect(try Data(contentsOf: suffixURL) == incomingData)
            #expect(targetDefaults.string(forKey: "readerFontID") == "custom:\(archivedFileName)")
        }
    }

    @Test func syncDownTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile() async throws {
        try await CaseSensitiveFontTestVolume.withFontsDirectory {
            let folder = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let targetContainer = try container()
            let targetContext = targetContainer.mainContext
            let targetDefaults = try testDefaults()
            defer { FolderSyncService.disconnect(defaults: targetDefaults) }

            let (incomingData, fileExtension) = try validFontData()
            let orphanData = Data("case-variant-orphan".utf8)
            let baseName = "sync-local-ambiguity-\(UUID().uuidString)"
            let archivedFileName = "\(baseName.uppercased()).\(fileExtension.lowercased())"
            let orphanFileName = "\(baseName.lowercased()).\(fileExtension.uppercased())"
            let incomingFileName = "\(baseName.lowercased()).\(fileExtension.lowercased())"
            let suffixName = (incomingFileName as NSString).deletingPathExtension
                + "-restored-1.\((incomingFileName as NSString).pathExtension)"
            let archivedURL = Storage.fontsDirectory.appendingPathComponent(archivedFileName)
            let orphanURL = Storage.fontsDirectory.appendingPathComponent(orphanFileName)
            let suffixURL = Storage.fontsDirectory.appendingPathComponent(suffixName)
            defer {
                try? FileManager.default.removeItem(at: archivedURL)
                try? FileManager.default.removeItem(at: orphanURL)
                try? FileManager.default.removeItem(at: suffixURL)
            }
            try FileManager.default.createDirectory(
                at: Storage.fontsDirectory,
                withIntermediateDirectories: true
            )
            try incomingData.write(to: archivedURL)
            try orphanData.write(to: orphanURL)
            let existingRow = CustomFont(name: "Existing", fileName: archivedFileName)
            targetContext.insert(existingRow)
            try targetContext.save()
            targetDefaults.set("custom:\(archivedFileName)", forKey: "readerFontID")

            let manifest = try fontManifest(
                fileName: incomingFileName,
                readerFontID: "custom:\(archivedFileName)"
            )
            try writeRemoteFont(
                manifest: manifest,
                fileName: incomingFileName,
                data: incomingData,
                to: folder
            )
            try FolderSyncService.connect(to: folder, defaults: targetDefaults)

            let result = try await FolderSyncService.syncDown(
                in: targetContext,
                defaults: targetDefaults
            )

            #expect(result.didReadRemoteFile)
            #expect(
                (try? Data(contentsOf: suffixURL)) == incomingData,
                "Local-file ambiguity must force a suffixed folder-sync restore."
            )
            #expect(existingRow.fileName == archivedFileName)
            #expect(try Data(contentsOf: archivedURL) == incomingData)
            #expect(try Data(contentsOf: orphanURL) == orphanData)
            #expect(
                Set(try targetContext.fetch(FetchDescriptor<CustomFont>()).map(\.fileName))
                    == [archivedFileName, suffixName],
                "Folder sync must retain the row-owned font and add a suffixed incoming row."
            )
            #expect(targetDefaults.string(forKey: "readerFontID") == "custom:\(archivedFileName)")
        }
    }

    @Test func syncUpThenSyncDownConvergesWithoutDuplicates() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let firstContainer = try container()
        let firstContext = firstContainer.mainContext
        let firstDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: firstDefaults) }
        try insertWork(into: firstContext, title: "Device A Work", ao3WorkID: 2001)
        try FolderSyncService.connect(to: folder, defaults: firstDefaults)
        _ = try await FolderSyncService.syncUp(in: firstContext, defaults: firstDefaults)

        let secondContainer = try container()
        let secondContext = secondContainer.mainContext
        let secondDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: secondDefaults) }
        try FolderSyncService.connect(to: folder, defaults: secondDefaults)
        _ = try await FolderSyncService.syncDown(in: secondContext, defaults: secondDefaults)
        try insertWork(into: secondContext, title: "Device B Work", ao3WorkID: 2002)
        _ = try await FolderSyncService.syncNow(in: secondContext, defaults: secondDefaults)

        _ = try await FolderSyncService.syncDown(in: firstContext, defaults: firstDefaults)

        let firstWorks = try firstContext.fetch(FetchDescriptor<SavedWork>())
        let secondWorks = try secondContext.fetch(FetchDescriptor<SavedWork>())
        #expect(firstWorks.count == 2)
        #expect(secondWorks.count == 2)
        #expect(Set(firstWorks.compactMap(\.ao3WorkID)) == [2001, 2002])
        #expect(Set(secondWorks.compactMap(\.ao3WorkID)) == [2001, 2002])
    }

    @Test func syncDownMissingFileIsNoop() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        try FolderSyncService.connect(to: folder, defaults: defaults)
        let result = try await FolderSyncService.syncDown(in: context, defaults: defaults)

        #expect(result.missingRemoteFile)
        #expect(result.didReadRemoteFile == false)
        #expect(try context.fetch(FetchDescriptor<SavedWork>()).isEmpty)
    }

    @Test func operationGatePreventsInterleavedFolderSync() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        try FolderSyncService.connect(to: folder, defaults: defaults)
        #expect(PersistenceOperationGate.begin(.backupImport))
        defer { PersistenceOperationGate.end(.backupImport) }

        do {
            _ = try await FolderSyncService.syncNow(in: context, defaults: defaults)
            Issue.record("Expected folder sync to respect the active backup import gate.")
        } catch let error as FolderSyncError {
            #expect(error == .operationInProgress(PersistenceOperationKind.backupImport.title))
        }
        // A gate-rejected attempt must still be visible, not silently dropped, since it
        // isn't a "real" failure like a bad bookmark or a read error.
        #expect(!FolderSyncService.snapshot(defaults: defaults).lastError.isEmpty)
    }

    @Test func dirtyFlagOnlyClearsAfterAnActualWrite() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        try FolderSyncService.connect(to: folder, defaults: defaults)
        FolderSyncService.markDirty(defaults: defaults)
        #expect(FolderSyncService.snapshot(defaults: defaults).isDirty)

        // A pure sync-down (nothing to read yet) must not clear it — dirty means "local
        // changes not yet written out", and no write happened.
        _ = try await FolderSyncService.syncDown(in: context, defaults: defaults)
        #expect(FolderSyncService.snapshot(defaults: defaults).isDirty)

        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        #expect(FolderSyncService.snapshot(defaults: defaults).isDirty == false)
    }

    @Test func foldConflictContentsMergesAllInputs() throws {
        let defaults = try testDefaults()
        let first = try backupContents(title: "Conflict A", ao3WorkID: 3001)
        let second = try backupContents(title: "Conflict B", ao3WorkID: 3002)
        let targetContainer = try container()
        let targetContext = targetContainer.mainContext

        let result = try FolderSyncService.foldConflictContents([first, second], into: targetContext, defaults: defaults)

        let works = try targetContext.fetch(FetchDescriptor<SavedWork>())
        #expect(result.foldedConflicts == 2)
        #expect(result.restoredWorks == 2)
        #expect(Set(works.compactMap(\.ao3WorkID)) == [3001, 3002])
    }

    @Test func foldConflictContentsDoesNotAdoptIncomingUnsignedTombstones() throws {
        let defaults = try testDefaults()
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let work = try insertWork(into: sourceContext, title: "From remote", ao3WorkID: 4242)
        let hostile = SyncTombstone(recordID: work.id, recordType: .savedWork, ao3WorkID: 4242)
        sourceContext.insert(hostile)
        try sourceContext.save()
        let remote = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            tombstones: [hostile],
            defaults: defaults
        )
        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        _ = try FolderSyncService.foldConflictContents([remote], into: targetContext, defaults: defaults)
        #expect(
            try targetContext.fetch(FetchDescriptor<SyncTombstone>()).isEmpty,
            "folder-sync fold must not insert the remote unsigned tombstone"
        )
        #expect(
            try targetContext.fetch(FetchDescriptor<SavedWork>()).contains { $0.ao3WorkID == 4242 },
            "folder-sync fold must still insert a work present in the remote snapshot"
        )
    }

    /// `foldFileProviderConflicts` (the private, `performSyncDown`-only path) folds its
    /// own `FolderSyncResult` into the caller's via this overload rather than discarding
    /// it — regression coverage for the undercount §6.3 of the ponytail audit found:
    /// conflict-restore counts must reach the totals `SettingsView` displays, not just
    /// the raw folded-version count.
    @Test func folderSyncResultAbsorbsAnotherResultsCountsRatherThanDiscardingThem() {
        var total = FolderSyncResult()
        total.restoredWorks = 1
        total.suppressedQueues = 1

        var conflictFold = FolderSyncResult()
        conflictFold.restoredWorks = 2
        conflictFold.suppressedQueues = 3
        conflictFold.revivedQueues = 1
        conflictFold.ambiguousQueueConflicts = 1
        conflictFold.foldedConflicts = 2

        total.absorb(conflictFold)

        #expect(total.restoredWorks == 3)
        #expect(total.suppressedQueues == 4)
        #expect(total.revivedQueues == 1)
        #expect(total.ambiguousQueueConflicts == 1)
        #expect(total.foldedConflicts == 2)
    }

    /// A work explicitly removed from a collection must not be silently re-added by a
    /// stale sync file that still lists it — the same resurrection bug class fixed for
    /// deleted works/queues, now closed for collection membership too.
    @Test func removedCollectionMembershipIsNotResurrectedByStaleSync() async throws {
        let defaults = try testDefaults()
        let container = try container()
        let context = container.mainContext

        let work = try insertWork(into: context, title: "Shelved Work", ao3WorkID: 5001)
        let collection = WorkCollection(name: "Comfort Shelf")
        collection.id = UUID(uuidString: "00000000-0000-0000-0000-0000000C0111")!
        collection.markModified(Date(timeIntervalSince1970: 100))
        collection.works.append(work)
        work.collections.append(collection)
        context.insert(collection)
        try context.save()

        // The stale manifest: a snapshot from before the removal, still listing the work.
        let staleContents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            collections: [collection],
            readingQueues: [],
            defaults: defaults
        )

        // The user removes the work from the collection at t=150 — after the stale
        // manifest's t=100, so that snapshot must not resurrect it. Constructed directly
        // (rather than via the real-"now"-stamping helper) for a meaningful boundary
        // comparison rather than "any real date dwarfs a synthetic epoch timestamp".
        context.insert(SyncTombstone(
            recordID: SyncTombstone.collectionMembershipID(collectionID: collection.id, workID: work.id),
            recordType: .workCollectionMembership,
            createdAt: Date(timeIntervalSince1970: 150)
        ))
        collection.works.removeAll { $0.id == work.id }
        work.collections.removeAll { $0.id == collection.id }
        collection.markModified(Date(timeIntervalSince1970: 200))
        try context.save()

        _ = try KudosBackupService.restore(staleContents, into: context, defaults: defaults)

        let restored = try #require(try context.fetch(FetchDescriptor<WorkCollection>()).first)
        #expect(restored.works.isEmpty)
    }

    /// A collection snapshot demonstrably newer than the removal (e.g. the work was
    /// re-added on another device afterward) must still be allowed through.
    @Test func newerCollectionSnapshotRevivesRemovedMembership() async throws {
        let defaults = try testDefaults()
        let container = try container()
        let context = container.mainContext

        let work = try insertWork(into: context, title: "Re-shelved Work", ao3WorkID: 5002)
        let collection = WorkCollection(name: "Comfort Shelf")
        collection.id = UUID(uuidString: "00000000-0000-0000-0000-0000000C0222")!
        collection.markModified(Date(timeIntervalSince1970: 100))
        context.insert(collection)
        try context.save()

        // The user removes the work at t=150 — constructed directly (rather than via
        // SyncTombstones.recordCollectionMembershipRemoval, which stamps real "now") so
        // the timestamp is comparable against the synthetic t=300 archive below.
        context.insert(SyncTombstone(
            recordID: SyncTombstone.collectionMembershipID(collectionID: collection.id, workID: work.id),
            recordType: .workCollectionMembership,
            createdAt: Date(timeIntervalSince1970: 150)
        ))
        try context.save()

        // A newer snapshot (t=300) re-adds the work — newer than the removal, so it wins.
        collection.works.append(work)
        collection.markModified(Date(timeIntervalSince1970: 300))
        let newerContents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            collections: [collection],
            readingQueues: [],
            defaults: defaults
        )
        collection.works.removeAll { $0.id == work.id }
        collection.markModified(Date(timeIntervalSince1970: 100))
        try context.save()

        _ = try KudosBackupService.restore(newerContents, into: context, defaults: defaults)

        let restored = try #require(try context.fetch(FetchDescriptor<WorkCollection>()).first)
        #expect(restored.works.map(\.id) == [work.id])
    }

    /// The queue-conflict path reports suppressed/revived/ambiguous counts to the user;
    /// collections now must too, rather than resolving conflicts invisibly.
    @Test func collectionTombstoneConflictsAreReportedInRestoreSummary() throws {
        let defaults = try testDefaults()

        // Build the stale archived collection in a throwaway source container, mirroring
        // how every other test in this file builds KudosBackup* structs from real models.
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let staleCollection = WorkCollection(name: "Long Gone")
        let suppressedID = UUID(uuidString: "00000000-0000-0000-0000-0000000C0333")!
        staleCollection.id = suppressedID
        staleCollection.markModified(Date(timeIntervalSince1970: 100))
        sourceContext.insert(staleCollection)
        try sourceContext.save()
        let staleContents = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [],
            collections: [staleCollection],
            readingQueues: [],
            defaults: defaults
        )

        let container = try container()
        let context = container.mainContext
        context.insert(SyncTombstone(
            recordID: suppressedID,
            recordType: .workCollection,
            createdAt: Date(timeIntervalSince1970: 500)
        ))
        try context.save()

        let summary = try KudosBackupService.restore(staleContents, into: context, defaults: defaults)

        #expect(summary.suppressedCollections == 1)
        #expect(try context.fetch(FetchDescriptor<WorkCollection>()).isEmpty)
        #expect(summary.conflictMessage.contains("previously deleted collection"))
    }

    @Test func syncUpDoesNotChangeLocalModificationDates() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        let modifiedAt = Date(timeIntervalSince1970: 400)
        let work = SavedWork(title: "Stable Work", author: "Writer")
        work.markModified(modifiedAt)
        let collection = WorkCollection(name: "Stable Shelf")
        collection.markModified(modifiedAt)
        context.insert(work)
        context.insert(collection)
        try context.save()

        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        #expect(work.lastModifiedAt == modifiedAt)
        #expect(collection.lastModifiedAt == modifiedAt)
    }

    /// A failed sync-up write must never destroy the existing remote manifest — the
    /// previous copy is the only cloud copy, so other devices must still be able to
    /// restore from it.
    @Test func failedSyncUpWritePreservesExistingRemoteManifest() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        try insertWork(into: context, title: "Survivor Work", ao3WorkID: 7001)
        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        // A read-only sync directory makes the manifest's atomic replacement fail
        // mid-write — exactly the window where a non-atomic writer would have
        // already truncated or removed the previous copy.
        let syncDirectoryURL = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: syncDirectoryURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: syncDirectoryURL.path
            )
        }

        try insertWork(into: context, title: "Doomed Update", ao3WorkID: 7002)
        await #expect(throws: (any Error).self) {
            _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)
        }

        let contents = try KudosBackupContents.read(from: syncDirectoryURL)
        #expect(contents.manifest.works.count == 1)
        #expect(contents.manifest.works.first?.title == "Survivor Work")
    }

    /// Migration: a folder that still holds the pre-archive
    /// `KudosLibrary.kudosbackup` directory package is folded read-only — its
    /// data arrives, the new plain-directory layout is written alongside, and
    /// the legacy package itself is never modified or deleted, so an
    /// old-version device (or an interrupted migration) can still rely on it.
    @Test func legacySyncPackageIsFoldedReadOnlyAndLeftUntouched() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Build the legacy on-disk shape by hand — production code no longer writes it.
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let work = try insertWork(into: sourceContext, title: "Legacy Survivor", ao3WorkID: 8001)
        let legacyContents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let legacyManifestData = try legacyContents.manifestData()
        let legacyURL = folder.appendingPathComponent(FolderSyncService.legacySyncFileName)
        let wrapper = FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: legacyManifestData),
            "Works": FileWrapper(directoryWithFileWrappers: [:]),
            "Fonts": FileWrapper(directoryWithFileWrappers: [:])
        ])
        try wrapper.write(to: legacyURL, options: .atomic, originalContentsURL: nil)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let first = try await FolderSyncService.syncNow(in: targetContext, defaults: targetDefaults)
        #expect(first.restoredWorks == 1)
        #expect(first.didReadRemoteFile)
        #expect(first.missingRemoteFile == false)

        // The new layout now exists; the legacy package is byte-identical.
        let newManifestURL = folder
            .appendingPathComponent(FolderSyncService.syncDirectoryName)
            .appendingPathComponent(FolderSyncService.manifestFileName)
        #expect(FileManager.default.fileExists(atPath: newManifestURL.path))
        let legacyManifestAfter = try Data(
            contentsOf: legacyURL.appendingPathComponent("manifest.json")
        )
        #expect(legacyManifestAfter == legacyManifestData)

        // Idempotent: a repeat sync neither duplicates records nor re-reads.
        let second = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(second.skippedUnchanged)
        #expect(try targetContext.fetch(FetchDescriptor<SavedWork>()).count == 1)
    }

    /// The point of the plain-directory payload: an unchanged EPUB is not
    /// rewritten by later sync-ups, so iCloud Drive never re-uploads it.
    @Test func syncUpLeavesUnchangedEPUBFilesAlone() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        let work = try insertWork(into: context, title: "Stable EPUB", ao3WorkID: 9001)
        work.hasEPUB = true
        let epub = try Data(contentsOf: EPUBTests.sampleEPUB)
        try epub.write(to: work.fileURL)
        defer { try? FileManager.default.removeItem(at: work.fileURL) }
        try context.save()

        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        let remoteEPUBURL = folder
            .appendingPathComponent(FolderSyncService.syncDirectoryName)
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
            .appendingPathComponent("\(work.id.uuidString).epub")
        #expect(FileManager.default.fileExists(atPath: remoteEPUBURL.path))
        // Backdate the remote copy so any rewrite is detectable.
        let sentinelDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: sentinelDate],
            ofItemAtPath: remoteEPUBURL.path
        )

        try insertWork(into: context, title: "Unrelated Addition", ao3WorkID: 9002)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        let modified = try #require(
            try FileManager.default.attributesOfItem(atPath: remoteEPUBURL.path)[.modificationDate]
                as? Date
        )
        #expect(modified == sentinelDate)
    }

    /// Orphaned asset files (no manifest record references them anymore) are
    /// removed after the manifest commit; a remote EPUB whose work is still in
    /// the manifest survives even when this device holds no local copy, and
    /// unrelated hidden files are left alone.
    @Test func syncUpRemovesOrphanedAssetsButKeepsManifestReferencedOnes() async throws {
        let container = try container()
        let context = container.mainContext
        let defaults = try testDefaults()
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        defer { FolderSyncService.disconnect(defaults: defaults) }

        let work = try insertWork(into: context, title: "Referenced Work", ao3WorkID: 9101)
        try FolderSyncService.connect(to: folder, defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        let worksDirectory = folder
            .appendingPathComponent(FolderSyncService.syncDirectoryName)
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
        let orphanURL = worksDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        try Data("orphan".utf8).write(to: orphanURL)
        // Another device preserved this work's EPUB; this device has no local copy.
        let keptURL = worksDirectory.appendingPathComponent("\(work.id.uuidString).epub")
        try Data("kept-remote-epub".utf8).write(to: keptURL)
        let hiddenURL = worksDirectory.appendingPathComponent(".DS_Store")
        try Data("hidden".utf8).write(to: hiddenURL)

        FolderSyncService.markDirty(defaults: defaults)
        _ = try await FolderSyncService.syncUp(in: context, defaults: defaults)

        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        #expect(FileManager.default.fileExists(atPath: keptURL.path))
        #expect(FileManager.default.fileExists(atPath: hiddenURL.path))
    }

    /// A manifest can sync down while an EPUB is still an undownloaded iCloud
    /// placeholder. The work must still restore (without the EPUB), the skip
    /// stamp must stay withheld, and the EPUB must be fetched by a later sync
    /// even though the manifest never changes again.
    @Test func syncDownRetriesManifestReferencedEPUBOnceItAppears() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        // Remote state by hand: a manifest listing an EPUB-bearing work, but no
        // EPUB file uploaded yet.
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let work = try insertWork(into: sourceContext, title: "Late EPUB", ao3WorkID: 9201)
        work.hasEPUB = true
        try sourceContext.save()
        let contents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let syncDirectoryURL = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let worksDirectory = syncDirectoryURL
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
        try FileManager.default.createDirectory(
            at: worksDirectory,
            withIntermediateDirectories: true
        )
        try contents.manifestData().write(
            to: syncDirectoryURL.appendingPathComponent(FolderSyncService.manifestFileName),
            options: .atomic
        )
        // The EPUB itself is still only an iCloud placeholder — present in the
        // listing, contents not yet downloaded.
        let placeholderURL = worksDirectory
            .appendingPathComponent(".\(work.id.uuidString).epub.icloud")
        try Data().write(to: placeholderURL)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let first = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        let restored = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        defer { try? FileManager.default.removeItem(at: restored.fileURL) }
        #expect(first.didReadRemoteFile)
        #expect(restored.hasEPUB == false)

        // The EPUB materializes later, with no manifest change at all.
        let epub = try Data(contentsOf: EPUBTests.sampleEPUB)
        try epub.write(to: worksDirectory.appendingPathComponent("\(work.id.uuidString).epub"))
        try FileManager.default.removeItem(at: placeholderURL)

        let second = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(second.skippedUnchanged == false)
        #expect(second.didReadRemoteFile)
        #expect(restored.hasEPUB)
        #expect(FileManager.default.fileExists(atPath: restored.fileURL.path))

        // Once everything has arrived, the skip stamp finally engages.
        let third = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(third.skippedUnchanged)
    }

    /// A4 / M12: a regular sync folder whose EPUB asset is a symlink to a file
    /// outside the folder must not import that file's bytes.
    ///
    /// The symlink target is a *valid* EPUB (`EPUBTests.sampleEPUB`). A5-F3's
    /// restore-time validator would accept those bytes, so `hasEPUB == false`
    /// after `syncDown` can only come from `readRegularFileData`'s `lstat` /
    /// `S_IFLNK` reject — not from the EPUB validator discarding garbage.
    @Test func syncDownRejectsSymlinkedEPUBAsset() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let work = try insertWork(into: sourceContext, title: "Symlink Bait", ao3WorkID: 9301)
        work.hasEPUB = true
        try sourceContext.save()
        let contents = try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let syncDirectoryURL = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let worksDirectory = syncDirectoryURL
            .appendingPathComponent(FolderSyncService.worksSubdirectoryName)
        try FileManager.default.createDirectory(
            at: worksDirectory,
            withIntermediateDirectories: true
        )
        try contents.manifestData().write(
            to: syncDirectoryURL.appendingPathComponent(FolderSyncService.manifestFileName),
            options: .atomic
        )

        let secretDirectory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: secretDirectory) }
        let secretURL = secretDirectory.appendingPathComponent("secret.epub")
        let secretBytes = try Data(contentsOf: EPUBTests.sampleEPUB)
        try secretBytes.write(to: secretURL)
        // A5-F3 would accept these bytes if the symlink were followed.
        _ = try EPUBDocument.inspectPackage(ofEPUBAt: secretURL)
        let remoteEPUB = worksDirectory.appendingPathComponent("\(work.id.uuidString).epub")
        try FileManager.default.createSymbolicLink(at: remoteEPUB, withDestinationURL: secretURL)
        #expect(FolderSyncService.isSymbolicLink(at: remoteEPUB))
        #expect(throws: FolderSyncError.symlinkedAsset) {
            try FolderSyncService.readRegularFileData(from: remoteEPUB)
        }
        #expect(try Data(contentsOf: remoteEPUB) == secretBytes)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        _ = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        let restored = try #require(try targetContext.fetch(FetchDescriptor<SavedWork>()).first)
        defer { try? FileManager.default.removeItem(at: restored.fileURL) }

        #expect(restored.hasEPUB == false)
        #expect(FileManager.default.fileExists(atPath: restored.fileURL.path) == false)
        if FileManager.default.fileExists(atPath: restored.fileURL.path) {
            let imported = try Data(contentsOf: restored.fileURL)
            #expect(imported != secretBytes)
        }
    }

    @Test func syncDownSkipsUnchangedRemotePackage() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let sourceDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: sourceDefaults) }
        try insertWork(into: sourceContext, title: "Skip Candidate", ao3WorkID: 6001)
        try FolderSyncService.connect(to: folder, defaults: sourceDefaults)
        _ = try await FolderSyncService.syncUp(in: sourceContext, defaults: sourceDefaults)

        // The writing device must not fully re-restore its own just-written file.
        let ownDown = try await FolderSyncService.syncDown(in: sourceContext, defaults: sourceDefaults)
        #expect(ownDown.skippedUnchanged)
        #expect(ownDown.didReadRemoteFile == false)

        let targetContainer = try container()
        let targetContext = targetContainer.mainContext
        let targetDefaults = try testDefaults()
        defer { FolderSyncService.disconnect(defaults: targetDefaults) }
        try FolderSyncService.connect(to: folder, defaults: targetDefaults)

        let first = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(first.didReadRemoteFile)
        #expect(first.skippedUnchanged == false)
        #expect(first.restoredWorks == 1)

        let second = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(second.skippedUnchanged)
        #expect(second.didReadRemoteFile == false)
        #expect(second.restoredWorks == 0)
        #expect(second.foldedConflicts == 0)

        // A genuine remote change makes the next sync-down restore again. The explicit
        // modification-date bump guards against filesystem timestamp granularity.
        try insertWork(into: sourceContext, title: "Second Work", ao3WorkID: 6002)
        _ = try await FolderSyncService.syncUp(in: sourceContext, defaults: sourceDefaults)
        let manifestURL = folder
            .appendingPathComponent(FolderSyncService.syncDirectoryName)
            .appendingPathComponent(FolderSyncService.manifestFileName)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: manifestURL.path
        )

        let third = try await FolderSyncService.syncDown(in: targetContext, defaults: targetDefaults)
        #expect(third.skippedUnchanged == false)
        #expect(third.didReadRemoteFile)
        let targetWorks = try targetContext.fetch(FetchDescriptor<SavedWork>())
        #expect(Set(targetWorks.compactMap(\.ao3WorkID)) == [6001, 6002])
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
            .appendingPathComponent("FolderSyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "FolderSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func validFontData(excluding excludedData: Data? = nil) throws -> (Data, String) {
        let names = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        for name in names {
            let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, 12)
            guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL,
                  ["ttf", "otf"].contains(url.pathExtension.lowercased()),
                  let data = try? Data(contentsOf: url),
                  data.count <= KudosBackupContents.maxFontEntryBytes,
                  data != excludedData
            else { continue }
            return (data, url.pathExtension.lowercased())
        }
        throw KudosBackupError.invalidPackage
    }

    private func fontManifest(fileName: String, readerFontID: String) throws -> KudosBackupManifest {
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let font = CustomFont(name: "Remote", fileName: fileName)
        sourceContext.insert(font)
        try sourceContext.save()
        let defaults = try testDefaults()
        defaults.set(readerFontID, forKey: "readerFontID")
        return try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [font],
            readingQueues: [],
            defaults: defaults
        ).manifest
    }

    private func writeRemoteFont(
        manifest: KudosBackupManifest,
        fileName: String,
        data: Data,
        to folder: URL
    ) throws {
        try writeRemoteFonts(manifest: manifest, fontFiles: [fileName: data], to: folder)
    }

    private func writeRemoteFonts(
        manifest: KudosBackupManifest,
        fontFiles: [String: Data],
        to folder: URL
    ) throws {
        let syncDirectory = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        let fontsDirectory = syncDirectory.appendingPathComponent(
            FolderSyncService.fontsSubdirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
        try KudosBackupContents(manifest: manifest).manifestData().write(
            to: syncDirectory.appendingPathComponent(FolderSyncService.manifestFileName),
            options: .atomic
        )
        for (fileName, data) in fontFiles {
            try data.write(to: fontsDirectory.appendingPathComponent(fileName), options: .atomic)
        }
    }

    @discardableResult
    private func insertWork(
        into context: ModelContext,
        title: String,
        ao3WorkID: Int
    ) throws -> SavedWork {
        let work = SavedWork(
            title: title,
            author: "Writer",
            sourceURL: "https://archiveofourown.org/works/\(ao3WorkID)"
        )
        work.ao3WorkID = ao3WorkID
        work.markModified(Date(timeIntervalSince1970: TimeInterval(ao3WorkID)))
        context.insert(work)
        try context.save()
        return work
    }

    private func insertLibraryFixture(into context: ModelContext) throws -> (
        workID: UUID,
        queueID: UUID,
        collectionID: UUID
    ) {
        let work = try insertWork(into: context, title: "Synced Fixture", ao3WorkID: 4001)
        let queue = ReadingQueue(
            name: "Weekend Reads",
            dateCreated: Date(timeIntervalSince1970: 100),
            dateUpdated: Date(timeIntervalSince1970: 100)
        )
        let membership = ReadingQueueMembership(
            queue: queue,
            work: work,
            queuedAt: Date(timeIntervalSince1970: 101),
            sortOrderInQueue: 0
        )
        let collection = WorkCollection(name: "Comfort Shelf")
        collection.works.append(work)
        work.collections.append(collection)
        context.insert(queue)
        context.insert(membership)
        context.insert(collection)
        queue.memberships.append(membership)
        work.queueMemberships.append(membership)
        try context.save()
        return (work.id, queue.id, collection.id)
    }

    private func backupContents(title: String, ao3WorkID: Int) throws -> KudosBackupContents {
        let sourceContainer = try container()
        let sourceContext = sourceContainer.mainContext
        let work = try insertWork(into: sourceContext, title: title, ao3WorkID: ao3WorkID)
        return try KudosBackupService.makeContents(
            works: [work],
            bookmarks: [],
            fonts: [],
            readingQueues: [],
            defaults: try testDefaults()
        )
    }
}
}
