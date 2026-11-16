package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Where a chapter bar is drawn. Width and gap stay fixed until the line is full,
 * then the bars shrink, and past [minBarWidth] chapters group equally
 * (`ChapterBars.swift`).
 */
enum class ChapterBarScale(
    /** 6 dp on a row; 27 dp cap on a card so a few chapters do not stretch across the card. */
    val nominalWidth: Float,
    /** Minimum bar width before chapters group (`ceil(n / fit)`): 3 dp in a row, 4 dp on a card. */
    val minBarWidth: Float,
    /** Default bar count that fits when no container width has been measured yet. */
    val defaultFit: Int,
    /** Default container width used before layout measures (326 on a card, 200 on a row). */
    val defaultAvailableWidth: Float,
    /** Row draws a 2 dp gap; cards take 4 dp. */
    val gap: Float,
    val trackHeight: Dp
) {
    Row(
        nominalWidth = 6f,
        minBarWidth = 3f,
        defaultFit = 36,
        defaultAvailableWidth = 200f,
        gap = 2f,
        trackHeight = 16.dp
    ),
    Card(
        nominalWidth = 27f,
        minBarWidth = 4f,
        defaultFit = 46,
        defaultAvailableWidth = 326f,
        gap = 4f,
        trackHeight = 76.dp
    )
}

/** How far a reader is through one planned chapter or group. */
sealed interface ChapterBarRole {
    /** Read through. Accent ink on a row; white when the bar sits on a dark gradient. */
    data object Read : ChapterBarRole

    /** The chapter (or group) being read, filled from the bottom by [fill] (0…1). */
    data class Current(val fill: Double) : ChapterBarRole

    /** Posted, not read yet. */
    data object PostedUnread : ChapterBarRole

    /** Planned, not posted. Drawn dashed. */
    data object NotPosted : ChapterBarRole

    /** A chapter posted since the reader last looked. */
    data object NewChapter : ChapterBarRole
}

data class ChapterBarItem(
    val role: ChapterBarRole,
    /** Relative height. The tallest bar fills the track; the rest scale to it. */
    val weight: Double
)

data class ChapterBarMetrics(
    val width: Float,
    val gap: Float,
    val radius: Float
)

/**
 * Pure bar layout result produced by [ChapterBarGeometry.layout].
 * Views only draw what this returns.
 */
