package io.github.cidy02.kudos.network.ao3.account

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3CollectionParserTest {
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
