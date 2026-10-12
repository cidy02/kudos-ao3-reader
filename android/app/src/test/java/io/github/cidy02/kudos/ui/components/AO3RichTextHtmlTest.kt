package io.github.cidy02.kudos.ui.components

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3RichTextHtmlTest {
    @Test
    fun aStrangersWritingKeepsItsFormattingAndOnlyWebLinks() {
        val clean = AO3RichTextHtml.clean(
            """<p>I write <strong>space opera</strong> and <em>quiet mysteries</em>.</p>
               <p><a href="https://example.com/reading-order">my site</a> <a href="/users/Avery_Archive">me</a></p>
               <ul><li><a href="javascript:alert('nope')">Unsafe links stay plain text.</a></li>
               <li><a href="intent://scan#Intent;scheme=zxing;end">scan</a> <a href="mailto:a@example.com">write</a></li></ul>
               <script>alert(1)</script><img src="https://example.com/track.png">"""
        )
        assertTrue(clean, "<strong>space opera</strong>" in clean && "<em>quiet mysteries</em>" in clean)
        assertTrue(clean, "<li>" in clean && "Unsafe links stay plain text." in clean)
        assertTrue(clean, "href=\"https://example.com/reading-order\"" in clean)
        // A link within AO3 is whole, so it can be told from one that leaves it.
        assertTrue(clean, "href=\"https://archiveofourown.org/users/Avery_Archive\"" in clean)
        listOf("javascript", "intent:", "mailto", "script", "alert(1)", "<img", "track.png").forEach {
            assertFalse("$it in $clean", it in clean)
        }
    }
}
