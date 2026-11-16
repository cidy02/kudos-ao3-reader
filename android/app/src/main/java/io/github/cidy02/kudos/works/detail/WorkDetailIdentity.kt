package io.github.cidy02.kudos.works.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.ui.components.AO3StatusTint
import io.github.cidy02.kudos.ui.components.AO3TagPalette
import io.github.cidy02.kudos.ui.components.ChapterBarRole
import io.github.cidy02.kudos.ui.components.ChapterBarScale
import io.github.cidy02.kudos.ui.components.ChapterBars
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.WorkReadingOrDownloadRing
import io.github.cidy02.kudos.ui.subject.downloadDimmed
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale

/**
 * Port of iOS `WorkWarningStatus` (`WorkStatLabel.swift:857`).
 * AO3's Archive Warnings field is one of three mutually-exclusive states.
 */
sealed class WorkWarningStatus {
    data object None : WorkWarningStatus()
    data object Undisclosed : WorkWarningStatus()
    data class Present(val count: Int) : WorkWarningStatus()

    val figureText: String
        get() = when (this) {
            is None -> "None"
            is Undisclosed -> "Undisclosed"
            is Present -> count.toString()
        }

    fun figureColor(theme: ReaderTheme): Color = when (this) {
        is None -> AO3TagPalette.General
        is Undisclosed -> AO3TagPalette.Mature
        is Present -> AO3TagPalette.Explicit
    }

    companion object {
        fun from(rawWarnings: List<String>): WorkWarningStatus {
            if (rawWarnings.any { it.contains("Chose Not To Use", ignoreCase = true) }) {
                return Undisclosed
            }
            val real = rawWarnings.filter {
                !it.contains("No Archive Warnings", ignoreCase = true) &&
                    !it.contains("Chose Not To Use", ignoreCase = true)
            }
            return if (real.isEmpty()) None else Present(real.size)
        }
    }
}

/**
 * Port of iOS `WorkStat.ratingLetter` and `WorkStat.ratingColor` (`WorkStatLabel.swift:1009`).
 */
object WorkStatRating {
    fun letter(rating: String): String {
        return when (rating.trim()) {
            "General Audiences" -> "G"
            "Teen And Up Audiences" -> "T"
            "Mature" -> "M"
            "Explicit" -> "E"
            "Not Rated" -> "NR"
            else -> if (rating.isBlank()) "—" else rating.trim().take(2).uppercase()
        }
    }

    fun color(rating: String, isDark: Boolean): Color? {
        val fill = AO3StatusTint.rating(rating) ?: return null
        if (!isDark && rating.trim() == "Teen And Up Audiences") return AO3TagPalette.TeenTextOnLight
        return if (isDark) ReaderTheme.Dark.accentInk(fill) else fill
    }
}

/**
 * Port of iOS `WorkCompletionStatus` (`WorkStatLabel.swift:795`).
 */
enum class WorkCompletionStatus(val text: String, val shortText: String) {
    Complete("Complete", "Complete"),
    InProgress("In Progress", "WIP"),
    Unknown("Unknown", "Unknown");

    companion object {
        fun from(isComplete: Boolean?): WorkCompletionStatus {
            return when (isComplete) {
                true -> Complete
                false -> InProgress
                null -> Unknown
            }
        }
    }
}

/** Native author navigation shared by work bylines, including picker candidates. */
val LocalOpenAuthor = androidx.compose.runtime.staticCompositionLocalOf<(String) -> Unit> { {} }

@Composable
internal fun VerifiedAuthorByline(
    author: String,
    identities: String,
    authorNames: List<String> = io.github.cidy02.kudos.works.resolveTappableAuthorNames(null, author),
    compact: Boolean = false,
    onOpenAuthor: (String) -> Unit = LocalOpenAuthor.current,
    includesBy: Boolean = false
) {
    AuthorBylineRow(authorNames, author, LocalKudosTokens.current.scopePalette.controlInk,
        compact = compact, includesBy = includesBy,
        isLinked = { io.github.cidy02.kudos.network.ao3.author.AO3AuthorIdentities.byline(identities, it) != null },
        onOpenAuthor = { name ->
            io.github.cidy02.kudos.network.ao3.author.AO3AuthorIdentities.byline(identities, name)?.let(onOpenAuthor)
        })
}

