package io.github.cidy02.kudos.data.local

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/**
 * Room migrations for [KudosDatabase].
 *
 * v1 → v2 (Epic 2): LWW timestamps + soft-delete on works; sync tombstones;
 * reading queues + memberships; in-book annotations.
 *
 * v2 → v3: LWW timestamp + soft-delete on collections, matching works — collection
 * deletion had no Recently Deleted / undo at all, and backup restore couldn't tell
 * whether a local rename was newer than an archived one.
 *
 * v3 → v4: `isQueuedForLater` on works (T-89 queue-only semantics) — a work added
 * to a reading queue is no longer implicitly marked `isSaved`.
 *
 * v7 → v8: EPUB preservation pass-through columns on works (nullable, no backfill).
 * Android stores and re-emits them only — it does not run a preservation feature.
 */
object KudosDatabaseMigrations {
    val MIGRATION_1_2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            // Work LWW / soft-delete columns (nullable Instant → INTEGER; bool → INTEGER).
            db.execSQL("ALTER TABLE works ADD COLUMN lastModifiedAt INTEGER")
            db.execSQL("ALTER TABLE works ADD COLUMN progressModifiedAt INTEGER")
            db.execSQL(
                "ALTER TABLE works ADD COLUMN isDeleted INTEGER NOT NULL DEFAULT 0"
            )
            db.execSQL("ALTER TABLE works ADD COLUMN deletedAt INTEGER")
            db.execSQL("ALTER TABLE works ADD COLUMN permanentDeletionScheduledAt INTEGER")
            // Backfill lastModifiedAt from dateAdded so LWW has a baseline.
            db.execSQL(
                "UPDATE works SET lastModifiedAt = dateAdded WHERE lastModifiedAt IS NULL"
            )
            db.execSQL(
                "UPDATE works SET progressModifiedAt = lastReadDate " +
                    "WHERE progressModifiedAt IS NULL AND lastReadDate IS NOT NULL"
            )

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
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_sync_tombstones_recordID` " +
                    "ON `sync_tombstones` (`recordID`)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_sync_tombstones_recordTypeRaw` " +
                    "ON `sync_tombstones` (`recordTypeRaw`)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_sync_tombstones_ao3WorkID` " +
                    "ON `sync_tombstones` (`ao3WorkID`)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_sync_tombstones_sourceURL` " +
                    "ON `sync_tombstones` (`sourceURL`)"
            )

            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS `reading_queues` (
                    `id` TEXT NOT NULL,
                    `name` TEXT NOT NULL,
                    `kindRaw` TEXT NOT NULL,
                    `sortOrder` INTEGER NOT NULL,
                    `dateCreated` INTEGER NOT NULL,
                    `dateUpdated` INTEGER NOT NULL,
                    `lastMembershipChangedAt` INTEGER,
                    `deletedAt` INTEGER,
                    `isDeleted` INTEGER NOT NULL,
                    `permanentDeletionScheduledAt` INTEGER,
                    PRIMARY KEY(`id`)
                )
                """.trimIndent()
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_reading_queues_name` " +
                    "ON `reading_queues` (`name`)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_reading_queues_kindRaw` " +
                    "ON `reading_queues` (`kindRaw`)"
            )

            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS `reading_queue_memberships` (
                    `id` TEXT NOT NULL,
                    `queueID` TEXT NOT NULL,
                    `workID` TEXT NOT NULL,
                    `queuedAt` INTEGER NOT NULL,
                    `lastModifiedAt` INTEGER,
                    `sortOrderInQueue` INTEGER NOT NULL,
                    `note` TEXT NOT NULL,
                    PRIMARY KEY(`id`),
                    FOREIGN KEY(`queueID`) REFERENCES `reading_queues`(`id`)
                        ON UPDATE NO ACTION ON DELETE CASCADE
                )
                """.trimIndent()
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_reading_queue_memberships_queueID` " +
                    "ON `reading_queue_memberships` (`queueID`)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_reading_queue_memberships_workID` " +
                    "ON `reading_queue_memberships` (`workID`)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_reading_queue_memberships_queueID_workID` " +
                    "ON `reading_queue_memberships` (`queueID`, `workID`)"
            )

            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS `annotations` (
                    `id` TEXT NOT NULL,
                    `workID` TEXT NOT NULL,
                    `kindRaw` TEXT NOT NULL,
                    `colorRaw` TEXT NOT NULL,
                    `locatorString` TEXT NOT NULL,
                    `selectedText` TEXT NOT NULL,
                    `note` TEXT NOT NULL,
                    `progression` REAL NOT NULL,
                    `spineIndex` INTEGER NOT NULL,
                    `chapterTitle` TEXT NOT NULL,
                    `createdAt` INTEGER NOT NULL,
                    `lastModifiedAt` INTEGER,
                    `deletedAt` INTEGER,
                    `isPendingDeletion` INTEGER NOT NULL,
                    PRIMARY KEY(`id`)
                )
                """.trimIndent()
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_annotations_workID` " +
                    "ON `annotations` (`workID`)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_annotations_lastModifiedAt` " +
                    "ON `annotations` (`lastModifiedAt`)"
            )
        }
    }

    val MIGRATION_2_3 = object : Migration(2, 3) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE collections ADD COLUMN lastModifiedAt INTEGER")
            db.execSQL(
                "ALTER TABLE collections ADD COLUMN isDeleted INTEGER NOT NULL DEFAULT 0"
            )
            db.execSQL("ALTER TABLE collections ADD COLUMN deletedAt INTEGER")
            db.execSQL("ALTER TABLE collections ADD COLUMN permanentDeletionScheduledAt INTEGER")
            db.execSQL(
                "UPDATE collections SET lastModifiedAt = dateAdded WHERE lastModifiedAt IS NULL"
            )
        }
    }

    val MIGRATION_3_4 = object : Migration(3, 4) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                "ALTER TABLE works ADD COLUMN isQueuedForLater INTEGER NOT NULL DEFAULT 0"
            )
        }
    }

    val MIGRATION_4_5 = object : Migration(4, 5) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                "ALTER TABLE works ADD COLUMN searchText TEXT NOT NULL DEFAULT ''"
            )
            db.execSQL(
                "ALTER TABLE works ADD COLUMN searchIndexVersion INTEGER NOT NULL DEFAULT 0"
            )
        }
    }

    val MIGRATION_5_6 = object : Migration(5, 6) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE works ADD COLUMN ao3Unavailable INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE works ADD COLUMN lastAvailabilityCheck INTEGER")
        }
    }

    val MIGRATION_6_7 = object : Migration(6, 7) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE works ADD COLUMN lastTagRefreshAttemptAt INTEGER")
        }
    }

    /**
     * v7 → v8: EPUB preservation pass-through columns on works.
     *
     * Nullable, no backfill — Android does not run a preservation feature; it only
     * stores and re-emits values so an iOS→Android→iOS backup round trip keeps
     * `epubPreservationStatusRaw` / `preservedAt` / `lastPreservationAttemptAt`.
     */
    val MIGRATION_7_8 = object : Migration(7, 8) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE works ADD COLUMN epubPreservationStatusRaw TEXT")
            db.execSQL("ALTER TABLE works ADD COLUMN preservedAt INTEGER")
            db.execSQL("ALTER TABLE works ADD COLUMN lastPreservationAttemptAt INTEGER")
        }
    }
}
