package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "reading_queues",
    indices = [Index("name"), Index("kindRaw")]
)
data class ReadingQueueEntity(
    @PrimaryKey val id: String,
    val name: String,
    val kindRaw: String,
    val sortOrder: Int,
    val dateCreated: Instant,
    val dateUpdated: Instant,
    val lastMembershipChangedAt: Instant? = null,
    val deletedAt: Instant? = null,
    val isDeleted: Boolean = false,
    val permanentDeletionScheduledAt: Instant? = null
)

@Entity(
    tableName = "reading_queue_memberships",
    indices = [
        Index("queueID"),
        Index("workID"),
        Index(value = ["queueID", "workID"])
    ],
    foreignKeys = [
        ForeignKey(
            entity = ReadingQueueEntity::class,
            parentColumns = ["id"],
            childColumns = ["queueID"],
            onDelete = ForeignKey.CASCADE
        )
        // workID is not a hard FK: memberships may restore before/without work
        // if a work was tombstoned; merge applies only when work is present.
    ]
)
data class ReadingQueueMembershipEntity(
    @PrimaryKey val id: String,
    val queueID: String,
    val workID: String,
    val queuedAt: Instant,
    val lastModifiedAt: Instant? = null,
    val sortOrderInQueue: Int = 0,
    val note: String = ""
)
