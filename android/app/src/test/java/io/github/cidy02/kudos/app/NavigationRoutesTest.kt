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

    @Test
    fun recentlyDeletedRouteHasUserFacingTitle() {
        assertEquals("Recently Deleted", Routes.titleFor(Routes.RecentlyDeleted))
    }

    @Test
    fun readingQueueRoutesHaveUserFacingTitles() {
        assertEquals("Reading Queues", Routes.titleFor(Routes.ReadingQueues))
        assertEquals("Queue", Routes.titleFor(Routes.QueueDetail))
    }

    @Test
    fun readingStatisticsRouteHasUserFacingTitle() {
        assertEquals("Reading Insights", Routes.titleFor(Routes.ReadingStatistics))
    }

    @Test
    fun authorWorksRouteHasUserFacingTitle() {
        assertEquals("Author", Routes.titleFor(Routes.AuthorWorks))
    }
}
