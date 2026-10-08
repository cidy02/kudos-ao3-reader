package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.account.WritingWorkDestination
import io.github.cidy02.kudos.app.Routes
import org.junit.Assert.*
import org.junit.Test

class WritingWorkFormRoutesTest {
    @Test fun threeSingleArgumentDemoRoutesUsePushedChromeWithoutQuerySeparators() {
        for ((route, title) in listOf(Routes.WritingWorkNewDemo to "New work", Routes.WritingWorkDraftDemo to "Draft",
            Routes.WritingWorkPostedDemo to "Edit work")) {
            assertFalse(route.contains('&'))
            assertFalse(route.contains('?'))
            assertTrue(Routes.hasSubjectHeader(route))
            assertTrue(Routes.hidesTabBar(route))
            assertFalse(Routes.isShellRoot(route))
            assertEquals(title, Routes.titleFor(route))
        }
    }

    @Test fun draftsAndNewWorkStillHaveTheirExactBrowserDestinations() {
        assertEquals("https://archiveofourown.org/works/new", WritingWorkDestination.url())
        assertEquals("https://archiveofourown.org/works/995001/edit", WritingWorkDestination.url(995001L))
        assertEquals("Drafts", Routes.titleFor(Routes.WritingDrafts))
        assertTrue(Routes.hasSubjectHeader(Routes.WritingDrafts))
        assertTrue(Routes.hidesTabBar(Routes.WritingDrafts))
    }
}
