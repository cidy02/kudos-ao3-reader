package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.CustomFont
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.data.local.entity.toEntity
import io.github.cidy02.kudos.files.FontFileStore
import io.github.cidy02.kudos.files.FileWriteResult
import io.github.cidy02.kudos.reader.speech.KokoroPronunciationStore
import java.io.File
import java.time.Instant
import java.util.Base64
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull

/** Same distinctive values as iOS CrossPlatformFixtureFields; no fixture may default these away. */
internal object CrossPlatformFixtureFields {
    const val COLLECTION_ID = "e0000000-0000-4000-8000-000000000001"
    const val QUEUE_ID = "e0000000-0000-4000-8000-000000000002"
    const val ANNOTATION_ID = "e0000000-0000-4000-8000-000000000003"
    const val TOMBSTONE_ID = "c0000000-0000-4000-8000-000000000002"
    const val FONT_NAME = "Kudos Fixture Regular"
    const val FONT_FILE = "kudos-cross-platform-fixture.ttf"
    val deletedAt: Instant = Instant.parse("2023-11-14T22:31:20Z")
    val fontDate: Instant = Instant.parse("2023-11-14T22:14:20Z")
    private const val PUBLIC_KEY = "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8"
    private const val SIGNATURE = "ed5fe7713c031096df77adb16525722bf6c7dd8485bebd596eb9977570d55a5bef8883cb1545e9765d935143b81adf95b2e41f47eabc999a9230621ccc067904"
    val pronunciations = KokoroPronunciationStore.Document(
        global = mapOf("Nico" to "nˈikoʊ"),
        fandoms = mapOf("Portable Fandom" to mapOf("Sam" to "sæm")),
        works = mapOf("820002" to mapOf("Sam" to "sɑm"))
    )

