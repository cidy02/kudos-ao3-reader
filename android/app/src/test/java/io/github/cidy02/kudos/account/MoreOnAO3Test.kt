package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.web.AO3WebUrlPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The More on AO3 screen: every row must be an address the in-app browser will open. */
class MoreOnAO3Test {
    private val rows = MoreOnAO3.sections.flatMap { it.rows }

    @Test fun everyRowIsAnAddressTheBrowserKeeps() {
        for (row in rows) {
            val url = MoreOnAO3.url(row.target, "AO3_Reader")
            assertTrue("${row.title}: $url", url != null && AO3WebUrlPolicy.isAllowedInApp(url))
        }
    }

    @Test fun addressesAreIosS() {
        fun url(title: String) = MoreOnAO3.url(rows.single { it.title == title }.target, "AO3_Reader")
        assertEquals("https://archiveofourown.org/works/new?import=true", url("Import work"))
        assertEquals("https://archiveofourown.org/users/AO3_Reader/works/show_multiple", url("Edit works in bulk"))
        assertEquals("https://archiveofourown.org/users/AO3_Reader/collection_items", url("Manage collection items"))
        assertEquals("https://archiveofourown.org/abuse_reports/new", url("Report abuse"))
    }

    @Test fun aPageOfTheReadersOwnHasNoAddressWhenSignedOut() {
        val own = rows.filter { it.target is MoreOnAO3.Target.User }
        val site = rows.filter { it.target is MoreOnAO3.Target.Site }
        assertEquals(14, own.size)
        assertEquals(9, site.size)
        own.forEach { assertNull(it.title, MoreOnAO3.url(it.target, null)) }
        own.forEach { assertNull(it.title, MoreOnAO3.url(it.target, "  ")) }
        site.forEach { assertTrue(it.title, MoreOnAO3.url(it.target, null) != null) }
    }

    @Test fun sectionsAndRowsAreInIosSOrder() {
        assertEquals(listOf("Post and manage", "Challenges", "Your account", "The archive"), MoreOnAO3.sections.map { it.title })
        assertEquals(
            listOf("Post new work", "Import work", "Edit works in bulk", "Manage collection items", "Related works", "Drafts"),
            MoreOnAO3.sections[0].rows.map { it.title }
        )
        assertEquals(listOf("Sign-ups", "Assignments", "Claims", "Gifts given and received"), MoreOnAO3.sections[1].rows.map { it.title })
    }
}
