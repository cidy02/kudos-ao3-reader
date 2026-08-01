package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "annotations",
    indices = [
        Index("workID"),
        Index("lastModifiedAt")
    ]
)
data class AnnotationEntity(
    @PrimaryKey val id: String,
    val workID: String,
    val kindRaw: String,
    val colorRaw: String,
    val locatorString: String,
    val selectedText: String,
    val note: String,
    val progression: Double,
    val spineIndex: Int,
    val chapterTitle: String,
    val createdAt: Instant,
    val lastModifiedAt: Instant? = null,
    val deletedAt: Instant? = null,
    val isPendingDeletion: Boolean = false
)
