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
    fun namedSubscriptionsUseIosTypeAndOnlyPaginateAfterPageOne() {
        assertEquals("https://archiveofourown.org/users/AO3_Reader/subscriptions?type=series",
            urls.namedSubscriptionsUrl(" AO3_Reader ", AO3NamedSubscriptionsScope.Series))
        assertEquals("https://archiveofourown.org/users/AO3_Reader/subscriptions?type=users",
            urls.namedSubscriptionsUrl("AO3_Reader", AO3NamedSubscriptionsScope.Users))
        assertEquals("https://archiveofourown.org/users/AO3%20Reader/subscriptions?type=series&page=2",
            urls.namedSubscriptionsUrl("AO3 Reader", AO3NamedSubscriptionsScope.Series, 2))
        assertEquals("https://archiveofourown.org/users/AO3_Reader/subscriptions?type=users&page=3",
            urls.namedSubscriptionsUrl("AO3_Reader", AO3NamedSubscriptionsScope.Users, 3))
    }

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
        assertEquals(
            "https://archiveofourown.org/users/AO3_Reader/collections",
            urls.collectionsUrl("AO3_Reader")
        )
        assertEquals(
            "https://archiveofourown.org/users/AO3_Reader/collections?page=2",
            urls.collectionsUrl("AO3_Reader", page = 2)
        )
        assertEquals(
            "https://archiveofourown.org/collections/cool_fics/works",
            urls.collectionWorksUrl("cool_fics")
        )
        assertEquals(
            "https://archiveofourown.org/collections/cool_fics/works?page=3",
            urls.url(
                AccountListType.Collection(name = "cool_fics", displayTitle = "Cool Fics"),
                username = "AO3_Reader",
                page = 3
            )
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
    fun bundledMixedPageKeepsWorksSeriesAndUsersSeparate() {
        val candidates = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
        val html = candidates.map { java.io.File(it, "fixtures/ao3_subscriptions.html") }
            .first { it.isFile }.readText()
        val parser = AO3AccountParser()
        assertEquals(listOf(45678901L, 12345L, 999000002L), parser.parseSubscriptionsPage(html, 1).works.map { it.id })
        val series = parser.parseNamedSubscriptions(html, AO3NamedSubscriptionsScope.Series)
        assertEquals("/series/999", series.rows.single().path)
        assertEquals("My Series", series.rows.single().name)
        assertEquals(listOf("seriesauthor"), series.rows.single().creators.map { it.displayName })
        assertEquals(3, series.totalPages)
        val users = parser.parseNamedSubscriptions(html, AO3NamedSubscriptionsScope.Users, 2)
        assertEquals("/users/someuser", users.rows.single().path)
        assertEquals("someuser", users.rows.single().name)
        assertTrue(users.rows.single().creators.isEmpty())
        assertEquals(2, users.currentPage)
        assertEquals(3, users.totalPages)
    }

    @Test
    fun firstLinkSelectsScopeAndDuplicatePathsAndDeepUserLinksAreSkipped() {
        val html = """<dl class="subscription">
            <dt><a href="/series/999">Series</a><a rel="author" href="/users/one/pseuds/Pen">Pen</a></dt>
            <dt><a href="https://archiveofourown.org/series/999">Duplicate</a></dt>
            <dt><a href="/users/one/works">Works</a></dt>
            <dt><a href="/users/one/pseuds/Pen">Pseud</a></dt>
            <dt><a href="/users/one">one</a></dt>
            <dt><a href="/series/no-id">Bad series</a></dt>
            </dl>"""
        val parser = AO3AccountParser()
        assertEquals(listOf("/series/999"), parser.parseNamedSubscriptions(html, AO3NamedSubscriptionsScope.Series).rows.map { it.path })
        assertEquals(listOf("/users/one"), parser.parseNamedSubscriptions(html, AO3NamedSubscriptionsScope.Users).rows.map { it.path })
    }

    @Test
    fun namedEmptyCopyAndCountsMatchIos() {
        assertEquals("No series subscriptions", AO3NamedSubscriptionsScope.Series.emptyTitle)
        assertEquals("Series you subscribe to on AO3 show up here.", AO3NamedSubscriptionsScope.Series.emptyMessage)
        assertEquals("No author subscriptions", AO3NamedSubscriptionsScope.Users.emptyTitle)
        assertEquals("Authors you subscribe to on AO3 show up here.", AO3NamedSubscriptionsScope.Users.emptyMessage)
        assertEquals("1 series", AO3NamedSubscriptionsScope.Series.subtitle(1, 1, 1))
        assertEquals("1 author", AO3NamedSubscriptionsScope.Users.subtitle(1, 1, 1))
        assertEquals("2 authors · page 2 of 3", AO3NamedSubscriptionsScope.Users.subtitle(2, 2, 3))
    }

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

class AO3CollectionsParserTest {
    @Test
    fun parsesCollectionsIndexNameTitleByline() {
        val collections = AO3AccountParser().parseCollections(
            accountResourceText("ao3/account/collections.html")
        )

        assertEquals(2, collections.size)
        assertEquals(listOf("cool_fics", "another_one"), collections.map { it.name })
        assertEquals("Cool Fics", collections[0].title)
        assertEquals("Maintained by someone", collections[0].byline)
        assertEquals("Another One", collections[1].title)
        assertEquals("", collections[1].byline)
    }

    @Test
    fun emptyCollectionsIndexIsNotAnError() {
        val collections = AO3AccountParser().parseCollections(
            accountResourceText("ao3/account/empty_list.html")
        )
        assertTrue(collections.isEmpty())
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
