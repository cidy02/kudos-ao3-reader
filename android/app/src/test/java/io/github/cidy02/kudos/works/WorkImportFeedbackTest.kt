package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.files.ImportedFileFormat
import org.junit.Assert.*
import org.junit.Test

class WorkImportFeedbackTest {
    @Test fun unsupportedPickedFormatIsNamedAndExtensionlessFilesStillGetGuidance() {
        assertEquals("This XYZ file isn't a format Kudos can read. Try an EPUB, HTML, or text file.",
            WorkImporter.unsupportedMessage(ImportedFileFormat.UNKNOWN, "story.xyz"))
        assertEquals("This file isn't a format Kudos can read. Try an EPUB, HTML, or text file.",
            WorkImporter.unsupportedMessage(ImportedFileFormat.UNKNOWN, "attachment"))
    }

    @Test fun namedUnsupportedFormatsUseIosConversionInstructions() {
        for ((format, name) in listOf(ImportedFileFormat.DOCX to "Word document",
            ImportedFileFormat.ODT to "OpenDocument text", ImportedFileFormat.RTF to "RTF")) {
            assertEquals("$name import is coming in a later update. For now, convert it " +
                "to EPUB (calibre, or Word's \"Save as\") and import that.", WorkImporter.unsupportedMessage(format))
        }
        assertEquals("Kindle files aren't supported yet. Convert it to EPUB with calibre and import that.",
            WorkImporter.unsupportedMessage(ImportedFileFormat.MOBI))
        assertEquals("RAR archives aren't supported yet. Unpack it first, then import the files inside.",
            WorkImporter.unsupportedMessage(ImportedFileFormat.RAR))
        assertEquals("7-Zip archives aren't supported yet. Unpack it first, then import the files inside.",
            WorkImporter.unsupportedMessage(ImportedFileFormat.SEVEN_ZIP))
    }

    @Test fun archiveAndPdfFailuresKeepTheirFormatSpecificGuidance() {
        assertTrue(WorkImporter.unsupportedMessage(ImportedFileFormat.PDF, "story.pdf").contains("PDF"))
        assertTrue(WorkImporter.unsupportedMessage(ImportedFileFormat.ZIP, "chapters.zip")
            .contains("Couldn't find anything readable in that archive."))
    }
}
