import CoreText
import Foundation
import SwiftData
import Testing
@testable import Kudos

extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct KudosBackupFontRestoreTests {
    private func setupSchema() throws -> ModelContext {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, SavedSearch.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self,
            ReadingAnnotation.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func getValidFontData(excluding excludedData: Data? = nil) throws -> (Data, String) {
        let names = CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        for name in names.sorted() {
            let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, 12.0)
            guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL else {
                continue
            }
            let fileExtension = url.pathExtension.lowercased()
            guard fileExtension == "ttf" || fileExtension == "otf" else { continue }
            guard let data = try? Data(contentsOf: url), data.count <= 4 * 1024 * 1024 else { continue }
            if data != excludedData {
                return (data, fileExtension)
            }
        }
        throw KudosBackupError.invalidPackage
    }

    private func testDefaults() throws -> UserDefaults {
        let name = "KudosBackupFontRestoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func validFontRestoresInstalledBytes() throws {
        let context = try setupSchema()
        let (fontData, ext) = try getValidFontData()
        let fileName = "test-font-\(UUID().uuidString).\(ext)"

        let archivedFont = CustomFont(name: "Test Font", fileName: fileName)
        let baseContents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [archivedFont], readingQueues: [], defaults: try testDefaults()
        )
        let directContents = KudosBackupContents(
            manifest: baseContents.manifest,
            fontFiles: [fileName: fontData]
        )

        let zipData = try directContents.zipData()
        let zippedContents = try KudosBackupContents(zipData: zipData)

        let installedURL = Storage.fontsDirectory.appendingPathComponent(fileName)
        defer { try? FileManager.default.removeItem(at: installedURL) }

        // zip round trip
        _ = try KudosBackupService.restore(zippedContents, into: context, defaults: try testDefaults())
        #expect(try Data(contentsOf: installedURL) == fontData)

        // direct sync shape
        try? FileManager.default.removeItem(at: installedURL)
        _ = try KudosBackupService.restore(directContents, into: context, defaults: try testDefaults())
        #expect(try Data(contentsOf: installedURL) == fontData)
    }

    @Test func invalidBytesWithSFNTSignatureAreRejected() throws {
        let context = try setupSchema()
        let fileName = "invalid-\(UUID().uuidString).ttf"
        let sfntData = Data([
            0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]) + Data(repeating: 0x41, count: 100)

        let archivedFont = CustomFont(name: "Invalid", fileName: fileName)
        let baseContents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [archivedFont], readingQueues: [], defaults: try testDefaults()
        )
        let contents = KudosBackupContents(manifest: baseContents.manifest, fontFiles: [fileName: sfntData])

        #expect(throws: KudosBackupError.self) {
            _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())
        }
    }

    @Test func unsupportedExtensionIsRejected() throws {
        let context = try setupSchema()
        let (fontData, _) = try getValidFontData()
        let fileName = "font-\(UUID().uuidString).txt"

        let archivedFont = CustomFont(name: "Invalid Ext", fileName: fileName)
        let baseContents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [archivedFont], readingQueues: [], defaults: try testDefaults()
        )
        let contents = KudosBackupContents(manifest: baseContents.manifest, fontFiles: [fileName: fontData])

        #expect(throws: KudosBackupError.self) {
            _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())
        }
    }

    @Test func zipOversizedEntryIsRejectedBeforeExtraction() throws {
        let (fontData, ext) = try getValidFontData()
        // limit is 4MiB, we add 4MiB to make it clearly over
        let oversizedData = fontData + Data(repeating: 0, count: 4 * 1024 * 1024)
        let fileName = "huge-\(UUID().uuidString).\(ext)"

        let archivedFont = CustomFont(name: "Huge Font", fileName: fileName)
        let baseContents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [archivedFont], readingQueues: [], defaults: try testDefaults()
        )
        let contents = KudosBackupContents(manifest: baseContents.manifest, fontFiles: [fileName: oversizedData])

        #expect(
            throws: KudosBackupError.self,
            "ZIP font size limits must be enforced before entry extraction."
        ) {
            _ = try KudosBackupContents(zipData: contents.zipData())
        }
    }

    @Test func zipOversizedAggregateIsRejectedBeforeExtraction() throws {
        let (fontData, ext) = try getValidFontData()

        var fontFiles: [String: Data] = [:]
        var archivedFonts: [CustomFont] = []
        // Aggregate limit is 32MiB. We use 10 files of 3.5MiB each = 35MiB total.
        let paddedData = fontData + Data(repeating: 0, count: (3 * 1024 * 1024 + 512 * 1024) - fontData.count)

        for i in 0..<10 {
            let fileName = "font\(i)-\(UUID().uuidString).\(ext)"
            archivedFonts.append(CustomFont(name: "Font \(i)", fileName: fileName))
            fontFiles[fileName] = paddedData
        }

        let baseContents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: archivedFonts, readingQueues: [], defaults: try testDefaults()
        )
        let contents = KudosBackupContents(manifest: baseContents.manifest, fontFiles: fontFiles)

        #expect(
            throws: KudosBackupError.self,
            "ZIP aggregate font limits must be enforced before entry extraction."
        ) {
            _ = try KudosBackupContents(zipData: contents.zipData())
        }
    }

    @Test func legacyDirectoryOversizedEntryIsRejectedBeforeRead() throws {
        let (fontData, ext) = try getValidFontData()
        let oversizedData = fontData + Data(repeating: 0, count: 4 * 1024 * 1024)
        let fileName = "legacy-huge-\(UUID().uuidString).\(ext)"
        let archivedFont = CustomFont(name: "Legacy Huge", fileName: fileName)
        let contents = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [archivedFont],
            readingQueues: [],
            defaults: try testDefaults()
        )
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-huge-\(UUID().uuidString).kudosbackup", isDirectory: true)
        let fontsURL = packageURL.appendingPathComponent("Fonts", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL) }
        try FileManager.default.createDirectory(at: fontsURL, withIntermediateDirectories: true)
        try contents.manifestData().write(to: packageURL.appendingPathComponent("manifest.json"))
        try oversizedData.write(to: fontsURL.appendingPathComponent(fileName))

        #expect(
            throws: KudosBackupError.self,
            "Legacy font size limits must be enforced before the full file is read."
        ) {
            _ = try KudosBackupContents.read(from: packageURL)
        }
    }

    @Test func unreadableLocalBytesAndOrphanSuffixArePreserved() throws {
        let context = try setupSchema()
        let (fontData, _) = try getValidFontData()
        let (archiveFontData, ext2) = try getValidFontData(excluding: fontData)

        let baseName = "conflict-\(UUID().uuidString)"
        let fileName = "\(baseName).\(ext2)"

        let archivedFont = CustomFont(name: "Archive Font", fileName: fileName)
        let baseContents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [archivedFont], readingQueues: [], defaults: try testDefaults()
        )
        let contents = KudosBackupContents(manifest: baseContents.manifest, fontFiles: [fileName: archiveFontData])

        try FileManager.default.createDirectory(at: Storage.fontsDirectory, withIntermediateDirectories: true)

        // 1. Write the local occupied file
        let occupiedURL = Storage.fontsDirectory.appendingPathComponent(fileName)
        try fontData.write(to: occupiedURL)
        let originalPermissions = try #require(
            try FileManager.default.attributesOfItem(atPath: occupiedURL.path)[.posixPermissions]
                as? NSNumber
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: occupiedURL.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: originalPermissions],
                ofItemAtPath: occupiedURL.path
            )
            try? FileManager.default.removeItem(at: occupiedURL)
        }
        try #require((try? Data(contentsOf: occupiedURL)) == nil)

        // 2. Also occupy the first `-restored-1` name
        let restored1URL = Storage.fontsDirectory.appendingPathComponent("\(baseName)-restored-1.\(ext2)")
        try fontData.write(to: restored1URL)
        defer { try? FileManager.default.removeItem(at: restored1URL) }

        // Expected fallback is `-restored-2`
        let expectedFallbackURL = Storage.fontsDirectory.appendingPathComponent("\(baseName)-restored-2.\(ext2)")
        defer { try? FileManager.default.removeItem(at: expectedFallbackURL) }

        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        try FileManager.default.setAttributes(
            [.posixPermissions: originalPermissions],
            ofItemAtPath: occupiedURL.path
        )
        #expect(try Data(contentsOf: occupiedURL) == fontData) // original unchanged
        #expect(try Data(contentsOf: restored1URL) == fontData) // restored-1 unchanged
        #expect(try Data(contentsOf: expectedFallbackURL) == archiveFontData) // archive written to restored-2

        let restoredFonts = try context.fetch(FetchDescriptor<CustomFont>())
        let dbFont = try #require(restoredFonts.first)
        #expect(dbFont.fileName == expectedFallbackURL.lastPathComponent)
    }

    @Test func identicalCaseVariantReusesLocalFileAndDatabaseRow() throws {
        let context = try setupSchema()
        let (fontData, fileExtension) = try getValidFontData()
        let baseName = "case-\(UUID().uuidString)"
        let localFileName = "\(baseName).\(fileExtension)"
        let archivedFileName = "\(baseName.uppercased()).\(fileExtension.uppercased())"
        let localURL = Storage.fontsDirectory.appendingPathComponent(localFileName)
        let archivedURL = Storage.fontsDirectory.appendingPathComponent(archivedFileName)
        defer {
            try? FileManager.default.removeItem(at: localURL)
            try? FileManager.default.removeItem(at: archivedURL)
        }

        try FileManager.default.createDirectory(at: Storage.fontsDirectory, withIntermediateDirectories: true)
        try fontData.write(to: localURL)
        context.insert(CustomFont(name: "Local Font", fileName: localFileName))
        try context.save()

        let archivedFont = CustomFont(name: "Archive Font", fileName: archivedFileName)
        let baseContents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [archivedFont], readingQueues: [], defaults: try testDefaults()
        )
        let contents = KudosBackupContents(
            manifest: baseContents.manifest,
            fontFiles: [archivedFileName: fontData]
        )

        _ = try KudosBackupService.restore(contents, into: context, defaults: try testDefaults())

        let restoredFonts = try context.fetch(FetchDescriptor<CustomFont>())
        #expect(restoredFonts.count == 1)
        #expect(restoredFonts.first?.fileName == localFileName)
        #expect(try Data(contentsOf: localURL) == fontData)
    }

    @Test func zipRestorePreservesAmbiguousCaseFoldedRowsAndFiles() async throws {
        try await CaseSensitiveFontTestVolume.withFontsDirectory {
            let fixture = try makeCaseVariantFixture()
            defer { cleanUpCaseVariantFixture(fixture) }
            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("case-fold-\(UUID().uuidString).kudosbackup")
            defer { try? FileManager.default.removeItem(at: archiveURL) }
            try fixture.contents.zipData().write(to: archiveURL)

            let decoded = try KudosBackupContents.read(from: archiveURL)
            _ = try KudosBackupService.restore(
                decoded,
                into: fixture.context,
                defaults: fixture.defaults
            )

            try assertCaseVariantFixtureWasPreserved(fixture)
        }
    }

    @Test func restorePreservesOneRowAndTwoCaseVariantFilesWhenIncomingMatchesOrphan() async throws {
        try await CaseSensitiveFontTestVolume.withFontsDirectory {
            let context = try setupSchema()
            let defaults = try testDefaults()
            let (incomingData, fileExtension) = try getValidFontData()
            let rowData = Data("original-row-bytes".utf8)
            let baseName = "one-row-case-\(UUID().uuidString)"
            let archivedFileName = "\(baseName.uppercased()).\(fileExtension.uppercased())"
            let orphanFileName = "\(baseName).\(fileExtension)"
            let suffixFileName = (archivedFileName as NSString).deletingPathExtension
                + "-restored-1.\((archivedFileName as NSString).pathExtension)"
            let archivedURL = Storage.fontsDirectory.appendingPathComponent(archivedFileName)
            let orphanURL = Storage.fontsDirectory.appendingPathComponent(orphanFileName)
            let suffixURL = Storage.fontsDirectory.appendingPathComponent(suffixFileName)
            defer {
                try? FileManager.default.removeItem(at: archivedURL)
                try? FileManager.default.removeItem(at: orphanURL)
                try? FileManager.default.removeItem(at: suffixURL)
            }
            try FileManager.default.createDirectory(
                at: Storage.fontsDirectory,
                withIntermediateDirectories: true
            )
            try rowData.write(to: archivedURL)
            try incomingData.write(to: orphanURL)

            let existingRow = CustomFont(name: "Existing", fileName: archivedFileName)
            context.insert(existingRow)
            try context.save()
            defaults.set("custom:\(archivedFileName)", forKey: "readerFontID")
            let incomingFont = CustomFont(name: "Incoming", fileName: archivedFileName)
            let baseContents = try KudosBackupService.makeContents(
                works: [],
                bookmarks: [],
                fonts: [incomingFont],
                readingQueues: [],
                defaults: defaults
            )
            let contents = KudosBackupContents(
                manifest: baseContents.manifest,
                fontFiles: [archivedFileName: incomingData]
            )

            _ = try KudosBackupService.restore(contents, into: context, defaults: defaults)

            #expect(
                try Data(contentsOf: archivedURL) == rowData,
                "The file owned by the sole DB row must retain its original bytes."
            )
            #expect(
                try Data(contentsOf: orphanURL) == incomingData,
                "The case-variant orphan file must retain its original bytes."
            )
            #expect(
                try Data(contentsOf: suffixURL) == incomingData,
                "An incoming font must use a suffix when two case-variant local files exist."
            )
            #expect(
                existingRow.fileName == archivedFileName,
                "The sole DB row must keep its original file name."
            )
            #expect(
                Set(try context.fetch(FetchDescriptor<CustomFont>()).map(\.fileName))
                    == [archivedFileName, suffixFileName],
                "The restore must retain the original row and add only the suffixed incoming row."
            )
            #expect(defaults.string(forKey: "readerFontID") == "custom:\(archivedFileName)")
        }
    }

    @Test func restoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile() async throws {
        try await CaseSensitiveFontTestVolume.withFontsDirectory {
            let fixture = try makeLocalFileAmbiguityFixture()
            defer { cleanUpLocalFileAmbiguityFixture(fixture) }

            _ = try KudosBackupService.restore(
                fixture.contents,
                into: fixture.context,
                defaults: fixture.defaults
            )

            try assertLocalFileAmbiguityFixtureWasPreserved(fixture)
        }
    }

    @Test func legacyDirectoryRestorePreservesAmbiguousCaseFoldedRowsAndFiles() async throws {
        try await CaseSensitiveFontTestVolume.withFontsDirectory {
            let fixture = try makeCaseVariantFixture()
            defer { cleanUpCaseVariantFixture(fixture) }
            let packageURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("case-fold-\(UUID().uuidString).kudosbackup", isDirectory: true)
            let fontsURL = packageURL.appendingPathComponent("Fonts", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: packageURL) }
            try FileManager.default.createDirectory(at: fontsURL, withIntermediateDirectories: true)
            try fixture.contents.manifestData().write(
                to: packageURL.appendingPathComponent("manifest.json")
            )
            try fixture.incomingData.write(
                to: fontsURL.appendingPathComponent(fixture.archivedFileName)
            )

            let decoded = try KudosBackupContents.read(from: packageURL)
            _ = try KudosBackupService.restore(
                decoded,
                into: fixture.context,
                defaults: fixture.defaults
            )

            try assertCaseVariantFixtureWasPreserved(fixture)
        }
    }

    @Test func zipRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile() async throws {
        try await CaseSensitiveFontTestVolume.withFontsDirectory {
            let fixture = try makeLocalFileAmbiguityFixture()
            defer { cleanUpLocalFileAmbiguityFixture(fixture) }
            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("case-fold-local-\(UUID().uuidString).kudosbackup")
            defer { try? FileManager.default.removeItem(at: archiveURL) }
            try fixture.contents.zipData().write(to: archiveURL)

            let decoded = try KudosBackupContents.read(from: archiveURL)
            _ = try KudosBackupService.restore(
                decoded,
                into: fixture.context,
                defaults: fixture.defaults
            )

            try assertLocalFileAmbiguityFixtureWasPreserved(fixture)
        }
    }

    @Test func legacyDirectoryRestoreTreatsTwoLocalFilesAsAmbiguousWhenIncomingMatchesDatabaseFile() async throws {
        try await CaseSensitiveFontTestVolume.withFontsDirectory {
            let fixture = try makeLocalFileAmbiguityFixture()
            defer { cleanUpLocalFileAmbiguityFixture(fixture) }
            let packageURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "case-fold-local-\(UUID().uuidString).kudosbackup",
                    isDirectory: true
                )
            let fontsURL = packageURL.appendingPathComponent("Fonts", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: packageURL) }
            try FileManager.default.createDirectory(at: fontsURL, withIntermediateDirectories: true)
            try fixture.contents.manifestData().write(
                to: packageURL.appendingPathComponent("manifest.json")
            )
            try fixture.incomingData.write(
                to: fontsURL.appendingPathComponent(fixture.archivedFileName)
            )

            let decoded = try KudosBackupContents.read(from: packageURL)
            _ = try KudosBackupService.restore(
                decoded,
                into: fixture.context,
                defaults: fixture.defaults
            )

            try assertLocalFileAmbiguityFixtureWasPreserved(fixture)
        }
    }

    @Test func localReaderFontIDRetention() throws {
        let context = try setupSchema()
        let defaults = try testDefaults()
        defaults.set("local-font-id", forKey: "readerFontID")

        let archiveDefaults = try testDefaults()
        archiveDefaults.set("archive-font-id", forKey: "readerFontID")

        let baseContents = try KudosBackupService.makeContents(
            works: [], bookmarks: [], fonts: [], readingQueues: [], defaults: archiveDefaults
        )
        let contents = KudosBackupContents(manifest: baseContents.manifest)

        _ = try KudosBackupService.restore(contents, into: context, defaults: defaults)

        #expect(defaults.string(forKey: "readerFontID") == "local-font-id")
    }

    private struct CaseVariantFixture {
        let context: ModelContext
        let defaults: UserDefaults
        let contents: KudosBackupContents
        let incomingData: Data
        let archivedFileName: String
        let localFileName: String
        let suffixFileName: String
        let archivedCaseRow: CustomFont
        let localCaseRow: CustomFont
    }

    private func makeCaseVariantFixture() throws -> CaseVariantFixture {
        let context = try setupSchema()
        let defaults = try testDefaults()
        let (incomingData, fileExtension) = try getValidFontData()
        let baseName = "restore-case-\(UUID().uuidString)"
        let archivedFileName = "\(baseName.uppercased()).\(fileExtension.uppercased())"
        let localFileName = "\(baseName).\(fileExtension)"
        let suffixFileName = (archivedFileName as NSString).deletingPathExtension
            + "-restored-1.\((archivedFileName as NSString).pathExtension)"
        let localURL = Storage.fontsDirectory.appendingPathComponent(localFileName)
        let suffixURL = Storage.fontsDirectory.appendingPathComponent(suffixFileName)
        let archivedURL = Storage.fontsDirectory.appendingPathComponent(archivedFileName)
        var fixtureCompleted = false
        defer {
            if !fixtureCompleted {
                try? FileManager.default.removeItem(at: localURL)
                try? FileManager.default.removeItem(at: suffixURL)
                try? FileManager.default.removeItem(at: archivedURL)
            }
        }
        try incomingData.write(to: localURL)
        try incomingData.write(to: archivedURL)

        let archivedCaseRow = CustomFont(name: "Archived Case", fileName: archivedFileName)
        let localCaseRow = CustomFont(name: "Local Case", fileName: localFileName)
        context.insert(archivedCaseRow)
        context.insert(localCaseRow)
        try context.save()
        defaults.set("custom:\(archivedFileName)", forKey: "readerFontID")

        let incomingFont = CustomFont(name: "Incoming", fileName: archivedFileName)
        let baseContents = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [incomingFont],
            readingQueues: [],
            defaults: defaults
        )
        let fixture = CaseVariantFixture(
            context: context,
            defaults: defaults,
            contents: KudosBackupContents(
                manifest: baseContents.manifest,
                fontFiles: [archivedFileName: incomingData]
            ),
            incomingData: incomingData,
            archivedFileName: archivedFileName,
            localFileName: localFileName,
            suffixFileName: suffixFileName,
            archivedCaseRow: archivedCaseRow,
            localCaseRow: localCaseRow
        )
        fixtureCompleted = true
        return fixture
    }

    private func assertCaseVariantFixtureWasPreserved(
        _ fixture: CaseVariantFixture
    ) throws {
        let rows = try fixture.context.fetch(FetchDescriptor<CustomFont>())
        #expect(
            Set(rows.map(\.fileName)) == [
                fixture.archivedFileName,
                fixture.localFileName,
                fixture.suffixFileName
            ],
            "Ambiguous case-fold matches must preserve every DB row and install a suffixed font."
        )
        #expect(fixture.archivedCaseRow.fileName == fixture.archivedFileName)
        #expect(fixture.localCaseRow.fileName == fixture.localFileName)
        #expect(
            try Data(
                contentsOf: Storage.fontsDirectory
                    .appendingPathComponent(fixture.localFileName)
            ) == fixture.incomingData
        )
        #expect(
            try Data(
                contentsOf: Storage.fontsDirectory
                    .appendingPathComponent(fixture.archivedFileName)
            ) == fixture.incomingData
        )
        #expect(
            try Data(
                contentsOf: Storage.fontsDirectory
                    .appendingPathComponent(fixture.suffixFileName)
            ) == fixture.incomingData
        )
        #expect(
            fixture.defaults.string(forKey: "readerFontID")
                == "custom:\(fixture.archivedFileName)"
        )
    }

    private func cleanUpCaseVariantFixture(_ fixture: CaseVariantFixture) {
        try? FileManager.default.removeItem(
            at: Storage.fontsDirectory.appendingPathComponent(fixture.localFileName)
        )
        try? FileManager.default.removeItem(
            at: Storage.fontsDirectory.appendingPathComponent(fixture.suffixFileName)
        )
        try? FileManager.default.removeItem(
            at: Storage.fontsDirectory.appendingPathComponent(fixture.archivedFileName)
        )
    }

    private struct LocalFileAmbiguityFixture {
        let context: ModelContext
        let defaults: UserDefaults
        let contents: KudosBackupContents
        let incomingData: Data
        let orphanData: Data
        let archivedFileName: String
        let orphanFileName: String
        let suffixFileName: String
        let existingRow: CustomFont
    }

    private func makeLocalFileAmbiguityFixture() throws -> LocalFileAmbiguityFixture {
        let context = try setupSchema()
        let defaults = try testDefaults()
        let (incomingData, fileExtension) = try getValidFontData()
        let orphanData = Data("case-variant-orphan".utf8)
        let baseName = "local-ambiguity-\(UUID().uuidString)"
        let archivedFileName = "\(baseName.uppercased()).\(fileExtension.uppercased())"
        let orphanFileName = "\(baseName).\(fileExtension)"
        let suffixFileName = (archivedFileName as NSString).deletingPathExtension
            + "-restored-1.\((archivedFileName as NSString).pathExtension)"
        let archivedURL = Storage.fontsDirectory.appendingPathComponent(archivedFileName)
        let orphanURL = Storage.fontsDirectory.appendingPathComponent(orphanFileName)
        let suffixURL = Storage.fontsDirectory.appendingPathComponent(suffixFileName)
        var fixtureCompleted = false
        defer {
            if !fixtureCompleted {
                try? FileManager.default.removeItem(at: archivedURL)
                try? FileManager.default.removeItem(at: orphanURL)
                try? FileManager.default.removeItem(at: suffixURL)
            }
        }
        try FileManager.default.createDirectory(
            at: Storage.fontsDirectory,
            withIntermediateDirectories: true
        )
        try incomingData.write(to: archivedURL)
        try orphanData.write(to: orphanURL)

        let existingRow = CustomFont(name: "Existing", fileName: archivedFileName)
        context.insert(existingRow)
        try context.save()
        defaults.set("custom:\(archivedFileName)", forKey: "readerFontID")
        let incomingFont = CustomFont(name: "Incoming", fileName: archivedFileName)
        let baseContents = try KudosBackupService.makeContents(
            works: [],
            bookmarks: [],
            fonts: [incomingFont],
            readingQueues: [],
            defaults: defaults
        )
        let fixture = LocalFileAmbiguityFixture(
            context: context,
            defaults: defaults,
            contents: KudosBackupContents(
                manifest: baseContents.manifest,
                fontFiles: [archivedFileName: incomingData]
            ),
            incomingData: incomingData,
            orphanData: orphanData,
            archivedFileName: archivedFileName,
            orphanFileName: orphanFileName,
            suffixFileName: suffixFileName,
            existingRow: existingRow
        )
        fixtureCompleted = true
        return fixture
    }

    private func assertLocalFileAmbiguityFixtureWasPreserved(
        _ fixture: LocalFileAmbiguityFixture
    ) throws {
        let archivedURL = Storage.fontsDirectory.appendingPathComponent(fixture.archivedFileName)
        let orphanURL = Storage.fontsDirectory.appendingPathComponent(fixture.orphanFileName)
        let suffixURL = Storage.fontsDirectory.appendingPathComponent(fixture.suffixFileName)
        #expect(
            (try? Data(contentsOf: suffixURL)) == fixture.incomingData,
            "Local-file ambiguity must force a suffixed restore even when the DB file matches."
        )
        #expect(fixture.existingRow.fileName == fixture.archivedFileName)
        #expect(try Data(contentsOf: archivedURL) == fixture.incomingData)
        #expect(try Data(contentsOf: orphanURL) == fixture.orphanData)
        #expect(
            Set(try fixture.context.fetch(FetchDescriptor<CustomFont>()).map(\.fileName))
                == [fixture.archivedFileName, fixture.suffixFileName],
            "A local-file ambiguity must preserve the row-owned bytes and add a suffixed row."
        )
        #expect(
            fixture.defaults.string(forKey: "readerFontID")
                == "custom:\(fixture.archivedFileName)"
        )
    }

    private func cleanUpLocalFileAmbiguityFixture(_ fixture: LocalFileAmbiguityFixture) {
        try? FileManager.default.removeItem(
            at: Storage.fontsDirectory.appendingPathComponent(fixture.archivedFileName)
        )
        try? FileManager.default.removeItem(
            at: Storage.fontsDirectory.appendingPathComponent(fixture.orphanFileName)
        )
        try? FileManager.default.removeItem(
            at: Storage.fontsDirectory.appendingPathComponent(fixture.suffixFileName)
        )
    }
}
}
