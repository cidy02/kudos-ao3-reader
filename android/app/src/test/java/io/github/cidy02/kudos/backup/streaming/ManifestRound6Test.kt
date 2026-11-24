package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.A567Corpus
import io.github.cidy02.kudos.backup.BackupWork
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.decodeFromStream
import io.github.cidy02.kudos.backup.BackupJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ManifestRound6Test {
    @get:Rule val tmp = TemporaryFolder()

    @OptIn(ExperimentalSerializationApi::class)
    @Test fun stagedChunksDecodeAcrossUnicodeAndChunkBoundaries() {
        val summary = "a".repeat((1 shl 20) + 17) + "😀tail"
        val id = A567Corpus.uuid(1)
        val json = """{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[{"id":"$id","summary":"$summary","title":"first","\u0074itle":"second"}]}"""
        ManifestStager.stage(ByteArrayInputStream(json.toByteArray()), File(tmp.root, "stage")).use { staged ->
            val meta = staged.records("works").single()
            assertTrue(meta.oversize)
            val bytes = ByteArrayOutputStream()
            StagedChunkInputStream(staged.db, "s_works_chunk", meta.ord).use { stream ->
                val buffer = ByteArray(7)
                while (true) {
                    val count = stream.read(buffer, 0, buffer.size)
                    if (count < 0) break
                    bytes.write(buffer, 0, count)
                }
            }
            val decoded = BackupJson.decodeFromStream(BackupWork.serializer(), bytes.toByteArray().inputStream())
            assertEquals(summary, decoded.summary)
            assertEquals("first", decoded.title)
            assertEquals(staged.recordTextInMemory("works", 0), bytes.toString(Charsets.UTF_8.name()))
            staged.validate(Instant.parse("2026-06-15T00:00:00Z"))
        }
    }
}
