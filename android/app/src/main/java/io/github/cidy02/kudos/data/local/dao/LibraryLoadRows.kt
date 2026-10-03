package io.github.cidy02.kudos.data.local.dao

import java.time.Instant

/** One active keep-offline queue or collection name for a work, in keeper-priority order. */
data class WorkKeeperName(
    val workId: String,
    val name: String
)

/** Active collection membership. Rows are ordered by [workId] so each collection's ids stay sorted. */
data class CollectionWorkLink(
    val collectionId: String,
    val workId: String
)

/** A user tag attached to a work. Rows are ordered by tag name, case-insensitive. */
data class WorkTagLink(
    val workId: String,
    val id: String,
    val name: String,
    val dateCreated: Instant
)