class ChapterBarLayout(
    val bars: List<ChapterBarItem> = emptyList(),
    /** Non-null (0…1) for a finished/single one-chapter work (1/1), which draws a plain progress track instead of bars. */
    val trackFill: Double? = null,
    /** True when the author has not set a chapter total (AO3 "12/?"): draw three fading dots after the posted bars, never a dashed bar. */
    val showsOpenTotalDots: Boolean = false,
    /** How many chapters each bar represents (1 while chapters fit, `ceil(count / fit)` when grouped). */
    val chaptersPerBar: Int = 1,
    /** `"Each bar is k chapters"` when [chaptersPerBar] > 1, null otherwise. */
    val groupNote: String? = null,
    val metrics: ChapterBarMetrics = ChapterBarMetrics(0f, 0f, 0f),
    val accessibilityLabel: String = "",
    internal val source: Source? = null
) {
    data class Source(
        val planned: Int?,
        val posted: Int,
        val read: Int?,
        val chapterProgress: Double,
        val progress: Double?,
        val isFinished: Boolean,
        val weights: List<Double>?,
        val heights: List<Double>?,
        val newChapterCount: Int,
        val scale: ChapterBarScale,
        val fit: Int?
    )

    val isEmpty: Boolean
        get() = bars.isEmpty() && trackFill == null

    constructor(items: List<ChapterBarItem>, scale: ChapterBarScale = ChapterBarScale.Row) : this(
        bars = items,
        trackFill = null,
        showsOpenTotalDots = false,
        chaptersPerBar = 1,
        groupNote = null,
        metrics = ChapterBarGeometry.metrics(
            count = items.size,
            availableWidth = scale.defaultAvailableWidth,
            nominalWidth = scale.nominalWidth,
            gap = scale.gap
        ),
        accessibilityLabel = ChapterBarGeometry.accessibilityLabel(items),
        source = null
    )

    fun resolved(availableWidth: Float, scale: ChapterBarScale): ChapterBarLayout {
        if (source != null) {
            return ChapterBarGeometry.layout(
                planned = source.planned,
                posted = source.posted,
                read = source.read,
                chapterProgress = source.chapterProgress,
                progress = source.progress,
                isFinished = source.isFinished,
                weights = source.weights,
                heights = source.heights,
                newChapterCount = source.newChapterCount,
                scale = scale,
                availableWidth = availableWidth,
                fit = source.fit
            )
        }
        if (bars.isEmpty()) return this
        val widthForMetrics = if (availableWidth > 0f) availableWidth else scale.defaultAvailableWidth
        return ChapterBarLayout(
            bars = bars,
            trackFill = trackFill,
            showsOpenTotalDots = showsOpenTotalDots,
            chaptersPerBar = chaptersPerBar,
            groupNote = groupNote,
            metrics = ChapterBarGeometry.metrics(
                count = bars.size,
                availableWidth = widthForMetrics,
                nominalWidth = scale.nominalWidth,
                gap = scale.gap
            ),
            accessibilityLabel = accessibilityLabel,
            source = null
        )
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ChapterBarLayout) return false
        return bars == other.bars &&
            trackFill == other.trackFill &&
            showsOpenTotalDots == other.showsOpenTotalDots &&
            chaptersPerBar == other.chaptersPerBar &&
            groupNote == other.groupNote &&
            metrics == other.metrics &&
            accessibilityLabel == other.accessibilityLabel
    }

    override fun hashCode(): Int {
        var result = bars.hashCode()
        result = 31 * result + (trackFill?.hashCode() ?: 0)
        result = 31 * result + showsOpenTotalDots.hashCode()
        result = 31 * result + chaptersPerBar
        result = 31 * result + (groupNote?.hashCode() ?: 0)
        result = 31 * result + metrics.hashCode()
        result = 31 * result + accessibilityLabel.hashCode()
        return result
    }
}

/** Pure bar layout matching iOS `ChapterBarGeometry`. */
object ChapterBarGeometry {
    const val OPEN_DOTS_WIDTH: Float = 24f

    /**
     * Fixed width and gap while they fit. Past that, the width shrinks and the
     * gap stays; the gap shrinks only when the width would otherwise go to
     * nothing. Radius is `min(3, width / 2)`. An unknown width (0, before
     * layout) keeps the nominal size.
     */
    fun metrics(
        count: Int,
        availableWidth: Float,
        nominalWidth: Float,
        gap: Float
    ): ChapterBarMetrics {
        if (count <= 0 || nominalWidth <= 0f) {
            return ChapterBarMetrics(width = 0f, gap = 0f, radius = 0f)
        }
        val width: Float
        val usedGap: Float
        if (availableWidth <= 0f) {
            width = nominalWidth
            usedGap = gap
        } else if (count == 1) {
            width = min(nominalWidth, availableWidth)
            usedGap = gap
        } else {
            val natural = count * nominalWidth + (count - 1) * gap
            if (natural <= availableWidth) {
                width = nominalWidth
                usedGap = gap
            } else {
                val gapBudget = (count - 1) * gap
                if (availableWidth > gapBudget) {
                    width = (availableWidth - gapBudget) / count.toFloat()
                    usedGap = gap
                } else {
                    val scale = availableWidth / natural
                    width = nominalWidth * scale
                    usedGap = gap * scale
                }
            }
        }
        return ChapterBarMetrics(width = width, gap = usedGap, radius = min(3f, width / 2f))
    }

