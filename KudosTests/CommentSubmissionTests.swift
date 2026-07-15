import Foundation
import Testing
@testable import Kudos

/// The duplicate-post prevention state machine: a POST can begin at most once
/// per identical submission, ambiguity blocks resubmission until verification,
/// and drafts survive everything short of verified success.
@MainActor
struct CommentSubmissionTests {

    private func key(
        body: String = "Great chapter!",
        parent: Int? = nil,
        identity: String = "reader"
    ) -> CommentSubmissionKey {
        CommentSubmissionKey(
            context: AO3CommentContext(workID: 42, chapterID: 7, parentCommentID: parent),
            body: body,
            identity: identity
        )
    }

    // MARK: Key normalization

    @Test func keysNormalizeWhitespaceButPreserveCase() {
        #expect(key(body: "Great   chapter!\n") == key(body: "Great chapter!"))
        #expect(key(body: "great chapter!") != key(body: "Great chapter!"))
        #expect(key(body: "Great chapter!", parent: 5) != key(body: "Great chapter!"))
        #expect(key(identity: "a") != key(identity: "b"))
    }

    /// `postCommentReply`/`postComment` don't take a chapter — the same
    /// logical reply composed from an Inbox focused thread (chapter-scoped)
    /// and from a work-comments screen (`.all`, no chapter) must dedup to the
    /// same key, or an unresolved block recorded on one surface silently
    /// wouldn't apply on the other.
    @Test func keysIgnoreChapterScopeForTheSameParentAndBody() {
        let chapterScoped = CommentSubmissionKey(
            context: AO3CommentContext(workID: 42, chapterID: 7, parentCommentID: 5),
            body: "Great chapter!", identity: "reader"
        )
        let workScoped = CommentSubmissionKey(
            context: AO3CommentContext(workID: 42, chapterID: nil, parentCommentID: 5),
            body: "Great chapter!", identity: "reader"
        )
        #expect(chapterScoped == workScoped)

        let differentChapter = CommentSubmissionKey(
            context: AO3CommentContext(workID: 42, chapterID: 3, parentCommentID: 5),
            body: "Great chapter!", identity: "reader"
        )
        #expect(chapterScoped == differentChapter)

        // Top-level (no parent) keys are equally chapter-agnostic.
        let topLevelChapterScoped = CommentSubmissionKey(
            context: AO3CommentContext(workID: 42, chapterID: 7, parentCommentID: nil),
            body: "Loved it!", identity: "reader"
        )
        let topLevelWorkScoped = CommentSubmissionKey(
            context: AO3CommentContext(workID: 42, chapterID: nil, parentCommentID: nil),
            body: "Loved it!", identity: "reader"
        )
        #expect(topLevelChapterScoped == topLevelWorkScoped)
    }

    // MARK: Single flight

    @Test func secondBeginWhileInFlightIsRejected() {
        let guardrail = CommentSubmissionGuard()
        #expect(guardrail.begin(key()))
        // A rapid second tap — same or different content — cannot start a POST.
        #expect(!guardrail.begin(key()))
        #expect(!guardrail.begin(key(body: "Other text")))
        #expect(guardrail.phase == .submitting)
    }

    @Test func identicalSubmissionAfterSuccessIsBlockedInsideWindow() {
        var now = Date(timeIntervalSince1970: 1_000)
        let guardrail = CommentSubmissionGuard(duplicateWindow: 300, now: { now })

        #expect(guardrail.begin(key()))
        guardrail.succeed()
        #expect(guardrail.phase == .succeeded)

        // Re-tapping Post with the same text right away: blocked, reads as done.
        #expect(!guardrail.begin(key()))

        // A different comment is fine immediately.
        #expect(guardrail.begin(key(body: "A second, different thought.")))
        guardrail.succeed()

        // And the identical text becomes postable again once the window passes
        // (deliberate repeat, e.g. "🧡" on every chapter).
        now = now.addingTimeInterval(301)
        #expect(guardrail.begin(key()))
    }

    // MARK: Ambiguity → verification

