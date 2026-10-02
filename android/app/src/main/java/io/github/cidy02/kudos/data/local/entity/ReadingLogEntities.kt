package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

/** iOS `ReadingSession`: one stretch of reading, for Reading Insights (1bi). */
@Entity(tableName = "reading_sessions", indices = [Index("workID"), Index("startedAt")])
data class ReadingSessionEntity(
    @PrimaryKey val id: String,
    val workID: String,
    val ao3WorkID: Int? = null,
    val sourceURL: String = "",
    val workTitle: String = "",
    val startedAt: Instant,
    val endedAt: Instant,
    val durationSeconds: Double = 0.0,
    val lastSpineIndex: Int = 0,
    val chapterTitle: String = "",
    val endingProgress: Double = 0.0,
    val wordCount: Int = 0,
    val chapterCountAtVisit: Int = 0,
    val didFinish: Boolean = false,
    val lastModifiedAt: Instant
)

/** iOS `ReadingFavorite`: a favourited work, author, fandom or tag (1aj–1bd). */
@Entity(tableName = "reading_favorites", indices = [Index(value = ["kindRaw", "targetKey"])])
data class ReadingFavoriteEntity(
    @PrimaryKey val id: String,
    val kindRaw: String,
    val targetKey: String,
    val displayName: String = "",
    val createdAt: Instant,
    val lastModifiedAt: Instant
)

/** iOS `FandomReadWatermark`: when a fandom was last visited (Jump Back In, 1bc). */
@Entity(tableName = "fandom_read_watermarks", indices = [Index("fandomName")])
data class FandomReadWatermarkEntity(
    @PrimaryKey val id: String,
    /** The raw AO3 tag name, never a parsed display title. */
    val fandomName: String,
    val lastVisitedAt: Instant,
    val newestWorkIDSeen: Int? = null,
    val newestWorkTitleSeen: String = "",
    val lastModifiedAt: Instant
)

/** iOS `ReadingQueue.tags`: a queue's tags share the `tags` table with works. */
@Entity(
    tableName = "queue_tag_cross_refs",
    primaryKeys = ["queueId", "tagId"],
    foreignKeys = [
        ForeignKey(
            entity = ReadingQueueEntity::class,
            parentColumns = ["id"],
            childColumns = ["queueId"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = TagEntity::class,
            parentColumns = ["id"],
            childColumns = ["tagId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("queueId"), Index("tagId")]
)
data class QueueTagCrossRef(
    val queueId: String,
    val tagId: String
)