/**
 * Artboard 1a's WorkDetailIdentityHeader (`WorkDetailIdentityBlock.swift:26`).
 * Kicker (primary fandom), 32sp title, and tappable author byline underneath.
 */
@Composable
fun WorkDetailIdentityHeader(
    title: String,
    author: String,
    authorNames: List<String>,
    fandoms: List<String>,
    palette: SubjectPalette,
    modifier: Modifier = Modifier,
    /** Whether a name opens its author: only one AO3 linked to an account (iOS `AO3AuthorBylineResolver`). */
    isLinked: (String) -> Boolean = { true },
    onOpenAuthor: (String) -> Unit = {}
) {
    val namedFandoms = fandoms.filter { it.isNotBlank() }
    val primaryFandom = HomeFacts.primaryFandom(namedFandoms) ?: "Work"
    val kickerCount = (namedFandoms.size - 1).coerceAtLeast(0)

    SubjectHeaderBlock(
        kicker = primaryFandom,
        title = title.ifBlank { "Work" },
        palette = palette,
        modifier = modifier,
        kickerTrailingCount = kickerCount,
        gutter = SubjectMetrics.headerGutter,
        trailing = {
            AuthorBylineRow(
                authorNames = authorNames,
                displayAuthor = author,
                accent = palette.controlInk,
                isLinked = isLinked,
                onOpenAuthor = onOpenAuthor
            )
        }
    )
}

/**
 * Individually tappable authors, with caption sizing for compact storage rows.
 */
@Composable
private fun AuthorBylineRow(
    authorNames: List<String>,
    displayAuthor: String,
    /** A name that opens its author is in the page's accent, as iOS draws it. It was grey, like "Anonymous". */
    accent: androidx.compose.ui.graphics.Color,
    isLinked: (String) -> Boolean,
    onOpenAuthor: (String) -> Unit,
    compact: Boolean = false,
    includesBy: Boolean = false
) {
    val tokens = LocalKudosTokens.current
    val fontSize = if (compact) 12.sp else 15.5.sp
    if (authorNames.isEmpty()) {
        Text(
            text = (if (includesBy) "by " else "") + displayAuthor.ifBlank { "Anonymous" },
            color = tokens.secondaryInk,
            fontSize = fontSize,
            maxLines = if (compact) 1 else 2,
            overflow = TextOverflow.Ellipsis
        )
        return
    }

    // A row that wraps: in one line a second co-author was cut to "Second Pse…" at twice the text
    // size, and a third or fourth would be at any size, cut and out of reach of a tap.
    @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
    androidx.compose.foundation.layout.FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        itemVerticalAlignment = Alignment.CenterVertically
    ) {
        if (includesBy) Text("by", color = tokens.secondaryInk, fontSize = fontSize)
        authorNames.forEachIndexed { index, name ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                // A name AO3 never linked to an account (a file from elsewhere, an old copy not yet
                // refreshed) is plain text, as on iOS: opened by its words it was a guessed address,
                // and could be somebody else's page.
                val linked = isLinked(name)
                Text(
                    text = name,
                    color = if (linked) accent else tokens.secondaryInk,
                    fontSize = fontSize,
                    fontWeight = if (compact) FontWeight.Normal else FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .weight(1f, fill = false)
                        .then(if (linked) Modifier
                            .semantics { contentDescription = "Author: $name" }
                            .clickable { onOpenAuthor(name) } else Modifier)
                )
                if (index < authorNames.lastIndex) {
                    Text(
                        text = ",",
                        color = tokens.secondaryInk,
                        fontSize = fontSize
                    )
                }
            }
        }
    }
}