    @Test func ambiguousOutcomeBlocksResubmitUntilResolved() {
        let guardrail = CommentSubmissionGuard()
        #expect(guardrail.begin(key()))
        guardrail.markAmbiguous("Connection dropped.")

        // The same submission cannot be re-POSTed while unresolved.
        #expect(!guardrail.begin(key()))

        guardrail.beginVerifying()
        #expect(guardrail.phase == .verifying)
        #expect(!guardrail.begin(key()))

        // Verification found the comment on AO3 → success; still no re-POST.
        guardrail.resolveAmbiguity(.found)
        #expect(guardrail.phase == .succeeded)
        #expect(!guardrail.begin(key()))
    }

    @Test func verifiedAbsenceReleasesAsFailureAllowingExplicitRetry() {
        let guardrail = CommentSubmissionGuard()
        #expect(guardrail.begin(key()))
        guardrail.markAmbiguous("Connection dropped.")
        guardrail.beginVerifying()
        guardrail.resolveAmbiguity(.absent)

        guard case .failed = guardrail.phase else {
            Issue.record("expected .failed, got \(String(describing: guardrail.phase))")
            return
        }
        // Verification says it never landed → an explicit retry may POST again.
        #expect(guardrail.begin(key()))
    }

    @Test func unknownVerificationKeepsResubmissionBlocked() {
        let guardrail = CommentSubmissionGuard()
        #expect(guardrail.begin(key()))
        guardrail.markAmbiguous("Connection dropped.")
        guardrail.beginVerifying()
        // Couldn't reach AO3 to check — this must NOT unlock a re-POST.
        guardrail.resolveAmbiguity(.unknown)

        guard case .ambiguous = guardrail.phase else {
            Issue.record("expected .ambiguous, got \(String(describing: guardrail.phase))")
            return
        }
        #expect(!guardrail.begin(key()))

        // A later check that definitively finds it resolves to success.
        guardrail.beginVerifying()
        guardrail.resolveAmbiguity(.found)
        #expect(guardrail.phase == .succeeded)
        #expect(!guardrail.begin(key()))
    }

    @Test func hiddenCommentEvidenceSurvivesGuardRecreationAndUnknownRecheck() {
        let store = UnresolvedCommentSubmissionStore()
        let pending = key()
        let original = CommentSubmissionGuard(store: store)
        #expect(original.begin(pending))
        original.markAmbiguous(
            "AO3 did not confirm the post.", commentMayBeHidden: true
        )
        #expect(original.pendingCommentMayBeHidden)

        let reopened = CommentSubmissionGuard(store: store)
        reopened.adopt(pending)
        #expect(reopened.pendingCommentMayBeHidden)
        reopened.beginVerifying()
        reopened.resolveAmbiguity(.unknown)

        #expect(reopened.pendingCommentMayBeHidden)
        #expect(!CommentSubmissionGuard(store: store).begin(pending))
    }

    @Test func definitiveFailureAllowsRetry() {
        let guardrail = CommentSubmissionGuard()
        #expect(guardrail.begin(key()))
        guardrail.fail("AO3 rejected the comment.")
        #expect(guardrail.begin(key()))
    }

    // MARK: Durable unresolved-submission store (T91-RF2)
    //
    // `CommentSubmissionGuard.begin`/`markAmbiguous`/etc. above exercise one
    // long-lived guard instance. In the app, `CommentsModel` — and the guard
    // it owns — is recreated on target switches, popping back to Inbox and
    // reopening, and Comments-screen recreation in general; only a store that
    // outlives any one guard instance can keep an unresolved submission
    // blocked through that. These tests construct a fresh guard per "screen"
    // the way `CommentsModel` would, sharing one store the way the app shares
    // `UnresolvedCommentSubmissionStore.shared`.