    /**
     * The one rule for chapter bars (Resume card, Work Detail, Home rows, library and search rows):
     * 1. A one-chapter work (1/1): no bars, a plain progress track.
     * 2. Total unknown (AO3 "12/?"): one bar per posted chapter, then three fading dots; never a dashed bar.
     * 3. More chapters than fit (4 dp minimum on a card, 3 dp in a row): equal groups of `ceil(n / fit)`
     *    chapters per bar + a note. A group counts as posted when any chapter in it is.
     * 4. Otherwise one bar per chapter; dashed = planned but not posted, capped at 27 dp wide on a card.
     * Lengths unknown (not downloaded) keep every bar one height. Read is capped at posted.
     */
    fun layout(
        planned: Int?,
        posted: Int,
        read: Int? = null,
        chapterProgress: Double = 0.0,
        progress: Double? = null,
        isFinished: Boolean = false,
        weights: List<Double>? = null,
        heights: List<Double>? = null,
        newChapterCount: Int = 0,
        scale: ChapterBarScale = ChapterBarScale.Card,
        availableWidth: Float = 0f,
        fit: Int? = null
    ): ChapterBarLayout {
        val safePosted = max(0, posted)
        val total: Int? = if (planned != null && planned >= safePosted && planned > 0) {
            planned
        } else {
            null
        }
        val count = total ?: safePosted
        val source = ChapterBarLayout.Source(
            planned = planned,
            posted = safePosted,
            read = read,
            chapterProgress = chapterProgress,
            progress = progress,
            isFinished = isFinished,
            weights = weights,
            heights = heights,
            newChapterCount = newChapterCount,
            scale = scale,
            fit = fit
        )
        if (count <= 0) {
            return ChapterBarLayout(source = source)
        }

        fun usable(values: List<Double>?): List<Double>? =
            values?.takeIf { it.size == safePosted && safePosted > 0 && it.all { v -> v > 0.0 } }

        val known = usable(weights)
        val postedWeights = List(safePosted) { known?.get(it) ?: 1.0 }
        val drawn = usable(heights) ?: known
        val postedHeights = List(safePosted) { drawn?.get(it) ?: 1.0 }
        val unpostedHeight = drawn?.let { it.sum() / it.size.toDouble() } ?: 1.0
        val fresh = min(max(0, newChapterCount), safePosted)
        val freshStart = safePosted - fresh

        val chapterRoles: List<ChapterBarRole>
        val chapterFills: List<Double>
        val readCount: Int
        if (read != null) {
            val clampedRead = if (isFinished) safePosted else min(max(0, read), safePosted)
            val inChapter = if (clampedRead >= safePosted) 0.0 else min(max(chapterProgress, 0.0), 1.0)
            val roles = ArrayList<ChapterBarRole>(safePosted)
            val fills = ArrayList<Double>(safePosted)
            for (index in 0 until safePosted) {
                if (index < clampedRead) {
                    roles.add(ChapterBarRole.Read)
                    fills.add(1.0)
                } else if (index == clampedRead && inChapter >= 1.0 - 0.000_001) {
                    roles.add(ChapterBarRole.Read)
                    fills.add(1.0)
                } else if (index == clampedRead && inChapter > 0.000_001) {
                    roles.add(ChapterBarRole.Current(inChapter))
                    fills.add(inChapter)
                } else {
                    roles.add(ChapterBarRole.PostedUnread)
                    fills.add(0.0)
                }
            }
            chapterRoles = roles
            chapterFills = fills
            readCount = roles.count { it is ChapterBarRole.Read }
        } else {
            val totalWeight = postedWeights.sum()
            val fraction: Double? = if (isFinished) 1.0 else progress?.let { min(max(it, 0.0), 1.0) }
            var remaining = (fraction ?: 0.0) * totalWeight
            val roles = ArrayList<ChapterBarRole>(safePosted)
            val fills = ArrayList<Double>(safePosted)
            for (index in 0 until safePosted) {
                val span = postedWeights[index]
                if (fraction == null || fraction == 0.0) {
                    roles.add(ChapterBarRole.PostedUnread)
                    fills.add(0.0)
                } else if (remaining >= span - 0.000_001) {
                    roles.add(ChapterBarRole.Read)
                    fills.add(1.0)
                    remaining -= span
                } else if (remaining > 0.000_001) {
                    val fill = remaining / span
                    roles.add(ChapterBarRole.Current(fill))
                    fills.add(fill)
                    remaining = 0.0
                } else {
                    roles.add(ChapterBarRole.PostedUnread)
                    fills.add(0.0)
                }
            }
            chapterRoles = roles
            chapterFills = fills
            readCount = roles.count { it is ChapterBarRole.Read }
        }

        if (total == 1 && safePosted == 1) {
            val fill: Double = when {
                isFinished || readCount >= 1 -> 1.0
                progress != null -> min(max(progress, 0.0), 1.0)
                chapterProgress > 0.0 -> min(max(chapterProgress, 0.0), 1.0)
                fresh > 0 -> 1.0
                else -> 0.0
            }
            val percent = (fill * 100.0).roundToInt()
            val label = if (scale == ChapterBarScale.Row && read == null && progress == null && chapterProgress == 0.0) {
                if (fresh > 0) "New work, one chapter" else "One chapter"
            } else {
                "One chapter, $percent percent read"
            }
            val widthForTrack = if (availableWidth > 0f) {
                availableWidth
            } else if (scale == ChapterBarScale.Row) {
                96f
            } else {
                scale.defaultAvailableWidth
            }
            val trackWidth = if (scale == ChapterBarScale.Row) min(96f, widthForTrack) else widthForTrack
            return ChapterBarLayout(
                bars = emptyList(),
                trackFill = fill,
                showsOpenTotalDots = false,
                chaptersPerBar = 1,
                groupNote = null,
                metrics = ChapterBarMetrics(width = trackWidth, gap = 0f, radius = 3f),
                accessibilityLabel = label,
                source = source
            )
        }

        val showsOpenTotalDots = (total == null)
        val resolvedFit: Int = when {
            fit != null -> max(4, fit)
            availableWidth > 0f -> {
                val widthForBars = if (showsOpenTotalDots) max(0f, availableWidth - OPEN_DOTS_WIDTH) else availableWidth
                max(4, floor((widthForBars + scale.gap) / (scale.minBarWidth + scale.gap)).toInt())
            }
            else -> scale.defaultFit
        }
        val chaptersPerBar = max(1, ceil(count.toDouble() / resolvedFit.toDouble()).toInt())
        val bars: List<ChapterBarItem> = if (chaptersPerBar == 1) {
            List(count) { index ->
                if (index >= safePosted) {
                    ChapterBarItem(role = ChapterBarRole.NotPosted, weight = unpostedHeight)
                } else {
                    val weight = postedHeights[index]
                    if (index >= freshStart && fresh > 0) {
                        ChapterBarItem(role = ChapterBarRole.NewChapter, weight = weight)
                    } else {
                        ChapterBarItem(role = chapterRoles[index], weight = weight)
                    }
                }
            }
        } else {
            val grouped = ArrayList<ChapterBarItem>()
            var groupIndex = 0
            while (groupIndex * chaptersPerBar < count) {
                val from = groupIndex * chaptersPerBar
                val to = min(count, from + chaptersPerBar)
                val liveEnd = min(to, safePosted)
                val live = max(0, liveEnd - from)
                if (live == 0) {
                    grouped.add(ChapterBarItem(role = ChapterBarRole.NotPosted, weight = unpostedHeight))
                } else {
                    val weight = (from until liveEnd).sumOf { postedHeights[it] } / live.toDouble()
                    val freshInGroup = if (fresh > 0) (from until liveEnd).count { it >= freshStart } else 0
                    val role: ChapterBarRole = if (freshInGroup == live) {
                        ChapterBarRole.NewChapter
                    } else {
                        val onSum = (from until liveEnd).sumOf { i ->
                            if (i >= freshStart && fresh > 0) 1.0 else chapterFills[i]
                        }
                        val fill = onSum / live.toDouble()
                        when {
                            fill >= 1.0 - 0.000_001 -> ChapterBarRole.Read
                            fill > 0.000_001 -> ChapterBarRole.Current(fill)
                            else -> ChapterBarRole.PostedUnread
                        }
                    }
                    grouped.add(ChapterBarItem(role = role, weight = weight))
                }
                groupIndex += 1
            }
            grouped
        }

        val widthForMetrics = if (availableWidth > 0f) availableWidth else scale.defaultAvailableWidth
        val barsAvailableWidth = if (showsOpenTotalDots) max(0f, widthForMetrics - OPEN_DOTS_WIDTH) else widthForMetrics
        val metrics = metrics(
            count = bars.size,
            availableWidth = barsAvailableWidth,
            nominalWidth = scale.nominalWidth,
            gap = scale.gap
        )
        val groupNote = if (chaptersPerBar > 1) "Each bar is $chaptersPerBar chapters" else null
        val label = spokenSummary(
            read = readCount,
            posted = safePosted,
            total = total,
            fresh = fresh,
            chaptersPerBar = chaptersPerBar,
            scale = scale
        )
        return ChapterBarLayout(
            bars = bars,
            trackFill = null,
            showsOpenTotalDots = showsOpenTotalDots,
            chaptersPerBar = chaptersPerBar,
            groupNote = groupNote,
            metrics = metrics,
            accessibilityLabel = label,
            source = source
        )
    }

