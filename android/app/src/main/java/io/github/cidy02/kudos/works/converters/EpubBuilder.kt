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
            <html xmlns="http://www.w3.org/1999/xhtml">
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
