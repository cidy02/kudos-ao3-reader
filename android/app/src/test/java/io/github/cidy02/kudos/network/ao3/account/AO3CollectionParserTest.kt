package io.github.cidy02.kudos.network.ao3.account

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test

class AO3CollectionParserTest {
    @Test
    fun collectionShowReadsTotalsFromItsOwnNavLinks() {
        val parser = AO3CollectionParser()
        val html = """<html><body>
            <div class="primary header module"><h2 class="heading">Winter Fest</h2></div>
            <ul class="navigation actions">
              <li><a href="/collections/winter_child/works">Works (999)</a></li>
              <li><a href="/collections/winter/works">Works (1,234)</a></li>
              <li><a href="/collections/winter/bookmarks">Bookmarked Items (56)</a></li>
            </ul></body></html>"""
        val show = parser.parseCollectionShow(html, "winter")
        assertEquals(1234, show.collection.worksCount)
        assertEquals(56, show.collection.bookmarksCount)
        assertEquals(false, show.collection.viewerIsOwner)
        val bare = parser.parseCollectionShow("<html><body><h2 class=heading>Winter</h2></body></html>", "winter")
        assertNull(bare.collection.worksCount)
        assertNull(bare.collection.bookmarksCount)
        val zero = parser.parseCollectionShow(html.replace("(1,234)", "(0)").replace("(56)", "(0)"), "winter")
        assertEquals(0, zero.collection.worksCount)
        assertEquals(0, zero.collection.bookmarksCount)
    }

    @Test
    fun parsesCollectionShowFixture() {
        val show = AO3CollectionParser().parseCollectionShow(
            fixture("ao3_collection_show.html"),
            slug = "winter_exchange"
        )

        assertEquals("Winter Exchange 2026", show.collection.title)
        assertEquals(234, show.collection.worksCount)
        assertEquals(18, show.collection.bookmarksCount)
        assertTrue((show.collection.worksCount ?: 0) > 0)
        assertTrue(show.collection.maintainerIdentities.isNotEmpty())
        assertEquals("AO3_Reader", show.collection.maintainerIdentities.first().displayName)
    }

    private fun fixture(name: String): String {
        val candidates = listOf(
            File("src/debug/assets/fixtures/$name"),
            File("app/src/debug/assets/fixtures/$name"),
            File("android/app/src/debug/assets/fixtures/$name")
        )
        return candidates.firstOrNull(File::isFile)?.readText()
            ?: error("Missing debug fixture: $name")
    }
}