    private fun spokenSummary(
        read: Int,
        posted: Int,
        total: Int?,
        fresh: Int,
        chaptersPerBar: Int,
        scale: ChapterBarScale
    ): String {
        val builder = StringBuilder()
        if (scale == ChapterBarScale.Row && read == 0 && fresh > 0) {
            builder.append("$fresh ${if (fresh == 1) "new chapter" else "new chapters"}, $posted posted")
        } else {
            builder.append("Chapters: $read read, $posted posted")
            if (fresh > 0) {
                builder.append(", $fresh new")
            }
        }
        if (total != null) {
            if (total > posted) {
                builder.append(", ${total - posted} not posted yet")
            }
        } else {
            builder.append(", total not set by the author")
        }
        if (chaptersPerBar > 1) {
            builder.append(". Each bar is $chaptersPerBar chapters")
        }
        return builder.toString()
    }

    /** Convenience forwarding to [layout]. */
    fun items(
        planned: Int?,
        posted: Int,
        progress: Double?,
        weights: List<Double>?,
        heights: List<Double>? = null,
        newChapterCount: Int = 0
    ): List<ChapterBarItem> = layout(
        planned = planned,
        posted = posted,
        progress = progress,
        weights = weights,
        heights = heights,
        newChapterCount = newChapterCount
    ).bars

