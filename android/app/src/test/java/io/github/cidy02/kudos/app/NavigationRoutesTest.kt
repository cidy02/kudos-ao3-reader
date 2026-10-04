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
        assertTrue(Routes.hasSubjectHeader(Routes.BrowseWorks))
        assertTrue(Routes.hasSubjectHeader(Routes.browseWorks("Sherlock")))
        assertTrue(Routes.hasSubjectHeader(Routes.SeriesWorks))
        assertTrue(Routes.hasSubjectHeader(Routes.seriesWorks("https://archiveofourown.org/series/123")))

        assertFalse(Routes.hasSubjectHeader(Routes.HomeSection))
        assertFalse(Routes.hasSubjectHeader(Routes.WorkDetail))
        assertFalse(Routes.hasSubjectHeader(Routes.Settings))
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
        assertTrue(Routes.hidesTabBar(Routes.WorkDetail))
        assertTrue(Routes.hidesTabBar(Routes.QueueDetail))
        assertTrue(Routes.hidesTabBar(Routes.Collections))
        assertTrue(Routes.hidesTabBar(Routes.About))
        assertTrue(Routes.hidesTabBar(Routes.Backup))
        assertTrue(Routes.hidesTabBar(Routes.BrowseWorks))
        assertTrue(Routes.hidesTabBar(Routes.ReadingStatistics))
        assertTrue(Routes.hidesTabBar(Routes.AccountList))
        assertTrue(Routes.hidesTabBar(Routes.AO3Preferences))

        // The selectable lists opt back in on iOS (.toolbar(.automatic, for: .tabBar))
        assertFalse(Routes.hidesTabBar(Routes.ReadingQueues))
        assertFalse(Routes.hidesTabBar(Routes.readingQueues("test-queue")))
        assertFalse(Routes.hidesTabBar(Routes.LibrarySection))
        assertFalse(Routes.hidesTabBar(Routes.LocalHistory))
        assertFalse(Routes.hidesTabBar(Routes.LocalFavorites))
        assertFalse(Routes.hidesTabBar(Routes.HomeSection))
        assertFalse(Routes.hidesTabBar(Routes.RecentlyDeleted))
        assertFalse(Routes.hidesTabBar(Routes.CollectionDetail))
        assertFalse(Routes.hidesTabBar(null))
    }
}
