package io.github.cidy02.kudos.writing

import org.junit.Assert.*
import org.junit.Test

class WritingTextEditorTests {
    private fun apply(tag: String, text: String, selected: String?, link: String = ""): Pair<String, String>? {
        val start = selected?.let { text.indexOf(it) } ?: text.length
        val end = start + (selected?.length ?: 0)
        val insertion = WritingMarkup.insertion(tag, text, start, end, link) ?: return null
        val result = text.substring(0, start) + insertion.text + text.substring(end)
        return result to result.substring(start + insertion.contentOffset,
            start + insertion.contentOffset + insertion.contentLength)
    }

    @Test fun tagInsertionPreservesSelectedMarkupAndEscapesLinkAttributes() {
        val selected = "<unknown data-x='1'>👩🏽‍💻 &amp; 世界</unknown>"
        assertEquals("<strong>$selected</strong>", WritingMarkup.insertion("strong", selected)!!.text)
        assertEquals(8, WritingMarkup.insertion("strong", selected)!!.contentOffset)
        assertNull(WritingMarkup.insertion("script", selected))
        assertNull(WritingMarkup.insertion("a", selected, "javascript:alert(1)"))
        assertEquals("<a href=\"https://example.com/?a=1&amp;b=2\">site</a>",
            WritingMarkup.insertion("a", "site", "https://example.com/?a=1&b=2")!!.text)
        assertEquals("<br>keep", WritingMarkup.insertion("br", "keep")!!.text)
        assertEquals("<a href=\"https://example.com/?q=&quot;&lt;&gt;\">site</a>",
            WritingMarkup.insertion("a", "site", "https://example.com/?q=\"<>")!!.text)
    }

    @Test fun aTagNestsInsideAnEnclosingOne() {
        assertEquals("<em><strong>word</strong></em>" to "word", apply("strong", "<em>word</em>", "word"))
    }

    @Test fun selectionsAtTheBufferEdgesAndACaret() {
        assertEquals("<em>first</em> rest" to "first", apply("em", "first rest", "first"))
        assertEquals("rest <em>last</em>" to "last", apply("em", "rest last", "last"))
        assertEquals("text <u></u>" to "", apply("u", "text ", null))
        assertNull(apply("script", "text", "text"))
    }

    @Test fun everyTagAtStartEndAndInsideExistingMarkupWithAndWithoutSelection() {
        assertEquals(listOf("strong", "em", "u", "s", "sup", "sub", "small", "code", "p", "br", "blockquote", "ul", "ol", "h3", "hr", "a", "details"),
            WritingMarkup.tags.map { it.element })
        val contexts = listOf("" to " tail", "head " to "", "<custom attr='keep'>" to "</custom>")
        for (tag in WritingMarkup.tags) for ((before, after) in contexts) for (selected in listOf("", "👩🏽‍💻 世界")) {
            val source = before + selected + after
            val inserted = WritingMarkup.insertion(tag.element, source, before.length, before.length + selected.length,
                "https://example.com")!!
            val (replacement, body, offset) = expected(tag.element, selected, before, after)
            assertEquals("${tag.element}: $source", replacement, inserted.text)
            assertEquals(body.length, inserted.contentLength)
            assertEquals(offset, inserted.contentOffset)
            val result = before + inserted.text + after
            assertTrue(result.startsWith(before)); assertTrue(result.endsWith(after))
            assertEquals(body, result.substring(before.length + offset, before.length + offset + body.length))
        }
    }

    private fun expected(tag: String, selected: String, before: String, after: String): Triple<String, String, Int> = when (tag) {
        "br" -> Triple("<br>$selected", selected, 4)
        "hr" -> {
            val rule = selected + (if ((before + selected).endsWith('\n') || (before + selected).isEmpty()) "" else "\n") +
                "<hr>" + (if (after.startsWith('\n')) "" else "\n")
            Triple(rule, "", rule.length)
        }
        "ul", "ol" -> if (selected.isEmpty()) Triple("<$tag>\n<li></li>\n</$tag>", "", 9)
            else Triple("<$tag>\n<li>$selected</li>\n</$tag>", "<li>$selected</li>", 5)
        "a" -> Triple("<a href=\"https://example.com\">$selected</a>", selected, 30)
        "details" -> Triple("<details><summary></summary>$selected</details>", "", 18)
        else -> Triple("<$tag>$selected</$tag>", selected, tag.length + 2)
    }