    /**
     * "Ch 7 · 58%". The chapter is where the progress falls; the percent is the
     * whole downloaded work. Nothing at zero: a row must not claim a session
     * that never happened.
     */
    fun progressLabel(
        chapters: String,
        progress: Double?,
        isFinished: Boolean,
        weights: List<Int>? = null
    ): String? {
        val fraction: Double? = if (isFinished) 1.0 else progress
        if (fraction == null || fraction <= 0.0) return null
        val percent = (min(fraction, 1.0) * 100.0).roundToInt()
        val posted = ChapterBarModel.postedChapterCount(chapters)
        if (posted <= 0) return "$percent%"
        val chapter = readingChapter(posted = posted, progress = fraction, weights = weights?.map(Int::toDouble))
        return "Ch $chapter · $percent%"
    }

    /**
     * 1-based story chapter that contains [progress] across the posted chapters (equal
     * without [weights], which are Readium positions per chapter),
     * or the last posted chapter when the work is finished.
     */
    fun readingChapter(posted: Int, progress: Double, weights: List<Double>?): Int {
        if (posted <= 0) return 1
        val fraction = min(max(progress, 0.0), 1.0)
        if (fraction >= 1.0) return posted
        val known = weights?.takeIf { it.size == posted && it.all { w -> w > 0.0 } }
        val postedWeights = List(posted) { known?.get(it) ?: 1.0 }
        val total = postedWeights.sum()
        var remaining = fraction * total
        for (index in 0 until posted) {
            val weight = postedWeights[index]
            if (remaining < weight - 0.000_001 || index == posted - 1) {
                return index + 1
            }
            remaining -= weight
        }
        return posted
    }

    fun accessibilityLabel(items: List<ChapterBarItem>): String {
        val read = items.count { it.role is ChapterBarRole.Read }
        val posted = items.count { it.role !is ChapterBarRole.NotPosted }
        val unposted = items.size - posted
        val builder = StringBuilder("Chapters: $read read, $posted posted")
        if (unposted > 0) {
            builder.append(", $unposted not posted yet")
        }
        val fresh = items.count { it.role is ChapterBarRole.NewChapter }
        if (fresh > 0) {
            builder.append(", $fresh new")
        }
        return builder.toString()
    }
}

/**
 * Bars built from the chapter stat a work already stores, plus optional
 * per-chapter lengths. No lengths, or a count that disagrees with the posted
 * chapters, keeps every bar the same height.
 */
