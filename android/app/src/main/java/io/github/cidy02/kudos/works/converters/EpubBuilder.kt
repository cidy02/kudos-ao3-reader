package io.github.cidy02.kudos.works.converters

import java.io.ByteArrayOutputStream
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object EpubBuilder {
    /** A single spine document: a display name and its body HTML. */
    data class Chapter(val title: String, val bodyHtml: String)

    /**
     * Minimal stylesheet matching iOS `EPUBBuilder.stylesheet`.
     * Exists only so author's notes look like apparatus rather than prose —
     * `currentColor` / `em` keep it inside the reader's typography choices.
     * Class name is stable so a reader-injected rule can dim or hide notes later.
     */
    val AUTHOR_NOTE_STYLESHEET: String = """
.author-note {
  font-size: 0.9em;
  font-style: italic;
  border-inline-start: 3px solid currentColor;
  padding-inline-start: 0.75em;
  margin: 1em 0;
  opacity: 0.75;
}
.author-note p { margin: 0.4em 0; }
""".trimIndent()

    /**
     * Multi-chapter EPUB, used when an archive stitches several member files
     * into one work. Single-chapter callers keep using the simpler overload.
     */
    fun buildEpub(title: String, chapters: List<Chapter>): ByteArray {
        if (chapters.size <= 1) {
            return buildEpub(title, chapters.firstOrNull()?.bodyHtml.orEmpty())
        }
        val body = chapters.joinToString("\n") { chapter ->
            "<h1>${escape(chapter.title)}</h1>\n${chapter.bodyHtml}"
        }
        // ponytail: one spine document with per-chapter headings rather than N
        // spine items. Readium paginates it identically; split it properly if a
        // real per-chapter TOC becomes a requirement.
        return buildEpub(title, body)
    }

    private fun escape(value: String): String =
        value.replace("&", "&amp;").replace("<", "&lt;")

    /** What the OPF states about a work. Only [title] is required. */
    data class Book(
        val title: String,
        val author: String = "",
        /** `dc:language` code. */
        val language: String = "en",
        val description: String = "",
        /** `dc:source`: the work's canonical URL, which is how the file keeps its AO3 identity. */
        val source: String = "",
        /** `dc:date`, `yyyy-MM-dd`. */
        val date: String = "",
        val subjects: List<String> = emptyList(),
        val seriesTitle: String = "",
        val seriesIndex: String = "",
        val dir: String = ""
    )

    private fun xml(value: String): String = escape(value).replace(">", "&gt;").replace("\"", "&quot;")

    /**
     * One spine item per chapter (`section-<index>.xhtml`, from 0) with a nav and an
     * NCX, so the reader's contents list, chapter counts and Preface/Afterword
     * handling see the same shape calibre gives an AO3 EPUB. Bodies are written as
     * given: no heading is added, and they must already be sanitized XHTML.
     * [images] maps a path relative to the chapters (`images/x.jpg`) to its bytes.
     * The same input always produces the same bytes.
     */
    fun buildEpub(
        book: Book,
        chapters: List<Chapter>,
        images: Map<String, ByteArray> = emptyMap(),
        extraCss: String = ""
    ): ByteArray {
        val id = "urn:uuid:" + java.util.UUID.nameUUIDFromBytes(book.source.ifEmpty { book.title }.toByteArray())
        val language = xml(book.language.ifBlank { "en" })
        val dir = book.dir.trim().lowercase().takeIf { it in setOf("rtl", "ltr", "auto") }.orEmpty()
        val dirAttr = if (dir.isNotEmpty()) " dir=\"$dir\"" else ""
        val spineProgression = if (dir == "rtl") " page-progression-direction=\"rtl\"" else ""
        val metadata = buildList {
            add("<dc:identifier id=\"pub-id\">$id</dc:identifier>")
            add("<dc:title>${xml(book.title)}</dc:title>")
            add("<dc:language>$language</dc:language>")
            add("<meta property=\"dcterms:modified\">${book.date.ifBlank { "1970-01-01" }}T00:00:00Z</meta>")
            if (book.author.isNotBlank()) add("<dc:creator>${xml(book.author)}</dc:creator>")
            if (book.description.isNotBlank()) add("<dc:description>${xml(book.description)}</dc:description>")
            if (book.source.isNotBlank()) add("<dc:source>${xml(book.source)}</dc:source>")
            if (book.date.isNotBlank()) add("<dc:date>${xml(book.date)}</dc:date>")
            book.subjects.forEach { add("<dc:subject>${xml(it)}</dc:subject>") }
            if (book.seriesTitle.isNotBlank()) {
                add("<meta name=\"calibre:series\" content=\"${xml(book.seriesTitle)}\"/>")
                add("<meta name=\"calibre:series_index\" content=\"${xml(book.seriesIndex.ifBlank { "1" })}\"/>")
            }
        }.joinToString("\n")
        val imageItems = images.keys.mapIndexed { index, path ->
            "<item id=\"image-$index\" href=\"${xml(path)}\" media-type=\"${imageMediaType(path)}\"/>"
        }
        val opf = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
$metadata
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="style" href="style.css" media-type="text/css"/>
${(chapters.indices.map { "<item id=\"section-$it\" href=\"section-$it.xhtml\" media-type=\"application/xhtml+xml\"/>" } + imageItems).joinToString("\n")}
</manifest>
<spine toc="ncx"$spineProgression>
${chapters.indices.joinToString("\n") { "<itemref idref=\"section-$it\"/>" }}
</spine>
</package>"""
        val nav = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="$language"$dirAttr>
<head><title>${xml(book.title)}</title></head>
<body><nav epub:type="toc"><ol>
${chapters.withIndex().joinToString("\n") { (index, chapter) -> "<li><a href=\"section-$index.xhtml\">${xml(chapter.title)}</a></li>" }}
</ol></nav></body>
</html>"""
        val ncx = """<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="$id"/></head>
<docTitle><text>${xml(book.title)}</text></docTitle>
<navMap>
${chapters.withIndex().joinToString("\n") { (index, chapter) ->
            "<navPoint id=\"section-$index\" playOrder=\"${index + 1}\"><navLabel><text>${xml(chapter.title)}</text></navLabel>" +
                "<content src=\"section-$index.xhtml\"/></navPoint>"
        }}
</navMap>
</ncx>"""
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            fun put(name: String, bytes: ByteArray, stored: Boolean = false) {
                zip.putNextEntry(ZipEntry(name).apply {
                    // A fixed time, or the same work would never produce the same file twice.
                    time = 0
                    if (stored) {
                        method = ZipEntry.STORED
                        size = bytes.size.toLong()
                        crc = CRC32().apply { update(bytes) }.value
                    }
                })
                zip.write(bytes)
                zip.closeEntry()
            }
            // mimetype must come first and uncompressed.
            put("mimetype", "application/epub+zip".toByteArray(), stored = true)
            put(
                "META-INF/container.xml",
                ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                    "<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">" +
                    "<rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/>" +
                    "</rootfiles></container>").toByteArray()
            )
            put("OEBPS/content.opf", opf.toByteArray())
            put("OEBPS/nav.xhtml", nav.toByteArray())
            put("OEBPS/toc.ncx", ncx.toByteArray())
            put("OEBPS/style.css", (AUTHOR_NOTE_STYLESHEET + "\n" + extraCss).toByteArray())
            chapters.forEachIndexed { index, chapter ->
                put(
                    "OEBPS/section-$index.xhtml",
                    """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="$language"$dirAttr>
<head><title>${xml(chapter.title)}</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
<body>
${chapter.bodyHtml}
</body>
</html>""".toByteArray()
                )
            }
            // Already-compressed formats: storing them costs nothing and saves the work.
            images.forEach { (path, bytes) -> put("OEBPS/$path", bytes, stored = true) }
        }
        return output.toByteArray()
    }

    private fun imageMediaType(path: String): String = when (path.substringAfterLast('.').lowercase()) {
        "png" -> "image/png"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        else -> "image/jpeg"
    }

    fun buildEpub(title: String, contentHtml: String): ByteArray {
        val baos = ByteArrayOutputStream()
        val zos = ZipOutputStream(baos)
        val safeTitle = escape(title)

        // 1. mimetype (must be uncompressed)
        val mimetype = "application/epub+zip".toByteArray(Charsets.UTF_8)
        val mimeEntry = ZipEntry("mimetype").apply {
            method = ZipEntry.STORED
            size = mimetype.size.toLong()
            crc = CRC32().apply { update(mimetype) }.value
        }
        zos.putNextEntry(mimeEntry)
        zos.write(mimetype)
        zos.closeEntry()

        // 2. META-INF/container.xml
        val containerXml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                <rootfiles>
                    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
                </rootfiles>
            </container>
        """.trimIndent().toByteArray(Charsets.UTF_8)
        zos.putNextEntry(ZipEntry("META-INF/container.xml"))
        zos.write(containerXml)
        zos.closeEntry()

        // 3. OEBPS/content.opf
        val contentOpf = """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
                <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                    <dc:title>$safeTitle</dc:title>
                    <dc:language>en</dc:language>
                    <dc:identifier id="pub-id">urn:uuid:12345</dc:identifier>
                </metadata>
                <manifest>
                    <item id="content" href="content.html" media-type="application/xhtml+xml"/>
                    <item id="style" href="style.css" media-type="text/css"/>
                    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                </manifest>
                <spine toc="ncx">
                    <itemref idref="content"/>
                </spine>
            </package>
        """.trimIndent().toByteArray(Charsets.UTF_8)
        zos.putNextEntry(ZipEntry("OEBPS/content.opf"))
        zos.write(contentOpf)
        zos.closeEntry()

        // 4. OEBPS/toc.ncx
        val tocNcx = """
            <?xml version="1.0" encoding="UTF-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
                <head>
                    <meta name="dtb:uid" content="urn:uuid:12345"/>
                </head>
                <docTitle><text>$safeTitle</text></docTitle>
                <navMap>
                    <navPoint id="navPoint-1" playOrder="1">
                        <navLabel><text>Content</text></navLabel>
                        <content src="content.html"/>
                    </navPoint>
                </navMap>
            </ncx>
        """.trimIndent().toByteArray(Charsets.UTF_8)
        zos.putNextEntry(ZipEntry("OEBPS/toc.ncx"))
        zos.write(tocNcx)
        zos.closeEntry()

        // 5. OEBPS/style.css — author's note apparatus (iOS EPUBBuilder parity)
        zos.putNextEntry(ZipEntry("OEBPS/style.css"))
        zos.write(AUTHOR_NOTE_STYLESHEET.toByteArray(Charsets.UTF_8))
        zos.closeEntry()

        // 6. OEBPS/content.html
        val fullHtml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
            <head>
                <title>$safeTitle</title>
                <link rel="stylesheet" type="text/css" href="style.css"/>
            </head>
            <body>
                $contentHtml
            </body>
            </html>
        """.trimIndent().toByteArray(Charsets.UTF_8)
        zos.putNextEntry(ZipEntry("OEBPS/content.html"))
        zos.write(fullHtml)
        zos.closeEntry()

        zos.close()
        return baos.toByteArray()
    }
}
