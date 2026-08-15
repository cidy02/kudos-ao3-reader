package io.github.cidy02.kudos.data.local

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
    fun roomOpensFreshDatabaseAtVersion9WithMigrationRegistered() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val db = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .addMigrations(
                KudosDatabaseMigrations.MIGRATION_7_8,
                KudosDatabaseMigrations.MIGRATION_8_9
            )
            .build()
        try {
            assertEquals(9, db.openHelper.readableDatabase.version)
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
