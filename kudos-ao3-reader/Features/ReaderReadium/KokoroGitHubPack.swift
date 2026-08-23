import CryptoKit
import Foundation

/// English Neural Engine Kokoro pack hosted on this repo's GitHub Releases.
/// FluidAudio's downloader speaks Hugging Face URL shapes, so Kudos fetches
/// a zip from GitHub and seeds FluidAudio's on-disk cache instead.
nonisolated enum KokoroGitHubPack: Sendable {
    /// To republish (e.g. after adding voices):
    /// 1. `Scripts/pack-kokoro-ane-github-release.sh` — prints the SHA-256.
    /// 2. `gh release create <newTag> <zip> --repo cidy02/kudos-ao3-reader`
    /// 3. Bump `tag` and `expectedSHA256` here.
    ///
    /// `tag` is also the install marker's contents, so bumping it makes every
    /// device treat its existing pack as stale and re-install — which is
    /// exactly what a new voice set needs. The app reads whatever voices the
    /// pack contains (`KokoroVoiceCatalog`), so no other code changes.
    static let tag = "kokoro-ane-coreml-fp16-2"
    static let zipFileName = "kokoro-ane-coreml-fp16.zip"

    static let downloadURL = URL(
        string: "https://github.com/cidy02/kudos-ao3-reader/releases/download/"
            + "\(tag)/\(zipFileName)"
    )!

    static let expectedSHA256 =
        "c8d747b749e66ae4ef6d94f2e7c6028d4ce6aa11e6fd7acc937287404a08fdb4"

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
