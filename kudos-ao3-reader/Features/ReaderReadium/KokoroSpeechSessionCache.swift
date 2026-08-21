import Foundation

/// In-memory phoneme cache for one Read Aloud session. Audio is not stored —
/// PCM for a chapter would dwarf the IPA strings. Invalidated when the
/// pronunciation set changes; voice and rate do not affect G2P.
nonisolated final class KokoroSpeechSessionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var phonemes: [String: String] = [:]
    private var revision: String = ""
    private let capacity: Int

    init(capacity: Int = 128) {
        self.capacity = max(8, capacity)
    }

    func phonemeString(for text: String, revision: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if revision != self.revision { return nil }
        return phonemes[text]
    }

    func store(phonemes value: String, for text: String, revision: String) {
        lock.lock()
        defer { lock.unlock() }
        if revision != self.revision {
            phonemes.removeAll(keepingCapacity: true)
            self.revision = revision
        }
        if phonemes.count >= capacity {
            phonemes.removeAll(keepingCapacity: true)
        }
        phonemes[text] = value
    }

    func clear() {
        lock.lock()
        phonemes.removeAll(keepingCapacity: true)
        revision = ""
        lock.unlock()
    }
}
