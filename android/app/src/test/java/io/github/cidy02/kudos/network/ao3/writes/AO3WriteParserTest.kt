package io.github.cidy02.kudos.network.ao3.writes

import io.github.cidy02.kudos.network.ao3.AO3FormEncoding
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AO3AuthenticityTokenParserTest {
    private val parser = AO3WriteFormParser()

    @Test
    fun parsesTokenFromHiddenInputBeforeMetaFallback() {
        val html = writeResource("ao3/writes/work_with_forms.html")

        assertEquals("token-from-input", parser.parseAuthenticityToken(html))
        assertEquals("token-from-input", parser.parseAuthenticityToken(html, "form#new_comment"))
    }

    @Test
    fun parsesTokenFromMetaTag() {
        val html = """<meta name="csrf-token" content="aB3/dEf+gh==">"""

        assertEquals("aB3/dEf+gh==", parser.parseAuthenticityToken(html))
    }

    @Test
    fun missingTokenReturnsNull() {
        assertNull(parser.parseAuthenticityToken("<html><body>No form</body></html>"))
    }
}

class AO3WriteFormParserTest {
    private val parser = AO3WriteFormParser()

    @Test
    fun parsesSelectedDefaultPseudAndBookmarkPseud() {
        val html = writeResource("ao3/writes/work_with_forms.html")

        assertEquals("22", parser.parseDefaultPseudId(html))
        assertEquals("44", parser.parseDefaultPseudId(html, field = "bookmark[pseud_id]"))
    }

    @Test
    fun detectsSubscribedAndUnsubscribedStates() {
        val subscribed = parser.parseSubscription(writeResource("ao3/writes/work_subscribed.html"))
        val unsubscribed = parser.parseSubscription(writeResource("ao3/writes/work_with_forms.html"))

        assertTrue(subscribed.isSubscribed)
        assertEquals("/users/AO3_Reader/subscriptions/789", subscribed.unsubscribePath)
        assertFalse(unsubscribed.isSubscribed)
        assertNull(unsubscribed.unsubscribePath)
    }

    @Test
    fun extractsValidationErrorsAndAlreadyKudosedText() {
        assertEquals(
            "Comment content can't be blank",
            parser.writeErrorMessage(writeResource("ao3/comments/comment_validation_error.html"))
        )
        assertTrue(parser.alreadyKudosed("<p>You have already left kudos here.</p>"))
    }

    @Test
    fun formEncodingMatchesApplePercentEncoding() {
        assertEquals(
            "authenticity_token=a%20b%2Fc&kudo%5Bcommentable_id%5D=123",
            AO3FormEncoding.encode(
                listOf(
                    "authenticity_token" to "a b/c",
                    "kudo[commentable_id]" to "123"
                )
            )
        )
    }
}

internal fun writeResource(path: String): String {
    val resource = Thread.currentThread().contextClassLoader?.getResource(path)
        ?: error("Missing test resource: $path")
    return resource.readText()
}
