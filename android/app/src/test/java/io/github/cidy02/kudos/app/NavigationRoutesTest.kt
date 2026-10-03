package io.github.cidy02.kudos.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
    fun searchIsAShellRootBesideTheFourTabs() {
        assertTrue(Routes.isShellRoot(Routes.Search))
        assertTrue(Routes.isShellRoot(Routes.Home))
        assertFalse(Routes.isTopLevel(Routes.Search))
        assertEquals("Home", Routes.shellTitle(Routes.Home))
        assertEquals(null, Routes.shellTitle(Routes.Account))
        assertFalse(Routes.isShellRoot(Routes.WorkDetail))
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

    @Test
    fun pushedRoutesWithSubjectHeaderBlockAreIdentified() {
        assertTrue(Routes.hasSubjectHeader(Routes.ReadingQueues))
        assertTrue(Routes.hasSubjectHeader(Routes.readingQueues("test-queue")))
        assertTrue(Routes.hasSubjectHeader(Routes.readingQueues()))
        assertTrue(Routes.hasSubjectHeader(Routes.QueueDetail))
        assertTrue(Routes.hasSubjectHeader(Routes.queueDetail("test-queue")))
        assertTrue(Routes.hasSubjectHeader(Routes.Collections))
        assertTrue(Routes.hasSubjectHeader(Routes.CollectionDetail))
        assertTrue(Routes.hasSubjectHeader(Routes.collectionDetail("test-collection")))
        assertTrue(Routes.hasSubjectHeader(Routes.RecentlyDeleted))
        assertTrue(Routes.hasSubjectHeader(Routes.LibrarySection))
        assertTrue(Routes.hasSubjectHeader(Routes.librarySection("to-read")))

        assertFalse(Routes.hasSubjectHeader(Routes.HomeSection))
        assertFalse(Routes.hasSubjectHeader(Routes.WorkDetail))
        assertFalse(Routes.hasSubjectHeader(Routes.Settings))
        assertFalse(Routes.hasSubjectHeader(Routes.BrowseWorks))
        assertFalse(Routes.hasSubjectHeader(null))
    }

    @Test
    fun tabBarVisibilityFollowsIOSHidesFloatingTabBar() {
        // Screens hiding tab bar matching iOS hidesFloatingTabBar() + reader
        assertTrue(Routes.hidesTabBar(Routes.AO3Collections))
        assertTrue(Routes.hidesTabBar(Routes.SeriesWorks))
        assertTrue(Routes.hidesTabBar(Routes.seriesWorks("https://archiveofourown.org/series/123")))
        assertTrue(Routes.hidesTabBar(Routes.AuthorProfile))
        assertTrue(Routes.hidesTabBar(Routes.authorProfile("author_name")))
        assertTrue(Routes.hidesTabBar(Routes.Comments))
        assertTrue(Routes.hidesTabBar(Routes.comments(12345L)))
        assertTrue(Routes.hidesTabBar(Routes.BrowseFandoms))
        assertTrue(Routes.hidesTabBar(Routes.browseFandoms("Anime", "anime-manga")))
        assertTrue(Routes.hidesTabBar(Routes.Settings))
        assertTrue(Routes.hidesTabBar(Routes.Reader))
        assertTrue(Routes.hidesTabBar(Routes.reader("12345")))

        // All other pushed screens keep tab bar visible
        assertFalse(Routes.hidesTabBar(Routes.ReadingQueues))
        assertFalse(Routes.hidesTabBar(Routes.readingQueues("test-queue")))
        assertFalse(Routes.hidesTabBar(Routes.QueueDetail))
        assertFalse(Routes.hidesTabBar(Routes.Collections))
        assertFalse(Routes.hidesTabBar(Routes.LibrarySection))
        assertFalse(Routes.hidesTabBar(Routes.LocalHistory))
        assertFalse(Routes.hidesTabBar(Routes.LocalFavorites))
        assertFalse(Routes.hidesTabBar(Routes.About))
        assertFalse(Routes.hidesTabBar(Routes.BrowseWorks))
        assertFalse(Routes.hidesTabBar(Routes.HomeSection))
        assertFalse(Routes.hidesTabBar(null))
    }
}
