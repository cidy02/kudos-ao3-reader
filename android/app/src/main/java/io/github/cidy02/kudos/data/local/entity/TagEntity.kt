package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import java.time.Instant

@Entity(
    tableName = "user_tags",
    indices = [Index(value = ["name"], unique = true)]
)
data class TagEntity(
    @androidx.room.PrimaryKey val id: String,
    val name: String,
    val dateCreated: Instant
)

@Entity(
    tableName = "work_tag_cross_refs",
    primaryKeys = ["workId", "tagId"],
    foreignKeys = [
        ForeignKey(
            entity = WorkEntity::class,
            parentColumns = ["id"],
            childColumns = ["workId"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = TagEntity::class,
            parentColumns = ["id"],
            childColumns = ["tagId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("workId"),
        Index("tagId")
    ]
)
data class WorkTagCrossRef(
    val workId: String,
    val tagId: String
)
