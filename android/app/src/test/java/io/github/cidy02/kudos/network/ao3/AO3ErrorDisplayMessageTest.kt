package io.github.cidy02.kudos.network.ao3

import java.net.UnknownHostException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3ErrorDisplayMessageTest {
    private val dataClassDump = Regex("""^[A-Z][A-Za-z]*\(""")

    @Test
    fun transportFailureClassifiesAsOfflineAndHttp500DoesNot() {
        val offline = AO3Error.networkFromTransport(UnknownHostException("Unable to resolve host"))
        assertTrue(offline.isOffline())
        assertTrue(offline.offline)
        assertEquals(AO3Error.OFFLINE_MESSAGE, offline.displayMessage())

        val server = AO3Error.Server(500)
        assertFalse(server.isOffline())
        assertEquals("AO3 had a server problem (HTTP 500).", server.displayMessage())
    }

    @Test
    fun displayMessageNeverLooksLikeKotlinDataClassToString() {
        val samples = listOf(
            AO3Error.BadRequest,
            AO3Error.AuthenticationRequired,
            AO3Error.Forbidden,
            AO3Error.NotFound,
            AO3Error.RateLimited(null),
            AO3Error.Server(503),
            AO3Error.Http(418),
            AO3Error.Network("timeout"),
            AO3Error.networkFromTransport(UnknownHostException("dns")),
            AO3Error.Overloaded(503, null),
            AO3Error.Parse("unexpected markup"),
            AO3Error.Validation("The selected file was empty.")
        )
        for (error in samples) {
            val message = error.displayMessage()
            assertFalse(
                "displayMessage for $error looked like toString(): $message",
                dataClassDump.containsMatchIn(message)
            )
            // Guard the raw toString shape itself so a future regression that
            // surfaces error.toString() in UI is caught when someone re-uses
            // this assertion set against UI-bound strings.
            assertTrue(
                "Kotlin data-class toString shape expected for $error",
                dataClassDump.containsMatchIn(error.toString()) ||
                    error is AO3Error.BadRequest ||
                    error is AO3Error.AuthenticationRequired ||
                    error is AO3Error.Forbidden ||
                    error is AO3Error.NotFound
            )
        }
    }

    @Test
    fun validationUsesMessageNotToStringDump() {
        val error = AO3Error.Validation("The selected file was empty.")
        assertEquals("The selected file was empty.", error.displayMessage())
        assertTrue(error.toString().startsWith("Validation("))
        assertFalse(dataClassDump.containsMatchIn(error.displayMessage()))
    }
}
