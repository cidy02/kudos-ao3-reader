#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// The store has always been tier 1 of the phonemizer's resolution order, but
/// nothing could write to it, so a mispronounced name was permanent. These
/// cover the write path the pronunciation editor uses.
///
/// Every case points the store at a temporary file — the default location is
/// the real Application Support directory, and a test that edits a reader's
/// actual pronunciations would be a genuinely bad bug to ship.
@Suite("Kokoro pronunciation store")
struct KokoroPronunciationStoreTests {
    private func temporaryStore() -> KokoroPronunciationStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kokoro-pron-\(UUID().uuidString).json")
        return KokoroPronunciationStore(url: url)
    }

    /// I11: the editor reports a failed write instead of closing as if it saved.
    @Test func anUnwritableFileThrows() {
        let store = KokoroPronunciationStore(url: URL(fileURLWithPath: "/dev/null/kokoro-pron.json"))
        #expect(throws: (any Error).self) { try store.setOverride("hɜɹmˈIəni", for: "Hermione") }
    }

    @Test func aMissingEditingFileIsAnEmptyStore() throws {
        #expect(try temporaryStore().loadForEditing() == KokoroPronunciationStore.empty)
    }

    @Test func anUnreadableEditingFileThrows() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kokoro-pron-directory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = KokoroPronunciationStore(url: url)
        #expect(throws: (any Error).self) { try store.loadForEditing() }
    }

    @Test func failedReadsDoNotOverwriteTheSavedFile() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kokoro-pron-invalid-\(UUID().uuidString).json")
        let original = Data("{broken corrections".utf8)
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = KokoroPronunciationStore(url: url)

        #expect(throws: (any Error).self) { try store.loadForEditing() }
        #expect(throws: (any Error).self) { try store.updateGlobal(["New": "n"]) }
        #expect(throws: (any Error).self) { try store.updateGlobal(removing: ["Old"]) }
        #expect(throws: (any Error).self) { try store.setOverride("n", for: "New") }
        #expect(throws: (any Error).self) { try store.removeOverride(for: "Old") }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func batchEditsPreserveUnrelatedCorrectionsAndLayers() throws {
        let store = temporaryStore()
        try store.setOverride("old", for: "Old")
        try store.setOverride("keep", for: "Keep")
        try store.setOverride("f", for: "Name", in: .fandom("Fandom"))
        try store.setOverride("w", for: "Name", in: .work("42"))

        try store.updateGlobal(["New": "new", "Other": "other"], removing: ["Old"])
        let imported = try store.loadForEditing()
        #expect(imported.global == ["New": "new", "Other": "other", "Keep": "keep"])
        #expect(imported.fandoms == ["Fandom": ["Name": "f"]])
        #expect(imported.works == ["42": ["Name": "w"]])
        try store.updateGlobal(removing: ["New", "Other"])
        #expect(try store.loadForEditing().global == ["Keep": "keep"])
    }

    @Test func setThenReadRoundTrips() throws {
        let store = temporaryStore()
        #expect(store.overrides().isEmpty)
        try store.setOverride("hɜɹmˈIəni", for: "Hermione")
        #expect(store.overrides() == ["Hermione": "hɜɹmˈIəni"])
    }

    /// FluidAudio consults a case-sensitive custom lexicon before the
    /// lower-cased one, so these must stay distinct rather than folding.
    @Test func spellingIsPreservedExactly() throws {
        let store = temporaryStore()
        try store.setOverride("A", for: "Anna")
        try store.setOverride("B", for: "anna")
        #expect(store.overrides() == ["Anna": "A", "anna": "B"])
    }

    @Test func setReplacesAnExistingEntry() throws {
        let store = temporaryStore()
        try store.setOverride("first", for: "Draco")
        try store.setOverride("second", for: "Draco")
        #expect(store.overrides() == ["Draco": "second"])
    }

    @Test func removeDeletesOnlyThatEntry() throws {
        let store = temporaryStore()
        try store.setOverride("a", for: "Aziraphale")
        try store.setOverride("b", for: "Crowley")
        try store.removeOverride(for: "Aziraphale")
        #expect(store.overrides() == ["Crowley": "b"])
    }

    /// Work and fandom layers must not leave empty dictionaries behind, or the
    /// file grows an object per work a reader ever corrected in.
    @Test func emptiedLayersAreDroppedFromTheFile() throws {
        let store = temporaryStore()
        try store.setOverride("x", for: "Tobio", in: .work("123"))
        #expect(store.load().works["123"] == ["Tobio": "x"])
        try store.removeOverride(for: "Tobio", in: .work("123"))
        #expect(store.load().works["123"] == nil)
    }

    /// The merge order the phonemizer depends on: work beats fandom beats
    /// global. A correction made while reading one work must not be undone by
    /// a broader entry.
    @Test func layersMergeWithWorkWinning() throws {
        let store = temporaryStore()
        try store.setOverride("global", for: "Sam")
        try store.setOverride("fandom", for: "Sam", in: .fandom("LOTR"))
        try store.setOverride("work", for: "Sam", in: .work("42"))
        #expect(store.lexicon()["Sam"] == "global")
        #expect(store.lexicon(fandom: "LOTR")["Sam"] == "fandom")
        #expect(store.lexicon(fandom: "LOTR", workID: "42")["Sam"] == "work")
    }

    /// The revision token feeds `KokoroSpeechSessionCache`. If it covered only
    /// keys, correcting a word already present would keep serving the old
    /// pronunciation from cache forever — so changing a *value* must move it.
    @Test func revisionChangesWhenAValueChanges() throws {
        let store = temporaryStore()
        try store.setOverride("one", for: "Nico")
        let before = store.resolved().revision
        try store.setOverride("two", for: "Nico")
        #expect(store.resolved().revision != before)
    }
}
#endif
