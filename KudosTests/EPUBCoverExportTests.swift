import Foundation
import ImageIO
import SwiftData
import Testing
@testable import Kudos

struct EPUBCoverExportTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
    }

    private func variant(_ change: (String) -> String,
                         chapter: ((String) -> String)? = nil,
                         mimetypeLast: Bool = false,
                         extra: [(name: String, data: Data)] = []) throws -> URL {
        let zip = try MiniZip(data: Data(contentsOf: EPUBTests.sampleEPUB))
        var names = zip.names
        if mimetypeLast { names.removeAll { $0 == "mimetype" }; names.append("mimetype") }
        let entries = try names.map { name -> (name: String, data: Data) in
            let bytes = try #require(zip.data(named: name))
            if name == "OEBPS/content.opf" {
                return (name, Data(change(try #require(String(data: bytes, encoding: .utf8))).utf8))
            }
            if name == "OEBPS/ch1.xhtml", let chapter {
                return (name, Data(chapter(try #require(String(data: bytes, encoding: .utf8))).utf8))
            }
            return (name, bytes)
        }
        let url = temporaryFile()
        try MiniZip.archiveData(entries + extra).write(to: url)
        return url
    }

    private func exported(from source: URL) throws -> MiniZip {
        let target = temporaryFile()
        defer { try? FileManager.default.removeItem(at: target) }
        try EPUBCoverExport.copy(from: source, to: target, includeCover: true,
                                 coverJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        return try MiniZip(data: Data(contentsOf: target))
    }

    @Test func addsCoverDeclarationAndReadableFirstPage() throws {
        let target = temporaryFile()
        defer { try? FileManager.default.removeItem(at: target) }
        let original = try Data(contentsOf: EPUBTests.sampleEPUB)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try EPUBCoverExport.copy(from: EPUBTests.sampleEPUB, to: target,
                                 includeCover: true, coverJPEG: jpeg)
        #expect(try Data(contentsOf: EPUBTests.sampleEPUB) == original)
        let zip = try MiniZip(data: Data(contentsOf: target))
        let opf = try #require(zip.data(named: "OEBPS/content.opf"))
        let before = OPFParser()
        let source = try MiniZip(data: Data(contentsOf: EPUBTests.sampleEPUB))
        #expect(before.parse(try #require(source.data(named: "OEBPS/content.opf"))))
        #expect(before.coverMetaID == nil)
        let after = OPFParser()
        #expect(after.parse(opf))
        #expect(after.coverMetaID == "kudos-export-cover-image")
        #expect(after.manifestProps["kudos-export-cover-image"] == nil) // EPUB 2 uses cover meta
        #expect(after.spine.first == "kudos-export-cover-page")
        #expect(zip.data(named: "OEBPS/kudos-export-cover.jpg") == jpeg)
        let unpacked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: unpacked) }
        let document = try EPUBDocument.open(epubURL: target, into: unpacked)
        #expect(document.spineURLs.count == before.spine.count + 1)
    }

    @Test func existingDeclaredCoverIsKeptByteForByte() throws {
        let original = try Data(contentsOf: EPUBTests.sampleEPUB)
        let zip = try MiniZip(data: original)
        let opfBytes = try #require(zip.data(named: "OEBPS/content.opf"))
        let opf = try #require(String(data: opfBytes, encoding: .utf8))
        let declared = opf.replacingOccurrences(of: "</metadata>",
            with: "<meta name=\"cover\" content=\"existing\"/></metadata>")
        #expect(declared != opf)
        let entries = try zip.names.map { name -> (name: String, data: Data) in
            (name, name == "OEBPS/content.opf" ? Data(declared.utf8) : try #require(zip.data(named: name)))
        }
        let source = temporaryFile(), target = temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: target)
        }
        let bytes = try MiniZip.archiveData(entries)
        try bytes.write(to: source)
        try EPUBCoverExport.copy(from: source, to: target, includeCover: true, coverJPEG: Data([1]))
        #expect(try Data(contentsOf: target) == bytes)
    }

    @Test func disabledCoverPreservesOriginalBytes() throws {
        let target = temporaryFile()
        defer { try? FileManager.default.removeItem(at: target) }
        try EPUBCoverExport.copy(from: EPUBTests.sampleEPUB, to: target, includeCover: false)
        #expect(try Data(contentsOf: target) == Data(contentsOf: EPUBTests.sampleEPUB))
    }

    @Test func cancelledCopyLeavesNoExport() async throws {
        let source = try EPUBTests.sampleEPUB
        let target = temporaryFile()
        defer { try? FileManager.default.removeItem(at: target) }
        let worker = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            try EPUBCoverExport.copy(from: source, to: target, includeCover: true,
                                     coverJPEG: Data([1]))
        }
        do {
            try await worker.value
            Issue.record("Expected cancellation before any export was written")
        } catch is CancellationError {
            #expect(!FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test func inlineImageOrCommentNeverLeavesCoverPageOutOfSpine() throws {
        for snippet in ["<img src='art.jpg'/>", "<!-- <img src='art.jpg'> -->"] {
            let source = try variant({ $0 }, chapter: {
                $0.replacingOccurrences(of: "</body>", with: snippet + "</body>")
            })
            defer { try? FileManager.default.removeItem(at: source) }
            let zip = try exported(from: source)
            let parser = OPFParser()
            #expect(parser.parse(try #require(zip.data(named: "OEBPS/content.opf"))))
            let pageID = try #require(parser.spine.first)
            #expect(parser.manifest[pageID] == "kudos-export-cover.xhtml")
            #expect(zip.data(named: "OEBPS/kudos-export-cover.xhtml") != nil)
        }
    }

    @Test func existingManifestIDsAreUniqued() throws {
        let source = try variant {
            $0.replacingOccurrences(of: "</manifest>", with: """
            <item id="kudos-export-cover-image" href="ch1.xhtml" media-type="application/xhtml+xml"/>
            <item id="kudos-export-cover-page" href="ch2.xhtml" media-type="application/xhtml+xml"/>
            </manifest>
            """)
        }
        defer { try? FileManager.default.removeItem(at: source) }
        let zip = try exported(from: source)
        let parser = OPFParser()
        #expect(parser.parse(try #require(zip.data(named: "OEBPS/content.opf"))))
        #expect(parser.coverMetaID == "kudos-export-cover-image-1")
        #expect(parser.spine.first == "kudos-export-cover-page-1")
    }

    @Test func prefixedPackageCommentsAndEmptySpineRemainParseable() throws {
        let source = try variant {
            $0.replacingOccurrences(of: "<package ", with:
                "<opf:package xmlns:opf=\"http://www.idpf.org/2007/opf\" ")
              .replacingOccurrences(of: "</package>", with: "</opf:package>")
              .replacingOccurrences(of: "  <metadata ", with:
                "  <!-- </metadata><spine -->\n  <opf:metadata ")
              .replacingOccurrences(of: "</metadata>", with: "</opf:metadata>")
              .replacingOccurrences(of: "<manifest>", with: "<opf:manifest>")
              .replacingOccurrences(of: "</manifest>", with: "</opf:manifest>")
              .replacingOccurrences(of: #"<spine toc="ncx">[\s\S]*?</spine>"#,
                                     with: "<opf:spine/>", options: .regularExpression)
        }
        defer { try? FileManager.default.removeItem(at: source) }
        let zip = try exported(from: source)
        let opf = try #require(zip.data(named: "OEBPS/content.opf"))
        let parser = OPFParser()
        #expect(parser.parse(opf))
        #expect(parser.coverMetaID != nil)
        #expect(parser.spine.count == 1)
        let text = try #require(String(data: opf, encoding: .utf8))
        #expect(text.contains("<opf:itemref"))
        #expect(text.contains("</opf:spine>"))
    }

    @Test func emptyCoverMetaGetsRealCoverAndMimetypeIsFirst() throws {
        let source = try variant({
            $0.replacingOccurrences(of: "</metadata>",
                with: "<meta name=\"cover\" content=\"\"/></metadata>")
        }, mimetypeLast: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let zip = try exported(from: source)
        #expect(zip.names.first == "mimetype")
        let parser = OPFParser()
        #expect(parser.parse(try #require(zip.data(named: "OEBPS/content.opf"))))
        #expect(parser.coverMetaID == "kudos-export-cover-image")
        #expect(parser.manifestProps["kudos-export-cover-image"] == nil) // EPUB 2
    }

    @Test func guideOnlyCoverPreservesOriginalBytes() throws {
        let source = try variant {
            $0.replacingOccurrences(of: "</package>",
                with: "<guide><reference type=\"cover\" href=\"ch1.xhtml\"/></guide></package>")
        }
        let target = temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: target)
        }
        try EPUBCoverExport.copy(from: source, to: target, includeCover: true, coverJPEG: Data([1]))
        #expect(try Data(contentsOf: source) == Data(contentsOf: target))
    }

    @Test func epub3CoverImagePropertyPreservesOriginalBytes() throws {
        let source = try variant {
            $0.replacingOccurrences(of: "version=\"2.0\"", with: "version=\"3.0\"")
              .replacingOccurrences(of: "id=\"ch1\" href=", with:
                "id=\"ch1\" properties=\"nav cover-image\" href=")
        }
        let target = temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: target)
        }
        try EPUBCoverExport.copy(from: source, to: target, includeCover: true, coverJPEG: Data([1]))
        #expect(try Data(contentsOf: source) == Data(contentsOf: target))
    }

    @Test func caseFoldedResourceNameGetsNewBasename() throws {
        let source = try variant({ $0 }, extra: [
            ("OEBPS/Kudos-Export-Cover.jpg", Data([1]))
        ])
        defer { try? FileManager.default.removeItem(at: source) }
        let zip = try exported(from: source)
        #expect(zip.data(named: "OEBPS/Kudos-Export-Cover.jpg") == Data([1]))
        #expect(zip.data(named: "OEBPS/kudos-export-cover-1.jpg") != nil)
    }

    @Test func utf16PackageGetsUtf8Declaration() throws {
        let base = try MiniZip(data: Data(contentsOf: EPUBTests.sampleEPUB))
        let entries = try base.names.map { name -> (name: String, data: Data) in
            let data = try #require(base.data(named: name))
            guard name == "OEBPS/content.opf" else { return (name, data) }
            let text = try #require(String(data: data, encoding: .utf8))
                .replacingOccurrences(of: "encoding=\"UTF-8\"", with: "encoding=\"UTF-16\"")
            return (name, try #require(text.data(using: .utf16)))
        }
        let source = temporaryFile()
        defer { try? FileManager.default.removeItem(at: source) }
        try MiniZip.archiveData(entries).write(to: source)
        let zip = try exported(from: source)
        let opf = try #require(zip.data(named: "OEBPS/content.opf"))
        #expect(String(data: opf, encoding: .utf8)?.contains("encoding=\"utf-8\"") == true)
        #expect(OPFParser().parse(opf))
    }

    @Test func embeddedArtKeepsWholeImageAndAppliesEXIFOrientation() throws {
        let context = try #require(CGContext(
            data: nil, width: 1200, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.7, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        let image = try #require(context.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            bytes, "public.jpeg" as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image,
                                   [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let encoded = try #require(EPUBCoverExport.encodedEmbeddedJPEG(bytes as Data))
        let source = try #require(CGImageSourceCreateWithData(encoded as CFData, nil))
        let upright = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(upright.width == 600)
        #expect(upright.height == 1200)
    }

    @Test @MainActor func generatedCoverHasNoWhiteCornerWedge() throws {
        let work = SavedWork(title: "A Generated Cover", author: "Writer")
        let jpeg = try #require(EPUBCoverExport.jpeg(for: work))
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 1600)
        #expect(image.height == 2400)
        let corner = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #expect(pixel.prefix(3).contains(where: { $0 < 245 }))
    }

    #if os(iOS)
    @Test @MainActor func concealedWorkNeverReachesExportInputs() {
        let safe = SavedWork(title: "Safe", author: "Author")
        safe.rating = "Teen And Up Audiences"
        let mature = SavedWork(title: "Secret", author: "Author")
        mature.rating = "Explicit"
        let gate = PrivacyGate()
        #expect(WorkEPUBExportSheet.exportable([safe, mature], gate: gate,
                                               hideMature: true).map(\.id) == [safe.id])
        #expect(WorkEPUBExportSheet.exportable([safe, mature], gate: gate,
                                               hideMature: false).count == 2)
    }

    @Test @MainActor func filenameStripsControlCharacters() {
        let name = WorkEPUBExportSheet.safeFilename(title: "bad\0/name:\nend", id: UUID())
        #expect(!name.contains("\0"))
        #expect(!name.contains("\n"))
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
    }

    @Test @MainActor func staleExportCleanupLeavesFreshAndUnrelatedFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let old = root.appendingPathComponent("KudosWorkExport-old")
        let fresh = root.appendingPathComponent("KudosWorkExport-fresh")
        let unrelated = root.appendingPathComponent("Unrelated-old")
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in [old, fresh, unrelated] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let past = Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: unrelated.path)
        WorkEPUBExportSheet.removeStaleExports(in: root, olderThan: Date().addingTimeInterval(-24 * 60 * 60))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }
    #endif

    @Test @MainActor func coveredFileImportsAsAWork() async throws {
        let target = temporaryFile()
        defer { try? FileManager.default.removeItem(at: target) }
        try EPUBCoverExport.copy(from: EPUBTests.sampleEPUB, to: target,
                                 includeCover: true, coverJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self, SyncTombstone.self
        ])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        let outcome = try await importUserEPUB(target, into: container.mainContext)
        switch outcome {
        case .imported(let work):
            #expect(work.title == "A Test Work")
            defer { try? FileManager.default.removeItem(at: work.fileURL) }
        case .restored, .duplicate:
            Issue.record("Expected a covered EPUB to import as a new work")
        }
    }

    #if os(iOS)
    @Test @MainActor func coveredFileOpensInReadium() async throws {
        let target = temporaryFile()
        defer { try? FileManager.default.removeItem(at: target) }
        let cover = try #require(EPUBCoverExport.generatedJPEG(
            for: SavedWork(title: "Reader Cover", author: "Writer")
        ))
        try EPUBCoverExport.copy(from: EPUBTests.sampleEPUB, to: target,
                                 includeCover: true, coverJPEG: cover)
        let publication = try await ReadiumPublicationLoader.openEPUB(at: target)
        let positions = try await publication.positionsByReadingOrder().get()
        #expect(positions.count == 3)
    }
    #endif
}
