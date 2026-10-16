package io.github.cidy02.kudos.network.ao3.comments

/** Chapter scope is presentation: AO3 identifies a submission by work and parent. */
data class CommentSubmissionKey(val workId: Long, val parentId: Long?, val body: String, val identity: String) {
    companion object {
        /**
         * Runs of whitespace become one space, as iOS's `isWhitespace` split. No regex: Android's
         * engine rejects the Unicode-class flag, and a pattern with it crashed the composer on a device.
         */
        fun normalize(body: String): String =
            String(body.map { if (it.isWhitespace()) ' ' else it }.toCharArray())
                .split(' ').filter(String::isNotEmpty).joinToString(" ")
        fun of(target: AO3CommentTarget, parentId: Long?, body: String, identity: String) =
            CommentSubmissionKey(target.workId, parentId, normalize(body), identity)
    }
}

enum class CommentVerification { Found, Absent, Unknown }

/** Process-lifetime, account-scoped evidence survives a popped and reopened Comments screen. */
class CommentSubmissionStore(private val now: () -> Long = System::currentTimeMillis) {
    enum class Phase { Sending, Ambiguous, Succeeded }
    data class Entry(val phase: Phase, val submittedAt: Long, val mayBeHidden: Boolean = false, val succeededAt: Long? = null)
    private val entries = mutableMapOf<CommentSubmissionKey, Entry>()

    @Synchronized fun entry(key: CommentSubmissionKey): Entry? {
        val entry = entries[key] ?: return null
        val lifetime = if (entry.phase == Phase.Succeeded) 300_000L else 3_600_000L
        val anchor = if (entry.phase == Phase.Succeeded) entry.succeededAt ?: entry.submittedAt else entry.submittedAt
        if (now() - anchor >= lifetime) { entries.remove(key); return null }
        return entry
    }

    @Synchronized fun begin(key: CommentSubmissionKey): Boolean {
        if (entry(key) != null) return false
        entries[key] = Entry(Phase.Sending, now())
        return true
    }

    @Synchronized fun prepared(key: CommentSubmissionKey, mayBeHidden: Boolean) {
        entries[key]?.let { entries[key] = it.copy(mayBeHidden = it.mayBeHidden || mayBeHidden) }
    }

    @Synchronized fun ambiguous(key: CommentSubmissionKey) {
        entries[key]?.let { entries[key] = it.copy(phase = Phase.Ambiguous) }
    }

    @Synchronized fun succeed(key: CommentSubmissionKey) {
        entries[key]?.let { entries[key] = it.copy(phase = Phase.Succeeded, succeededAt = now()) }
    }

    @Synchronized fun resolve(key: CommentSubmissionKey, verdict: CommentVerification) {
        when (verdict) {
            CommentVerification.Found -> succeed(key)
            CommentVerification.Absent -> entries.remove(key)
            CommentVerification.Unknown -> ambiguous(key)
        }
    }

    @Synchronized fun clear(identity: String) { entries.keys.removeAll { it.identity == identity } }

    companion object { val shared = CommentSubmissionStore() }
}