    @Test func distinctTargetProceedsWithoutErasingAnUnresolvedOne() {
        let store = UnresolvedCommentSubmissionStore()
        let keyA = key(parent: 5)
        let keyB = key(parent: 6)

        let guardA = CommentSubmissionGuard(store: store)
        #expect(guardA.begin(keyA))
        guardA.markAmbiguous("Connection dropped.")

        // A distinct target (different parent → different key) proceeds and
        // resolves normally without touching A's entry.
        let guardB = CommentSubmissionGuard(store: store)
        guardB.adopt(keyB)
        #expect(guardB.phase == .idle)
        #expect(guardB.begin(keyB))
        guardB.succeed()
        #expect(guardB.phase == .succeeded)

        // A → B → A: reopening on A (even via a brand-new guard, as a popped
        // and reopened Comments screen would produce) still shows it blocked.
        let guardA2 = CommentSubmissionGuard(store: store)
        guardA2.adopt(keyA)
        #expect(guardA2.phase == .ambiguous("Connection dropped."))
        #expect(!guardA2.begin(keyA))
    }

    @Test func ambiguousAPopAndReopenStaysBlocked() {
        let store = UnresolvedCommentSubmissionStore()
        let keyA = key()

        let firstScreen = CommentSubmissionGuard(store: store)
        #expect(firstScreen.begin(keyA))
        firstScreen.markAmbiguous("Connection dropped.")
        // Popping back to Inbox discards this guard instance entirely — no
        // `reset()`/`succeed()`/`fail()` call, just abandonment.

        // Reopening the same reply target creates a brand-new CommentsModel
        // (and guard) — as if the pushed CommentsView had been destroyed.
        let reopenedScreen = CommentSubmissionGuard(store: store)
        reopenedScreen.adopt(keyA)
        #expect(reopenedScreen.phase == .ambiguous("Connection dropped."))
        #expect(!reopenedScreen.begin(keyA))
    }

    @Test func modelRecreationRetainsTheGuardWhereRequired() {
        let store = UnresolvedCommentSubmissionStore()
        let keyA = key()

        let original = CommentSubmissionGuard(store: store)
        #expect(original.begin(keyA))
        original.markAmbiguous("Connection dropped.")

        // A brand-new guard for the same key (simulating `CommentsModel`
        // reconstruction) must adopt the block immediately, and `begin` must
        // reject it even without an explicit `adopt` call first.
        let recreated = CommentSubmissionGuard(store: store)
        #expect(!recreated.begin(keyA))
        if case .ambiguous = recreated.phase {} else {
            Issue.record("expected .ambiguous, got \(String(describing: recreated.phase))")
        }
    }

    @Test func resolvingOneUnresolvedKeyDoesNotAffectAnother() {
        let store = UnresolvedCommentSubmissionStore()
        let keyA = key(parent: 5)
        let keyB = key(parent: 6)

        let guardA = CommentSubmissionGuard(store: store)
        #expect(guardA.begin(keyA))
        guardA.markAmbiguous("Connection dropped.")

        let guardB = CommentSubmissionGuard(store: store)
        #expect(guardB.begin(keyB))
        guardB.markAmbiguous("Connection dropped.")

        // Verification proves A never posted — A resolves to a definitive
        // failure (explicit retry becomes possible for A only).
        guardA.resolveAmbiguity(.absent)
        #expect(guardA.begin(keyA))

        // B's entry is untouched: a fresh guard for B is still blocked.
        let guardB2 = CommentSubmissionGuard(store: store)
        #expect(!guardB2.begin(keyB))
    }

    @Test func oneAccountsUnresolvedStateIsUnavailableToAnother() {
        let store = UnresolvedCommentSubmissionStore()
        let keyAccountA = key(identity: "accountA")
        let keyAccountB = key(identity: "accountB")

        let guardA = CommentSubmissionGuard(store: store)
        #expect(guardA.begin(keyAccountA))
        guardA.markAmbiguous("Connection dropped.")

        // Same context/body, different signed-in identity: B's key is simply
        // a different key, structurally invisible to A's entry.
        let guardB = CommentSubmissionGuard(store: store)
        #expect(guardB.begin(keyAccountB))
    }