    // Original two-glyph TrueType font (.notdef and A), accepted by CoreText/CGFont.
    val fontBytes: ByteArray get() = Base64.getDecoder().decode(
        "AAEAAAAKAIAAAwAgT1MvMkoJUIsAAACsAAAATmNtYXAADAB0AAAA/AAAACxnbHlmCXMJcgAAASgAAABEaGVhZGEKQ6EAAAFsAAAA" +
        "NmhoZWEFFgH3AAABpAAAACRobXR4BLAAAAAAAcgAAAAIbG9jYQAiABEAAAHQAAAABm1heHAABAAGAAAB2AAAACBuYW1lFAAqxAAA" +
        "AfgAAAEKcG9zdAADAAAAAAMEAAAAIAAAAlgBkAAFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
        "AAAAAABLVURPAEAAQQBBAyD/OAAAAyAAyAAAAAAAAQADAAEAAAAMAAQAIAAAAAQABAABAAAAQf//AAAAQf///8AAAQAAAAAAAQAA" +
        "AAAB9AK8AAMAAAEBAQEAAAH0AAD+DAAAAAACvAAAAAEAAAAAAfQCvAADAAABAQEBAAAB9AAA/gwAAAAAArwAAAABAAAAAQAAAJUE" +
        "p18PPPUAAwPoAAAAAAAAAAAAAAAAAAAAAAAAAAAB9AK8AAAACAACAAAAAAAAAAEAAAMg/zgAAAJYAAAAZAH0AAEAAAAAAAAAAAAA" +
        "AAAAAAACAlgAAAJYAAAAAAARACIAAAABAAAAAgAEAAEAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAABgBOAAMAAQQJAAEAGgAAAAMA" +
        "AQQJAAIADgAaAAMAAQQJAAMALAAoAAMAAQQJAAQAKgBUAAMAAQQJAAUAFgB+AAMAAQQJAAYAKACUAEsAdQBkAG8AcwAgAEYAaQB4" +
        "AHQAdQByAGUAUgBlAGcAdQBsAGEAcgBLAHUAZABvAHMARgBpAHgAdAB1AHIAZQAtAFIAZQBnAHUAbABhAHIALQAxAEsAdQBkAG8A" +
        "cwAgAEYAaQB4AHQAdQByAGUAIABSAGUAZwB1AGwAYQByAFYAZQByAHMAaQBvAG4AIAAxAC4AMABLAHUAZABvAHMARgBpAHgAdAB1" +
        "AHIAZQAtAFIAZQBnAHUAbABhAHIAAAADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    )

    /** Native Android writes, also used by the Android-only sync generator. */
    suspend fun seed(database: KudosDatabase, fonts: FontFileStore, root: File, work: SavedWork) {
        database.customFontDao().upsert(CustomFont(
            name = FONT_NAME, fileName = FONT_FILE, dateAdded = fontDate
        ).toEntity())
        check(fonts.writeFont(FONT_FILE, fontBytes) is FileWriteResult.Success)
        KokoroPronunciationStore(root).save(pronunciations)
        database.collectionDao().upsert(WorkCollection(
            id = COLLECTION_ID, name = "Deleted Portable Collection", dateAdded = fontDate,
            createdAt = fontDate, lastModifiedAt = deletedAt, syncStatusRaw = "localOnly", isDeleted = true,
            deletedAt = deletedAt
        ).toEntity())
        database.readingQueueDao().upsertQueue(ReadingQueue(
            id = QUEUE_ID, name = "Deleted Portable Queue", dateCreated = fontDate,
            dateUpdated = deletedAt, lastMembershipChangedAt = fontDate,
            isDeleted = true, deletedAt = deletedAt
        ).toEntity())
        database.annotationDao().upsert(ReadingAnnotation(
            id = ANNOTATION_ID, workID = work.id, kindRaw = "highlight", colorRaw = "yellow",
            locatorString = """{"href":"deleted.xhtml","locations":{"totalProgression":0.33}}""",
            selectedText = "Deleted passage", note = "Deleted reader note", createdAt = fontDate,
            lastModifiedAt = deletedAt, deletedAt = deletedAt, isPendingDeletion = true
        ).toEntity())
        val tombstone = SyncTombstone(
            id = TOMBSTONE_ID, recordID = "b0000000-0000-4000-8000-000000000002",
            recordTypeRaw = "savedSearch", createdAt = deletedAt, lastModifiedAt = deletedAt,
            sourceURL = "https://archiveofourown.org/works/829998", ao3WorkID = 829998,
            deletedOnDeviceID = "cross-platform-fixture", deletionReason = "fixture coverage",
            signerPublicKey = PUBLIC_KEY, signature = SIGNATURE
        )
        check(TombstoneSigning.verify(tombstone))
        database.syncTombstoneDao().upsert(tombstone.toEntity())
    }

    /** Raw JSON matters: decoding an unknown field first could silently erase it on both sides. */
    fun assertManifest(bytes: ByteArray) {
        val root = BackupJson.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
        fun record(key: String, id: String): JsonObject {
            val row = root[key]?.jsonArray?.map { it.jsonObject }?.singleOrNull {
                it["id"]?.jsonPrimitive?.content?.equals(id, ignoreCase = true) == true
            }
            assertNotNull("Brief 3ge: missing $key/$id; regenerate iOS goldens first, then Android goldens", row)
            return checkNotNull(row)
        }
        fun field(row: JsonObject, key: String, value: String) {
            assertEquals("Brief 3ge: missing/changed $key (stale fixture or dropped field); regenerate iOS then Android",
                JsonPrimitive(value), row[key])
        }
        assertEquals("Brief 3ge: stale fixture or dropped pronunciations; regenerate iOS then Android goldens",
            BackupJson.parseToJsonElement(BackupJson.encodeToString(pronunciations.corrections())),
            root["pronunciations"])
        val font = root["fonts"]?.jsonArray?.map { it.jsonObject }?.singleOrNull {
            it["fileName"] == JsonPrimitive(FONT_FILE)
        }
        assertNotNull("Brief 3ge: font fixture predates coverage; regenerate iOS then Android", font)
        field(checkNotNull(font), "name", FONT_NAME)
        field(font, "fileName", FONT_FILE)
        field(font, "dateAdded", BackupValidator.formatInstant(fontDate))
        field(record("collections", COLLECTION_ID), "deletedAt", BackupValidator.formatInstant(deletedAt))
        field(record("readingQueues", QUEUE_ID), "deletedAt", BackupValidator.formatInstant(deletedAt))
        field(record("readingQueues", QUEUE_ID), "lastMembershipChangedAt", BackupValidator.formatInstant(fontDate))
        field(record("annotations", ANNOTATION_ID), "deletedAt", BackupValidator.formatInstant(deletedAt))
        assertEquals("Brief 3ge: tombstone AO3 identity must survive", JsonPrimitive(829998),
            record("tombstones", TOMBSTONE_ID)["ao3WorkID"])
    }

    suspend fun assertRestored(database: KudosDatabase, fonts: FontFileStore, root: File) {
        val font = checkNotNull(database.customFontDao().getByFileName(FONT_FILE)) { "Brief 3ge: restored font missing" }
        assertEquals(FONT_NAME, font.name)
        assertEquals(FONT_FILE, font.fileName)
        assertEquals(fontDate, font.dateAdded)
        assertArrayEquals(fontBytes, fonts.readFont(FONT_FILE))
        assertEquals(pronunciations, KokoroPronunciationStore(root).load())
        val collection = checkNotNull(database.collectionDao().getById(COLLECTION_ID)) {
            "Brief 3ge: incoming soft-deleted collection was dropped by restore"
        }
        assertEquals(deletedAt, collection.deletedAt)
        val queue = database.readingQueueDao().getAllQueues().single { it.id == QUEUE_ID }
        assertEquals(deletedAt, queue.deletedAt)
        assertEquals(fontDate, queue.lastMembershipChangedAt)
        assertEquals(deletedAt, database.annotationDao().getById(ANNOTATION_ID)?.deletedAt)
        assertEquals(829998, database.syncTombstoneDao().getAll().single { it.id == TOMBSTONE_ID }.ao3WorkID)
    }

    fun assertPack(pack: KudosBackupPackage) {
        assertManifest(BackupJson.encodeToString(pack.manifest).toByteArray())
        assertArrayEquals("Brief 3ge: Fonts/$FONT_FILE must survive byte for byte",
            fontBytes, pack.fontFilesByFileName[FONT_FILE])
    }
}
