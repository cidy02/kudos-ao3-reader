import Foundation
import Testing
@testable import Kudos

/// T-579: View Original previews the archived file under its own name, never moving or changing the stored copy.
struct WorkProvenanceOriginalPreviewTests {
    private func makeOriginal() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("t579-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stored = root.appendingPathComponent("\(UUID().uuidString).pdf")
        try Data("%PDF-1.4 test".utf8).write(to: stored)
        return (root, stored)
    }

    @Test func previewUsesTheOriginalNameAndLeavesTheStoredFile() throws {
        let (root, stored) = try makeOriginal()
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = WorkProvenanceSections.namedPreviewURL(for: stored, name: "My Story.pdf", in: root)
        #expect(preview.lastPathComponent == "My Story.pdf")
        #expect(try Data(contentsOf: preview) == Data(contentsOf: stored))
        #expect(FileManager.default.fileExists(atPath: stored.path))
    }

    @Test func noNameOrAPathInTheNameFallsBackSafely() throws {
        let (root, stored) = try makeOriginal()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(WorkProvenanceSections.namedPreviewURL(for: stored, name: nil, in: root) == stored)
        #expect(WorkProvenanceSections.namedPreviewURL(for: stored, name: "", in: root) == stored)
        // a recorded name can't escape the preview folder
        let escaped = WorkProvenanceSections.namedPreviewURL(for: stored, name: "../../evil.pdf", in: root)
        #expect(escaped.lastPathComponent == "evil.pdf")
        #expect(escaped.deletingLastPathComponent().deletingLastPathComponent() == root)
    }
}
