package io.github.cidy02.kudos.ui.components

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.LinkInteractionListener
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.fromHtml
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import org.jsoup.Jsoup
import org.jsoup.safety.Safelist

/**
 * Words someone wrote on AO3, with their formatting: bold, italics, lists and links, as iOS
 * `AO3RichTextView` draws a profile's bio. An AO3 address opens in the app and any other in the
 * browser, as there.
 */
@Composable
fun AO3RichText(html: String, onOpenAo3: (String) -> Unit, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    val accent = LocalSubjectPalette.current.controlInk
    val uriHandler = LocalUriHandler.current
    val openAo3 by rememberUpdatedState(onOpenAo3)
    val text = remember(html, accent) {
        val open = LinkInteractionListener { link ->
            val url = (link as? LinkAnnotation.Url)?.url ?: return@LinkInteractionListener
            if (AO3BrowseUrls.isAo3Url(url)) openAo3(url) else runCatching { uriHandler.openUri(url) }
        }
        AnnotatedString.fromHtml(AO3RichTextHtml.clean(html), TextLinkStyles(SpanStyle(color = accent)), open)
            .let { it.subSequence(0, it.text.trimEnd().length) }
    }
    Text(text, modifier, color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 22.sp)
}

internal object AO3RichTextHtml {
    // ponytail: text formatting only. Images and headings are dropped; widen the list when a
    // page that needs them is drawn with this.
    private val safelist: Safelist = Safelist.basic().removeProtocols("a", "href", "ftp", "mailto")

    /**
     * The page is a stranger's writing. Only plain formatting is kept, and a link stays a link
     * only when it is http or https: `javascript:`, `intent:` and the rest become plain words.
     */
    fun clean(html: String): String = Jsoup.clean(html, AO3Constants.BASE_URL, safelist)
}
