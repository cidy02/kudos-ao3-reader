import CryptoKit
import Foundation

/// English Neural Engine Kokoro pack hosted on this repo's GitHub Releases.
/// FluidAudio's downloader speaks Hugging Face URL shapes, so Kudos fetches
/// a zip from GitHub and seeds FluidAudio's on-disk cache instead.
nonisolated enum KokoroGitHubPack: Sendable {
    static let tag = "kokoro-ane-coreml-fp16-1"
    static let zipFileName = "kokoro-ane-coreml-fp16.zip"

    static let downloadURL = URL(
        string: "https://github.com/cidy02/kudos-ao3-reader/releases/download/"
            + "\(tag)/\(zipFileName)"
    )!

    static let expectedSHA256 =
        "44705ed4708d703b18e56f5761d000e183eae883db0ac0aac2d5a701bcf6f6f4"

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Chunked so verifying the ~180 MB pack costs 4 MB of memory, not a full
    /// second copy of the archive.
    static func sha256Hex(ofFileAt url: URL, chunkSize: Int = 4 << 20) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
