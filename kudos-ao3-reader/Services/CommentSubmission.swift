import Foundation

/// The lifecycle of one comment submission. The state machine exists to make
/// double-posting structurally impossible: a POST is attempted at most once per
/// submission; anything ambiguous routes through verification, never a blind
/// retry (see `docs/ai/COMMENTS_HANDOFF.md`).
enum CommentSubmissionPhase: Equatable {
    case idle
    /// The single POST is in flight (post button disabled).
    case submitting
    /// The POST result was ambiguous (timeout / dropped connection after send);
    /// a verification fetch is checking whether the comment actually landed.
    case verifying
    case succeeded
    /// Verification couldn't confirm either way — resubmitting stays blocked
    /// until the user explicitly retries after seeing the warning.
    case ambiguous(String)
    /// Definitive failure (AO3 rejected it / network failed before send) —
    /// nothing was posted; retrying is safe.
    case failed(String)

    var isBusy: Bool {
        self == .submitting || self == .verifying
    }
}

/// Identity of one attempted submission: where it's going plus the normalized
/// body. Two taps producing the same key are the same comment.
struct CommentSubmissionKey: Hashable {
    let context: AO3CommentContext
    let normalizedBody: String
    /// The signed-in username (guests can't post in Kudos), so an account switch
    /// mid-session never suppresses a legitimately different submission.
    let identity: String

    init(context: AO3CommentContext, body: String, identity: String) {
        self.context = context
        self.normalizedBody = Self.normalize(body)
        self.identity = identity
    }

    /// Whitespace-insensitive, case-preserving normalization: AO3 trims and
    /// re-wraps whitespace when rendering, so byte-equality would miss real
    /// duplicates while case-folding would merge legitimately distinct edits.
    static func normalize(_ body: String) -> String {
        body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Single-flight + recent-success guard for comment POSTs.
///
/// Rules enforced:
/// - `begin` fails while any submission is in flight (`submitting`/`verifying`).
/// - `begin` fails for a key that already succeeded within `duplicateWindow` —
///   a re-tap after success can't re-post the same text to the same place.
/// - After an ambiguous outcome, `begin` fails for that key until
///   `resolveAmbiguity` runs (verification), keeping "retry" explicit and safe.
@MainActor
@Observable
final class CommentSubmissionGuard {
    private(set) var phase: CommentSubmissionPhase = .idle
    /// Keys that completed with a verified success, with when.
    private var recentSuccesses: [CommentSubmissionKey: Date] = [:]
    /// The key whose outcome is unresolved (in flight or ambiguous).
    private(set) var pendingKey: CommentSubmissionKey?

    /// How long an identical submission stays blocked after a success. Long
    /// enough to cover any double-tap/re-open flow, short enough to allow a
    /// genuinely repeated (identical) comment later on purpose.
    let duplicateWindow: TimeInterval
    private let now: () -> Date

    init(duplicateWindow: TimeInterval = 300, now: @escaping () -> Date = Date.init) {
        self.duplicateWindow = duplicateWindow
        self.now = now
    }

    /// Claims the right to POST `key`. Returns false (and sets a user-readable
    /// phase) when posting must not proceed.
    func begin(_ key: CommentSubmissionKey) -> Bool {
        if phase.isBusy { return false }
        if let pendingKey, pendingKey == key, case .ambiguous = phase {
            // Unresolved earlier attempt for this exact comment — verification,
            // not a second POST, is the only way forward.
            return false
        }
        if let succeededAt = recentSuccesses[key],
           now().timeIntervalSince(succeededAt) < duplicateWindow {
            phase = .succeeded
            return false
        }
        pendingKey = key
        phase = .submitting
        return true
    }

    /// The POST returned a definitive success (or verification found the comment).
    func succeed() {
        if let pendingKey { recentSuccesses[pendingKey] = now() }
        pendingKey = nil
        phase = .succeeded
    }

    /// The POST failed before anything could have been recorded server-side
    /// (rejected by AO3, no connection, signed out). Safe to retry explicitly.
    func fail(_ message: String) {
        pendingKey = nil
        phase = .failed(message)
    }

    /// The POST's outcome is unknown (e.g. timeout after the request was sent).
    /// Keeps the key pending; `begin` for it stays blocked.
    func markAmbiguous(_ message: String) {
        phase = .ambiguous(message)
    }

    /// A verification pass is running for the pending ambiguous key.
    func beginVerifying() {
        phase = .verifying
    }

    /// Verification finished. `found` → success. `absent` → AO3 was checked and
    /// the comment isn't there, so the attempt is released as a definitive
    /// failure and an explicit retry becomes possible. `unknown` → stays
    /// ambiguous: resubmission remains blocked (re-posting on a guess is the
    /// double-post path); the UI offers "Check Again" instead.
    func resolveAmbiguity(_ verification: AO3AuthService.CommentVerification) {
        switch verification {
        case .found:
            succeed()
        case .absent:
            fail("The comment didn't reach AO3. You can try posting again.")
        case .unknown:
            phase = .ambiguous(
                "We couldn't confirm whether this posted — AO3 wasn't reachable. "
                + "Your draft is saved. Check again before re-posting."
            )
        }
    }

    /// Back to rest (e.g. composer dismissed after success/failure was seen).
    func reset() {
        if !phase.isBusy { phase = .idle }
    }
}

/// Per-context comment drafts, persisted so nothing typed is lost to a dismissal,
/// an app exit, or an offline gap. Cleared only on *verified* success.
@MainActor
final class CommentDraftStore {
    private let defaults: UserDefaults
    private let storageKey = "ao3CommentDrafts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for context: AO3CommentContext) -> String {
        "w\(context.workID)-c\(context.chapterID ?? 0)-p\(context.parentCommentID ?? 0)"
    }

    func draft(for context: AO3CommentContext) -> String {
        drafts()[key(for: context)] ?? ""
    }

    func save(_ text: String, for context: AO3CommentContext) {
        var all = drafts()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            all.removeValue(forKey: key(for: context))
        } else {
            all[key(for: context)] = text
        }
        defaults.set(all, forKey: storageKey)
    }

    func clear(for context: AO3CommentContext) {
        var all = drafts()
        all.removeValue(forKey: key(for: context))
        defaults.set(all, forKey: storageKey)
    }

    private func drafts() -> [String: String] {
        defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }
}
