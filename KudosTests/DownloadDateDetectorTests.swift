import Foundation
import Testing
@testable import Kudos

struct DownloadDateDetectorTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func earliestFileDateWins() {
        let created = now.addingTimeInterval(-3_600)
        let modified = now.addingTimeInterval(-1_800)
        #expect(DownloadDateDetector.detect(
            fileCreated: created,
            fileModified: modified,
            epubGeneratedAt: now.addingTimeInterval(-7_200),
            now: now
        ) == DownloadDateDetection(date: created, source: .file))
    }

    @Test func freshCopyFallsBackToAO3Generation() {
        let generated = now.addingTimeInterval(-86_400)
        #expect(DownloadDateDetector.detect(
            fileCreated: now.addingTimeInterval(-60),
            fileModified: nil,
            epubGeneratedAt: generated,
            now: now
        ) == DownloadDateDetection(date: generated, source: .ao3Generated))
    }

    @Test func fileDateBeforeGenerationIsDiscarded() {
        let generated = now.addingTimeInterval(-3_600)
        #expect(DownloadDateDetector.detect(
            fileCreated: now.addingTimeInterval(-7_200),
            fileModified: nil,
            epubGeneratedAt: generated,
            now: now
        ) == DownloadDateDetection(date: generated, source: .ao3Generated))
    }

    @Test func noUsableFileDateOrTimestampUsesImportTime() {
        #expect(DownloadDateDetector.detect(
            fileCreated: now.addingTimeInterval(-60),
            fileModified: nil,
            epubGeneratedAt: nil,
            now: now
        ) == DownloadDateDetection(date: now, source: .importTime))
        #expect(DownloadDateDetector.detect(
            fileCreated: nil,
            fileModified: nil,
            epubGeneratedAt: nil,
            now: now
        ) == DownloadDateDetection(date: now, source: .importTime))
    }

    @Test func parsesCalibreTimestampWithAndWithoutFractionalSeconds() {
        #expect(DownloadDateDetector.parseEPUBTimestamp("2026-10-02T03:04:05.123Z") != nil)
        #expect(DownloadDateDetector.parseEPUBTimestamp("2026-10-02T03:04:05Z") != nil)
        #expect(DownloadDateDetector.parseEPUBTimestamp("") == nil)
    }

    @Test func opfParserReadsCalibreTimestamp() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf">
          <metadata><meta name="calibre:timestamp" content="2026-03-03T04:05:06Z"/></metadata>
        </package>
        """
        let parser = OPFParser()
        #expect(parser.parse(Data(xml.utf8)))
        #expect(parser.calibreTimestamp == "2026-03-03T04:05:06Z")
    }

    @Test @MainActor func backupWorkRoundTripsWithAndWithoutDownloadedAt() throws {
        let work = SavedWork(title: "A Work", author: "A Writer")
        let downloadedAt = Date(timeIntervalSince1970: 1_700_000_000)
        work.downloadedAt = downloadedAt

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(KudosBackupWork(work: work))
        #expect(try decoder.decode(KudosBackupWork.self, from: encoded).downloadedAt == downloadedAt)

        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "downloadedAt")
        let olderArchive = try JSONSerialization.data(withJSONObject: object)
        let decoded = try decoder.decode(KudosBackupWork.self, from: olderArchive)
        #expect(decoded.downloadedAt == nil)
        let reencoded = try #require(JSONSerialization.jsonObject(with: encoder.encode(decoded)) as? [String: Any])
        #expect(reencoded["downloadedAt"] == nil)
    }
}