object ChapterBarModel {
    fun postedChapterCount(chapters: String): Int =
        chapters.substringBefore('/').trim().toIntOrNull() ?: 0

    fun totalChapterCount(chapters: String): Int? {
        val parts = chapters.split('/')
        if (parts.size != 2) return null
        val total = parts[1].trim().toIntOrNull() ?: return null
        return total.takeIf { it > 0 }
    }

    fun layout(
        chapters: String,
        read: Int? = null,
        chapterProgress: Double = 0.0,
        progress: Double?,
        isFinished: Boolean = false,
        weights: List<Int>?,
        heights: List<Int>? = null,
        newChapterCount: Int = 0,
        scale: ChapterBarScale = ChapterBarScale.Card,
        availableWidth: Float = 0f,
        fit: Int? = null
    ): ChapterBarLayout {
        val posted = postedChapterCount(chapters)
        val planned = totalChapterCount(chapters)
        return ChapterBarGeometry.layout(
            planned = planned,
            posted = posted,
            read = read,
            chapterProgress = chapterProgress,
            progress = progress,
            isFinished = isFinished,
            weights = weights?.map(Int::toDouble),
            heights = heights?.map(Int::toDouble),
            newChapterCount = newChapterCount,
            scale = scale,
            availableWidth = availableWidth,
            fit = fit
        )
    }

    fun items(
        chapters: String,
        progress: Double?,
        isFinished: Boolean = false,
        weights: List<Int>?,
        heights: List<Int>? = null,
        newChapterCount: Int = 0
    ): List<ChapterBarItem> = layout(
        chapters = chapters,
        progress = progress,
        isFinished = isFinished,
        weights = weights,
        heights = heights,
        newChapterCount = newChapterCount
    ).bars
}

/**
 * Draws what [ChapterBarGeometry.layout] returns: bars (with optional fading
 * dots for an unknown total and a grouping note when grouped) or a plain
 * progress track for a 1/1 work.
 */
@Composable
fun ChapterBars(
    layout: ChapterBarLayout,
    modifier: Modifier = Modifier,
    scale: ChapterBarScale = ChapterBarScale.Row,
    onGradient: Boolean = false,
    height: Dp? = null,
    accessibilityLabel: String? = null
) {
    val tokens = LocalKudosTokens.current
    val scaledRowHeight = with(LocalDensity.current) { 16.sp.toDp() }
    val resolvedHeight = height ?: if (scale == ChapterBarScale.Row) scaledRowHeight else scale.trackHeight
    val preview = layout.resolved(availableWidth = 0f, scale = scale)
    if (preview.isEmpty) return

    val readColor = if (onGradient) Color.White else tokens.accentInk
    val faint = tokens.primaryInk.copy(alpha = if (onGradient) 0.28f else 0.14f)
    val notPostedColor = tokens.primaryInk.copy(alpha = if (onGradient) 0.55f else 0.35f)
    val dotColor = if (onGradient) Color.White else tokens.secondaryInk
    val spoken = accessibilityLabel ?: preview.accessibilityLabel

    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .clearAndSetSemantics {
                if (spoken.isNotEmpty()) contentDescription = spoken
            }
    ) {
        val availableWidth = if (constraints.hasBoundedWidth && maxWidth.value > 0f) maxWidth.value else 0f
        val resolved = layout.resolved(availableWidth = availableWidth, scale = scale)
        if (resolved.isEmpty) return@BoxWithConstraints

        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            val trackFill = resolved.trackFill
            if (trackFill != null) {
                TrackView(
                    fill = trackFill,
                    scale = scale,
                    availableWidth = availableWidth,
                    height = resolvedHeight,
                    readColor = readColor,
                    trackColor = faint
                )
            } else {
                val metrics = resolved.metrics
                val tallest = resolved.bars.maxOfOrNull { it.weight } ?: 1.0
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(resolvedHeight),
                    horizontalArrangement = Arrangement.spacedBy(metrics.gap.dp),
                    verticalAlignment = Alignment.Bottom
                ) {
                    resolved.bars.forEach { item ->
                        ChapterBarGlyph(
                            item = item,
                            metrics = metrics,
                            tallest = tallest,
                            resolvedHeight = resolvedHeight,
                            readColor = readColor,
                            faint = faint,
                            notPostedColor = notPostedColor,
                            newChapterColor = tokens.accentInk
                        )
                    }
                    if (resolved.showsOpenTotalDots) {
                        OpenTotalDots(dotColor = dotColor)
                    }
                }
            }

            if (scale == ChapterBarScale.Card && resolved.groupNote != null) {
                Text(
                    text = resolved.groupNote,
                    fontSize = 12.sp,
                    color = if (onGradient) Color.White.copy(alpha = 0.85f) else tokens.secondaryInk
                )
            }
        }
    }
}

