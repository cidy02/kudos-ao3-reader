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

    @Test func definitiveFailureAllowsRetry() {
        let guardrail = CommentSubmissionGuard()
        #expect(guardrail.begin(key()))
        guardrail.fail("AO3 rejected the comment.")
        #expect(guardrail.begin(key()))
    }

    // MARK: Ambiguity classification

    @Test func onlyPossiblySentErrorsCountAsAmbiguous() {
        #expect(CommentsModel.isAmbiguousSubmitError(URLError(.timedOut)))
        #expect(CommentsModel.isAmbiguousSubmitError(URLError(.networkConnectionLost)))
        // Never reached the server → nothing could have been posted.
        #expect(!CommentsModel.isAmbiguousSubmitError(URLError(.notConnectedToInternet)))
        #expect(!CommentsModel.isAmbiguousSubmitError(URLError(.cannotConnectToHost)))
        // Definitive server answers are not ambiguous.
        #expect(!CommentsModel.isAmbiguousSubmitError(AO3Error.rateLimited(retryAfter: 10)))
        #expect(!CommentsModel.isAmbiguousSubmitError(AO3WriteError.rejected("nope")))
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
