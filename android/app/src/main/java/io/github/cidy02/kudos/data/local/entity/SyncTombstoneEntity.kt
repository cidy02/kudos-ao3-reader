package io.github.cidy02.kudos.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "sync_tombstones",
    indices = [
        Index("recordID"),
        Index("recordTypeRaw"),
        Index("ao3WorkID"),
        Index("sourceURL")
    ]
)
data class SyncTombstoneEntity(
    @PrimaryKey val id: String,
    val recordID: String,
    val recordTypeRaw: String,
    val createdAt: Instant,
    val lastModifiedAt: Instant,
    val sourceURL: String = "",
    val ao3WorkID: Int? = null,
    val deletedOnDeviceID: String = "",
    val deletionReason: String = "",
    val signerPublicKey: String = "",
    val signature: String = ""
)