@Composable
fun ChapterBars(
    items: List<ChapterBarItem>,
    modifier: Modifier = Modifier,
    scale: ChapterBarScale = ChapterBarScale.Row,
    onGradient: Boolean = false,
    height: Dp? = null,
    accessibilityLabel: String? = null
) {
    ChapterBars(
        layout = ChapterBarLayout(items = items, scale = scale),
        modifier = modifier,
        scale = scale,
        onGradient = onGradient,
        height = height,
        accessibilityLabel = accessibilityLabel
    )
}

@Composable
private fun TrackView(
    fill: Double,
    scale: ChapterBarScale,
    availableWidth: Float,
    height: Dp,
    readColor: Color,
    trackColor: Color
) {
    val clamped = fill.coerceIn(0.0, 1.0).toFloat()
    val maxW = if (scale == ChapterBarScale.Row) {
        min(96f, if (availableWidth > 0f) availableWidth else 96f)
    } else {
        max(0f, if (availableWidth > 0f) availableWidth else scale.defaultAvailableWidth)
    }
    val capsule = RoundedCornerShape(percent = 50)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(height),
        contentAlignment = Alignment.CenterStart
    ) {
        Box(
            modifier = Modifier
                .width(maxW.dp)
                .height(6.dp)
                .clip(capsule)
                .background(trackColor)
        ) {
            if (clamped > 0f) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(clamped)
                        .fillMaxHeight()
                        .background(readColor)
                )
            }
        }
    }
}

@Composable
private fun OpenTotalDots(dotColor: Color) {
    Row(
        modifier = Modifier.padding(start = 3.dp, bottom = 3.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(4.dp).background(dotColor, CircleShape))
        Box(Modifier.size(4.dp).background(dotColor.copy(alpha = 0.7f), CircleShape))
        Box(Modifier.size(4.dp).background(dotColor.copy(alpha = 0.4f), CircleShape))
    }
}

@Composable
private fun ChapterBarGlyph(
    item: ChapterBarItem,
    metrics: ChapterBarMetrics,
    tallest: Double,
    resolvedHeight: Dp,
    readColor: Color,
    faint: Color,
    notPostedColor: Color,
    newChapterColor: Color
) {
    val fraction = if (tallest > 0.0) (item.weight / tallest).toFloat() else 1f
    val barHeight = max(2f, resolvedHeight.value * fraction).dp
    val shape = RoundedCornerShape(metrics.radius.dp)
    val barModifier = Modifier.size(width = metrics.width.dp, height = barHeight)

    when (val role = item.role) {
        ChapterBarRole.NotPosted -> {
            Canvas(modifier = barModifier) {
                val strokeWidth = 1.dp.toPx()
                val inset = strokeWidth / 2f
                val corner = metrics.radius.dp.toPx()
                drawRoundRect(
                    color = notPostedColor,
                    topLeft = Offset(inset, inset),
                    size = Size(max(0f, size.width - strokeWidth), max(0f, size.height - strokeWidth)),
                    cornerRadius = CornerRadius(corner, corner),
                    style = Stroke(
                        width = strokeWidth,
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 1.5.dp.toPx()))
                    )
                )
            }
        }
        is ChapterBarRole.Current -> {
            val clamped = role.fill.coerceIn(0.0, 1.0).toFloat()
            val fillHeight = max(if (clamped > 0f) 2f else 0f, barHeight.value * clamped).dp
            Box(
                modifier = barModifier
                    .clip(shape)
                    .background(faint),
                contentAlignment = Alignment.BottomCenter
            ) {
                if (fillHeight > 0.dp) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(fillHeight)
                            .background(readColor)
                    )
                }
            }
        }
        ChapterBarRole.Read -> {
            Box(modifier = barModifier.background(readColor, shape))
        }
        ChapterBarRole.PostedUnread -> {
            Box(modifier = barModifier.background(faint, shape))
        }
        ChapterBarRole.NewChapter -> {
            Box(modifier = barModifier.background(newChapterColor, shape))
        }
    }
}

