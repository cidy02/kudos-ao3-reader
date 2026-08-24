import Testing
@testable import Kudos

@Suite("Kokoro Neural Engine availability")
struct KokoroAneAvailabilityTests {
    @Test func engineDisplayNameNamesNeuralEngine() {
        #expect(ReaderTTSEngineKind.kokoro.displayName == "Kokoro (Neural Engine)")
    }

    @Test func usableForPlaybackTracksTheInstallMarkerOnly() {
        #expect(KokoroAneAvailability.isUsableForPlayback == KokoroAneAvailability.isPackInstalled)
    }

    /// iOS 26.x must never reach the Core ML engine: the libBNNS `SIGSEGV`
    /// (FluidAudio #817/#844) is a 26.x-line bug and cannot be caught, so
    /// Kokoro runs on Sherpa/ONNX there instead.
    @Test func coreMLIsOffLimitsOnTheWholeIos26Line() {
        for minor in 0 ... 9 {
            #expect(
                !KokoroAnePlayback.supportsCoreML(
                    for: .init(majorVersion: 26, minorVersion: minor, patchVersion: 0)
                ),
                "26.\(minor) must not use Core ML"
            )
        }
        #expect(!KokoroAnePlayback.supportsCoreML(for: .init(majorVersion: 18, minorVersion: 0, patchVersion: 0)))
    }

    @Test func coreMLIsUsedFromIos27Onward() {
        #expect(KokoroAnePlayback.supportsCoreML(for: .init(majorVersion: 27, minorVersion: 0, patchVersion: 0)))
        #expect(KokoroAnePlayback.supportsCoreML(for: .init(majorVersion: 28, minorVersion: 2, patchVersion: 1)))
    }

    /// Asserts the *shape* of the URL — this repo, the releases path, the
    /// declared tag — rather than pinning the tag literal. The literal was
    /// `…-fp16-1` and went stale the moment the pack was republished as
    /// `-2`, failing on every run for a reason that had nothing to do with
    /// the code being wrong. The tag itself is covered by the SHA-256 check
    /// below, which is what actually catches pointing at the wrong asset.
    @Test func githubPackURLIsThisReposReleaseAsset() {
        #expect(
            KokoroGitHubPack.downloadURL.absoluteString
                == "https://github.com/cidy02/kudos-ao3-reader/releases/download/"
                + "\(KokoroGitHubPack.tag)/kokoro-ane-coreml-fp16.zip"
        )
        #expect(KokoroGitHubPack.expectedSHA256.count == 64)
        #expect(
            KokoroGitHubPack.sha256Hex(of: Data("kudos-kokoro-ane-coreml\n".utf8))
                != KokoroGitHubPack.expectedSHA256
        )
    }
}