    @Test func logoutInvalidatesTheLoggedOutAccountsUnresolvedState() {
        let store = UnresolvedCommentSubmissionStore()
        let keyA = key(identity: "accountA")

        let guardA = CommentSubmissionGuard(store: store)
        #expect(guardA.begin(keyA))
        guardA.markAmbiguous("Connection dropped.")
        #expect(store.entry(for: keyA) != nil)

        // What AO3AuthService.logout()/clearStoredSession() do on sign-out.
        store.clear(identity: "accountA")
        #expect(store.entry(for: keyA) == nil)

        // A fresh guard (as a reopened composer would use) is no longer blocked.
        let afterLogout = CommentSubmissionGuard(store: store)
        #expect(afterLogout.begin(keyA))
    }

    @Test func multipleUnresolvedKeysDoNotOverwriteEachOther() {
        let store = UnresolvedCommentSubmissionStore()
        let keys = (0 ..< 3).map { key(body: "Reply #\($0)", parent: $0) }

        for (index, aKey) in keys.enumerated() {
            let guardForKey = CommentSubmissionGuard(store: store)
            #expect(guardForKey.begin(aKey))
            guardForKey.markAmbiguous("Ambiguous #\(index)")
        }

        // Every key is still independently retrievable and blocking.
        for (index, aKey) in keys.enumerated() {
            #expect(store.entry(for: aKey)?.message == "Ambiguous #\(index)")
            let guardForKey = CommentSubmissionGuard(store: store)
            #expect(!guardForKey.begin(aKey))
        }
    }

    @Test func storeMarkAmbiguousAnchorsTheOriginalSubmissionTime() {
        var now = Date(timeIntervalSince1970: 1_000)
        let store = UnresolvedCommentSubmissionStore(now: { now })
        let aKey = key()

        store.markAmbiguous(aKey, message: "First check.", submittedAt: now)
        now = now.addingTimeInterval(120)
        // A later "Check Again" re-records the same key — the timing anchor
        // for verification must stay the ORIGINAL attempt, not this retry.
        store.markAmbiguous(aKey, message: "Still checking.", submittedAt: now)

        #expect(store.entry(for: aKey)?.submittedAt == Date(timeIntervalSince1970: 1_000))
        #expect(store.entry(for: aKey)?.message == "Still checking.")
    }

    @Test func guardAnchorsSubmittedAtWhenTheAttemptBegins() {
        var now = Date(timeIntervalSince1970: 1_000)
        let store = UnresolvedCommentSubmissionStore(now: { now })
        let guardrail = CommentSubmissionGuard(now: { now }, store: store)
        let pending = key()

        #expect(guardrail.begin(pending))
        #expect(guardrail.pendingSubmittedAt == Date(timeIntervalSince1970: 1_000))
        now = now.addingTimeInterval(600)
        guardrail.markAmbiguous("The response arrived late.")

        #expect(store.entry(for: pending)?.submittedAt == Date(timeIntervalSince1970: 1_000))
        #expect(guardrail.pendingSubmittedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func storeEntriesExpireAfterMaxAge() {
        var now = Date(timeIntervalSince1970: 1_000)
        let store = UnresolvedCommentSubmissionStore(maxAge: 60, now: { now })
        let aKey = key()

        store.markAmbiguous(aKey, message: "Ambiguous.", submittedAt: now)
        #expect(store.entry(for: aKey) != nil)

        now = now.addingTimeInterval(61)
        #expect(store.entry(for: aKey) == nil)
    }

    @Test func guardAdoptShowsIdleForAKeyTheStoreHasNoEntryFor() {
        let store = UnresolvedCommentSubmissionStore()
        let guardrail = CommentSubmissionGuard(store: store)
        guardrail.adopt(key())
        #expect(guardrail.phase == .idle)
        #expect(guardrail.pendingKey == nil)
    }

