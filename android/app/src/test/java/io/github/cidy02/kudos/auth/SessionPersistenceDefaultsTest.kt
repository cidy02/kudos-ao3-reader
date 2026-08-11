package io.github.cidy02.kudos.auth

import java.nio.file.Files
import java.time.Clock
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `AO3Session.savedAtEpochMillis` defaults to `Clock.systemUTC().millis()`.
 * kotlinx.serialization re-evaluates a property's default when deciding whether to
 * omit it, so with `encodeDefaults = false` a session written inside the same
 * millisecond it was built had the field dropped from the file entirely — and the
 * next `load()` re-stamped it with load time.
 *
 * It surfaced as a ~1-in-700 flake in the full suite (passing in isolation, because
 * isolation is slower). Nothing reads the value today, so it was never a live
 * defect; these tests exist so it cannot quietly become one.
 */
class SessionPersistenceDefaultsTest {

    private fun store(): FileAO3SessionStore {
        val dir = Files.createTempDirectory("kudos-session-defaults").toFile()
        return FileAO3SessionStore(sessionFile = java.io.File(dir, "session.json"))
    }

    private fun session(savedAt: Long) = AO3Session(
        username = "AO3_Reader",
        cookies = listOf(
            AO3StoredCookie(name = AO3StoredCookie.SessionCookieName, value = "secret")
        ),
        savedAtEpochMillis = savedAt
    )

    /**
     * The regression itself: a timestamp that equals "now" at write time is the
     * exact case the old config dropped.
     */
    @Test
    fun savedAtSurvivesWhenItEqualsTheDefaultAtWriteTime() = runTest {
        val store = store()
        val now = Clock.systemUTC().millis()
        store.save(session(now))

        val loaded = store.load()
        assertEquals(now, loaded?.savedAtEpochMillis)
    }

    /** The field is physically present in the file, not merely defaulted back on read. */
    @Test
    fun savedAtIsWrittenToDiskRatherThanReconstructed() = runTest {
        val dir = Files.createTempDirectory("kudos-session-defaults").toFile()
        val file = java.io.File(dir, "session.json")
        FileAO3SessionStore(sessionFile = file).save(session(Clock.systemUTC().millis()))

        assertTrue(
            "savedAtEpochMillis must be persisted, not omitted as a default",
            file.readText().contains("savedAtEpochMillis")
        )
    }

    /** A distinctly non-default value obviously round-trips too. */
    @Test
    fun anExplicitPastTimestampRoundTrips() = runTest {
        val store = store()
        store.save(session(1_700_000_000_000L))
        assertEquals(1_700_000_000_000L, store.load()?.savedAtEpochMillis)
    }
}
