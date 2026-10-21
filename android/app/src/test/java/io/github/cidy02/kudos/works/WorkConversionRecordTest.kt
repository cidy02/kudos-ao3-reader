package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.files.WorkFileStore
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class WorkConversionRecordTest {
    @Test fun staleVersionsIncludeMissingAndForeignStamps() {
        assertTrue(WorkConversionRecord.isStale(null))
        val local = WorkConversionRecord(format = "plainText", originalFileName = "story.txt", converterPlatform = "android")
        assertFalse(local.isStale)
        assertTrue(local.copy(converterVersion = 0).isStale)
        assertFalse(local.copy(converterVersion = WorkConversionRecord.CURRENT_VERSION + 1).isStale)
        val ios = WorkConversionRecord.decode("""{"converterVersion":999,"format":"pdf","originalFileName":"story.pdf","convertedAt":0}""".encodeToByteArray())!!
        assertTrue("iOS's scale cannot certify an Android conversion", ios.isStale)
        assertTrue(WorkConversionRecord.isStale(WorkConversionRecord.decode("invalid".encodeToByteArray())))
    }

    @Test fun sidecarRoundTripsBesideTheOriginalWithSwiftsDateShape() = runBlocking {
        val root = Files.createTempDirectory("conversion-stamp")
        try {
            val id = "5b00abcd-0000-4000-8000-00000000000a"
            val files = WorkFileStore(root)
            files.writeOriginal(id, "txt", "Original words".encodeToByteArray())
            val record = WorkConversionRecord(format = "plainText", originalFileName = "story.txt",
                convertedAt = WorkConversionRecord.appleDate(Instant.parse("2001-01-01T00:00:00.125Z")),
                converterPlatform = "android")
            assertTrue(files.writeConversionRecord(id, record.encode()))
            assertEquals(record, WorkConversionRecord.decode(files.readConversionRecord(id)))
            assertEquals(0.125, record.convertedAt, 0.0)
            assertTrue(Files.exists(root.resolve("originals/$id.conversion.json")))
            assertEquals("txt", files.readOriginal(id)!!.first)
        } finally {
            root.toFile().deleteRecursively()
        }
    }
}
