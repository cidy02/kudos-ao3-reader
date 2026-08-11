package io.github.cidy02.kudos.network.ao3.browse

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3BrowseUrlsTest {
    @Test
    fun mediaIndexUrlIsAo3MediaPath() {
        assertEquals("https://archiveofourown.org/media", AO3BrowseUrls.mediaIndexUrl())
    }

    @Test
    fun resolvesRelativeAo3PathToAbsoluteWithoutDoubleEncoding() {
        val resolved = AO3BrowseUrls.resolveAo3Url("/media/TV%20Shows/fandoms")
        assertEquals("https://archiveofourown.org/media/TV%20Shows/fandoms", resolved)
    }

    @Test
    fun keepsAbsoluteAo3Url() {
        val url = "https://archiveofourown.org/tags/Naruto/works"
        assertEquals(url, AO3BrowseUrls.resolveAo3Url(url))
    }

    @Test
    fun rejectsNonAo3AndEmptyUrls() {
        assertNull(AO3BrowseUrls.resolveAo3Url("https://evil.example.com/media/fandoms"))
        assertNull(AO3BrowseUrls.resolveAo3Url("   "))
        assertNull(AO3BrowseUrls.resolveAo3Url("javascript:alert(1)"))
    }

    @Test
    fun isAo3UrlAcceptsApexAndSubdomainHttpsOnly() {
        assertTrue(AO3BrowseUrls.isAo3Url("https://archiveofourown.org/works/1"))
        assertTrue(AO3BrowseUrls.isAo3Url("https://download.archiveofourown.org/x"))
        assertFalse(AO3BrowseUrls.isAo3Url("http://archiveofourown.org/works/1"))
        assertFalse(AO3BrowseUrls.isAo3Url("https://notarchiveofourown.org/works/1"))
        assertFalse(AO3BrowseUrls.isAo3Url("https://archiveofourown.org.evil.com/x"))
    }
}
