package io.github.cidy02.kudos.works.converters

class PlainTextWorkConverter {
    fun convert(title: String, bytes: ByteArray): ByteArray {
        val text = String(bytes, Charsets.UTF_8)
        val escaped = text.replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\n", "<br/>")
        return EpubBuilder.buildEpub(title, "<p>$escaped</p>")
    }
}
