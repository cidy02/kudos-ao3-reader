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

    @Test
    fun aPseudOfTwoWordsReadFromALinkIsItsNameAndIsAskedForOnce() {
        val about = AO3AuthorParser().parseAbout(
            """<div class="user home profile"><dl class="meta"><dd class="pseuds">
               <a href="/users/Avery_Archive/pseuds/Avery%20Writes">Avery Writes</a>,
               <a href="https://archiveofourown.org/users/Avery_Archive/pseuds/NightShift">NightShift</a>
               </dd></dl></div>""",
            AO3AuthorRoute("Avery_Archive", "Avery Writes")
        )
        assertEquals(listOf("Avery Writes", "NightShift"), about.pseuds.map { it.route.pseud })
        assertEquals("/users/Avery_Archive/pseuds/Avery%20Writes/works",
            about.pseuds.first().route.worksUrl.toHttpUrl().encodedPath)
    }

    @Test
    fun aBylineWithAPseudOpensTheAccountBehindIt() {
        val route = AO3AuthorRoute.fromByline(" Second Pseud (SecondAccount) ")
        assertEquals(AO3AuthorRoute("SecondAccount", "Second Pseud"), route)
        assertEquals("/users/SecondAccount/pseuds/Second%20Pseud/works", route.worksUrl.toHttpUrl().encodedPath)
        // A pseud may hold brackets of its own; the account is the last pair.
        assertEquals(AO3AuthorRoute("baz", "Foo (bar)"), AO3AuthorRoute.fromByline("Foo (bar) (baz)"))
    }

    @Test
    fun aBylineThatIsNotAO3sPseudFormIsTakenWhole() {
        assertEquals(AO3AuthorRoute("nine_of_wands"), AO3AuthorRoute.fromByline("nine_of_wands"))
        // No space before the bracket, or something an account name cannot hold.
        assertEquals(AO3AuthorRoute("name(x)"), AO3AuthorRoute.fromByline("name(x)"))
        assertEquals(AO3AuthorRoute("A (b c)"), AO3AuthorRoute.fromByline("A (b c)"))
    }
}
