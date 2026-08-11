package io.github.cidy02.kudos.network.ao3.author

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AO3AuthorUrlsTest {
    @Test
    fun worksSearchUrlUsesCreatorsQueryAndPage() {
        val url = AO3AuthorUrls.worksSearchUrl("Alice Writer", page = 2)!!.toHttpUrl()

        assertEquals("https", url.scheme)
        assertEquals("archiveofourown.org", url.host)
        assertEquals("/works/search", url.encodedPath)
        assertEquals("Alice Writer", url.queryParameter("work_search[creators]"))
        assertEquals("2", url.queryParameter("page"))
    }

    @Test
    fun worksSearchUrlTrimsCreatorAndClampsPage() {
        val url = AO3AuthorUrls.worksSearchUrl("  Bob  ", page = 0)!!.toHttpUrl()

        assertEquals("Bob", url.queryParameter("work_search[creators]"))
        assertEquals("1", url.queryParameter("page"))
    }

    @Test
    fun worksSearchUrlReturnsNullForBlankCreator() {
        assertNull(AO3AuthorUrls.worksSearchUrl(""))
        assertNull(AO3AuthorUrls.worksSearchUrl("   "))
    }

    @Test
    fun userWorksUrlBuildsUsersWorksPath() {
        val page1 = AO3AuthorUrls.userWorksUrl("AO3_Reader")!!.toHttpUrl()
        assertEquals("/users/AO3_Reader/works", page1.encodedPath)
        assertNull(page1.queryParameter("page"))

        val page3 = AO3AuthorUrls.userWorksUrl("AO3_Reader", page = 3)!!.toHttpUrl()
        assertEquals("3", page3.queryParameter("page"))
    }

    @Test
    fun userWorksUrlReturnsNullForBlankUsername() {
        assertNull(AO3AuthorUrls.userWorksUrl("  "))
    }

    @Test
    fun userDraftsUrlBuildsWorksDraftsPath() {
        val url = AO3AuthorUrls.userDraftsUrl("AO3_Reader")!!.toHttpUrl()
        assertEquals("/users/AO3_Reader/works/drafts", url.encodedPath)
        assertNull(url.queryParameter("page"))
    }

    @Test
    fun userDraftsUrlReturnsNullForBlankUsername() {
        assertNull(AO3AuthorUrls.userDraftsUrl(""))
        assertNull(AO3AuthorUrls.userDraftsUrl("  "))
    }
}
