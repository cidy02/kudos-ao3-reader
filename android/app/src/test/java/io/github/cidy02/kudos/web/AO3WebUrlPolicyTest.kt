package io.github.cidy02.kudos.web

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3WebUrlPolicyTest {
    @Test
    fun ao3HttpsStaysInApp() {
        assertEquals(WebNavDecision.Allow, AO3WebUrlPolicy.classify("https://archiveofourown.org/media"))
        assertTrue(AO3WebUrlPolicy.isAllowedInApp("https://archiveofourown.org/tags/Naruto/works"))
    }

    @Test
    fun nonAo3WebUrlsAreExternalized() {
        val decision = AO3WebUrlPolicy.classify("https://example.com/page")
        assertTrue(decision is WebNavDecision.External)
        assertEquals("https://example.com/page", (decision as WebNavDecision.External).url)
        assertFalse(AO3WebUrlPolicy.isAllowedInApp("https://example.com/page"))
    }

    @Test
    fun nonWebSchemesAreBlocked() {
        assertEquals(WebNavDecision.Block, AO3WebUrlPolicy.classify("javascript:alert(1)"))
        assertEquals(WebNavDecision.Block, AO3WebUrlPolicy.classify("intent://evil#Intent;end"))
        assertEquals(WebNavDecision.Block, AO3WebUrlPolicy.classify("file:///etc/passwd"))
    }

    @Test
    fun plainHttpAo3IsExternalizedNotInApp() {
        // http (not https) AO3 is not treated as in-app-allowed; it is externalized.
        assertTrue(AO3WebUrlPolicy.classify("http://archiveofourown.org/media") is WebNavDecision.External)
    }
}
