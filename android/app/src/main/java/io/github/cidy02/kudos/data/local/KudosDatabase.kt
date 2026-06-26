package io.github.cidy02.kudos.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import io.github.cidy02.kudos.data.local.converters.KudosTypeConverters
import io.github.cidy02.kudos.data.local.dao.BookmarkDao
import io.github.cidy02.kudos.data.local.dao.CollectionDao
import io.github.cidy02.kudos.data.local.dao.CustomFontDao
import io.github.cidy02.kudos.data.local.dao.SavedSearchDao
import io.github.cidy02.kudos.data.local.dao.TagDao
import io.github.cidy02.kudos.data.local.dao.WorkDao
import io.github.cidy02.kudos.data.local.entity.BookmarkEntity
import io.github.cidy02.kudos.data.local.entity.CollectionEntity
import io.github.cidy02.kudos.data.local.entity.CollectionWorkCrossRef
import io.github.cidy02.kudos.data.local.entity.CustomFontEntity
import io.github.cidy02.kudos.data.local.entity.SavedSearchEntity
import io.github.cidy02.kudos.data.local.entity.TagEntity
import io.github.cidy02.kudos.data.local.entity.WorkEntity
import io.github.cidy02.kudos.data.local.entity.WorkTagCrossRef

@Database(
    entities = [
        WorkEntity::class,
        TagEntity::class,
        WorkTagCrossRef::class,
        CollectionEntity::class,
        CollectionWorkCrossRef::class,
        BookmarkEntity::class,
        CustomFontEntity::class,
        SavedSearchEntity::class
    ],
    version = 1,
    exportSchema = true
)
@TypeConverters(KudosTypeConverters::class)
abstract class KudosDatabase : RoomDatabase() {
    abstract fun workDao(): WorkDao
    abstract fun tagDao(): TagDao
    abstract fun collectionDao(): CollectionDao
    abstract fun bookmarkDao(): BookmarkDao
    abstract fun customFontDao(): CustomFontDao
    abstract fun savedSearchDao(): SavedSearchDao

    companion object {
        const val DatabaseName = "kudos.db"
    }
}
