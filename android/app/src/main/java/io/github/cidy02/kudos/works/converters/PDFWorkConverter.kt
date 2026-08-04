package io.github.cidy02.kudos.works.converters

class PDFWorkConverter {
    fun convert(title: String, bytes: ByteArray): ByteArray {
        // Very basic PDF text extraction stub. Since we lack a dedicated PDF library,
        // we attempt to extract raw string literals found within the PDF stream.
        val rawData = String(bytes, Charsets.ISO_8859_1)
        val extracted = java.lang.StringBuilder()
        
        // Match text inside parentheses (...) which is how basic PDFs encode strings in text objects
        val regex = Regex("\\((.*?)\\)")
        val matches = regex.findAll(rawData)
        for (match in matches) {
            val text = match.groupValues[1]
                .replace("\\(", "(")
                .replace("\\)", ")")
                .replace("\\\\", "\\")
            if (text.isNotBlank()) {
                extracted.append("<p>").append(text.replace("&", "&amp;").replace("<", "&lt;")).append("</p>\n")
            }
        }
        
        val body = if (extracted.isEmpty()) {
            "<p>No easily extractable text found in this PDF.</p>"
        } else {
            extracted.toString()
        }
        
        return EpubBuilder.buildEpub(title, body)
    }
}
