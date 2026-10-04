package io.github.cidy02.kudos.core

import org.junit.Assert.assertEquals
import org.junit.Test

/** The cases iOS's `strippingHTML()` handles (`Utilities/HTMLText.swift`). */
class HtmlTextTest {
    @Test
    fun plainTextIsReturnedAsIs() {
        assertEquals("Nothing to strip.", "Nothing to strip.".strippingHtml())
    }

    @Test
    fun paragraphsBecomeLinesAndOtherTagsGo() {
        assertEquals(
            "Wednesday came to her dorm.\nEnid was <not> there.",
            "<p>Wednesday came to <em>her</em> dorm.</p><p>Enid was &lt;not&gt; there.</p>".strippingHtml()
        )
    }

    @Test
    fun lineBreaksEntitiesAndBlankRuns() {
        assertEquals(
            "Tea & toast\nit's late\n\nThe end",
            "Tea &amp; toast<br/>it&#39;s late  <BR><br />\n\n\nThe end</div>".strippingHtml()
        )
    }
}
