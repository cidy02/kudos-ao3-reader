import Testing
import Foundation
@testable import Kudos

@Suite("Storage Tests")
struct StorageTests {
    @Test("A legitimate basename is kept inside Downloads")
    func tempDownloadURLKeepsASafeBasenameInsideDownloads() {
        let url = Storage.tempDownloadURL(suggestedName: "work-123.epub")
        #expect(url.lastPathComponent == "work-123.epub")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Downloads")
    }

    @Test("Downloads remain inside the Downloads directory despite hostile filenames")
    func hostileFilenamesAreSanitized() throws {
        let hostileNames = [
            "../../../evil.epub",
            "/absolute/path/to/evil.epub",
            "../evil.epub",
            "foo/bar/evil.epub",
            ".\0hidden.epub"
        ]

        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let downloadsDirectory = cachesDirectory.appendingPathComponent("Downloads", isDirectory: true)

        for hostileName in hostileNames {
            let url = Storage.tempDownloadURL(suggestedName: hostileName)
            #expect(
                url.deletingLastPathComponent().standardizedFileURL.path
                    == downloadsDirectory.standardizedFileURL.path,
                "Hostile name '\(hostileName)' escaped the Downloads directory: \(url.path)"
            )
            #expect(!url.lastPathComponent.contains(".."), "Hostile name '\(hostileName)' retained '..'")
            #expect(!url.lastPathComponent.contains("/"), "Hostile name '\(hostileName)' retained '/'")
            // last-component extraction of attacker input is not a sanitizer:
            // `../../../evil.epub` must not become a trusted `evil.epub`.
            #expect(
                url.lastPathComponent != "evil.epub",
                "Hostile name '\(hostileName)' was rewritten into a trusted-looking basename"
            )
            #expect(url.lastPathComponent.hasSuffix(".epub"))
        }
    }

    @Test("Parent-directory traversal falls back to a UUID name")
    func tempDownloadURLRejectsParentDirectoryTraversal() {
        let escaped = Storage.tempDownloadURL(suggestedName: "../escaped.epub")
        #expect(!escaped.path.contains(".."))
        #expect(escaped.deletingLastPathComponent().lastPathComponent == "Downloads")
        #expect(escaped.lastPathComponent != "escaped.epub")
        #expect(escaped.lastPathComponent.hasSuffix(".epub"))

        let nested = Storage.tempDownloadURL(suggestedName: "foo/../../../tmp/evil.epub")
        #expect(nested.deletingLastPathComponent().lastPathComponent == "Downloads")
        #expect(!nested.path.contains(".."))
        #expect(nested.lastPathComponent != "evil.epub")
    }

    @Test("Path separators are not accepted as part of a download name")
    func tempDownloadURLRejectsPathSeparators() {
        let slashed = Storage.tempDownloadURL(suggestedName: "subdir/file.epub")
        #expect(slashed.deletingLastPathComponent().lastPathComponent == "Downloads")
        #expect(slashed.lastPathComponent != "file.epub")

        let backslash = Storage.tempDownloadURL(suggestedName: "subdir\\file.epub")
        #expect(backslash.deletingLastPathComponent().lastPathComponent == "Downloads")
        #expect(backslash.path.contains("\\") == false)
    }

    @Test("Empty, dot, and control-character names fall back")
    func safeTempDownloadNameFallsBackForEmptyAndDotNames() {
        #expect(Storage.safeTempDownloadName("").hasSuffix(".epub"))
        #expect(Storage.safeTempDownloadName("   ").hasSuffix(".epub"))
        #expect(Storage.safeTempDownloadName(".") != ".")
        #expect(Storage.safeTempDownloadName("..") != "..")
        #expect(Storage.safeTempDownloadName("ok.epub") == "ok.epub")
        #expect(Storage.safeTempDownloadName(".\u{0}hidden.epub") != ".\u{0}hidden.epub")
    }
}
