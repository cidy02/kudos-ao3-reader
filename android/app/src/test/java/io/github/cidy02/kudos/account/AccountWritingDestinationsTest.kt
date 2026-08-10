package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.author.AO3AuthorUrls
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit-testable destinations for Account → Writing tabs that are not plain
 * [AccountListType] loads (Series is author-profile series; Drafts is web).
 */
class AccountWritingDestinationsTest {

    @Test
    fun draftsUrlBuildsUsersWorksDraftsPath() {
        val url = AO3AuthorUrls.userDraftsUrl("AO3_Reader")!!.toHttpUrl()
        assertEquals("https", url.scheme)
        assertEquals("archiveofourown.org", url.host)
        assertEquals("/users/AO3_Reader/works/drafts", url.encodedPath)
    }

    @Test
    fun draftsUrlTrimsUsername() {
        val url = AO3AuthorUrls.userDraftsUrl("  Alice  ")!!.toHttpUrl()
        assertEquals("/users/Alice/works/drafts", url.encodedPath)
    }

    @Test
    fun draftsUrlReturnsNullForBlankUsername() {
        assertNull(AO3AuthorUrls.userDraftsUrl(""))
        assertNull(AO3AuthorUrls.userDraftsUrl("   "))
    }

    @Test
    fun writingSeriesAndDraftsHaveNoAccountListType() {
        // Signed-out and these kinds share the same gate: no list-type load path.
        // Series uses author series parser; Drafts uses [userDraftsUrl] + web fallback.
        assertNull(AccountWritingKind.Series.toAccountListType())
        assertNull(AccountWritingKind.Drafts.toAccountListType())
        assertEquals(AccountListType.MyWorks, AccountWritingKind.Works.toAccountListType())
    }

    @Test
    fun seriesUrlMatchesAuthorProfileSeriesPath() {
        // Series tab reuses the same URL the author profile series tab hits.
        val url = AO3AuthorUrls.userSeriesUrl("AO3_Reader")!!.toHttpUrl()
        assertEquals("/users/AO3_Reader/series", url.encodedPath)
    }
}
