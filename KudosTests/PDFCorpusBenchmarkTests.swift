import Foundation
import Testing
@testable import Kudos

/// Runs the app's PDF converter over a local corpus and writes what it made, so the result can be scored against each
/// story's source outside the repo (T-579). Off unless `KUDOS_PDF_CORPUS` names a manifest:
/// `{"out": "/path/to/results", "pdfs": [{"id": "...", "path": "/path/to/file.pdf"}]}`. The corpus is never committed:
/// the stories belong to their authors.
struct PDFCorpusBenchmarkTests {
    private static let manifestPath = ProcessInfo.processInfo.environment["KUDOS_PDF_CORPUS"]

    @Test(.enabled(if: manifestPath != nil)) func convertEveryCorpusPDF() throws {
        let path = try #require(Self.manifestPath)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)))
        let manifest = try #require(object as? [String: Any])
        let out = URL(fileURLWithPath: try #require(manifest["out"] as? String), isDirectory: true)
        let entries = try #require(manifest["pdfs"] as? [[String: String]])
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for entry in entries {
            guard let id = entry["id"], let pdf = entry["path"] else { continue }
            var record: [String: Any] = ["id": id]
            let started = Date()
            do {
                let result = try PDFWorkConverter.convert(fileAt: URL(fileURLWithPath: pdf), fallbackTitle: "Untitled")
                record["title"] = result.metadata.title
                record["chapters"] = result.chapters.map { ["title": $0.title, "html": $0.bodyXHTML] }
            } catch {
                record["error"] = String(describing: error)
            }
            record["seconds"] = Date().timeIntervalSince(started)
            try JSONSerialization.data(withJSONObject: record).write(to: out.appendingPathComponent("\(id).json"))
        }
    }
}
