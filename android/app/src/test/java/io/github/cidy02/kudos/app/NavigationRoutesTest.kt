package io.github.cidy02.kudos.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class NavigationRoutesTest {
    @Test
    fun topLevelDestinationsStayLimitedToApprovedAppSections() {
        assertEquals(
            listOf(Routes.Home, Routes.Library, Routes.Browse, Routes.Account),
            Routes.topLevelDestinations.map { it.route }
        )
        assertFalse(Routes.Search in Routes.topLevelDestinations.map { it.route })
    }

    @Test
    fun phaseTenAndElevenRoutesHaveUserFacingTitles() {
        assertEquals("Comments", Routes.titleFor(Routes.Comments))
        assertEquals("Fandoms", Routes.titleFor(Routes.BrowseFandoms))
        assertEquals("Works", Routes.titleFor(Routes.BrowseWorks))
        assertEquals("AO3", Routes.titleFor(Routes.WebFallback))
    }
}