/**
 * Owner's Version E short reading card (`WorkDetailIdentityBlock.swift`): dark fandom-hue
 * gradient surface, optional 40dp dial, `Ch N, <name>` title, chapter bars + legend, and
 * primary pill beside circular `Contents` / `Read Aloud` / optional `Update download` actions.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WorkDetailResumeCard(
    actionTitle: String,
    model: ResumeCardModel,
    chapterLengths: ChapterLengths?,
    isBusy: Boolean,
    downloadFraction: Double?,
    canUpdateDownload: Boolean,
    onPrimaryClick: () -> Unit,
    onContentsClick: () -> Unit,
    onReadAloudClick: () -> Unit,
    onUpdateDownloadClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val accessible = isAccessibilityFontScale()
    val (startColor, endColor) = workArtGradientColors(model.fandoms, model.title)
    val items = model.chapterItems(chapterLengths)
    val initial = model.title.trim().firstOrNull()?.uppercaseChar()?.toString()
    val shape = RoundedCornerShape(16.dp)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .downloadDimmed(if (downloadFraction != null) 1f else 0f)
            .padding(horizontal = SubjectMetrics.panelGutter)
            .clip(shape)
            .background(Brush.linearGradient(listOf(startColor, endColor)), shape)
            .border(0.5.dp, Color.White.copy(alpha = 0.14f), shape)
    ) {
        if (initial != null) {
            Text(
                text = initial,
                fontFamily = FontFamily.Serif,
                fontWeight = FontWeight.Bold,
                fontSize = 112.sp,
                color = Color.White.copy(alpha = 0.08f),
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .offset(x = (-10).dp, y = 14.dp)
                    .clearAndSetSemantics {}
            )
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (downloadFraction != null || model.progress != null) {
                    WorkReadingOrDownloadRing(
                        downloadFraction = downloadFraction,
                        progress = model.progress,
                        state = null,
                        diameter = if (accessible) 54.dp else 40.dp,
                        tint = Color.White
                    )
                }

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    Text(
                        text = model.detailChapterName,
                        fontSize = 15.5.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White,
                        maxLines = if (accessible) 3 else 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    model.detailProgressLine?.let { line ->
                        Text(
                            text = line,
                            fontSize = 12.5.sp,
                            color = Color.White.copy(alpha = 0.78f),
                            maxLines = if (accessible) 3 else 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }

            if (items.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    val barsModifier = if (items.size in 1..9) {
                        Modifier
                            .widthIn(max = (items.size * 30).dp)
                            .fillMaxWidth()
                    } else {
                        Modifier.fillMaxWidth()
                    }
                    ChapterBars(
                        items = items,
                        scale = ChapterBarScale.Card,
                        onGradient = true,
                        height = 34.dp,
                        accessibilityLabel = model.chapterBarsLabel,
                        modifier = barsModifier
                    )
                    ChapterBarsLegend(hasUnposted = items.any { it.role is ChapterBarRole.NotPosted })
                }
            }

            val circleButtons: @Composable () -> Unit = {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ResumeCircleAction(
                        icon = Icons.AutoMirrored.Filled.List,
                        accessibilityLabel = "Contents",
                        enabled = !isBusy,
                        badge = null,
                        badgeInk = startColor,
                        onClick = onContentsClick
                    )
                    ResumeCircleAction(
                        icon = Icons.AutoMirrored.Filled.VolumeUp,
                        accessibilityLabel = "Read Aloud",
                        enabled = !isBusy,
                        badge = null,
                        badgeInk = startColor,
                        onClick = onReadAloudClick
                    )
                    if (canUpdateDownload && onUpdateDownloadClick != null) {
                        val spoken = "Update download, ${model.updateChapterValue}"
                        ResumeCircleAction(
                            icon = Icons.Filled.Download,
                            accessibilityLabel = spoken,
                            enabled = !isBusy,
                            badge = model.clampedNewChapterCount.takeIf { it > 0 }?.toString(),
                            badgeInk = startColor,
                            onClick = onUpdateDownloadClick
                        )
                    }
                }
            }

            if (accessible) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    ResumePrimaryPill(
                        actionTitle = actionTitle,
                        spokenTitle = "$actionTitle, ${model.detailChapterName}",
                        ink = startColor,
                        isBusy = isBusy,
                        accessible = true,
                        onClick = onPrimaryClick,
                        modifier = Modifier.fillMaxWidth()
                    )
                    circleButtons()
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ResumePrimaryPill(
                        actionTitle = actionTitle,
                        spokenTitle = "$actionTitle, ${model.detailChapterName}",
                        ink = startColor,
                        isBusy = isBusy,
                        accessible = false,
                        onClick = onPrimaryClick,
                        modifier = Modifier.weight(1f)
                    )
                    circleButtons()
                }
            }
        }
    }
}

@Composable
private fun ResumePrimaryPill(
    actionTitle: String,
    spokenTitle: String,
    ink: Color,
    isBusy: Boolean,
    accessible: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clip(CircleShape)
            .background(Color.White, CircleShape)
            .clickable(enabled = !isBusy, role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp)
            .semantics { contentDescription = spokenTitle },
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (isBusy) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                color = ink,
                strokeWidth = 2.dp
            )
        } else {
            Icon(
                imageVector = Icons.Filled.PlayArrow,
                contentDescription = null,
                tint = ink,
                modifier = Modifier.size(18.dp)
            )
        }
        Text(
            text = actionTitle,
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            color = ink,
            maxLines = if (accessible) 2 else 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(start = 6.dp)
        )
    }
}

@Composable
private fun ResumeCircleAction(
    icon: ImageVector,
    accessibilityLabel: String,
    enabled: Boolean,
    badge: String?,
    badgeInk: Color,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier
            .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .clip(CircleShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics(mergeDescendants = true) { contentDescription = accessibilityLabel },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.16f), CircleShape)
                .border(1.dp, Color.White.copy(alpha = 0.24f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = Color.White.copy(alpha = if (enabled) 1f else 0.55f),
                modifier = Modifier.size(20.dp)
            )
        }
        if (badge != null) {
            Text(
                text = badge,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                color = badgeInk,
                maxLines = 1,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .background(Color.White, CircleShape)
                    .padding(horizontal = 4.dp, vertical = 1.dp)
                    .clearAndSetSemantics {}
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChapterBarsLegend(hasUnposted: Boolean) {
    FlowRow(
        modifier = Modifier.clearAndSetSemantics {},
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        LegendChip(
            swatch = {
                Box(
                    Modifier
                        .size(width = 7.dp, height = 7.dp)
                        .background(Color.White, RoundedCornerShape(1.5.dp))
                )
            },
            label = "Read"
        )
        LegendDot()
        LegendChip(
            swatch = {
                Box(
                    Modifier
                        .size(width = 3.dp, height = 7.dp)
                        .background(Color.White.copy(alpha = 0.42f), RoundedCornerShape(1.dp))
                )
            },
            label = "Posted"
        )
        if (hasUnposted) {
            LegendDot()
            LegendChip(
                swatch = {
                    Box(
                        Modifier
                            .size(width = 7.dp, height = 7.dp)
                            .border(1.dp, Color.White.copy(alpha = 0.45f), RoundedCornerShape(1.5.dp))
                    )
                },
                label = "Not posted yet"
            )
        }
    }
}

@Composable
private fun LegendChip(
    swatch: @Composable () -> Unit,
    label: String
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        swatch()
        Text(
            text = label,
            fontSize = 11.sp,
            color = Color.White.copy(alpha = 0.78f),
            maxLines = 1
        )
    }
}

@Composable
private fun LegendDot() {
    Text(
        text = "·",
        fontSize = 11.sp,
        color = Color.White.copy(alpha = 0.6f),
        maxLines = 1
    )
}
