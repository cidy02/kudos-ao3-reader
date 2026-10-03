package io.github.cidy02.kudos.browse

import io.github.cidy02.kudos.data.local.dao.ReadingLogDao
import io.github.cidy02.kudos.data.local.entity.FandomReadWatermarkEntity
import java.time.Instant
import java.util.UUID

/**
 * Records that a fandom was opened from Browse.
 * Port of iOS `ReadingLogService.markVisited`: update the row for that raw
 * name, otherwise insert one. A blank name is ignored.
 */
object FandomVisits {
    fun nextWatermark(
        existing: FandomReadWatermarkEntity?,
        rawName: String,
        now: Instant,
        newId: String
    ): FandomReadWatermarkEntity? {
        val name = rawName.trim()
        if (name.isEmpty()) return null
        return existing?.copy(lastVisitedAt = now, lastModifiedAt = now)
            ?: FandomReadWatermarkEntity(
                id = newId,
                fandomName = name,
                lastVisitedAt = now,
                lastModifiedAt = now
            )
    }

    suspend fun markVisited(
        dao: ReadingLogDao,
        fandom: String,
        now: Instant = Instant.now()
    ) {
        val name = fandom.trim()
        if (name.isEmpty()) return
        val next = nextWatermark(dao.getWatermark(name), name, now, UUID.randomUUID().toString())
            ?: return
        dao.upsertWatermark(next)
    }
}
