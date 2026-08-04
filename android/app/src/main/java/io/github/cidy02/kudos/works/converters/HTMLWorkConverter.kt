package io.github.cidy02.kudos.works.converters

import org.jsoup.Jsoup
import org.jsoup.safety.Safelist

class HTMLWorkConverter {
    fun convert(title: String, bytes: ByteArray): ByteArray {
        val rawHtml = String(bytes, Charsets.UTF_8)
        // Parse and clean to prevent XSS
        val document = Jsoup.parse(rawHtml)
        val cleanedBody = Jsoup.clean(document.body().html(), Safelist.relaxed())
        return EpubBuilder.buildEpub(title, cleanedBody)
    }
}
