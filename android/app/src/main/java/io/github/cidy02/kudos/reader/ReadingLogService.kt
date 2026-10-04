package io.github.cidy02.kudos.reader

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.readingProgress
import io.github.cidy02.kudos.data.local.dao.ReadingLogDao
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/** Records one reader visit using the same lifecycle and fields as iOS ReadingLogService. */
class ReadingLogService(
    private val dao: ReadingLogDao,
    private val clock: () -> Instant = { Instant.now() },
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() }
) {
    private data class OpenSession(
        val recordId: String,
        val workId: String,
        val ao3WorkId: Int?,
        val sourceUrl: String,
        val workTitle: String,
        val startedAt: Instant,
        val lastResumedAt: Instant,
        val accumulatedSeconds: Double,
        val isPaused: Boolean,
        val wasFinishedAtStart: Boolean,
        val didFinish: Boolean = false
    )

    private val mutex = Mutex()
    private val openSessions = mutableMapOf<String, OpenSession>()

    suspend fun startSession(work: SavedWork): Unit = mutex.withLock {
        if (openSessions.containsKey(work.id)) return@withLock
        val now = clock()
        openSessions[work.id] = OpenSession(
            recordId = uuidFactory(),
            workId = work.id,
            ao3WorkId = work.ao3WorkID,
            sourceUrl = work.sourceUrl,
            workTitle = work.title,
            startedAt = now,
            lastResumedAt = now,
            accumulatedSeconds = 0.0,
            isPaused = false,
            wasFinishedAtStart = work.isFinished
        )
    }

    /** Banks foreground time and checkpoints the row before Android may reclaim the process. */
    suspend fun pauseSession(work: SavedWork): Unit = mutex.withLock {
        val current = openSessions[work.id] ?: return@withLock
        if (current.isPaused) return@withLock
        val now = clock()
        val session = current.copy(
            lastResumedAt = now,
            accumulatedSeconds = current.accumulatedSeconds + elapsed(current.lastResumedAt, now),
            isPaused = true,
            didFinish = current.didFinish || didFinish(current, work)
        )
        openSessions[work.id] = session
        persist(session, work, now)
    }

    suspend fun resumeSession(workId: String): Unit = mutex.withLock {
        val current = openSessions[workId] ?: return@withLock
        if (!current.isPaused) return@withLock
        openSessions[workId] = current.copy(lastResumedAt = clock(), isPaused = false)
    }

    suspend fun endSession(work: SavedWork): Unit = mutex.withLock {
        val current = openSessions.remove(work.id) ?: return@withLock
        val now = clock()
        val session = current.copy(
            accumulatedSeconds = current.accumulatedSeconds + if (current.isPaused) {
                0.0
            } else {
                elapsed(current.lastResumedAt, now)
            },
            didFinish = current.didFinish || didFinish(current, work)
        )
        persist(session, work, now)
    }

    private suspend fun persist(session: OpenSession, work: SavedWork, now: Instant) {
        if (session.accumulatedSeconds < MINIMUM_PERSISTABLE_SECONDS) return
        dao.upsertSession(
            ReadingSessionEntity(
                id = session.recordId,
                workID = session.workId,
                ao3WorkID = work.ao3WorkID ?: session.ao3WorkId,
                sourceURL = work.sourceUrl.ifBlank { session.sourceUrl },
                workTitle = work.title.ifBlank { session.workTitle },
                startedAt = session.startedAt,
                endedAt = now,
                durationSeconds = session.accumulatedSeconds.coerceAtLeast(0.0),
                lastSpineIndex = work.lastSpineIndex,
                chapterTitle = locatorTitle(work.readiumLocator),
                endingProgress = (work.readingProgress ?: 0.0).coerceIn(0.0, 1.0),
                wordCount = work.wordCount,
                chapterCountAtVisit = work.postedChapterCount,
                didFinish = session.didFinish,
                lastModifiedAt = now
            )
        )
    }

    private fun didFinish(session: OpenSession, work: SavedWork): Boolean =
        work.isFinished && !session.wasFinishedAtStart

    private fun elapsed(from: Instant, to: Instant): Double {
        val duration = Duration.between(from, to)
        if (duration.isNegative) return 0.0
        return duration.seconds.toDouble() + duration.nano / 1_000_000_000.0
    }

    private fun locatorTitle(locator: String?): String {
        if (locator.isNullOrBlank()) return ""
        val root = runCatching { json.parseToJsonElement(locator) }.getOrNull() as? JsonObject
            ?: return ""
        val inner = root["locator"] as? JsonObject ?: root
        val title = inner["title"] as? JsonPrimitive
        return title?.takeIf { it.isString }?.contentOrNull?.trim().orEmpty()
    }

    companion object {
        const val MINIMUM_PERSISTABLE_SECONDS = 15.0
        private val json = Json { ignoreUnknownKeys = true }
    }
}
