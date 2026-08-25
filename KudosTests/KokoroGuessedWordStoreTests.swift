#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// Words that reached the neural G2P fallback — the ones no dictionary knew.
/// In fanfiction that is mostly character names, and ranking by frequency is
/// what turns ~1,700 distinct fallbacks per work into a list worth reading.
///
/// Every case uses a temporary file: the default location is real Application
/// Support, and a test that edited a reader's own data would be a bad bug.
@Suite("Kokoro guessed-word store")
struct KokoroGuessedWordStoreTests {
    private func temporaryStore() -> KokoroGuessedWordStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kokoro-guessed-\(UUID().uuidString).json")
        return KokoroGuessedWordStore(url: url)
    }

    @Test func recordingCountsRepeats() throws {
        let store = temporaryStore()
        try store.record(["Marvolo", "Severus", "Marvolo"])
        let ranked = store.ranked()
        #expect(ranked.first?.word == "Marvolo")
        #expect(ranked.first?.count == 2)
        #expect(ranked.count == 2)
    }

    /// Counts must accumulate across sessions, or a name said twice per
    /// chapter never rises above one said twice in a single burst.
    @Test func countsAccumulateAcrossCalls() throws {
        let store = temporaryStore()
        try store.record(["Oikawa"])
        try store.record(["Oikawa"])
        try store.record(["Oikawa"])
        #expect(store.ranked().first?.count == 3)
    }

    /// Frequency first is the whole point: the top of the list has to be what
    /// the reader hears most, not what was heard last.
    @Test func rankingIsByFrequency() throws {
        let store = temporaryStore()
        try store.record(["rare"])
        try store.record(Array(repeating: "common", count: 5))
        #expect(store.ranked().map(\.word) == ["common", "rare"])
    }

    @Test func forgettingRemovesOneWord() throws {
        let store = temporaryStore()
        try store.record(["Tobio", "Cecil"])
        try store.forget("Tobio")
        #expect(store.ranked().map(\.word) == ["Cecil"])
    }

    /// A long work yields thousands of distinct fallbacks and nobody scrolls
    /// past the first dozen, so the file must not grow without bound. When
    /// full, the least-frequent go: a name said once is the least worth
    /// keeping, and if it recurs it comes straight back.
    @Test func capacityIsEnforcedKeepingTheMostFrequent() throws {
        let store = temporaryStore()
        let overflow = KokoroGuessedWordStore.capacity + 50
        try store.record((0 ..< overflow).map { "word\($0)" })
        try store.record(Array(repeating: "kept", count: 9))
        let ranked = store.ranked()
        #expect(ranked.count <= KokoroGuessedWordStore.capacity)
        #expect(ranked.first?.word == "kept")
        #expect(ranked.first?.count == 9)
    }

    @Test func emptyAndBlankInputIsIgnored() throws {
        let store = temporaryStore()
        try store.record([])
        try store.record(["   ", ""])
        #expect(store.ranked().isEmpty)
    }

    @Test func clearEmptiesTheList() throws {
        let store = temporaryStore()
        try store.record(["Ahsael"])
        try store.clear()
        #expect(store.ranked().isEmpty)
    }

    /// Whitespace must be trimmed, or the same name arrives twice under two
    /// keys and neither reaches the top of the list.
    @Test func wordsAreTrimmedSoTheyDoNotSplitIntoTwoEntries() throws {
        let store = temporaryStore()
        try store.record(["Liv", " Liv", "Liv "])
        #expect(store.ranked().count == 1)
        #expect(store.ranked().first?.count == 3)
    }
}
#endif
