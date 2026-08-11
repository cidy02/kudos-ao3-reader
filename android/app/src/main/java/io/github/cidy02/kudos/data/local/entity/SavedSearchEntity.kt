package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "saved_searches",
    indices = [Index("dateAdded")]
)
data class SavedSearchEntity(
    @PrimaryKey val id: String,
    val name: String,
    val dateAdded: Instant,
    val filtersJson: String
)
