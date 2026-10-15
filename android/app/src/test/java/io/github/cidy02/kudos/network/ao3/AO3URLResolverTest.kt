package io.github.cidy02.kudos.network.ao3

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3URLResolverTest {
    @Test
    fun resolvesRelativeWorkHref() {
        val url = AO3URLResolver.resolve("/works/12345")
        assertEquals("https://archiveofourown.org/works/12345", url)
    }

    @Test
    fun rejectsExternalHostByDefault() {
        assertNull(AO3URLResolver.resolve("https://example.com/works/1"))
    }

    @Test
    fun allowsExternalWhenRequested() {
        assertNotNull(
            AO3URLResolver.resolve("https://example.com/x", allowExternalHost = true)
        )
    }

    @Test
    fun rejectsJavascript() {
        assertNull(AO3URLResolver.resolve("javascript:alert(1)"))
    }

    @Test
    fun cleartextHTTPAbsoluteAO3URLIsRejected() {
        for (url in listOf("http://archiveofourown.org", "http://archiveofourown.org/works/1",
            "http://download.archiveofourown.org/works/1")) {
            assertNull(AO3URLResolver.resolve(url))
            assertNull(AO3URLResolver.resolve(url, allowExternalHost = true))
        }
    }

    @Test fun subdomainHostIsAllowedByDefaultAndLookalikesAreRejected() {
        assertEquals("https://download.archiveofourown.org/works/1", AO3URLResolver.resolve("https://download.archiveofourown.org/works/1"))
        assertEquals("https://archiveofourown.org/works/1?page=2#comments",
            AO3URLResolver.resolve("//archiveofourown.org/works/1?page=2#comments"))
        assertNull(AO3URLResolver.resolve("https://archiveofourown.org.evil.example/works/1"))
        assertNull(AO3URLResolver.resolve("https://notarchiveofourown.org/works/1"))
        assertEquals("http://example.com/x", AO3URLResolver.resolve("http://example.com/x", allowExternalHost = true))
    }

    @Test
    fun trustedHostCheck() {
        assertTrue(AO3URLResolver.isTrustedAo3Host("https://archiveofourown.org/works/1"))
        assertFalse(AO3URLResolver.isTrustedAo3Host("https://evil.example/"))
    }
}
