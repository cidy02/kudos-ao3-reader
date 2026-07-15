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
    /// Chapter-stripped (see `dedupContext`) — not necessarily the exact
    /// `AO3CommentContext` the composer is showing; verification and draft
    /// storage must keep using their own live context, not this one.
    let context: AO3CommentContext
    let normalizedBody: String
    /// The signed-in username (guests can't post in Kudos), so an account switch
    /// mid-session never suppresses a legitimately different submission.
    let identity: String

    init(context: AO3CommentContext, body: String, identity: String) {
        self.context = Self.dedupContext(context)
        self.normalizedBody = Self.normalize(body)
        self.identity = identity
    }

    /// `postCommentReply(parentCommentID:)` and `postComment(workID:)` are
    /// both chapter-agnostic — a reply's parent id and a top-level comment's
    /// work id are all AO3 needs. Stripping `chapterID` here means the SAME
    /// logical submission gets the same key whether it was composed from an
    /// Inbox focused thread (chapter-scoped) or a work-comments screen
    /// (`.all`), so an unresolved block recorded from one surface still
    /// blocks the other instead of silently not applying.
    private static func dedupContext(_ context: AO3CommentContext) -> AO3CommentContext {
        AO3CommentContext(workID: context.workID, chapterID: nil, parentCommentID: context.parentCommentID)
    }

    /// Whitespace-insensitive, case-preserving normalization: AO3 trims and
    /// re-wraps whitespace when rendering, so byte-equality would miss real
    /// duplicates while case-folding would merge legitimately distinct edits.
    static func normalize(_ body: String) -> String {
        body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Auth-scoped record of comment submissions left unresolved by an ambiguous
/// POST outcome. `CommentSubmissionGuard` is created fresh with every
/// `CommentsModel` — a new Comments screen, a switched Reply target, or a
/// popped-and-reopened Inbox thread all recreate it — so a guard's own
/// in-memory state cannot be what keeps a duplicate POST blocked. This store
/// is the durable source of truth every guard instance reads through and
/// writes through to.
///
/// Keyed by the full `CommentSubmissionKey` (context + normalized body +
/// identity) and partitioned by `identity`, so a distinct submission (a
/// different target, or genuinely different text to the same target) can
/// proceed without disturbing an unresolved one, and one AO3 account's
/// unresolved state is neither visible to nor cleared by another's.
///
/// In-memory only, process-lifetime (same tradeoff as `CommentsModel`'s own
/// `CommentsPageCache`): comment text and submission timing are live session
/// state, not something to persist to disk, and nothing stored here is a
/// credential (no cookies/CSRF/HTML). `maxAge` bounds retention so a missed
/// resolution can't accumulate forever.
@MainActor
final class UnresolvedCommentSubmissionStore {
    struct Entry: Equatable {
        let message: String
        /// When the POST attempt that produced this entry was made — the
        /// timing anchor `verifyCommentPosted` matches candidate replies
        /// against. Re-recording the same key (e.g. a "Check Again" retry
        /// that finds it still ambiguous) keeps this original value rather
        /// than resetting it.
        let submittedAt: Date
        /// The form warned that a successful comment may be hidden from its
        /// visible thread (moderation / Anonymous Creator). Verification may
        /// find it, but absence is never authoritative while this is true.
        let commentMayBeHidden: Bool
    }

    /// The process-lifetime store production code shares across every
    /// `CommentsModel`/`CommentSubmissionGuard` and that `AO3AuthService`
    /// clears on logout/session loss. Tests construct their own instance
    /// (`CommentSubmissionGuard`'s default) so runs never share state.
    static let shared = UnresolvedCommentSubmissionStore()

    private var entriesByIdentity: [String: [CommentSubmissionKey: Entry]] = [:]
    private let maxAge: TimeInterval
    private let now: () -> Date

    // Default-constructible from a non-isolated context (e.g. as another
    // MainActor type's default parameter value) — every other member stays
    // actor-isolated, so this only defers, never bypasses, the isolation check.
    nonisolated init(maxAge: TimeInterval = 3600, now: @escaping () -> Date = Date.init) {
        self.maxAge = maxAge
        self.now = now
    }

    /// The unresolved entry for `key`, or nil if there isn't one or it aged out.
    func entry(for key: CommentSubmissionKey) -> Entry? {
        guard let stored = entriesByIdentity[key.identity]?[key] else { return nil }
        guard now().timeIntervalSince(stored.submittedAt) < maxAge else {
            entriesByIdentity[key.identity]?.removeValue(forKey: key)
            return nil
        }
        return stored
    }

    /// Records (or re-records) `key` as unresolved.
    func markAmbiguous(
        _ key: CommentSubmissionKey,
        message: String,
        submittedAt: Date,
        commentMayBeHidden: Bool = false
    ) {
        let existing = entriesByIdentity[key.identity]?[key]
        entriesByIdentity[key.identity, default: [:]][key] = Entry(
            message: message,
            submittedAt: existing?.submittedAt ?? submittedAt,
            commentMayBeHidden: existing?.commentMayBeHidden == true || commentMayBeHidden
        )
    }

    /// Authoritative resolution (verified success, or a definitive failure that
    /// proves nothing was posted): the block on `key` is lifted.
    func resolve(_ key: CommentSubmissionKey) {
        entriesByIdentity[key.identity]?.removeValue(forKey: key)
    }

    /// Logout / account change: `identity`'s unresolved state must not leak
    /// into, or keep blocking, whatever session follows.
    func clear(identity: String) {
        entriesByIdentity.removeValue(forKey: identity)
    }
}

/// Single-flight + recent-success guard for comment POSTs. Displays state for
/// whatever key its owning composer currently targets; the durable
/// `UnresolvedCommentSubmissionStore` (not this instance) is what actually
/// keeps an unresolved submission blocked across navigation.
///
/// Rules enforced:
/// - `begin` fails while any submission is in flight (`submitting`/`verifying`).
/// - `begin` fails for a key that already succeeded within `duplicateWindow` —
///   a re-tap after success can't re-post the same text to the same place.
/// - After an ambiguous outcome, `begin` fails for that key — even from a
///   brand-new guard instance — until `resolveAmbiguity` runs (verification),
///   keeping "retry" explicit and safe.
@MainActor
@Observable
final class CommentSubmissionGuard {
    private(set) var phase: CommentSubmissionPhase = .idle
    /// Keys that completed with a verified success, with when. Instance-local
    /// (not durable) — this dedup window is a courtesy against a fast re-tap,
    /// not a correctness invariant like the unresolved-submission block.
    private var recentSuccesses: [CommentSubmissionKey: Date] = [:]
    /// The key this guard instance is currently displaying status for.
    private(set) var pendingKey: CommentSubmissionKey?
    /// Captured when `begin` claims the attempt, before any form GET or POST.
    /// An error handled minutes later must not move verification's time anchor.
    private var startedAt: Date?

    /// How long an identical submission stays blocked after a success. Long
    /// enough to cover any double-tap/re-open flow, short enough to allow a
    /// genuinely repeated (identical) comment later on purpose.
    let duplicateWindow: TimeInterval
    private let now: () -> Date
    private let store: UnresolvedCommentSubmissionStore

    init(
        duplicateWindow: TimeInterval = 300,
        now: @escaping () -> Date = Date.init,
        store: UnresolvedCommentSubmissionStore = UnresolvedCommentSubmissionStore()
    ) {
        self.duplicateWindow = duplicateWindow
        self.now = now
        self.store = store
    }

    /// The durable-store timestamp of the POST attempt behind `pendingKey`
    /// (nil once resolved/idle) — the timing evidence verification anchors to.
    var pendingSubmittedAt: Date? {
        guard let pendingKey else { return nil }
        return store.entry(for: pendingKey)?.submittedAt ?? startedAt
    }

    var pendingCommentMayBeHidden: Bool {
        guard let pendingKey else { return false }
        return store.entry(for: pendingKey)?.commentMayBeHidden ?? false
    }

    /// Re-syncs `phase`/`pendingKey` for `key` against the durable store.
    /// Call whenever the composer opens or switches targets, so a key already
    /// unresolved — from an earlier attempt, possibly by a since-recreated
    /// guard — shows its true blocked state instead of a fresh idle one.
    func adopt(_ key: CommentSubmissionKey) {
        guard !phase.isBusy else { return }
        if let entry = store.entry(for: key) {
            pendingKey = key
            startedAt = entry.submittedAt
            phase = .ambiguous(entry.message)
        } else {
            pendingKey = nil
            startedAt = nil
            phase = .idle
        }
    }

    /// Claims the right to POST `key`. Returns false (and sets a user-readable
    /// phase) when posting must not proceed.
    func begin(_ key: CommentSubmissionKey) -> Bool {
        if phase.isBusy { return false }
        if let entry = store.entry(for: key) {
            // Unresolved earlier attempt for this exact comment — verification,
            // not a second POST, is the only way forward.
            pendingKey = key
            startedAt = entry.submittedAt
            phase = .ambiguous(entry.message)
            return false
        }
        if let succeededAt = recentSuccesses[key],
           now().timeIntervalSince(succeededAt) < duplicateWindow {
            phase = .succeeded
            return false
        }
        pendingKey = key
        startedAt = now()
        phase = .submitting
        return true
    }

    /// The POST returned a definitive success (or verification found the comment).
    func succeed() {
        if let pendingKey {
            recentSuccesses[pendingKey] = now()
            store.resolve(pendingKey)
        }
        pendingKey = nil
        startedAt = nil
        phase = .succeeded
    }

    /// The POST failed before anything could have been recorded server-side
    /// (rejected by AO3, no connection, signed out). Safe to retry explicitly.
    func fail(_ message: String) {
        if let pendingKey { store.resolve(pendingKey) }
        pendingKey = nil
        startedAt = nil
        phase = .failed(message)
    }

    /// The POST's outcome is unknown (e.g. timeout after the request was sent).
    /// Keeps the key pending in the durable store; `begin` for it stays
    /// blocked for every guard instance, not just this one.
    func markAmbiguous(_ message: String, commentMayBeHidden: Bool = false) {
        guard let pendingKey else { return }
        store.markAmbiguous(
            pendingKey,
            message: message,
            submittedAt: startedAt ?? now(),
            commentMayBeHidden: commentMayBeHidden
        )
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
            // No key to keep blocked (shouldn't happen — verification only
            // ever runs with one pending — but a stuck `.verifying` would be
            // worse than resetting to idle if some future caller manages it).
            guard let pendingKey else {
                phase = .idle
                return
            }
            let message = "We couldn't confirm whether this posted on AO3. "
                + "Your draft is saved. Check again before re-posting."
            store.markAmbiguous(
                pendingKey,
                message: message,
                submittedAt: startedAt ?? now(),
                commentMayBeHidden: pendingCommentMayBeHidden
            )
            phase = .ambiguous(message)
        }
    }

    /// Back to rest for this guard's own display (e.g. composer dismissed
    /// after success/failure was seen, or switching to a distinct target). An
    /// unresolved store entry for `pendingKey` is untouched — `adopt` restores
    /// this or any other guard's phase from it the next time something targets
    /// that key again — so this can never silently unblock a duplicate.
    func reset() {
        guard !phase.isBusy else { return }
        pendingKey = nil
        startedAt = nil
        phase = .idle
    }

    /// Drops only this screen's presentation state when another authentication
    /// generation takes over. Any durable ambiguous entry remains owned by its
    /// original identity in `store`; a stale continuation must not keep the new
    /// account's composer permanently busy.
    func resetForAuthenticationChange() {
        pendingKey = nil
        startedAt = nil
        phase = .idle
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

    private func key(for context: AO3CommentContext, identity: String) -> String {
        "\(identity)|w\(context.workID)-c\(context.chapterID ?? 0)-p\(context.parentCommentID ?? 0)"
    }

    func draft(for context: AO3CommentContext, identity: String = "") -> String {
        drafts()[key(for: context, identity: identity)] ?? ""
    }

    func save(_ text: String, for context: AO3CommentContext, identity: String = "") {
        var all = drafts()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            all.removeValue(forKey: key(for: context, identity: identity))
        } else {
            all[key(for: context, identity: identity)] = text
        }
        defaults.set(all, forKey: storageKey)
    }

    func clear(for context: AO3CommentContext, identity: String = "") {
        var all = drafts()
        all.removeValue(forKey: key(for: context, identity: identity))
        defaults.set(all, forKey: storageKey)
    }

    /// A verified post is work/parent-scoped on AO3, so clear every chapter
    /// variant of that same account's draft rather than leaving a stale sibling.
    func clearVariants(for context: AO3CommentContext, identity: String) {
        var all = drafts()
        let prefix = "\(identity)|w\(context.workID)-"
        let suffix = "-p\(context.parentCommentID ?? 0)"
        all.keys.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }.forEach {
            all.removeValue(forKey: $0)
        }
        defaults.set(all, forKey: storageKey)
    }

    private func drafts() -> [String: String] {
        defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }
}
