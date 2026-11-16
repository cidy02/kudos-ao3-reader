package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.readingProgressFraction
import io.github.cidy02.kudos.ui.components.ChapterBarGeometry
import io.github.cidy02.kudos.ui.components.ChapterBarItem
import io.github.cidy02.kudos.ui.components.ChapterBarLayout
import io.github.cidy02.kudos.ui.components.ChapterBarModel
import io.github.cidy02.kudos.ui.components.ChapterBarScale
import io.github.cidy02.kudos.works.ChapterLengths
import io.github.cidy02.kudos.works.WorkReadingPosition
import java.time.Instant
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Pure resume-card model matching iOS `ResumeCardModel` (`HomeResumeHero.swift`)
 * for Home's Resume hero and Work Detail's reading card.
 */
data class ResumeCardModel(
    val title: String,
    val chapters: String,
    val rawProgress: Double?,
    val rawChapterProgress: Double?,
    val chapterName: String?,
    val updated: String = "",
    val newChapterCount: Int = 0,
    val lastReadLabel: String? = null,
    val chapterPositions: List<Int>? = null,
    val isFinished: Boolean = false
) {
    val progress: Double? = rawProgress?.coerceIn(0.0, 1.0)
    val chapterProgress: Double? = rawChapterProgress?.coerceIn(0.0, 1.0)
    val clampedNewChapterCount: Int = maxOf(0, newChapterCount)

    val workPercent: Int get() = ((progress ?: 0.0) * 100.0).roundToInt()
    val chapterPercent: Int get() = ((chapterProgress ?: 0.0) * 100.0).roundToInt()

    val postedChapters: Int get() = ChapterBarModel.postedChapterCount(chapters)

    val totalChapters: Int?
        get() {
            val total = ChapterBarModel.totalChapterCount(chapters) ?: return null
            return if (total >= postedChapters && total > 0) total else null
        }

    val plannedChapters: Int get() = totalChapters ?: postedChapters

    val isOneChapter: Boolean get() = postedChapters == 1 && totalChapters == 1

    val chapterNumber: Int
        get() {
            chapterName?.let { name ->
                CHAPTER_NUMBER_REGEX.find(name)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let { number ->
                    return if (postedChapters > 0) minOf(number, postedChapters) else number
                }
            }
            return ChapterBarGeometry.readingChapter(
                posted = postedChapters,
                progress = progress ?: 0.0,
                weights = chapterPositions?.map(Int::toDouble)
            )
        }

    /** "Read" (the caller's title) until there is a position to resume; "Resume" for a 1/1 work. */
    fun detailPrimaryTitle(fallback: String): String {
        if (progress == null) return fallback
        if (isOneChapter) return "Resume"
        return "Resume Chapter $chapterNumber"
    }

    val detailProgressLine: String?
        get() {
            if (progress == null) return null
            val work = "$workPercent% of the work"
            return if (chapterProgress == null) work else "$chapterPercent% of the chapter · $work"
        }

    val displayedChapterName: String
        get() {
            if (chapterName != null) return chapterName
            if (progress == null || progress == 0.0) {
                return if (lastReadLabel == null) "Not started" else "Last opened"
            }
            return "Chapter $chapterNumber"
        }

    val detailChapterName: String
        get() {
            if (progress == null) return displayedChapterName
            val raw = chapterName ?: return "Ch $chapterNumber"
            if (raw.lowercase(Locale.US) in SPECIAL_CHAPTER_TITLES) return raw
            val name = CHAPTER_PREFIX_REGEX.replaceFirst(raw, "")
            return if (name.isEmpty()) "Ch $chapterNumber" else "Ch $chapterNumber, $name"
        }

    val postedLabel: String
        get() {
            if (postedChapters <= 0) return chapters
            val total = totalChapters ?: return "$postedChapters posted"
            if (isOneChapter) return "One chapter"
            val unread = (progress ?: 0.0) <= 0.0
            if (total == postedChapters && unread) {
                return "$postedChapters chapter${if (postedChapters == 1) "" else "s"}"
            }
            return "$postedChapters of $total posted"
        }

    val postedShortLabel: String
        get() {
            if (postedChapters <= 0) return chapters
            return "$postedChapters of ${totalChapters?.toString() ?: "?"}"
        }

    fun chapterBarLayout(lengths: ChapterLengths?, scale: ChapterBarScale = ChapterBarScale.Card): ChapterBarLayout =
        ChapterBarModel.layout(
            chapters = chapters,
            progress = progress,
            isFinished = isFinished || progress == 1.0,
            weights = lengths?.positions,
            heights = lengths?.words,
            scale = scale
        )

    fun chapterItems(lengths: ChapterLengths?): List<ChapterBarItem> =
        chapterBarLayout(lengths).bars

    companion object {
        private val CHAPTER_NUMBER_REGEX = Regex("""(?i)\bch(?:apter)?\s*(\d+)""")
        private val CHAPTER_PREFIX_REGEX = Regex("""(?i)^ch(?:apter)?\s*\d+\s*[:.,\-]?\s*""")
        private val SPECIAL_CHAPTER_TITLES = setOf("preface", "summary", "afterword")

        fun fromWork(
            work: SavedWork,
            chapterPositions: List<Int>? = null,
            now: Instant = Instant.now()
        ): ResumeCardModel {
            val known = work.knownChapterCount ?: work.postedChapterCount
            return ResumeCardModel(
                title = work.title,
                chapters = work.chapters,
                rawProgress = work.readingProgressFraction(),
                rawChapterProgress = WorkReadingPosition.chapterProgress(work.readiumLocator),
                chapterName = HomeFacts.locatorTitle(work.readiumLocator),
                updated = work.dateUpdated.trim(),
                newChapterCount = maxOf(0, work.postedChapterCount - known),
                lastReadLabel = work.lastReadDate?.let { HomeFacts.relativeNamed(it, now) },
                chapterPositions = chapterPositions,
                isFinished = work.isFinished
            )
        }
    }
}
