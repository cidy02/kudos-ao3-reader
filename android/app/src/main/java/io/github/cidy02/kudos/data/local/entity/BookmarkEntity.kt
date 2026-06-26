package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "bookmarks",
    indices = [Index(value = ["urlString"], unique = true)]
)
data class BookmarkEntity(
    @PrimaryKey val id: String,
    val title: String,
    val urlString: String,
    val dateAdded: Instant
)
