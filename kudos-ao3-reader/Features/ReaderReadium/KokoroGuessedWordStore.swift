#if os(iOS)
import Foundation

/// Words Read Aloud had to guess at, ranked by how often they came up.
///
/// A word reaches the neural G2P fallback only after missing the custom
/// lexicon, the Misaki lexicon and every recovery. In fanfiction that set is
/// overwhelmingly character names — measured across a 20-work corpus, the
/// most frequent were `Marvolo` (570), `Lucius` (461), `Severus` (392),
/// `Purilla` (464). Those are exactly the words a reader hears wrong most,
/// and the ones worth offering for correction.
///
/// Frequency is what makes this usable rather than a wall of text: a work
/// produces around 1,700 distinct fallbacks, but the top ten cover a median
/// **46%** of its occurrences. Ranking turns an unusable list into a short
/// one.
///
/// Deliberately not a prompt. The owner's decision was to surface these
/// silently and let the reader come to them, so nothing here interrupts
/// playback.
nonisolated struct KokoroGuessedWordStore: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var word: String
        var count: Int
        var lastSeen: Date
    }

    struct File: Codable, Equatable, Sendable {
        var version: Int
        var entries: [String: Entry]
    }

    static let empty = File(version: 1, entries: [:])

    /// Cap on distinct words retained.
    ///
    /// A long work yields ~2,600 distinct fallbacks and a reader will never
    /// scroll past the first dozen, so an unbounded file would grow for no
    /// benefit. When full, the least-frequent entries are dropped: a name
    /// said once is the one least worth keeping, and if it recurs it comes
    /// straight back.
    static let capacity = 500

    private let url: URL

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            self.url = support.appendingPathComponent(
                "TTS_Models/kokoro-guessed-words.json", isDirectory: false
            )
        }
    }

    func load() -> File {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            return Self.empty
        }
        return file
    }

    func save(_ file: File) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = folder
        try? directory.setResourceValues(values)
        try JSONEncoder().encode(file).write(to: url, options: .atomic)
    }

    /// Record a batch of guessed words, incrementing counts.
    ///
    /// Batched rather than one write per word: the observer fires per word
    /// during synthesis, and a disk write on each would put file I/O on the
    /// path that has to keep audio fed.
    func record(_ words: [String], now: Date = Date()) throws {
        guard !words.isEmpty else { return }
        var file = load()
        for word in words {
            let key = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if var existing = file.entries[key] {
                existing.count += 1
                existing.lastSeen = now
                file.entries[key] = existing
            } else {
                file.entries[key] = Entry(word: key, count: 1, lastSeen: now)
            }
        }
        if file.entries.count > Self.capacity {
            let keep = file.entries.values
                .sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }
                .prefix(Self.capacity)
            file.entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.word, $0) })
        }
        try save(file)
    }

    /// Most-guessed first, then most recent. The order the list is shown in.
    func ranked() -> [Entry] {
        load().entries.values.sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }
    }

    /// Drop one word — used when the reader corrects it, since a corrected
    /// word resolves from tier 1 next time and is no longer a guess.
    func forget(_ word: String) throws {
        var file = load()
        file.entries[word] = nil
        try save(file)
    }

    func clear() throws {
        try save(Self.empty)
    }
}
#endif
