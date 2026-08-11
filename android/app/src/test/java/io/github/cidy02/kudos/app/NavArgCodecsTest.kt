package io.github.cidy02.kudos.app

import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.works.WorkDetailSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NavArgCodecsTest {

    // --- WorkDetailSource ---

    @Test
    fun localWorkRoundTrips() {
        val source = WorkDetailSource.LocalWork(workId = "abc-123")
        val decoded = NavArgCodecs.decodeWorkDetailSource(NavArgCodecs.encodeWorkDetailSource(source))
        assertEquals(source, decoded)
    }

    @Test
    fun ao3WorkIdRoundTrips() {
        val source = WorkDetailSource.Ao3WorkId(workId = 456L)
        val decoded = NavArgCodecs.decodeWorkDetailSource(NavArgCodecs.encodeWorkDetailSource(source))
        assertEquals(source, decoded)
    }

    @Test
    fun remoteUrlRoundTripsIncludingSpecialCharacters() {
        val source = WorkDetailSource.RemoteUrl(url = "https://archiveofourown.org/works/1?a=b&c=d")
        val decoded = NavArgCodecs.decodeWorkDetailSource(NavArgCodecs.encodeWorkDetailSource(source))
        assertEquals(source, decoded)
    }

    @Test
    fun remoteSummaryCollapsesToAo3WorkIdSinceTheFullSummaryCannotTravelInARouteString() {
        val summary = sampleSummary(id = 789L)
        val encoded = NavArgCodecs.encodeWorkDetailSource(WorkDetailSource.RemoteSummary(summary))
        assertEquals(WorkDetailSource.Ao3WorkId(789L), NavArgCodecs.decodeWorkDetailSource(encoded))
    }

    @Test
    fun malformedWorkDetailSourceDecodesToNull() {
        assertNull(NavArgCodecs.decodeWorkDetailSource(""))
        assertNull(NavArgCodecs.decodeWorkDetailSource("garbage"))
        assertNull(NavArgCodecs.decodeWorkDetailSource("ao3:notanumber"))
    }

    // --- AccountListType ---

    @Test
    fun objectVariantsRoundTrip() {
        val types = listOf(
            AccountListType.MarkedForLater,
            AccountListType.Bookmarks,
            AccountListType.History,
            AccountListType.Subscriptions,
            AccountListType.MyWorks
        )
        for (type in types) {
            val decoded = NavArgCodecs.decodeAccountListType(NavArgCodecs.encodeAccountListType(type))
            assertEquals(type, decoded)
        }
    }

    @Test
    fun collectionVariantRoundTripsWithPlainNames() {
        val type = AccountListType.Collection(name = "my-collection", displayTitle = "My Collection")
        val decoded = NavArgCodecs.decodeAccountListType(NavArgCodecs.encodeAccountListType(type))
        assertEquals(type, decoded)
    }

    @Test
    fun collectionVariantRoundTripsWithColonsAndSlashesInBothFields() {
        // The delimiter used to join name/displayTitle is itself ':' - a name or title
        // that already contains ':' or '/' must not corrupt the split.
        val type = AccountListType.Collection(
            name = "weird:name/with-slash",
            displayTitle = "Title: With a Colon / and Slash"
        )
        val decoded = NavArgCodecs.decodeAccountListType(NavArgCodecs.encodeAccountListType(type))
        assertEquals(type, decoded)
    }

    @Test
    fun malformedAccountListTypeDecodesToNull() {
        assertNull(NavArgCodecs.decodeAccountListType(""))
        assertNull(NavArgCodecs.decodeAccountListType("NotARealType"))
        assertNull(NavArgCodecs.decodeAccountListType("Collection:onlyonepart"))
    }

    private fun sampleSummary(id: Long): AO3WorkSummary {
        return AO3WorkSummary(
            id = id,
            title = "Example",
            authors = listOf("Alice"),
            fandoms = listOf("Fandom"),
            rating = "Teen",
            warnings = listOf("No Archive Warnings Apply"),
            categories = listOf("Gen"),
            relationships = listOf("A/B"),
            characters = listOf("A"),
            freeforms = listOf("Fluff"),
            summary = "Summary",
            language = "English",
            wordCount = 1200,
            chapters = "1/1",
            kudos = 7,
            comments = 2,
            hits = 99,
            isComplete = true
        )
    }
}
