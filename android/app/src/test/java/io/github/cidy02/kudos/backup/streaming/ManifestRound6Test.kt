package io.github.cidy02.kudos.backup.streaming

import io.github.cidy02.kudos.backup.A567Corpus
import io.github.cidy02.kudos.backup.BackupWork
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.Instant
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
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
        val id = A567Corpus.uuid(1)
        val recordPrefix = "{\"id\":\"$id\",\"summary\":\""
        val fill = "a".repeat(StagingWriter.CHUNK_CHARS - 1 - recordPrefix.length)
        for ((label, marker) in listOf(
            "surrogate" to "😀", "cjk" to "漢", "newline" to "\n", "quote" to "\"",
            "slash" to "\\", "nul" to "\u0000", "control" to "\u001f"
        )) {
            val summary = fill + marker + "tail"
            val json = """{"version":8,"exportedAt":"2026-06-01T00:00:00Z","works":[{"id":"$id","summary":${Json.encodeToString(summary)},"title":"first","\u0074itle":"second"}]}"""
            ManifestStager.stage(ByteArrayInputStream(json.toByteArray()), File(tmp.root, "stage-$label")).use { staged ->
                val meta = staged.records("works").single()
                val firstLength = staged.db.rawQuery(
                    "SELECT len FROM s_works_chunk WHERE ord = 0 ORDER BY start LIMIT 1", null
                ).use { c -> c.moveToFirst(); c.getLong(0) }
                assertEquals(label, (StagingWriter.CHUNK_CHARS - if (label == "surrogate") 1 else 0).toLong(), firstLength)
                val bytes = ByteArrayOutputStream()
                StagedChunkInputStream(staged.db, "s_works_chunk", meta.ord).use { stream ->
                    val buffer = ByteArray(7)
                    while (true) {
                        val count = stream.read(buffer, 0, buffer.size)
                        if (count < 0) break
                        bytes.write(buffer, 0, count)
                    }
                }
                val stagedText = staged.recordTextInMemory("works", 0)
                assertEquals(label, stagedText, bytes.toString(Charsets.UTF_8.name()))
                val fromString = BackupJson.decodeFromString(BackupWork.serializer(), stagedText)
                val fromChunks = StagedChunkInputStream(staged.db, "s_works_chunk", meta.ord).use {
                    BackupJson.decodeFromStream(BackupWork.serializer(), it)
                }
                assertEquals(label, fromString, fromChunks)
                assertEquals(label, summary, fromChunks.summary)
                assertEquals("first", fromChunks.title)
                assertEquals(label, fromChunks, staged.reconstruct().first.works.single())
                staged.validate(Instant.parse("2026-06-15T00:00:00Z"))
            }
        }
    }
}
