#if os(iOS)
import CryptoKit
import Foundation
import Testing
@testable import Kudos

@Suite("Kokoro Core ML degradation")
struct KokoroAneHealthTests {
    @Test func cleanDeviceUsesTheNeuralEngine() {
        #expect(KokoroAneHealth.tier(forStrikes: 0) == .neuralEngine)
    }

    /// One crash drops the ANE but keeps Core ML. The demotion is `cpuOnly`,
    /// not `cpuAndGpu`: Metal is the *other* known-bad path on iOS 27 (#843).
    @Test func oneCrashDropsToCpuOnlyButKeepsCoreML() {
        #expect(KokoroAneHealth.tier(forStrikes: 1) == .coreMLCpuOnly)
    }

    @Test func repeatedCrashesHandOffToSherpa() {
        #expect(KokoroAneHealth.tier(forStrikes: 2) == .abandonCoreML)
        #expect(KokoroAneHealth.tier(forStrikes: 9) == .abandonCoreML)
    }

    /// A negative value can only come from a corrupted default; it must not
    /// read as "worse than clean" and disable the engine.
    @Test func corruptStrikeCountFallsBackToTheFastPath() {
        #expect(KokoroAneHealth.tier(forStrikes: -1) == .neuralEngine)
    }
}

@Suite("Kokoro pack verification")
struct KokoroGitHubPackHashTests {
    /// The chunked file hash replaced a full in-memory `Data(contentsOf:)`.
    /// It must agree with the one-shot hash, including across a chunk boundary.
    @Test func chunkedFileHashMatchesInMemoryHash() throws {
        let bytes = Data((0 ..< 40_000).map { UInt8($0 % 251) })
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-hash-\(UUID().uuidString).bin")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let streamed = try KokoroGitHubPack.sha256Hex(ofFileAt: url, chunkSize: 4_096)
        #expect(streamed == KokoroGitHubPack.sha256Hex(of: bytes))
    }

    @Test func emptyFileHashesWithoutHanging() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-hash-empty-\(UUID().uuidString).bin")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try KokoroGitHubPack.sha256Hex(ofFileAt: url)
            == KokoroGitHubPack.sha256Hex(of: Data()))
    }
}

@Suite("Kokoro pronunciation revisions")
struct KokoroPronunciationRevisionTests {
    private func store() -> (KokoroPronunciationStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-lex-\(UUID().uuidString).json")
        return (KokoroPronunciationStore(url: url), url)
    }

    /// The original revision hashed only the global *keys*, so correcting the
    /// IPA for a word already in the lexicon kept serving the stale
    /// pronunciation out of `KokoroSpeechSessionCache`.
    @Test func correctingAnExistingEntryChangesTheRevision() throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }

        var file = KokoroPronunciationStore.empty
        file.global["Hermione"] = "hɜːrˈmaɪəni"
        try store.save(file)
        let before = store.resolved().revision

        file.global["Hermione"] = "hɜːrmˈaɪəniː"
        try store.save(file)
        let after = store.resolved().revision

        #expect(before != after)
    }

    /// The revision also ignored the fandom and work layers entirely.
    @Test func workLayerParticipatesInTheRevision() throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }

        var file = KokoroPronunciationStore.empty
        file.works["12345"] = ["Ba'al": "bˈeɪəl"]
        try store.save(file)

        #expect(store.resolved().revision != store.resolved(workID: "12345").revision)
        #expect(store.resolved(workID: "12345").lexicon["Ba'al"] == "bˈeɪəl")
    }

    @Test func identicalContentIsStableAcrossReads() throws {
        let (store, url) = store()
        defer { try? FileManager.default.removeItem(at: url) }

        var file = KokoroPronunciationStore.empty
        file.global["AO3"] = "ˌeɪoʊθrˈiː"
        try store.save(file)

        #expect(store.resolved().revision == store.resolved().revision)
    }
}

@Suite("Kokoro voice catalog")
struct KokoroVoiceCatalogTests {
    @Test func parsesLocaleAndGenderFromTheIdentifier() throws {
        let bella = try #require(KokoroVoiceCatalog.voice(forIdentifier: "af_bella"))
        #expect(bella.name == "Bella")
        #expect(bella.gender == .female)
        #expect(bella.language.code.bcp47 == "en-US")

        let george = try #require(KokoroVoiceCatalog.voice(forIdentifier: "bm_george"))
        #expect(george.name == "George")
        #expect(george.gender == .male)
        #expect(george.language.code.bcp47 == "en-GB")
    }

    /// Non-English locales need a G2P frontend the English variant lacks, so
    /// they must not appear even if their `.bin` is present.
    @Test func rejectsLocalesTheEnglishFrontendCannotSpeak() {
        #expect(KokoroVoiceCatalog.voice(forIdentifier: "jf_alpha") == nil)
        #expect(KokoroVoiceCatalog.voice(forIdentifier: "zm_yunxi") == nil)
        #expect(KokoroVoiceCatalog.voice(forIdentifier: "ef_dora") == nil)
    }

    @Test func rejectsMalformedIdentifiers() {
        #expect(KokoroVoiceCatalog.voice(forIdentifier: "") == nil)
        #expect(KokoroVoiceCatalog.voice(forIdentifier: "af") == nil)
        #expect(KokoroVoiceCatalog.voice(forIdentifier: "af_") == nil)
        #expect(KokoroVoiceCatalog.voice(forIdentifier: "axx_bella") == nil)
        #expect(KokoroVoiceCatalog.voice(forIdentifier: "ax_bella") == nil)
    }

    @Test func readsVoicesFromTheInstalledPackDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-voices-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for name in ["af_heart.bin", "bm_george.bin", "vocab.json", "zm_yunxi.bin"] {
            try Data().write(to: dir.appendingPathComponent(name))
        }
        let voices = KokoroVoiceCatalog.installedVoices(in: dir)
        #expect(voices.map(\.identifier) == ["af_heart", "bm_george"])
        #expect(KokoroVoiceCatalog.defaultIdentifier(among: voices) == "af_heart")
    }

    @Test func emptyPackDirectoryYieldsNoVoices() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("kokoro-absent-\(UUID().uuidString)", isDirectory: true)
        #expect(KokoroVoiceCatalog.installedVoices(in: missing).isEmpty)
    }

    /// `packVoicesDirectory` duplicates FluidAudio's `TtsCacheDirectory`
    /// layout; if upstream moves, this is what catches it.
    @Test func packDirectoryMatchesFluidAudioLayout() {
        let path = KokoroAneAvailability.packVoicesDirectory.path
        #expect(path.hasSuffix("/fluidaudio/Models/kokoro-82m-coreml/ANE"))
        #expect(path.contains("Application Support"))
    }
}
#endif
