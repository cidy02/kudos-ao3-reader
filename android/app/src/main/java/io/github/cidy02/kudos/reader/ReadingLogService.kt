package io.github.cidy02.kudos.reader

import android.content.SharedPreferences
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.publicationProgress
import io.github.cidy02.kudos.core.model.readingProgress
import io.github.cidy02.kudos.data.local.dao.ReadingLogDao
import io.github.cidy02.kudos.data.local.entity.ReadingSessionEntity
import io.github.cidy02.kudos.data.local.entity.ReadingSessionMode
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
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
    private val uuidFactory: () -> String = { UUID.randomUUID().toString() },
    private val zoneIdProvider: () -> ZoneId = { ZoneId.systemDefault() },
    private val deviceIdProvider: (() -> String)? = null
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
        val tzOffsetSeconds: Int,
        val startProgress: Double?,
        val startSpineIndex: Int,
        val mode: ReadingSessionMode,
        val playbackRate: Double?,
        val activeSeconds: Double,
        val lastActivityAt: Instant,
        val deviceID: String,
        val wasFinishedAtStart: Boolean,
        val didFinish: Boolean = false
    )

    private val mutex = Mutex()
    private val openSessions = mutableMapOf<String, OpenSession>()
    private val fallbackDeviceId by lazy { uuidFactory() }

    private fun resolvedDeviceId(): String =
        deviceIdProvider?.invoke()?.takeIf { it.isNotEmpty() } ?: fallbackDeviceId

    suspend fun startSession(work: SavedWork): Unit = mutex.withLock {
        if (openSessions.containsKey(work.id)) return@withLock
        val now = clock()
        // A stored overall fraction is trustworthy; chapter-count fallbacks are not.
        val startProgress = work.publicationProgress?.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0)
            ?: if (work.readiumLocator.isNullOrEmpty() &&
                work.lastSpineIndex == 0 &&
                work.lastScrollFraction == 0.0
            ) {
                0.0
            } else {
                null
            }
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
            tzOffsetSeconds = zoneIdProvider().rules.getOffset(now).totalSeconds,
            startProgress = startProgress,
            startSpineIndex = work.lastSpineIndex,
            mode = ReadingSessionMode.READ,
            playbackRate = null,
            activeSeconds = 0.0,
            lastActivityAt = now,
            deviceID = resolvedDeviceId(),
            wasFinishedAtStart = work.isFinished
        )
    }

    suspend fun noteActivity(work: SavedWork): Unit = noteActivity(work.id)

    suspend fun noteActivity(workId: String): Unit = mutex.withLock {
        noteActivityLocked(workId, clock())
    }

    private fun noteActivityLocked(workId: String, now: Instant) {
        val current = openSessions[workId] ?: return
        if (current.isPaused || now.isBefore(current.lastActivityAt)) return
        openSessions[workId] = current.copy(
            activeSeconds = current.activeSeconds + activeGap(current.lastActivityAt, now),
            lastActivityAt = now
        )
    }

    suspend fun setMode(
        mode: ReadingSessionMode,
        workId: String,
        playbackRate: Double? = null
    ): Unit = mutex.withLock {
        val current = openSessions[workId] ?: return@withLock
        // One mode per sitting: any Read Aloud playback makes this a listening visit.
        if (current.mode == ReadingSessionMode.LISTEN && mode == ReadingSessionMode.READ) {
            return@withLock
        }
        val minRate = ReaderSpeechPreferences.RATE_RANGE.start.toDouble()
        val maxRate = ReaderSpeechPreferences.RATE_RANGE.endInclusive.toDouble()
        val clampedRate = if (mode == ReadingSessionMode.LISTEN) {
            playbackRate?.let {
                if (it.isFinite()) it.coerceIn(minRate, maxRate)
                else ReaderSpeechPreferences.DEFAULT_RATE.toDouble()
            }
        } else {
            null
        }
        openSessions[workId] = current.copy(
            mode = mode,
            playbackRate = clampedRate
        )
    }

    /** Banks foreground time and checkpoints the row before Android may reclaim the process. */
    suspend fun pauseSession(work: SavedWork): Unit = mutex.withLock {
        val now = clock()
        noteActivityLocked(work.id, now)
        val current = openSessions[work.id] ?: return@withLock
        if (current.isPaused) return@withLock
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
        val now = clock()
        openSessions[workId] = current.copy(
            lastResumedAt = now,
            lastActivityAt = if (current.lastActivityAt.isAfter(now)) current.lastActivityAt else now,
            isPaused = false
        )
    }

    suspend fun endSession(work: SavedWork): Unit = mutex.withLock {
        val now = clock()
        noteActivityLocked(work.id, now)
        val current = openSessions.remove(work.id) ?: return@withLock
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
                tzOffsetSeconds = session.tzOffsetSeconds,
                startProgress = session.startProgress,
                startSpineIndex = session.startSpineIndex,
                modeRaw = session.mode.rawValue,
                playbackRate = session.playbackRate,
                activeSeconds = session.activeSeconds,
                deviceID = session.deviceID,
                rulesVersion = CURRENT_RULES_VERSION,
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
        const val MAX_ACTIVE_GAP_SECONDS = 300.0
        const val CURRENT_RULES_VERSION = 1
        private const val DEVICE_ID_KEY = "readingLogDeviceID"
        private val json = Json { ignoreUnknownKeys = true }

        fun deviceId(
            preferences: SharedPreferences,
            uuidFactory: () -> String = { UUID.randomUUID().toString() }
        ): String {
            val existing = preferences.getString(DEVICE_ID_KEY, null)
            if (!existing.isNullOrEmpty()) return existing
            val value = uuidFactory()
            preferences.edit().putString(DEVICE_ID_KEY, value).apply()
            return value
        }

        fun activeGap(from: Instant, to: Instant): Double {
            val duration = Duration.between(from, to)
            if (duration.isNegative) return 0.0
            val seconds = duration.seconds.toDouble() + duration.nano / 1_000_000_000.0
            return seconds.coerceIn(0.0, MAX_ACTIVE_GAP_SECONDS)
        }
    }
}
