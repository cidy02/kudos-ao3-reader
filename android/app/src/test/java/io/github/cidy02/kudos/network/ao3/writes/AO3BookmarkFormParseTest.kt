package io.github.cidy02.kudos.network.ao3.writes

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * iOS `readsExistingBookmarkFromWorkPageEditForm` on the same page (A55): AO3 writes a hidden
 * `bookmark[private]=0` before the checkbox. Read from the hidden one, a private bookmark came
 * back public, and an edit saved it public.
 */
class AO3BookmarkFormParseTest {
    private val html = checkNotNull(
        javaClass.classLoader?.getResource("ao3/writes/ios_work_bookmarked_subscribed.html")
    ).readText()

    @Test fun anExistingPrivateBookmarkStaysPrivate() {
        val state = AO3WriteFormParser().parseBookmarkState(html)

        assertTrue(state.exists)
        assertEquals("/bookmarks/2997787566", state.editPath)
        assertEquals("Test bookmark", state.input.notes)
        assertTrue(state.input.tags.isEmpty())
        assertTrue(state.input.isPrivate)
        assertFalse(state.input.isRecommendation)
    }
}

/** iOS `parsesHiddenSinglePseudInput` and `hiddenPseudInputWinsOverSelect` (A55). */
class AO3PostingPseudParseTest {
    @Test fun aSinglePseudAccountsHiddenInputIsRead() {
        val html = """
            <form action="/works/1/comments" method="post" id="comment_for_1">
              <h4 class="heading">Comment as <span class="byline">solowriter</span>
                <input type="hidden" name="comment[pseud_id]" value="123456" id="comment_pseud_id_for_1">
              </h4>
              <textarea name="comment[comment_content]"></textarea>
            </form>
        """.trimIndent()
        assertEquals("123456", AO3WriteFormParser().parseDefaultPseudId(html))
    }

    @Test fun aHiddenPseudWinsOverASelect() {
        val html = """
            <input type="hidden" name="comment[pseud_id]" value="11">
            <select name="comment[pseud_id]"><option value="99" selected="selected">other</option></select>
        """.trimIndent()
        assertEquals("11", AO3WriteFormParser().parseDefaultPseudId(html))
    }
}
