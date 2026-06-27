package io.github.cidy02.kudos.network.ao3.account

import io.github.cidy02.kudos.account.AccountListType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AO3UsernameParserTest {
    @Test
    fun detectsLoggedInPageAndUsername() {
        val parser = AO3UsernameParser()
        val html = accountResourceText("ao3/account/logged_in.html")

        assertTrue(parser.isLoggedIn(html))
        assertEquals("AO3 Reader", parser.username(html))
    }
}

class AO3AccountUrlsTest {
    private val urls = AO3AccountUrls()

    @Test
    fun buildsAppleCompatibleAccountUrls() {
        assertEquals(
            "https://archiveofourown.org/users/AO3_Reader/readings?show=to-read",
            urls.url(AccountListType.MarkedForLater, "AO3_Reader")
        )
        assertEquals(
            "https://archiveofourown.org/users/AO3_Reader/readings?page=2",
            urls.url(AccountListType.History, "AO3_Reader", page = 2)
        )
        assertEquals(
            "https://archiveofourown.org/users/AO3_Reader/bookmarks",
            urls.url(AccountListType.Bookmarks, "AO3_Reader")
        )
        assertEquals(
            "https://archiveofourown.org/users/AO3_Reader/subscriptions?type=works",
            urls.url(AccountListType.Subscriptions, "AO3_Reader")
        )
        assertEquals(
            "https://archiveofourown.org/users/AO3%20Reader/works",
            urls.url(AccountListType.MyWorks, "AO3 Reader")
        )
    }
}

class AO3MarkedForLaterParserTest {
    @Test
    fun parsesMarkedForLaterWorkBlurbs() {
        val page = AO3AccountParser().parseAccountList(
            accountResourceText("ao3/account/marked_for_later.html"),
            page = 1,
            type = AccountListType.MarkedForLater
        )

        val work = page.works.single()
        assertEquals(101L, work.id)
        assertEquals("Later Work", work.title)
        assertEquals(listOf("alice"), work.authors)
        assertEquals(1234, work.wordCount)
    }
}

class AO3HistoryParserTest {
    @Test
    fun parsesHistoryAndPagination() {
        val page = AO3AccountParser().parseAccountList(
            accountResourceText("ao3/account/history.html"),
            page = 1,
            type = AccountListType.History
        )

        assertEquals(202L, page.works.single().id)
        assertEquals(2, page.totalPages)
    }
}

class AO3BookmarksParserTest {
    @Test
    fun parsesBookmarkBlurbsAndSkipsNonWorkBookmarks() {
        val page = AO3AccountParser().parseAccountList(
            accountResourceText("ao3/account/bookmarks.html"),
            page = 1,
            type = AccountListType.Bookmarks
        )

        val work = page.works.single()
        assertEquals(303L, work.id)
        assertEquals("Bookmarked Work", work.title)
        assertEquals(listOf("casey"), work.authors)
    }
}

class AO3SubscriptionsParserTest {
    @Test
    fun parsesSparseWorkSubscriptionsOnly() {
        val page = AO3AccountParser().parseAccountList(
            accountResourceText("ao3/account/subscriptions.html"),
            page = 1,
            type = AccountListType.Subscriptions
        )

        val work = page.works.single()
        assertEquals(404L, work.id)
        assertEquals("Subscribed Work", work.title)
        assertEquals(listOf("drew"), work.authors)
        assertTrue(work.fandoms.isEmpty())
    }
}

class AO3AccountListEmptyStateParserTest {
    @Test
    fun emptySignedInListIsNotAnError() {
        val page = AO3AccountParser().parseAccountList(
            accountResourceText("ao3/account/empty_list.html"),
            page = 1,
            type = AccountListType.History
        )

        assertTrue(page.works.isEmpty())
        assertEquals(1, page.totalPages)
    }
}

class AO3AccountListLoginRequiredParserTest {
    @Test
    fun loginPageThrowsTypedParserError() {
        try {
            AO3AccountParser().parseAccountList(
                accountResourceText("ao3/account/login_required.html"),
                page = 1,
                type = AccountListType.History
            )
            fail("Expected login-required parser error.")
        } catch (error: AO3AccountParseException.LoginRequired) {
            assertNotNull(error.message)
        }
    }
}

class AO3AccountListOverloadParserTest {
    @Test
    fun overloadPageThrowsTypedParserError() {
        try {
            AO3AccountParser().parseAccountList(
                accountResourceText("ao3/account/overload.html"),
                page = 1,
                type = AccountListType.History
            )
            fail("Expected overload parser error.")
        } catch (error: AO3AccountParseException.Overloaded) {
            assertNotNull(error.message)
        }
    }
}

private fun accountResourceText(path: String): String {
    val resource = Thread.currentThread().contextClassLoader?.getResource(path)
        ?: error("Missing test resource: $path")
    return resource.readText()
}
