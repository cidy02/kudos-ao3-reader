import Foundation
import Testing
@testable import Kudos

/// T-579: View Original previews a copy under the original's name. The archived file stays put,
/// and a recorded name cannot leave the preview folder.
struct WorkProvenanceOriginalPreviewTests {
    private func makeOriginal() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t579-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stored = root.appendingPathComponent("\(UUID().uuidString).pdf")
        try Data("%PDF-1.4 test".utf8).write(to: stored)
        return (root, stored)
    }

    @Test func previewCopiesUnderTheOriginalName() throws {
        let (root, stored) = try makeOriginal()
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = WorkProvenanceSections.namedPreviewURL(for: stored, name: "My Story.pdf", in: root)
        #expect(preview.lastPathComponent == "My Story.pdf")
        #expect(preview.standardizedFileURL.path != stored.standardizedFileURL.path)
        #expect(try Data(contentsOf: preview) == Data(contentsOf: stored))
        // A hard link would let this write change the archive. Quick Look markup must not.
        try Data("marked up".utf8).write(to: preview)
        #expect(try Data(contentsOf: stored) == Data("%PDF-1.4 test".utf8))
        #expect(FileManager.default.fileExists(atPath: stored.path))
    }

    @Test func recordedNamesStayInThePreviewFolder() throws {
        let (root, stored) = try makeOriginal()
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = root.appendingPathComponent("do-not-touch.pdf")
        try Data("sentinel".utf8).write(to: sentinel)
        let storedBytes = try Data(contentsOf: stored)

        let names: [String?] = [
            nil, "", "..", ".", "/", "foo/..", "../../evil.pdf", "..:evil.pdf",
            "../do-not-touch.pdf", stored.lastPathComponent,
            String(repeating: "a", count: 400) + ".pdf",
        ]
        for name in names {
            let preview = WorkProvenanceSections.namedPreviewURL(for: stored, name: name, in: root)
            let folder = preview.deletingLastPathComponent()
            #expect(folder.lastPathComponent.hasPrefix("original-preview-"))
            #expect(folder.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path)
            #expect(try Data(contentsOf: preview) == storedBytes)
            #expect(try Data(contentsOf: sentinel) == Data("sentinel".utf8))
            #expect(try Data(contentsOf: stored) == storedBytes)
            if let name, name.count > 240 {
                #expect(preview.pathExtension == "pdf")
                #expect(preview.lastPathComponent.utf8.count <= 255)
            }
        }

        let namesAtRoot = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
        #expect(namesAtRoot.allSatisfy {
            $0 == stored.lastPathComponent || $0 == sentinel.lastPathComponent
                || $0.hasPrefix("original-preview-")
        })
    }

    @Test func discardingAPreviewLeavesTheStoredFile() throws {
        let (root, stored) = try makeOriginal()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = WorkProvenanceSections.namedPreviewURL(for: stored, name: "One.pdf", in: root)
        let second = WorkProvenanceSections.namedPreviewURL(for: stored, name: "Two.pdf", in: root)
        // On macOS, `/private/var/...` is the same file as `/var/...`. Quick Look can hand
        // that form back; it is still the open preview and must not be deleted.
        if first.path.hasPrefix("/var/") {
            let rewritten = URL(fileURLWithPath: "/private" + first.path)
            let sameFile = rewritten.resolvingSymlinksInPath().standardizedFileURL.path
                == first.resolvingSymlinksInPath().standardizedFileURL.path
            if sameFile {
                WorkProvenanceSections.discardReplacedPreview(first, current: rewritten)
                #expect(FileManager.default.fileExists(atPath: first.path))
            }
        }
        WorkProvenanceSections.discardReplacedPreview(first, current: second)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        WorkProvenanceSections.discardReplacedPreview(stored, current: nil)
        #expect(FileManager.default.fileExists(atPath: stored.path))
        WorkProvenanceSections.discardReplacedPreview(second, current: nil)
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }
}
