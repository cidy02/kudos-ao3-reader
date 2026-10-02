package io.github.cidy02.kudos.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LibrarySectionKindTest {
    @Test
    fun dashboardOrderMatchesIos() {
        assertEquals(
            listOf(
                "Reading Now",
                "Saved for Later",
                "Finished",
                "Collections",
                "Downloaded",
                "Reading History",
                "Favorites"
            ),
            LibrarySectionKind.entries.map { it.title }
        )
    }

    @Test
    fun routeIdsRoundTrip() {
        LibrarySectionKind.entries.forEach { kind ->
            assertEquals(kind, LibrarySectionKind.fromId(kind.id))
        }
        assertNull(LibrarySectionKind.fromId("unknown"))
    }
}
