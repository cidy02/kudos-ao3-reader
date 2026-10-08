package io.github.cidy02.kudos.data.local

import java.io.File
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.Json
import android.content.Context
import androidx.room.Room
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Migration 7→8: EPUB preservation pass-through columns.
 *
 * Builds a real pre-migration (v7) works table, runs [KudosDatabaseMigrations.MIGRATION_7_8],
 * and checks the new columns are nullable with no backfill. Uses the same migration
 * object production registers in [io.github.cidy02.kudos.app.KudosAppContainer].
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class KudosDatabaseMigrationTest {

    @Test
    fun migrate7To8_addsNullablePreservationColumnsWithoutBackfill() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name("kudos-migration-7-8")
                .callback(object : SupportSQLiteOpenHelper.Callback(7) {
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        // Minimal v7 works table: every NOT NULL column Room had at v7,
                        // without the three preservation fields added in v8.
                        db.execSQL(
                            """
                            CREATE TABLE IF NOT EXISTS `works` (
                                `id` TEXT NOT NULL,
                                `title` TEXT NOT NULL,
                                `author` TEXT NOT NULL,
                                `summary` TEXT NOT NULL,
                                `sourceUrl` TEXT NOT NULL,
                                `dateAdded` INTEGER NOT NULL,
                                `isFavorite` INTEGER NOT NULL,
                                `isSaved` INTEGER NOT NULL,
                                `isFinished` INTEGER NOT NULL,
                                `hasEpub` INTEGER NOT NULL,
                                `isComplete` INTEGER NOT NULL,
                                `rating` TEXT NOT NULL,
                                `language` TEXT NOT NULL,
                                `wordCount` INTEGER NOT NULL,
                                `chapters` TEXT NOT NULL,
                                `kudos` INTEGER NOT NULL,
                                `seriesTitle` TEXT NOT NULL,
                                `seriesPosition` INTEGER NOT NULL,
                                `seriesUrl` TEXT NOT NULL,
                                `lastSpineIndex` INTEGER NOT NULL,
                                `lastScrollFraction` REAL NOT NULL,
                                `lastReadDate` INTEGER,
                                `workWarnings` TEXT NOT NULL,
                                `workCategories` TEXT NOT NULL,
                                `workTags` TEXT NOT NULL,
                                `workFandoms` TEXT NOT NULL,
                                `workCharacters` TEXT NOT NULL,
                                `workRelationships` TEXT NOT NULL,
                                `workFreeforms` TEXT NOT NULL,
                                `workTagsFetched` INTEGER NOT NULL,
                                `readiumLocator` TEXT,
                                `comments` INTEGER,
                                `hits` INTEGER,
                                `knownChapterCount` INTEGER,
                                `lastUpdateCheck` INTEGER,
                                `lastModifiedAt` INTEGER,
                                `progressModifiedAt` INTEGER,
                                `ao3Unavailable` INTEGER NOT NULL,
                                `lastAvailabilityCheck` INTEGER,
                                `isDeleted` INTEGER NOT NULL,
                                `deletedAt` INTEGER,
                                `permanentDeletionScheduledAt` INTEGER,
                                `isQueuedForLater` INTEGER NOT NULL,
                                `searchText` TEXT NOT NULL,
                                `searchIndexVersion` INTEGER NOT NULL,
                                `lastTagRefreshAttemptAt` INTEGER,
                                PRIMARY KEY(`id`)
                            )
                            """.trimIndent()
                        )
                    }

                    override fun onUpgrade(
                        db: SupportSQLiteDatabase,
                        oldVersion: Int,
                        newVersion: Int
                    ) = Unit
                })
                .build()
        )

        val db = helper.writableDatabase
        try {
            assertEquals(7, db.version)
            db.execSQL(
                """
                INSERT INTO works (
                    id, title, author, summary, sourceUrl, dateAdded,
                    isFavorite, isSaved, isFinished, hasEpub, isComplete,
                    rating, language, wordCount, chapters, kudos,
                    seriesTitle, seriesPosition, seriesUrl,
                    lastSpineIndex, lastScrollFraction,
                    workWarnings, workCategories, workTags, workFandoms,
                    workCharacters, workRelationships, workFreeforms,
                    workTagsFetched, ao3Unavailable, isDeleted, isQueuedForLater,
                    searchText, searchIndexVersion
                ) VALUES (
                    'work-pre-migration', 'Title', 'Author', '', '', 0,
                    0, 1, 0, 1, 0,
                    '', '', 0, '', 0,
                    '', 0, '',
                    0, 0.0,
                    '[]', '[]', '[]', '[]',
                    '[]', '[]', '[]',
                    0, 0, 0, 0,
                    '', 0
                )
                """.trimIndent()
            )

            val before = columnNames(db, "works")
            assertFalse(before.contains("epubPreservationStatusRaw"))
            assertFalse(before.contains("preservedAt"))
            assertFalse(before.contains("lastPreservationAttemptAt"))

            KudosDatabaseMigrations.MIGRATION_7_8.migrate(db)
            db.version = 8

            val after = columnNames(db, "works")
            assertTrue(after.contains("epubPreservationStatusRaw"))
            assertTrue(after.contains("preservedAt"))
            assertTrue(after.contains("lastPreservationAttemptAt"))

            db.query(
                "SELECT epubPreservationStatusRaw, preservedAt, lastPreservationAttemptAt " +
                    "FROM works WHERE id = ?",
                arrayOf("work-pre-migration")
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertNull(cursor.getString(0))
                assertTrue(cursor.isNull(1))
                assertTrue(cursor.isNull(2))
            }
            assertEquals(8, db.version)
        } finally {
            db.close()
            helper.close()
        }
    }

    @Test
    fun migrate8To9_addsEmptyTombstoneSignatureColumns() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name("kudos-migration-8-9")
                .callback(object : SupportSQLiteOpenHelper.Callback(8) {
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        db.execSQL(
                            """
                            CREATE TABLE IF NOT EXISTS `sync_tombstones` (
                                `id` TEXT NOT NULL,
                                `recordID` TEXT NOT NULL,
                                `recordTypeRaw` TEXT NOT NULL,
                                `createdAt` INTEGER NOT NULL,
                                `lastModifiedAt` INTEGER NOT NULL,
                                `sourceURL` TEXT NOT NULL,
                                `ao3WorkID` INTEGER,
                                `deletedOnDeviceID` TEXT NOT NULL,
                                `deletionReason` TEXT NOT NULL,
                                PRIMARY KEY(`id`)
                            )
                            """.trimIndent()
                        )
                    }

                    override fun onUpgrade(
                        db: SupportSQLiteDatabase,
                        oldVersion: Int,
                        newVersion: Int
                    ) = Unit
                })
                .build()
        )

        val db = helper.writableDatabase
        try {
            assertEquals(8, db.version)
            db.execSQL(
                """
                INSERT INTO sync_tombstones (
                    id, recordID, recordTypeRaw, createdAt, lastModifiedAt,
                    sourceURL, ao3WorkID, deletedOnDeviceID, deletionReason
                ) VALUES (
                    'ts-pre', 'work-pre', 'savedWork', 0, 0,
                    'https://archiveofourown.org/works/1', 1, '', 'workDeleted'
                )
                """.trimIndent()
            )
            val before = columnNames(db, "sync_tombstones")
            assertFalse(before.contains("signerPublicKey"))
            assertFalse(before.contains("signature"))

            KudosDatabaseMigrations.MIGRATION_8_9.migrate(db)
            db.version = 9

            val after = columnNames(db, "sync_tombstones")
            assertTrue(after.contains("signerPublicKey"))
            assertTrue(after.contains("signature"))
            db.query(
                "SELECT signerPublicKey, signature FROM sync_tombstones WHERE id = ?",
                arrayOf("ts-pre")
            ).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("", cursor.getString(0))
                assertEquals("", cursor.getString(1))
            }
            assertEquals(9, db.version)
        } finally {
            db.close()
            helper.close()
        }
    }

    @Test
    fun migrate9To10_addsHasGivenKudosDefaultingToFalse() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name("kudos-migration-9-10")
                .callback(object : SupportSQLiteOpenHelper.Callback(9) {
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        createLegacyWorkFixture(db, 9)
                    }

                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
                })
                .build()
        )
        val db = helper.writableDatabase
        try {
            val columnsBefore = columnNames(db, "works")
            assertFalse(columnNames(db, "works").contains("hasGivenKudos"))

            KudosDatabaseMigrations.MIGRATION_9_10.migrate(db)
            db.version = 10

            db.query("SELECT hasGivenKudos FROM works WHERE id = ?", arrayOf("work-pre")).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(0, cursor.getInt(0))
            }
            assertEquals(columnsBefore + "hasGivenKudos", columnNames(db, "works"))
            assertLegacyWorkSurvived(db)
            assertEquals(10, db.version)
        } finally {
            db.close()
            helper.close()
        }
    }

    /**
     * The strongest check short of a device: build the database exactly as an
     * exported schema describes it, then let Room migrate it to the current
     * version and validate every table against the entities. A column with the
     * wrong type, nullability or default fails here, not on a user's phone.
     * Released 0.2.1 and 0.2.2 are schema 7.
     */
    @Test
    fun releasedSchema7MigratesToCurrentAndPassesRoomValidation() = migrateFromExportedSchema(7)

    @Test
    fun schema10MigratesToCurrentAndPassesRoomValidation() = migrateFromExportedSchema(10)

    @Test
    fun schema12MigratesToCurrentAndPassesRoomValidation() = migrateFromExportedSchema(12)

    @Test
    fun migrate12To13AddsNullableDownloadedAtWithoutBackfill() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name("kudos-migration-12-13")
                .callback(object : SupportSQLiteOpenHelper.Callback(12) {
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        createLegacyWorkFixture(db, 12)
                    }

                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
                })
                .build()
        )
        val db = helper.writableDatabase
        try {
            val columnsBefore = columnNames(db, "works")
            KudosDatabaseMigrations.MIGRATION_12_13.migrate(db)
            db.version = 13

            assertTrue(columnNames(db, "works").contains("downloadedAt"))
            db.query("SELECT downloadedAt FROM works WHERE id = 'work-pre'").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertTrue(cursor.isNull(0))
            }
            assertEquals(columnsBefore + "downloadedAt", columnNames(db, "works"))
            assertLegacyWorkSurvived(db)
            assertEquals(13, db.version)
        } finally {
            db.close()
            helper.close()
        }
    }

    @Test
    fun schema13MigratesTo14AndPassesRoomValidation() = migrateFromExportedSchema(13)

    @Test
    fun migrate13To14DefaultsRemoteEpubPendingToFalseAndKeepsExistingRows() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name("kudos-migration-13-14")
                .callback(object : SupportSQLiteOpenHelper.Callback(13) {
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        db.execSQL("CREATE TABLE works (id TEXT NOT NULL, title TEXT NOT NULL, PRIMARY KEY(id))")
                    }

                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
                })
                .build()
        )
        val db = helper.writableDatabase
        try {
            db.execSQL("INSERT INTO works (id, title) VALUES ('work-pre', 'Kept title')")
            assertFalse(columnNames(db, "works").contains("remoteEpubPending"))
            KudosDatabaseMigrations.MIGRATION_13_14.migrate(db)
            db.version = 14
            db.query("SELECT title, remoteEpubPending FROM works WHERE id = 'work-pre'").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals("Kept title", cursor.getString(0))
                assertEquals(0, cursor.getInt(1))
            }
            db.execSQL("UPDATE works SET remoteEpubPending = 1 WHERE id = 'work-pre'")
            db.query("SELECT remoteEpubPending FROM works WHERE id = 'work-pre'").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(1, cursor.getInt(0))
            }
            assertEquals(14, db.version)
        } finally {
            db.close()
            helper.close()
        }
    }

    /** Use the committed real table, with a title/progress sentinel, not an id-only substitute. */
    private fun createLegacyWorkFixture(db: SupportSQLiteDatabase, version: Int) {
        val schema = Json.parseToJsonElement(
            File("schemas/io.github.cidy02.kudos.data.local.KudosDatabase/$version.json").readText()
        ).jsonObject.getValue("database").jsonObject
        val work = schema.getValue("entities").jsonArray.single {
            it.jsonObject.getValue("tableName").jsonPrimitive.content == "works"
        }.jsonObject
        db.execSQL(work.getValue("createSql").jsonPrimitive.content.replace("\${TABLE_NAME}", "works"))
        val fields = work.getValue("fields").jsonArray.map { it.jsonObject }
        val names = fields.map { it.getValue("columnName").jsonPrimitive.content }
        val values = fields.map { field ->
            when (field.getValue("columnName").jsonPrimitive.content) {
                "id" -> "work-pre"
                "title" -> "Kept title"
                "lastSpineIndex" -> 7
                "lastScrollFraction" -> 0.4
                "readiumLocator" -> "kept-locator"
                else -> when {
                    field["notNull"]?.jsonPrimitive?.content != "true" -> null
                    field.getValue("affinity").jsonPrimitive.content == "TEXT" -> ""
                    else -> 0
                }
            }
        }
        val columns = names.joinToString(",") { "`$it`" }
        val placeholders = names.joinToString(",") { "?" }
        db.execSQL("INSERT INTO works ($columns) VALUES ($placeholders)", values.toTypedArray<Any?>())
    }

    private fun assertLegacyWorkSurvived(db: SupportSQLiteDatabase) {
        db.query("SELECT title,lastSpineIndex,lastScrollFraction,readiumLocator FROM works WHERE id = 'work-pre'").use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertEquals("Kept title", cursor.getString(0))
            assertEquals(7, cursor.getInt(1))
            assertEquals(0.4, cursor.getDouble(2), 0.0)
            assertEquals("kept-locator", cursor.getString(3))
        }
    }

    private fun migrateFromExportedSchema(version: Int) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "kudos-validate-from-$version"
        context.deleteDatabase(name)
        val schema = Json.parseToJsonElement(
            File("schemas/io.github.cidy02.kudos.data.local.KudosDatabase/$version.json").readText()
        ).jsonObject.getValue("database").jsonObject
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name(name)
                .callback(object : SupportSQLiteOpenHelper.Callback(version) {
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        for (entity in schema.getValue("entities").jsonArray) {
                            val table = entity.jsonObject.getValue("tableName").jsonPrimitive.content
                            fun sql(element: JsonElement) =
                                element.jsonPrimitive.content.replace("\${TABLE_NAME}", table)
                            db.execSQL(sql(entity.jsonObject.getValue("createSql")))
                            entity.jsonObject["indices"]?.jsonArray?.forEach {
                                db.execSQL(sql(it.jsonObject.getValue("createSql")))
                            }
                        }
                        schema["setupQueries"]?.jsonArray?.forEach { db.execSQL(it.jsonPrimitive.content) }
                    }

                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
                })
                .build()
        )
        helper.writableDatabase.close()
        helper.close()

        val room = Room.databaseBuilder(context, KudosDatabase::class.java, name)
            .allowMainThreadQueries()
            .addMigrations(
                KudosDatabaseMigrations.MIGRATION_7_8,
                KudosDatabaseMigrations.MIGRATION_8_9,
                KudosDatabaseMigrations.MIGRATION_9_10,
                KudosDatabaseMigrations.MIGRATION_10_11,
                KudosDatabaseMigrations.MIGRATION_11_12,
                KudosDatabaseMigrations.MIGRATION_12_13,
                KudosDatabaseMigrations.MIGRATION_13_14
            )
            .build()
        try {
            assertEquals(14, room.openHelper.writableDatabase.version)
        } finally {
            room.close()
            context.deleteDatabase(name)
        }
    }

    @Test
    fun roomOpensFreshDatabaseAtCurrentVersionWithMigrationsRegistered() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val db = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .addMigrations(
                KudosDatabaseMigrations.MIGRATION_7_8,
                KudosDatabaseMigrations.MIGRATION_8_9,
                KudosDatabaseMigrations.MIGRATION_9_10,
                KudosDatabaseMigrations.MIGRATION_10_11,
                KudosDatabaseMigrations.MIGRATION_11_12,
                KudosDatabaseMigrations.MIGRATION_12_13,
                KudosDatabaseMigrations.MIGRATION_13_14
            )
            .build()
        try {
            assertEquals(14, db.openHelper.readableDatabase.version)
        } finally {
            db.close()
        }
    }

    private fun columnNames(db: SupportSQLiteDatabase, table: String): Set<String> {
        val names = linkedSetOf<String>()
        db.query("PRAGMA table_info(`$table`)").use { cursor ->
            val nameIdx = cursor.getColumnIndex("name")
            while (cursor.moveToNext()) {
                names += cursor.getString(nameIdx)
            }
        }
        return names
    }
}
