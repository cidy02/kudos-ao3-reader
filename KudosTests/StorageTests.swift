import Foundation
import Testing
@testable import Kudos

struct StorageTests {
    @Test func tempDownloadURLKeepsASafeBasenameInsideDownloads() {
        let url = Storage.tempDownloadURL(suggestedName: "work-123.epub")
        #expect(url.lastPathComponent == "work-123.epub")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Downloads")
    }

    @Test func tempDownloadURLRejectsParentDirectoryTraversal() {
        let escaped = Storage.tempDownloadURL(suggestedName: "../escaped.epub")
        #expect(!escaped.path.contains(".."))
        #expect(escaped.deletingLastPathComponent().lastPathComponent == "Downloads")
        #expect(escaped.lastPathComponent != "escaped.epub")
        #expect(escaped.lastPathComponent.hasSuffix(".epub"))

        let nested = Storage.tempDownloadURL(suggestedName: "foo/../../../tmp/evil.epub")
        #expect(nested.deletingLastPathComponent().lastPathComponent == "Downloads")
        #expect(!nested.path.contains(".."))
    }

    @Test func tempDownloadURLRejectsPathSeparators() {
        let slashed = Storage.tempDownloadURL(suggestedName: "subdir/file.epub")
        #expect(slashed.deletingLastPathComponent().lastPathComponent == "Downloads")
        #expect(slashed.lastPathComponent != "file.epub")

        let backslash = Storage.tempDownloadURL(suggestedName: "subdir\\file.epub")
        #expect(backslash.deletingLastPathComponent().lastPathComponent == "Downloads")
        #expect(backslash.path.contains("\\") == false)
    }

    @Test func safeTempDownloadNameFallsBackForEmptyAndDotNames() {
        #expect(Storage.safeTempDownloadName("").hasSuffix(".epub"))
        #expect(Storage.safeTempDownloadName("   ").hasSuffix(".epub"))
        #expect(Storage.safeTempDownloadName(".") != ".")
        #expect(Storage.safeTempDownloadName("..") != "..")
        #expect(Storage.safeTempDownloadName("ok.epub") == "ok.epub")
    }
}
