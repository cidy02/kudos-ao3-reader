package io.github.cidy02.kudos.works.converters

import java.io.ByteArrayOutputStream
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object EpubBuilder {
    fun buildEpub(title: String, contentHtml: String): ByteArray {
        val baos = ByteArrayOutputStream()
        val zos = ZipOutputStream(baos)
        
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
                    <dc:title>${title.replace("&", "&amp;").replace("<", "&lt;")}</dc:title>
                    <dc:language>en</dc:language>
                    <dc:identifier id="pub-id">urn:uuid:12345</dc:identifier>
                </metadata>
                <manifest>
                    <item id="content" href="content.html" media-type="application/xhtml+xml"/>
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
                <docTitle><text>${title.replace("&", "&amp;").replace("<", "&lt;")}</text></docTitle>
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
        
        // 5. OEBPS/content.html
        val fullHtml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml">
            <head>
                <title>${title.replace("&", "&amp;").replace("<", "&lt;")}</title>
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
