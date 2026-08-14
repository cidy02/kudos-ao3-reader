import Testing
import Foundation
@testable import Kudos

@Suite("Storage Tests")
struct StorageTests {
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
            #expect(url.deletingLastPathComponent().standardizedFileURL.path == downloadsDirectory.standardizedFileURL.path, "Hostile name '\(hostileName)' escaped the Downloads directory: \(url.path)")
            #expect(!url.lastPathComponent.contains(".."), "Hostile name '\(hostileName)' retained '..'")
            #expect(!url.lastPathComponent.contains("/"), "Hostile name '\(hostileName)' retained '/'")
        }
    }
}