    @Test func guardAdoptNeverClobbersAnInFlightSubmission() {
        let store = UnresolvedCommentSubmissionStore()
        let guardrail = CommentSubmissionGuard(store: store)
        #expect(guardrail.begin(key()))
        #expect(guardrail.phase == .submitting)

        // Some other key becoming unresolved in the store must not interrupt
        // this guard's own in-flight POST.
        guardrail.adopt(key(body: "A different target's text", parent: 9))
        #expect(guardrail.phase == .submitting)
    }

    /// An ambiguous reply recorded from an Inbox focused thread (`.byChapter`)
    /// must still block the identical reply attempted from the work-comments
    /// screen (`.all`) — the two surfaces produce different `AO3CommentContext`
    /// values but must dedup to the same `CommentSubmissionKey`.
    @Test func unresolvedBlockFollowsTheSameReplyAcrossChapterScopes() {
        let store = UnresolvedCommentSubmissionStore()
        let fromInbox = CommentSubmissionKey(
            context: AO3CommentContext(workID: 42, chapterID: 7, parentCommentID: 5),
            body: "Great chapter!", identity: "reader"
        )
        let fromWorkComments = CommentSubmissionKey(
            context: AO3CommentContext(workID: 42, chapterID: nil, parentCommentID: 5),
            body: "Great chapter!", identity: "reader"
        )

        let inboxGuard = CommentSubmissionGuard(store: store)
        #expect(inboxGuard.begin(fromInbox))
        inboxGuard.markAmbiguous("Connection dropped.")

        // A fresh guard for the SAME logical reply, reached from the other
        // surface, must see it as blocked, not as a distinct submission.
        let workCommentsGuard = CommentSubmissionGuard(store: store)
        #expect(!workCommentsGuard.begin(fromWorkComments))
    }

    // MARK: Verification target (T-95 follow-up)
    //
    // `CommentsModel.reverify` ("Check Again") must authoritatively check the
    // ORIGINAL ambiguous submission, never whatever text happens to be in the
    // composer at the moment the user taps it — a "Check Again" tap after
    // editing the text would otherwise verify the wrong body, get a spurious
    // `.absent`, and erase the block on the real unresolved submission
    // (re-enabling a genuine duplicate POST for it). `CommentsModel.
    // verificationTarget` is the pure function that enforces this; it
    // deliberately has no parameter for "the composer's current text" so that
    // can't leak in by construction.

    @Test func verificationTargetsThePendingKeysBodyNeverTheComposersLiveText() {
        let pendingKey = CommentSubmissionKey(
            context: AO3CommentContext(workID: 42, chapterID: 7, parentCommentID: 5),
            body: "Original ambiguous text",
            identity: "reader"
        )
        let composerContext = AO3CommentContext(workID: 42, chapterID: 7, parentCommentID: 5)

        let target = CommentsModel.verificationTarget(
            pendingKey: pendingKey, composerContext: composerContext
        )
        #expect(target?.body == "Original ambiguous text")
        #expect(target?.context == composerContext)
    }

    @Test func verificationTargetIsNilWithNoPendingKey() {
        let target = CommentsModel.verificationTarget(
            pendingKey: nil, composerContext: AO3CommentContext(workID: 42)
        )
        #expect(target == nil)
    }

    /// End-to-end through the guard: begin an ambiguous reply, simulate the
    /// user editing the composer to different text (never fed into
    /// `verificationTarget`), then resolve using the target's body. The
    /// original key must be the one resolved — not some key built from the
    /// edited text — proving the fix closes the exact regression the review
    /// described.
    @Test func resolvingAfterAComposerEditStillTargetsTheOriginalSubmission() {
        let store = UnresolvedCommentSubmissionStore()
        let guardrail = CommentSubmissionGuard(store: store)
        let originalKey = key(body: "Original ambiguous text")

        #expect(guardrail.begin(originalKey))
        guardrail.markAmbiguous("Connection dropped.")

        // The user edits the composer text — a distinct, different key that
        // is NEVER passed to `verificationTarget`.
        let editedKey = key(body: "Something totally different now")
        #expect(editedKey != originalKey)

        let target = CommentsModel.verificationTarget(
            pendingKey: guardrail.pendingKey,
            composerContext: AO3CommentContext(workID: 42, chapterID: 7)
        )
        #expect(target?.body == originalKey.normalizedBody)

        // Resolving with that target's (correct) body releases the ORIGINAL
        // key, exactly as a real `.absent` verification result would.
        guardrail.resolveAmbiguity(.absent)
        #expect(store.entry(for: originalKey) == nil)
        // The edited text was never at risk of being blocked by this
        // resolution (it was never in the store to begin with) — begin for
        // it succeeds independently, confirming no cross-key confusion.
        #expect(guardrail.begin(editedKey))
    }

