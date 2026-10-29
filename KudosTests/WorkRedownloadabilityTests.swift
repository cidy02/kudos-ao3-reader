import Foundation
import Testing
@testable import Kudos

/// Pure "can this be downloaded again, and why not" — the reason Recently Deleted
/// notes, Delete from Library, and Delete Permanently all share.
struct WorkRedownloadabilityTests {
    @Test func anAO3WorkCanBeDownloadedAgain() {
        let reason = WorkRedownloadability.of(
            origin: .archiveOfOurOwn,
            ao3Unavailable: false
        )
        #expect(reason == .canRedownload)
        #expect(reason.canRedownload)
        #expect(reason.rowTitle == nil)
        #expect(reason.rowBody == nil)
        #expect(!reason.shouldConfirmDelete(settingOn: false))
        #expect(reason.shouldConfirmDelete(settingOn: true))
    }

    @Test func ao3UnavailableMeansNoLongerOnAO3() {
        let reason = WorkRedownloadability.of(
            origin: .archiveOfOurOwn,
            ao3Unavailable: true
        )
        #expect(reason == .noLongerOnAO3)
        #expect(!reason.canRedownload)
        #expect(reason.rowTitle == "No longer on AO3.")
        #expect(reason.rowBody?.contains("can't download it again") == true)
        #expect(reason.shouldConfirmDelete(settingOn: false))
    }

    @Test func aFanFictionNetPDFNamesFormatAndSite() {
        let reason = WorkRedownloadability.of(
            origin: .fanfictionNet,
            ao3Unavailable: false,
            importFormatDisplayName: "PDF"
        )
        #expect(reason == .imported(formatDisplayName: "PDF", origin: .fanfictionNet))
        #expect(reason.rowTitle == "Imported PDF from FanFiction.net.")
        #expect(reason.rowBody == "Kudos can only download from AO3, so this copy is the only one.")
        #expect(reason.importSourcePhrase == "a PDF from FanFiction.net")
        #expect(reason.shouldConfirmDelete(settingOn: false))
    }

    @Test func anImportedFileWithoutASiteNamesTheFormatOnly() {
        let reason = WorkRedownloadability.of(
            origin: .importedFile,
            ao3Unavailable: false,
            importFormatDisplayName: "HTML"
        )
        #expect(reason.rowTitle == "Imported HTML.")
        #expect(reason.importSourcePhrase == "an HTML")
    }

    @Test func aKnownSiteWithoutAFormatNamesTheSite() {
        let reason = WorkRedownloadability.of(
            origin: .wattpad,
            ao3Unavailable: false
        )
        #expect(reason.rowTitle == "Imported from Wattpad.")
        #expect(reason.importSourcePhrase == "Wattpad")
    }

    @Test func anUnknownSiteIsAnotherSite() {
        let reason = WorkRedownloadability.of(
            origin: .unknown,
            ao3Unavailable: false,
            importFormatDisplayName: "EPUB"
        )
        #expect(reason.rowTitle == "Imported EPUB from another site.")
    }

    @Test func aBareImportedFileIsJustAFile() {
        let reason = WorkRedownloadability.of(
            origin: .importedFile,
            ao3Unavailable: false
        )
        #expect(reason.rowTitle == "Imported file.")
        #expect(reason.importSourcePhrase == "a file")
    }

    @Test func ao3UnavailableDoesNotOverrideANonAO3Import() {
        // `ao3Unavailable` is an AO3-404 flag. A FanFiction.net copy is
        // irreplaceable because of its origin, even if that flag were set.
        let reason = WorkRedownloadability.of(
            origin: .fanfictionNet,
            ao3Unavailable: true,
            importFormatDisplayName: "PDF"
        )
        #expect(reason == .imported(formatDisplayName: "PDF", origin: .fanfictionNet))
    }

    @Test func anAO3MirrorCannotBeFetchedThroughTheNativeClient() {
        let reason = WorkRedownloadability.of(
            origin: .archiveOfOurOwnMirror,
            ao3Unavailable: false
        )
        #expect(!reason.canRedownload)
        #expect(reason.rowTitle == "Imported from AO3 mirror.")
    }

    @Test func blankFormatNamesAreDropped() {
        let reason = WorkRedownloadability.of(
            origin: .fanfictionNet,
            ao3Unavailable: false,
            importFormatDisplayName: "   "
        )
        #expect(reason == .imported(formatDisplayName: nil, origin: .fanfictionNet))
    }

    @MainActor @Test func savedWorkConvenienceFollowsOriginAndTheUnavailableFlag() {
        let available = SavedWork(title: "Fine", author: "A")
        available.ao3WorkID = 11
        #expect(WorkRedownloadability.of(available) == .canRedownload)

        let gone = SavedWork(title: "Gone", author: "A")
        gone.ao3WorkID = 12
        gone.ao3Unavailable = true
        #expect(WorkRedownloadability.of(gone) == .noLongerOnAO3)

        let imported = SavedWork(
            title: "Rescued",
            author: "A",
            sourceURL: "https://www.fanfiction.net/s/99/1/"
        )
        #expect(WorkRedownloadability.of(imported) == .imported(
            formatDisplayName: nil,
            origin: .fanfictionNet
        ))
    }

    @Test func originalFileUsesTheRecordedNameAndSkipsUUIDNames() throws {
        let id = UUID()
        let url = Storage.originalDocumentURL(for: id, fileExtension: "pdf")
        try Data("%PDF-1.4".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
            WorkConversionRecord.delete(for: id)
        }

        WorkConversionRecord(format: "pdf", originalFileName: "thesis.pdf").write(for: id)
        let named = try #require(WorkRedownloadability.originalFile(for: id))
        #expect(named.suggestedName == "thesis.pdf")
        #expect(named.url == url)

        WorkConversionRecord(
            format: "pdf",
            originalFileName: "\(id.uuidString).pdf"
        ).write(for: id)
        let uuidNamed = try #require(WorkRedownloadability.originalFile(for: id))
        #expect(uuidNamed.suggestedName == "Original.pdf")
    }

    @Test func importFormatDisplayNameReadsTheConversionRecord() throws {
        let id = UUID()
        WorkConversionRecord(format: "pdf", originalFileName: "fic.pdf").write(for: id)
        defer { WorkConversionRecord.delete(for: id) }
        #expect(WorkRedownloadability.importFormatDisplayName(for: id) == "PDF")
    }
}
