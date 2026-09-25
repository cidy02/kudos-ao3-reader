import Foundation

/// Writes one editor session's recovery copy off the main thread
/// (docs/WRITING_EDITOR_ARCHITECTURE.md §8, invariant I5).
///
/// The editor used to call `WritingTextRecovery.save` on the main thread for
/// every keystroke, and each save read every stored copy of the field back in
/// to prune. Now the editor hands over one text per checkpoint (§8.1) and this
/// actor does the JSON encoding, the digest of the field's original text (once
/// per session), the atomic write and the pruning on its own executor.
///
/// Each write carries the sequence number of the checkpoint that produced it,
/// assigned on the main actor in checkpoint order. Calls from separate tasks are
/// not guaranteed to reach an actor in the order they were made, so a write
/// older than one already on disk is dropped instead of replacing it.
actor WritingRecoveryWriter {
    private let store: WritingTextRecovery
    private let url: URL
    private let original: String
    private var originalDigest: String?
    private var lastWrittenSequence = 0

    init(store: WritingTextRecovery, url: URL, original: String) {
        self.store = store
        self.url = url
        self.original = original
    }

    /// Writes `text` unless a later checkpoint's text is already on disk.
    /// Returns whether it wrote.
    @discardableResult
    func write(_ text: String, sequence: Int) throws -> Bool {
        guard sequence > lastWrittenSequence else { return false }
        let digest = originalDigest ?? WritingTextRecovery.digest(original)
        originalDigest = digest
        try store.save(text: text, originalDigest: digest, to: url)
        lastWrittenSequence = sequence
        return true
    }
}
