package io.github.cidy02.kudos.works

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthorTapNamesTest {
    @Test
    fun prefersRemoteAuthorList() {
        assertEquals(
            listOf("Alice", "Bob"),
            resolveTappableAuthorNames(listOf("Alice", "Bob"), "Local Only")
        )
    }

    @Test
    fun splitsLocalCommaSeparatedAuthors() {
        assertEquals(
            listOf("Alice", "Bob"),
            resolveTappableAuthorNames(emptyList(), "Alice, Bob")
        )
    }

    @Test
    fun dropsAnonymousAndBlank() {
        assertTrue(resolveTappableAuthorNames(listOf("Anonymous", "  "), null).isEmpty())
        assertTrue(resolveTappableAuthorNames(null, "Anonymous").isEmpty())
        assertTrue(resolveTappableAuthorNames(null, "  ").isEmpty())
        assertEquals(
            listOf("Alice"),
            resolveTappableAuthorNames(listOf("Anonymous", "Alice"), null)
        )
    }
}
