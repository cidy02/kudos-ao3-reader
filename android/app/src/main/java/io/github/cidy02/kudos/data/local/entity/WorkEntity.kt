package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "works",
    indices = [
        Index("sourceUrl"),
        Index("title"),
        Index("author")
    ]
)
data class WorkEntity(
    @PrimaryKey val id: String,
    val title: String,
    val author: String,
    val summary: String,
    val sourceUrl: String,
    val dateAdded: Instant,
    val isFavorite: Boolean,
    val isSaved: Boolean,
    val isFinished: Boolean,
    val hasEpub: Boolean,
    val isComplete: Boolean,
    val rating: String,
    val language: String,
    val wordCount: Int,
    val chapters: String,
    val kudos: Int,
    val seriesTitle: String,
    val seriesPosition: Int,
    val seriesUrl: String,
    val lastSpineIndex: Int,
    val lastScrollFraction: Double,
    val lastReadDate: Instant?,
    val workWarnings: List<String>,
    val workCategories: List<String>,
    val workTags: List<String>,
    val workFandoms: List<String>,
    val workCharacters: List<String>,
    val workRelationships: List<String>,
    val workFreeforms: List<String>,
    val workTagsFetched: Boolean,
    val readiumLocator: String?,
    val comments: Int?,
    val hits: Int?,
    val knownChapterCount: Int?,
    val lastUpdateCheck: Instant?
)
