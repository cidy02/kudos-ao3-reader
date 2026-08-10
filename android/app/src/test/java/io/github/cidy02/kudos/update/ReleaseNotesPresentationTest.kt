package io.github.cidy02.kudos.update

import io.github.cidy02.kudos.network.github.GitHubRelease
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReleaseNotesPresentationTest {
    private val version = AppVersion(0, 2, 0)

    private fun release(
        name: String? = null,
        body: String? = null,
        publishedAt: String? = null
    ) = GitHubRelease(
        tagName = "android-v0.2.0-alpha",
        name = name,
        publishedAt = publishedAt,
        body = body
    )

    @Test
    fun `title prefers non-blank release name`() {
        assertEquals(
            "Kudos Android 0.2.0",
            ReleaseNotesPresentation.title(release(name = "Kudos Android 0.2.0"), version)
        )
    }

    @Test
    fun `title falls back to version when name is null or blank`() {
        assertEquals(
            "Version 0.2.0",
            ReleaseNotesPresentation.title(release(name = null), version)
        )
        assertEquals(
            "Version 0.2.0",
            ReleaseNotesPresentation.title(release(name = "   "), version)
        )
    }

    @Test
    fun `formatPublishedDate formats GitHub ISO timestamps`() {
        assertEquals(
            "Jul 6, 2026",
            ReleaseNotesPresentation.formatPublishedDate("2026-07-06T15:30:00Z")
        )
    }

    @Test
    fun `formatPublishedDate returns null for missing and blank`() {
        assertNull(ReleaseNotesPresentation.formatPublishedDate(null))
        assertNull(ReleaseNotesPresentation.formatPublishedDate("  "))
    }

    @Test
    fun `formatPublishedDate keeps unparseable stamps instead of dropping them`() {
        assertEquals(
            "not-a-date",
            ReleaseNotesPresentation.formatPublishedDate("not-a-date")
        )
    }

    @Test
    fun `notesForDisplay returns trimmed body and preserves line breaks and list markers`() {
        val body = """
            ## What's new

            - Fixed crash on open
            - Improved library sort

            Thanks for testing Alpha.
        """.trimIndent()
        val displayed = ReleaseNotesPresentation.notesForDisplay("\n$body\n")
        assertEquals(body, displayed)
        assertTrue(displayed.contains("- Fixed crash on open"))
        assertTrue(displayed.contains("\n"))
    }

    @Test
    fun `notesForDisplay uses fallback when body is null or blank`() {
        assertEquals(
            ReleaseNotesPresentation.EMPTY_NOTES_FALLBACK,
            ReleaseNotesPresentation.notesForDisplay(null)
        )
        assertEquals(
            ReleaseNotesPresentation.EMPTY_NOTES_FALLBACK,
            ReleaseNotesPresentation.notesForDisplay("   \n  ")
        )
    }
}
