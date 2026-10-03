package io.github.cidy02.kudos.comments

import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import org.junit.Assert.assertEquals
import org.junit.Test

class CommentMarkupTest {

    @Test
    fun `apply bold tag wraps selection`() {
        val initial = TextFieldValue(
            text = "Hello world",
            selection = TextRange(6, 11) // "world"
        )
        val result = CommentMarkup.applyTag(CommentMarkupTag.Bold, initial)
        assertEquals("Hello <strong>world</strong>", result.text)
        // Selection should cover the enclosed text
        assertEquals(TextRange(6 + 8, 6 + 8 + 5), result.selection)
    }

    @Test
    fun `apply italic tag with empty selection places cursor between tags`() {
        val initial = TextFieldValue(
            text = "Hello ",
            selection = TextRange(6, 6)
        )
        val result = CommentMarkup.applyTag(CommentMarkupTag.Italic, initial)
        assertEquals("Hello <em></em>", result.text)
        assertEquals(TextRange(10, 10), result.selection)
    }

    @Test
    fun `apply link tag with empty selection places cursor inside href`() {
        val initial = TextFieldValue(
            text = "",
            selection = TextRange.Zero
        )
        val result = CommentMarkup.applyTag(CommentMarkupTag.Link, initial)
        assertEquals("<a href=\"\"></a>", result.text)
        // cursor inside href="" -> index 9
        assertEquals(TextRange(9, 9), result.selection)
    }

    @Test
    fun `apply divider inserts hr tag without close tag`() {
        val initial = TextFieldValue(
            text = "Above\n",
            selection = TextRange(6, 6)
        )
        val result = CommentMarkup.applyTag(CommentMarkupTag.Divider, initial)
        assertEquals("Above\n<hr />\n", result.text)
        assertEquals(TextRange(6 + "<hr />\n".length), result.selection)
    }
}
