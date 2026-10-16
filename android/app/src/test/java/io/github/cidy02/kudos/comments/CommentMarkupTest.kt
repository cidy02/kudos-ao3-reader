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
        assertEquals("Above\n<hr>\n", result.text)
        assertEquals(TextRange(6 + "<hr>\n".length), result.selection)
    }

    // iOS `CommentMarkupTests` (A59): the tray writes as the chapter editor does.
    private fun apply(tag: CommentMarkupTag, text: String, start: Int, end: Int) =
        CommentMarkup.applyTag(tag, TextFieldValue(text, TextRange(start, end)))
    private fun typing(typed: String, into: TextFieldValue) =
        into.text.replaceRange(into.selection.start, into.selection.end, typed)
    private fun selected(value: TextFieldValue) = value.text.substring(value.selection.start, value.selection.end)

    @Test fun theDividerStandsAloneOnItsOwnLineKeepsTheWordsAndDoesNotDoubleABreak() {
        val done = apply(CommentMarkupTag.Divider, "done", 4, 4)
        assertEquals("done\n<hr>\n", done.text)
        assertEquals("done\n<hr>\nand then", typing("and then", done))
        assertEquals("keep me\n<hr>\n", apply(CommentMarkupTag.Divider, "keep me", 0, 7).text)
        assertEquals("done\n<hr>\nmore", apply(CommentMarkupTag.Divider, "done\n\nmore", 5, 5).text)
    }

    @Test fun listsMakeOneItemPerNonEmptyLineOrOneEmptyItem() {
        val bullets = apply(CommentMarkupTag.Bullets, "one\n\ntwo", 0, 8)
        assertEquals("<ul>\n<li>one</li>\n<li>two</li>\n</ul>", bullets.text)
        assertEquals("<li>one</li>\n<li>two</li>", selected(bullets))
        val empty = apply(CommentMarkupTag.Numbers, "", 0, 0)
        assertEquals("<ol>\n<li></li>\n</ol>", empty.text)
        assertEquals("<ol>\n<li>first</li>\n</ol>", typing("first", empty))
        assertEquals("<ul>\n<li></li>\n</ul>", apply(CommentMarkupTag.Bullets, "  \n  ", 0, 5).text)
    }

    @Test fun theLinkAndSpoilerPutTheCaretWhereTheTagIsUnfinished() {
        val link = apply(CommentMarkupTag.Link, "the coat", 0, 8)
        assertEquals("<a href=\"\">the coat</a>", link.text)
        assertEquals("<a href=\"https://example.com\">the coat</a>", typing("https://example.com", link))
        val spoiler = apply(CommentMarkupTag.Spoiler, "he dies", 0, 7)
        assertEquals("<details><summary></summary>he dies</details>", spoiler.text)
        assertEquals("<details><summary>Chapter 4</summary>he dies</details>", typing("Chapter 4", spoiler))
    }

    /** iOS `AO3MarkupTests.bothSurfacesSelectTheSameSpanForTheSameInput`; Link aside, as the tray has no URL. */
    @Test fun bothSurfacesSelectTheSameSpanForTheSameInput() {
        for (tag in CommentMarkupTag.entries.filter { it != CommentMarkupTag.Link }) {
            for (text in listOf("", "keep", "one\ntwo", "the coat", "done\n\nmore")) {
                for ((lower, upper) in listOf(0 to 0, 0 to text.length, text.length to text.length)) {
                    val writing = io.github.cidy02.kudos.writing.WritingMarkup.insertion(tag.element, text, lower, upper)!!
                    val comment = apply(tag, text, lower, upper)
                    val label = "<${tag.element}> in \"$text\" over $lower..$upper"
                    assertEquals(label, text.substring(0, lower) + writing.text + text.substring(upper), comment.text)
                    assertEquals(label, TextRange(lower + writing.contentOffset, lower + writing.contentOffset + writing.contentLength),
                        comment.selection)
                }
            }
        }
    }

    @Test fun onlyTheTagsAO3KeepsAreOfferedAndHeadingPrintsItsRange() {
        assertEquals(15, CommentMarkupTag.entries.size)
        assertEquals(listOf("strong", "em", "u", "s", "sup", "sub", "small", "code"),
            CommentMarkupTag.entries.filter { it.group == CommentMarkupTag.TagGroup.Text }.map { it.tagLabel })
        assertEquals(listOf("blockquote", "ul", "ol", "h1–h6", "hr", "a href", "details"),
            CommentMarkupTag.entries.filter { it.group == CommentMarkupTag.TagGroup.Blocks }.map { it.tagLabel })
        assertEquals("<h3>Part two</h3>", apply(CommentMarkupTag.Heading, "Part two", 0, 8).text)
    }

    /**
     * The composer's text comes back through a flow, late and with values skipped. What the field
     * sent is never a change from outside; anything else is, and ends the wait for older echoes.
     */
    @Test
    fun aLateEchoOfTypedTextIsNotTakenForADraftSetElsewhere() {
        val echoes = DraftEchoes()
        listOf("f", "fo", "for").forEach(echoes::sending)
        assertEquals(true, echoes.isEcho("f"))       // late, while the field already says "for"
        assertEquals(true, echoes.isEcho("for"))     // "fo" was skipped by the flow
        assertEquals(false, echoes.isEcho("fo"))     // settled with "for": now it would be news
        echoes.sending("for t")
        assertEquals(false, echoes.isEcho("a stored draft"))
        assertEquals(false, echoes.isEcho("for t"))  // the outside change ended the wait
    }
}
