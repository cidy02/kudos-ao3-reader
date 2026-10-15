package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3CollectionTotalsTest {
    @Test fun unknownCollectionTotalsOmitTheirCellsAndKnownZeroIsDisplayed() {
        val bare = AO3Collection(name = "winter", title = "Winter")
        assertTrue(collectionStatCells(bare).isEmpty())
        val works = collectionStatCells(bare.copy(worksCount = 0))
        assertEquals(listOf("Works" to "0"), works.map { it.label to it.value })
        val bookmarks = collectionStatCells(bare.copy(bookmarksCount = 56))
        assertEquals(listOf("Bookmarks" to "56"), bookmarks.map { it.label to it.value })
        assertEquals(listOf("Works" to "1234", "Bookmarks" to "56"),
            collectionStatCells(bare.copy(worksCount = 1234, bookmarksCount = 56)).map { it.label to it.value })
    }
}
