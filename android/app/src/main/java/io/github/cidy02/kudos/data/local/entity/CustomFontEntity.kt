package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "custom_fonts",
    indices = [Index(value = ["fileName"], unique = true)]
)
data class CustomFontEntity(
    @PrimaryKey val id: String,
    val name: String,
    val fileName: String,
    val dateAdded: Instant
)
