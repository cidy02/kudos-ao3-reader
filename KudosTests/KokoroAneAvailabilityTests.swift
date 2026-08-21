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

    @Test func ios264Through266PrefersGpuOverBnns() {
        #expect(KokoroAnePlayback.prefersGpuOverBnns(for: .init(majorVersion: 26, minorVersion: 4, patchVersion: 0)))
        #expect(KokoroAnePlayback.prefersGpuOverBnns(for: .init(majorVersion: 26, minorVersion: 6, patchVersion: 0)))
        #expect(!KokoroAnePlayback.prefersGpuOverBnns(for: .init(majorVersion: 26, minorVersion: 3, patchVersion: 0)))
        #expect(!KokoroAnePlayback.prefersGpuOverBnns(for: .init(majorVersion: 27, minorVersion: 0, patchVersion: 0)))
    }

    @Test func githubPackURLIsThisReposReleaseAsset() {
        #expect(
            KokoroGitHubPack.downloadURL.absoluteString
                == "https://github.com/cidy02/kudos-ao3-reader/releases/download/"
                + "kokoro-ane-coreml-fp16-1/kokoro-ane-coreml-fp16.zip"
        )
        #expect(KokoroGitHubPack.expectedSHA256.count == 64)
        #expect(
            KokoroGitHubPack.sha256Hex(of: Data("kudos-kokoro-ane-coreml\n".utf8))
                != KokoroGitHubPack.expectedSHA256
        )
    }
}
