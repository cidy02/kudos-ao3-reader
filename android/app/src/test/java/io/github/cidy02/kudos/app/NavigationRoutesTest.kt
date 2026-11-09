package io.github.cidy02.kudos.app

import androidx.compose.runtime.saveable.SaverScope
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.home.accountAvatarInitial
import io.github.cidy02.kudos.home.formatAccountUnreadAccessibilityValue
import io.github.cidy02.kudos.home.formatAccountUnreadBadge
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NavigationRoutesTest {
    @Test
    fun topLevelDestinationsStayLimitedToApprovedAppSections() {
        assertEquals(
            listOf(Routes.Home, Routes.Library, Routes.Writing, Routes.Browse),
            Routes.topLevelDestinations.map { it.route }
        )
        assertFalse(Routes.Account in Routes.topLevelDestinations.map { it.route })
        assertFalse(Routes.Search in Routes.topLevelDestinations.map { it.route })
    }

    @Test
    fun searchIsAShellRootBesideTheFourTabs() {
        assertTrue(Routes.isShellRoot(Routes.Search))
        assertTrue(Routes.isShellRoot(Routes.Home))
        assertTrue(Routes.isShellRoot(Routes.Writing))
        assertFalse(Routes.isShellRoot(Routes.Account))
        assertFalse(Routes.isTopLevel(Routes.Search))
        assertEquals("Home", Routes.shellTitle(Routes.Home))
        assertEquals("Writing", Routes.shellTitle(Routes.Writing))
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
        assertTrue(Routes.hasSubjectHeader(Routes.Backup))
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
        assertTrue(Routes.hidesTabBar(Routes.Search))
        assertTrue(Routes.hidesTabBar(Routes.BrowseWorks))
        assertTrue(Routes.hidesTabBar(Routes.ReadingStatistics))
        assertTrue(Routes.hidesTabBar(Routes.AccountList))
        assertTrue(Routes.hidesTabBar(Routes.AO3Preferences))

        // The selectable lists opt back in on iOS (.toolbar(.automatic, for: .tabBar))
        assertFalse(Routes.hidesTabBar(Routes.ReadingQueues))
        assertFalse(Routes.hidesTabBar(Routes.readingQueues("test-queue")))
        assertFalse(Routes.hidesTabBar(Routes.LibrarySection))
        assertFalse(Routes.hidesTabBar(Routes.HomeSection))
        assertFalse(Routes.hidesTabBar(Routes.RecentlyDeleted))
        assertFalse(Routes.hidesTabBar(Routes.CollectionDetail))
        assertFalse(Routes.hidesTabBar(Routes.Writing))
        assertFalse(Routes.hidesTabBar(null))
    }

    @Test
    fun everyFormerAccountTabRouteResolvesToSheetOrNewTabHome() {
        assertEquals(AccountSheetRoute.Profile, Routes.accountSheetRoute(Routes.Account))
        assertEquals(AccountSheetRoute.Inbox, Routes.accountSheetRoute(Routes.AccountInbox))
        assertEquals(AccountSheetRoute.Preferences, Routes.accountSheetRoute(Routes.AO3Preferences))
        assertEquals(AccountSheetRoute.Dashboard, Routes.accountSheetRoute(Routes.AO3Dashboard))
        assertEquals(AccountSheetRoute.MoreOnAO3, Routes.accountSheetRoute(Routes.AccountMoreOnAO3))
        assertEquals(AccountSheetRoute.Settings, Routes.accountSheetRoute(Routes.Settings))
        assertEquals(AccountSheetRoute.BackupAndSync, Routes.accountSheetRoute(Routes.Backup))
        assertEquals(AccountSheetRoute.About, Routes.accountSheetRoute(Routes.About))
        assertEquals(AccountSheetRoute.Shortcuts, Routes.accountSheetRoute(Routes.AccountShortcuts))
        assertEquals(AccountSheetRoute.Login, Routes.accountSheetRoute(Routes.AccountLogin))
        assertEquals(AccountSheetRoute.NativeLogin, Routes.accountSheetRoute(Routes.NativeLogin))
        assertEquals(AccountSheetRoute.BugReport, Routes.accountSheetRoute(Routes.BugReport))
        assertEquals(AccountSheetRoute.QueueStorage, Routes.accountSheetRoute(Routes.QueueStorage))
        assertEquals(AccountSheetRoute.AvailabilitySweep, Routes.accountSheetRoute(Routes.AvailabilitySweep))

        assertEquals(LegacyAccountDestination.Account(AccountSheetRoute.Dashboard), LegacyAccountRoute.Dashboard.destination)
        assertEquals(LegacyAccountDestination.Account(AccountSheetRoute.Inbox), LegacyAccountRoute.Inbox.destination)
        assertEquals(LegacyAccountDestination.Account(AccountSheetRoute.Preferences), LegacyAccountRoute.Preferences.destination)
        assertEquals(LegacyAccountDestination.Account(AccountSheetRoute.MoreOnAO3), LegacyAccountRoute.MoreOnAO3.destination)
        assertEquals(LegacyAccountDestination.Account(AccountSheetRoute.Settings), LegacyAccountRoute.Settings.destination)
        assertEquals(LegacyAccountDestination.Writing(WritingRoute.Works), LegacyAccountRoute.Works.destination)
        assertEquals(LegacyAccountDestination.Writing(WritingRoute.Drafts), LegacyAccountRoute.Drafts.destination)
        assertEquals(LegacyAccountDestination.Writing(WritingRoute.Series), LegacyAccountRoute.Series.destination)
        assertEquals(LegacyAccountDestination.Writing(WritingRoute.CollectionsAndChallenges), LegacyAccountRoute.Collections.destination)
        assertEquals(LegacyAccountDestination.Library(LibraryAO3Route.MarkedForLater), LegacyAccountRoute.MarkedForLater.destination)
        assertEquals(LegacyAccountDestination.Library(LibraryAO3Route.Bookmarks), LegacyAccountRoute.Bookmarks.destination)
        assertEquals(LegacyAccountDestination.Library(LibraryAO3Route.Subscriptions), LegacyAccountRoute.Subscriptions.destination)
        assertEquals(LegacyAccountDestination.Library(LibraryAO3Route.History), LegacyAccountRoute.History.destination)

        assertEquals(
            LegacyAccountDestination.Writing(WritingRoute.Drafts),
            Routes.resolveFormerAccountRoute(Routes.WritingDrafts)
        )
        assertEquals(
            LegacyAccountDestination.Writing(WritingRoute.CollectionsAndChallenges),
            Routes.resolveFormerAccountRoute(Routes.AO3Collections)
        )
        assertEquals(
            LegacyAccountDestination.Writing(WritingRoute.Series),
            Routes.resolveFormerAccountRoute(Routes.authorSeries("writer"))
        )
        assertEquals(
            LegacyAccountDestination.Writing(WritingRoute.Works),
            Routes.resolveFormerAccountRoute(Routes.accountList("MyWorks"))
        )
        assertEquals(
            LegacyAccountDestination.Library(LibraryAO3Route.MarkedForLater),
            Routes.resolveFormerAccountRoute(Routes.accountList("MarkedForLater"))
        )
        assertEquals(
            LegacyAccountDestination.Library(LibraryAO3Route.Bookmarks),
            Routes.resolveFormerAccountRoute(Routes.accountList("Bookmarks"))
        )
        assertEquals(
            LegacyAccountDestination.Library(LibraryAO3Route.Subscriptions),
            Routes.resolveFormerAccountRoute(Routes.accountList("Subscriptions"))
        )
        assertEquals(
            LegacyAccountDestination.Library(LibraryAO3Route.History),
            Routes.resolveFormerAccountRoute(Routes.accountList("History"))
        )
    }

    @Test
    fun restoredAccountSelectionMigratesToHomeAndPresentsAccountSheet() {
        assertEquals(
            RestoredTabSelection(tabRoute = Routes.Home, presentsAccount = true, accountRoute = AccountSheetRoute.Profile),
            Routes.restoredSelection(Routes.Account)
        )
        assertEquals(
            RestoredTabSelection(tabRoute = Routes.Home, presentsAccount = true, accountRoute = AccountSheetRoute.Inbox),
            Routes.restoredSelection(Routes.AccountInbox)
        )
        assertEquals(
            RestoredTabSelection(tabRoute = Routes.Writing, presentsAccount = false, accountRoute = null),
            Routes.restoredSelection(Routes.Writing)
        )
    }

    @Test
    fun accountSheetStateConsumesRoutesAndBackClosesInsideOut() {
        val state = AccountSheetState()

        state.showAccount(AccountSheetRoute.Inbox)
        assertTrue(state.isPresentingAccount)
        assertEquals(AccountSheetRoute.Inbox, state.consumePendingAccountRoute())
        assertNull(state.consumePendingAccountRoute())

        var poppedSubpage = 0
        var poppedStack = 0
        var dismissedSheet = 0
        handleAccountSheetBack(
            customOnBack = { poppedSubpage++ },
            canPopSheetStack = true,
            popSheetStack = { poppedStack++ },
            dismissSheet = { dismissedSheet++ }
        )
        assertEquals(1, poppedSubpage)
        assertEquals(0, poppedStack)
        assertEquals(0, dismissedSheet)

        handleAccountSheetBack(
            customOnBack = null,
            canPopSheetStack = true,
            popSheetStack = { poppedStack++ },
            dismissSheet = { dismissedSheet++ }
        )
        assertEquals(1, poppedStack)
        assertEquals(0, dismissedSheet)

        handleAccountSheetBack(
            customOnBack = null,
            canPopSheetStack = false,
            popSheetStack = { poppedStack++ },
            dismissSheet = { dismissedSheet++ }
        )
        assertEquals(1, poppedStack)
        assertEquals(1, dismissedSheet)
    }

    @Test
    fun profileButtonBadgeCountFormatsUnreadCountsAndInitials() {
        assertNull(formatAccountUnreadBadge(isLoggedIn = false, unreadCount = 5))
        assertNull(formatAccountUnreadBadge(isLoggedIn = true, unreadCount = null))
        assertNull(formatAccountUnreadBadge(isLoggedIn = true, unreadCount = 0))
        assertEquals("1", formatAccountUnreadBadge(isLoggedIn = true, unreadCount = 1))
        assertEquals("42", formatAccountUnreadBadge(isLoggedIn = true, unreadCount = 42))
        assertEquals("99", formatAccountUnreadBadge(isLoggedIn = true, unreadCount = 99))
        assertEquals("99+", formatAccountUnreadBadge(isLoggedIn = true, unreadCount = 100))

        assertEquals("", formatAccountUnreadAccessibilityValue(isLoggedIn = false, unreadCount = 3))
        assertEquals("", formatAccountUnreadAccessibilityValue(isLoggedIn = true, unreadCount = 0))
        assertEquals("1 unread in Inbox", formatAccountUnreadAccessibilityValue(isLoggedIn = true, unreadCount = 1))
        assertEquals("12 unread in Inbox", formatAccountUnreadAccessibilityValue(isLoggedIn = true, unreadCount = 12))

        assertEquals("A", accountAvatarInitial("  avery_archive "))
        assertNull(accountAvatarInitial("   "))
        assertNull(accountAvatarInitial(null))
    }

    @Test
    fun restoredAccountRunPopsEverySheetRouteAndKeepsTheDeepest() {
        val inbox = listOf(Routes.Home, Routes.Account, Routes.AccountInbox)
        assertEquals(
            RestoredNavigation.AccountSheet(AccountSheetRoute.Inbox, popCount = 2, tabRoute = Routes.Home),
            Routes.restoredNavigation(inbox, Routes.AccountInbox)
        )
        val settings = listOf(Routes.Home, Routes.Account, Routes.Settings)
        assertEquals(
            RestoredNavigation.AccountSheet(AccountSheetRoute.Settings, popCount = 2, tabRoute = Routes.Home),
            Routes.restoredNavigation(settings, Routes.Settings)
        )
        assertNull(Routes.restoredNavigation(listOf(Routes.Home, Routes.Settings), Routes.Settings))
    }

    @Test
    fun writingInboxAndLoginStayOnTheWritingStack() {
        assertFalse(Routes.shouldInterceptAccountRoute(Routes.AccountInbox, isInitialRestore = true))
        assertFalse(Routes.shouldInterceptAccountRoute(Routes.AccountLogin, isInitialRestore = true))
        assertTrue(Routes.shouldInterceptAccountRoute(Routes.Account, isInitialRestore = true))
        assertFalse(Routes.shouldInterceptAccountRoute(Routes.Account, isInitialRestore = false))
        assertNull(Routes.restoredNavigation(listOf(Routes.Writing, Routes.AccountInbox), Routes.AccountInbox))
        assertNull(Routes.restoredNavigation(listOf(Routes.Writing, Routes.AccountLogin), Routes.AccountLogin))
    }

    @Test
    fun formerAccountRoutesRetargetWritingAndLibrary() {
        assertEquals(
            RestoredNavigation.TabPush(Routes.Writing, Routes.WritingDrafts),
            Routes.restoredNavigation(listOf(Routes.Account, Routes.WritingDrafts), Routes.WritingDrafts)
        )
        val series = Routes.authorSeries("writer")
        assertEquals(
            RestoredNavigation.TabPush(Routes.Writing, series),
            Routes.restoredNavigation(listOf(Routes.Account, series), series)
        )
        val marked = Routes.accountList("MarkedForLater")
        assertEquals(
            RestoredNavigation.TabPush(Routes.Library, marked),
            Routes.legacyLaunchNavigation(marked)
        )
        assertEquals(
            RestoredNavigation.AccountSheet(AccountSheetRoute.Inbox, popCount = 0, tabRoute = Routes.Home),
            Routes.legacyLaunchNavigation(Routes.AccountInbox)
        )
    }

    @Test
    fun accountSheetStateRoundTripsTheOpenPage() {
        val state = AccountSheetState(
            initialIsPresenting = true,
            initialPendingRoute = AccountSheetRoute.Inbox,
            initialRequestEpoch = 4
        )
        val saved = with(AccountSheetState.Saver) { SaverScope { true }.save(state) }!!
        val back = AccountSheetState.Saver.restore(saved)!!
        assertTrue(back.isPresentingAccount)
        assertEquals(AccountSheetRoute.Inbox, back.pendingAccountRoute)
        assertEquals(4, back.requestEpoch)
    }

    @Test
    fun accountSheetHostsAccountDestinationsAndLeavesForLibraryOrBrowse() {
        assertTrue(Routes.belongsOnAccountSheet(Routes.Account))
        assertTrue(Routes.belongsOnAccountSheet(Routes.AccountInbox))
        assertTrue(Routes.belongsOnAccountSheet(Routes.NativeLogin))
        assertFalse(Routes.belongsOnAccountSheet(Routes.WorkDetail))
        assertFalse(Routes.belongsOnAccountSheet(Routes.Library))
        assertFalse(Routes.belongsOnAccountSheet(Routes.webFallback("https://archiveofourown.org")))
        assertEquals(Routes.Library, Routes.shellRootForAccountList(AccountListType.MarkedForLater))
        assertEquals(Routes.Library, Routes.shellRootForAccountList(AccountListType.History))
        assertEquals(Routes.Writing, Routes.shellRootForAccountList(AccountListType.MyWorks))
        assertEquals(
            Routes.Writing,
            Routes.shellRootForAccountList(AccountListType.Collection("tag-set", "Tag Set"))
        )
        val jump = Routes.externalWebJump("https://archiveofourown.org/users/login")
        assertEquals(Routes.Browse, jump.first)
        assertEquals(Routes.webFallback("https://archiveofourown.org/users/login"), jump.second)
        assertEquals(Routes.Library, Routes.libraryFilterRoot())
    }
}