    @Test func verificationTargetFoundResolvesThePendingKeyToSuccess() {
        let store = UnresolvedCommentSubmissionStore()
        let guardrail = CommentSubmissionGuard(store: store)
        let pendingKey = key()
        #expect(guardrail.begin(pendingKey))
        guardrail.markAmbiguous("Connection dropped.")

        let target = CommentsModel.verificationTarget(
            pendingKey: guardrail.pendingKey,
            composerContext: AO3CommentContext(workID: 42, chapterID: 7)
        )
        #expect(target != nil)
        guardrail.resolveAmbiguity(.found)
        #expect(guardrail.phase == .succeeded)
        #expect(store.entry(for: pendingKey) == nil)
    }

    // MARK: Ambiguity classification

    @Test func onlyPossiblySentErrorsCountAsAmbiguous() {
        #expect(CommentsModel.isAmbiguousSubmitError(URLError(.timedOut)))
        #expect(CommentsModel.isAmbiguousSubmitError(URLError(.networkConnectionLost)))
        // A final-200 page with neither error nor success flash: the POST reached
        // AO3 but nothing confirms it was recorded (CAA-2).
        #expect(CommentsModel.isAmbiguousSubmitError(AO3WriteError.unconfirmed))
        // Never reached the server → nothing could have been posted.
        #expect(!CommentsModel.isAmbiguousSubmitError(URLError(.notConnectedToInternet)))
        #expect(!CommentsModel.isAmbiguousSubmitError(URLError(.cannotConnectToHost)))
        // Definitive server answers are not ambiguous.
        #expect(!CommentsModel.isAmbiguousSubmitError(AO3Error.rateLimited(retryAfter: 10)))
        #expect(!CommentsModel.isAmbiguousSubmitError(AO3WriteError.rejected("nope")))
        // Pre-POST refusals are definitive — nothing was ever sent.
        #expect(!CommentsModel.isAmbiguousSubmitError(AO3WriteError.noPseudControl))
        #expect(!CommentsModel.isAmbiguousSubmitError(AO3WriteError.noCSRFToken))
    }

    @Test func ambiguousBannerNamesTheRightAmbiguityShape() {
        let unconfirmed = CommentsModel.ambiguousSubmitMessage(for: AO3WriteError.unconfirmed)
        let dropped = CommentsModel.ambiguousSubmitMessage(for: URLError(.timedOut))
        #expect(unconfirmed.contains("didn't confirm"))
        #expect(dropped.contains("connection dropped"))
        #expect(unconfirmed != dropped)
    }

    // MARK: Drafts

    @Test func draftsPersistPerContextAndClearOnSuccess() {
        let suiteName = "CommentSubmissionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CommentDraftStore(defaults: defaults)

        let topLevel = AO3CommentContext(workID: 42, chapterID: nil)
        let reply = AO3CommentContext(workID: 42, chapterID: 7, parentCommentID: 5)

        store.save("Half-typed thought…", for: topLevel)
        store.save("Reply in progress", for: reply)

        #expect(store.draft(for: topLevel) == "Half-typed thought…")
        #expect(store.draft(for: reply) == "Reply in progress")

        store.clear(for: topLevel)
        #expect(store.draft(for: topLevel).isEmpty)
        #expect(store.draft(for: reply) == "Reply in progress") // untouched

        // Saving an effectively-empty draft removes the entry.
        store.save("   \n", for: reply)
        #expect(store.draft(for: reply).isEmpty)
    }
}