    @Test fun dividerReadsSurroundingLinesAndNeverDeletesTheSelection() {
        assertEquals("<hr>\n", WritingMarkup.insertion("hr", "abc", 0, 0)!!.text)
        assertEquals("<hr>", WritingMarkup.insertion("hr", "a\n\nb", 2, 2)!!.text)
        assertEquals("words\n<hr>\n", WritingMarkup.insertion("hr", "words")!!.text)
        assertEquals("\n<hr>\n", WritingMarkup.insertion("hr", "a", 1, 1)!!.text)
    }

    @Test fun listsTrimLinesAndSkipBlanksButKeepMarkup() {
        assertEquals("<ul>\n<li>one</li>\n<li><em>two</em></li>\n</ul>",
            WritingMarkup.insertion("ul", " one \n\n\t<em>two</em>\t")!!.text)
        val empty = WritingMarkup.insertion("ol", " \n\t")!!
        assertEquals("<ol>\n<li></li>\n</ol>", empty.text)
        assertEquals(9, empty.contentOffset); assertEquals(0, empty.contentLength)
    }

    @Test fun invalidTagsLinksAndRangesWriteNothing() {
        for (url in listOf("", "/relative", "javascript:alert(1)", "data:text/html,x"))
            assertNull(WritingMarkup.insertion("a", "text", url))
        for (url in listOf("http://example.com", "HTTPS://example.com", "mailto:a@example.com"))
            assertNotNull(WritingMarkup.insertion("a", "text", url))
        assertNull(WritingMarkup.insertion("em", "x", -1, 0))
        assertNull(WritingMarkup.insertion("em", "x", 1, 0))
        assertNull(WritingMarkup.insertion("em", "😀", 1, 1))
    }

    @Test fun thePreviewParsesTheBufferAsAO3HTML() {
        val state = WritingBufferPreview.state("<p>One <strong>two</strong></p><p><em>three</em> <a href=\"https://example.com\">four</a></p><script>hidden words</script>")
            as WritingBufferPreview.State.Rendered
        assertEquals(2, state.blocks.size)
        val runs = state.blocks.flatMap { it.runs }
        assertTrue(runs.any { it.text.contains("two") && it.isBold })
        assertTrue(runs.any { it.text.contains("three") && it.isItalic })
        assertTrue(runs.any { it.link == "https://example.com" })
        assertFalse(runs.any { it.text.contains('<') || it.text.contains("hidden") })
        assertTrue((WritingBufferPreview.state("") as WritingBufferPreview.State.Rendered).blocks.isEmpty())
    }

    @Test fun thePreviewShowsTextTypedOutsideABlockTag() {
        fun texts(html: String) = (WritingBufferPreview.state(html) as WritingBufferPreview.State.Rendered)
            .blocks.map { block -> block.runs.joinToString("") { it.text } }
        // The demo's own text: one paragraph tag, then a loose line with a tag inside it.
        assertEquals(listOf("The gate.", "A small <boat> waited."),
            texts("<p>The gate.</p>\n\nA small <strong>&lt;boat&gt;</strong> waited.\n"))
        // Order is the buffer's; loose text inside something that holds blocks is kept too.
        assertEquals(listOf("before", "one", "between", "item", "after"),
            texts("before<p>one</p>between<ul>\n<li>item</li>\n</ul><details>after</details>"))
        // Nothing but loose text is still one block, with its blank line kept.
        assertEquals(listOf("first\n\nsecond"), texts("first\n\nsecond"))
        assertTrue(texts("<p>only</p>\n\n<!-- note --><script>hidden</script>") == listOf("only"))
    }

    @Test fun onlyTheCurrentPreviewParsePublishes() {
        assertTrue(WritingBufferPreview.publishes(3, 3, true))
        assertFalse(WritingBufferPreview.publishes(2, 3, true))
        assertFalse(WritingBufferPreview.publishes(3, 3, false))
    }

    @Test fun previewFollowsTheReferencesLimitedRendererWithoutRewritingSource() {
        val source = "<h3>Heading</h3><ol><li><u>One</u><br>Two</li></ol><p><a href='javascript:bad'>bad</a><a href='/works/17'>local</a></p><img src='https://example.com/image'>"
        val state = WritingBufferPreview.state(source) as WritingBufferPreview.State.Rendered
        assertEquals(3, state.blocks.size)
        assertTrue(state.blocks[1].listItem)
        assertEquals("One\nTwo", state.blocks[1].runs.single().text)
        assertNull(state.blocks[2].runs[0].link)
        assertEquals("https://archiveofourown.org/works/17", state.blocks[2].runs[1].link)
    }
}
