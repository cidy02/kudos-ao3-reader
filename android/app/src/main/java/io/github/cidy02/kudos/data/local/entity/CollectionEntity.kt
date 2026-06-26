package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "collections",
    indices = [Index("name")]
)
data class CollectionEntity(
    @PrimaryKey val id: String,
    val name: String,
    val dateAdded: Instant,
    val description: String?,
    val sortOrder: Int?
)

@Entity(
    tableName = "collection_work_cross_refs",
    primaryKeys = ["collectionId", "workId"],
    foreignKeys = [
        ForeignKey(
            entity = CollectionEntity::class,
            parentColumns = ["id"],
            childColumns = ["collectionId"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = WorkEntity::class,
            parentColumns = ["id"],
            childColumns = ["workId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("collectionId"),
        Index("workId")
    ]
)
data class CollectionWorkCrossRef(
    val collectionId: String,
    val workId: String
)