/**
 * Chapter bars and the `"Ch 7 · 58%"` label for work rows.
 * Empty when the work has no chapter plan.
 */
@Composable
fun WorkChapterBarLine(
    layout: ChapterBarLayout,
    label: String? = null,
    modifier: Modifier = Modifier
) {
    if (layout.isEmpty) return
    val tokens = LocalKudosTokens.current
    val spoken = listOfNotNull(
        layout.accessibilityLabel.takeIf { it.isNotEmpty() },
        label?.takeIf { it.isNotEmpty() }
    ).joinToString(", ")

    Row(
        modifier = modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                if (spoken.isNotEmpty()) contentDescription = spoken
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        ChapterBars(
            layout = layout,
            scale = ChapterBarScale.Row,
            accessibilityLabel = spoken,
            modifier = Modifier.weight(1f)
        )
        if (label != null) {
            Text(
                text = label,
                fontSize = 12.sp,
                color = tokens.secondaryInk,
                maxLines = 1,
                softWrap = false,
                modifier = Modifier.clearAndSetSemantics {}
            )
        }
    }
}

/**
 * Legend below the detail card's chapter bars matching iOS `chapterLegendItems`.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ChapterBarsLegend(
    totalChapters: Int?,
    postedChapters: Int,
    isOneChapter: Boolean,
    onGradient: Boolean = false,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val textColor = if (onGradient) Color.White.copy(alpha = 0.85f) else tokens.secondaryInk
    val readSwatch = if (onGradient) Color.White else tokens.accentInk
    val postedSwatch = tokens.primaryInk.copy(alpha = if (onGradient) 0.30f else 0.14f)
    val notPostedColor = tokens.primaryInk.copy(alpha = if (onGradient) 0.65f else 0.40f)
    val dotColor = if (onGradient) Color.White else tokens.secondaryInk

    FlowRow(
        modifier = modifier.clearAndSetSemantics {},
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        LegendEntry(
            swatch = {
                Box(Modifier.size(10.dp).background(readSwatch, RoundedCornerShape(2.dp)))
            },
            label = "Read",
            textColor = textColor
        )
        LegendEntry(
            swatch = {
                Box(Modifier.size(10.dp).background(postedSwatch, RoundedCornerShape(2.dp)))
            },
            label = "Posted",
            textColor = textColor
        )
        if (totalChapters == null && postedChapters > 0) {
            LegendEntry(
                swatch = {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(Modifier.size(4.dp).background(dotColor, CircleShape))
                        Box(Modifier.size(4.dp).background(dotColor.copy(alpha = 0.7f), CircleShape))
                        Box(Modifier.size(4.dp).background(dotColor.copy(alpha = 0.4f), CircleShape))
                    }
                },
                label = "More to come, total not set",
                textColor = textColor
            )
        } else if (!isOneChapter) {
            LegendEntry(
                swatch = {
                    Canvas(Modifier.size(10.dp)) {
                        val strokeWidth = 1.dp.toPx()
                        val inset = strokeWidth / 2f
                        val corner = 2.dp.toPx()
                        drawRoundRect(
                            color = notPostedColor,
                            topLeft = Offset(inset, inset),
                            size = Size(size.width - strokeWidth, size.height - strokeWidth),
                            cornerRadius = CornerRadius(corner, corner),
                            style = Stroke(
                                width = strokeWidth,
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 1.5.dp.toPx()))
                            )
                        )
                    }
                },
                label = "Not posted yet",
                textColor = textColor
            )
        }
    }
}

@Composable
private fun LegendEntry(
    swatch: @Composable () -> Unit,
    label: String,
    textColor: Color
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        swatch()
        Text(
            text = label,
            fontSize = 12.sp,
            color = textColor,
            maxLines = 1
        )
    }
}
