package io.github.cidy02.kudos.network.ao3.comments

import org.junit.Assert.*
import org.junit.Test

class CommentSubmissionTest {
    private fun key(body: String = "Great chapter!", parent: Long? = 5, identity: String = "reader") =
        CommentSubmissionKey.of(AO3CommentTarget.Work(42), parent, body, identity)

    @Test fun keysNormalizeWhitespacePreserveCaseAndIgnoreChapterScope() {
        assertEquals(key(" Great\n chapter! "), key())
        assertNotEquals(key("great chapter!"), key())
        assertEquals(key(), CommentSubmissionKey.of(AO3CommentTarget.Chapter(42, 7), 5, "Great chapter!", "reader"))
    }

    @Test fun secondBeginWhileInFlightAndRecentSuccessAreRejected() {
        var now = 1_000L
        val store = CommentSubmissionStore { now }
        assertTrue(store.begin(key()))
        assertFalse(store.begin(key()))
        now += 600_000 // A slow answer must still start a fresh duplicate window.
        store.succeed(key())
        assertFalse(store.begin(key()))
        now += 300_001
        assertTrue(store.begin(key()))
    }

    @Test fun ambiguousPopAndReopenUnknownRecheckAndChapterSwitchStayBlocked() {
        val store = CommentSubmissionStore()
        val fromInbox = CommentSubmissionKey.of(AO3CommentTarget.Chapter(42, 7), 5, "Great chapter!", "reader")
        assertTrue(store.begin(fromInbox))
        store.prepared(fromInbox, true)
        store.ambiguous(fromInbox)
        // A fresh screen has only the shared store, not the previous screen's body hash.
        assertFalse(store.begin(key()))
        store.resolve(key(), CommentVerification.Unknown)
        assertFalse(store.begin(key()))
        assertTrue(store.entry(key())!!.mayBeHidden)
    }

    @Test fun verifiedAbsenceAndDefinitiveFailureReleaseOnlyTheirOwnKey() {
        val store = CommentSubmissionStore()
        val other = key(parent = 6)
        for (key in listOf(key(), other)) { assertTrue(store.begin(key)); store.ambiguous(key) }
        store.resolve(key(), CommentVerification.Absent)
        assertTrue(store.begin(key()))
        assertFalse(store.begin(other))
        val original = key()
        val edited = key("Edited composer text")
        store.resolve(original, CommentVerification.Found)
        assertFalse(store.begin(original))
        assertTrue(store.begin(edited))
    }

    @Test fun distinctAccountsBodiesAndParentsDoNotEraseUnresolvedEntriesAndLogoutClearsOnlyItsAccount() {
        val store = CommentSubmissionStore()
        val keys = listOf(key(), key(parent = 6), key("Another body"), key(identity = "bob"))
        for (key in keys) { assertTrue(store.begin(key)); store.ambiguous(key) }
        for (key in keys) assertFalse(store.begin(key))
        store.clear("reader")
        assertTrue(store.begin(key()))
        assertFalse(store.begin(key(identity = "bob")))
    }

    @Test fun logoutInvalidatesTheLoggedOutAccountsUnresolvedState() = kotlinx.coroutines.test.runTest {
        val identity = "submission-logout-test"
        val auth = io.github.cidy02.kudos.auth.AO3AuthRepository(
            io.github.cidy02.kudos.auth.MemorySessionStore(io.github.cidy02.kudos.auth.testSession(identity)),
            io.github.cidy02.kudos.auth.MemoryCookieStore()
        )
        auth.restoreSession()
        val key = key(identity = identity)
        val shared = CommentSubmissionStore.shared
        assertTrue(shared.begin(key))
        shared.ambiguous(key)
        auth.logout()
        assertNull(shared.entry(key))
    }

    @Test fun repeatedAmbiguityKeepsOriginalTimeAndExpiresAfterOneHour() {
        var now = 1_000L
        val store = CommentSubmissionStore { now }
        store.begin(key())
        now += 120_000
        store.ambiguous(key())
        store.resolve(key(), CommentVerification.Unknown)
        assertEquals(1_000L, store.entry(key())!!.submittedAt)
        now += 3_600_000
        assertNull(store.entry(key()))
    }

    private val entry = CommentSubmissionStore.Entry(CommentSubmissionStore.Phase.Ambiguous, 1_000)
    private fun comment(body: String = "Great chapter!", username: String? = "reader") = AO3Comment(
        "comment_9", AO3CommentAuthor("Pseud", username = username), "", body
    )
    private fun page(vararg comments: AO3Comment) = AO3CommentThread(AO3CommentTarget.Work(42), comments.toList(), null)

    @Test fun verificationRequiresTheExactLevelAndCanonicalAccountAndBody() {
        val parent = comment("Parent").copy(id = "comment_5", replies = listOf(comment()))
        assertEquals(CommentVerification.Found, commentVerification(page(parent), key(), entry))
        assertEquals(CommentVerification.Absent, commentVerification(page(parent), key(parent = null), entry))
        assertEquals(CommentVerification.Unknown, commentVerification(page(), key(), entry))
        assertEquals(CommentVerification.Absent, commentVerification(page(comment(username = "bob")), key(parent = null), entry))
        assertEquals(CommentVerification.Unknown, commentVerification(page(comment(username = null)), key(parent = null), entry))
        assertEquals(CommentVerification.Absent, commentVerification(page(comment().copy(isGuest = true)), key(parent = null), entry))
    }

    @Test fun hiddenTransformedCutoffAndOldEvidenceStayUnknown() {
        val top = key(parent = null)
        assertEquals(CommentVerification.Unknown, commentVerification(page(), top, entry.copy(mayBeHidden = true)))
        assertEquals(CommentVerification.Unknown, commentVerification(page(), key("<b>Great</b>", null), entry))
        assertEquals(CommentVerification.Unknown, commentVerification(page(comment().copy(isAnonymousCreator = true)), top, entry))
        assertEquals(CommentVerification.Unknown, commentVerification(page(comment().copy(isThreadCutoff = true)), top, entry))
        val old = comment().copy(date = "2020-01-01")
        assertEquals(CommentVerification.Unknown, commentVerification(page(old), top, entry.copy(submittedAt = 1_700_000_000_000)))
    }
}
