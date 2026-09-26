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
/// older than one already on disk is dropped instead of replacing it. Every
/// call writes the newest text it has received, not necessarily its own: a
/// newer checkpoint whose write failed is retried by the next call, and a late
/// older call can never put stale text on disk.
actor WritingRecoveryWriter {
    private let store: WritingTextRecovery
    private let url: URL
    private let original: String
    private var originalDigest: String?
    private var lastWrittenSequence = 0
    private var newest: (text: String, sequence: Int)?

    init(store: WritingTextRecovery, url: URL, original: String) {
        self.store = store
        self.url = url
        self.original = original
    }

    // ponytail: a failed write is retried only by the next call, so if the
    // session's last checkpoint fails nothing retries it; the editor's alert
    // tells the writer. Add a retry timer if that ever matters.
    /// Writes the newest checkpoint's text received so far, unless it is
    /// already on disk. Returns whether it wrote.
    @discardableResult
    func write(_ text: String, sequence: Int) throws -> Bool {
        if sequence > (newest?.sequence ?? 0) { newest = (text, sequence) }
        guard let newest, newest.sequence > lastWrittenSequence else { return false }
        let digest = originalDigest ?? WritingTextRecovery.digest(original)
        originalDigest = digest
        try store.save(text: newest.text, originalDigest: digest, to: url)
        lastWrittenSequence = newest.sequence
        return true
    }
}
