package io.github.cidy02.kudos.ui.subject

import io.github.cidy02.kudos.ui.components.hiddenMatureWorkSemantics
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.library.readingProgressFraction
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.GeneratedCoverRecipe
import io.github.cidy02.kudos.ui.components.GeneratedCoverView
import io.github.cidy02.kudos.ui.components.CoverEpub
import io.github.cidy02.kudos.ui.components.rememberCoverEpub
import io.github.cidy02.kudos.ui.components.generatedCoverRecipe
import io.github.cidy02.kudos.ui.components.statusChips
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.DownloadQueueStatus
import io.github.cidy02.kudos.works.EMBEDDED_COVER_ART_IMAGE_TAG
import io.github.cidy02.kudos.works.WorkTags
import kotlin.math.roundToInt
import io.github.cidy02.kudos.works.rememberWorkEmbeddedCoverArt

/** `CarouselCardMetrics`: 164 × 164√2, work corner 16, queue tile corner 12. */
object HomeCardMetrics {
    val width = 164.dp
    val height = 231.93.dp
    val radius = 16.dp
    val tileRadius = 12.dp
}

private data class ScaledHomeCardSize(val width: Dp, val height: Dp)

/** iOS `ScaledCarouselCardSize`: scale proportionally, then clamp to the window. */
@Composable
private fun scaledHomeCardSize(): ScaledHomeCardSize {
    val scale = carouselCardScale()
    return ScaledHomeCardSize(HomeCardMetrics.width * scale, HomeCardMetrics.height * scale)
}

/**
 * How much a carousel card [width] wide grows with the reader's text size: with the text, then
 * clamped so the card still fits the window. The cover cards have always done this; the queue deck
 * and Browse's Jump Back In cards kept their size and cut their titles to "Doct…" at twice the
 * text size.
 */
@Composable
fun carouselCardScale(width: Dp = HomeCardMetrics.width): Float {
    val fontScale = LocalDensity.current.fontScale
    val maxWidth = (LocalConfiguration.current.screenWidthDp.dp - 32.dp).coerceAtLeast(1.dp)
    return fontScale * minOf(1f, maxWidth.value / (width.value * fontScale))
}

enum class HomeStatusArrangement { Grid, Strip, Row }

@Composable
fun rememberWorkDownloadFraction(
    work: SavedWork,
    queue: DownloadQueue? = io.github.cidy02.kudos.ui.components.LocalWorkRowEnvironment.current?.downloads
): Double? = rememberDownloadFraction(work.id, work.ao3WorkID?.toLong() ?: WorkTags.ao3WorkIdFromUrl(work.sourceUrl), queue)

@Composable
fun rememberDownloadFraction(workId: String?, ao3WorkId: Long?, queue: DownloadQueue?): Double? {
    if (queue == null) return null
    val instant by queue.instantDownloads.collectAsState()
    val items by queue.items.collectAsState()
    instant[workId]?.let { return it }
    return items.firstOrNull { item ->
        item.ao3WorkId == ao3WorkId &&
            (item.status == DownloadQueueStatus.Queued || item.status == DownloadQueueStatus.Downloading)
    }?.fraction
}

/**
 * Shared portrait cover. Port of iOS `WorkCoverCard` / `WorkSummaryCardSurface`,
 * shared across Home and Library.
 */
@Composable
fun SubjectWorkCoverCard(
    work: SavedWork,
    obscured: Boolean,
    modifier: Modifier = Modifier,
    downloadFraction: Double? = rememberWorkDownloadFraction(work),
    footer: String? = null,
    progress: Double? = null,
    isSelecting: Boolean = false,
    isSelected: Boolean = false
) {
    val tokens = LocalKudosTokens.current
    val recipe = remember(
        work.id,
        work.ao3WorkID,
        work.sourceUrl,
        work.ao3SeriesID,
        work.seriesPosition,
        work.seriesUrl,
        work.title,
        work.author,
        work.authorIdentitiesJSON,
        work.workFandoms,
        work.workTags,
        work.workFreeforms,
        work.workTagsFetched,
        work.wordCount,
        work.chapters,
        work.isComplete,
        work.datePublished,
        work.dateUpdated
    ) {
        work.generatedCoverRecipe()
    }
    val epub = rememberCoverEpub(work, enabled = !obscured)
    val resolvedProgress = HomeFacts.resolvedCoverProgress(
        explicit = progress,
        footer = footer,
        isFinished = work.isFinished,
        saved = work.readingProgressFraction()
    )
    val accessibility = isAccessibilityFontScale()
    val metaLine = remember(resolvedProgress, work.chapters, footer, work.wordCount) {
        workCoverMetaLine(
            progress = resolvedProgress,
            chapters = work.chapters,
            footer = footer,
            words = work.wordCount
        )
    }
    val plusBadge = remember(footer) { footer?.let(::updateMarkerText) }

    WorkSummaryCoverSurface(
        recipe = recipe,
        modifier = modifier,
        epub = epub,
        obscured = obscured,
        isSelecting = isSelecting,
        isSelected = isSelected,
        downloadFraction = downloadFraction
    ) {
        if (obscured) {
            Text(
                text = "Hidden mature work",
                color = tokens.secondaryInk,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        } else {
            if (downloadFraction != null) {
                CoverProgressBar(
                    progress = downloadFraction,
                    accessibilityLabel = "Download progress"
                )
            } else if (resolvedProgress != null) {
                CoverProgressBar(
                    progress = resolvedProgress,
                    accessibilityLabel = "Reading progress"
                )
            }
            HomeStatusTray(
                rating = work.rating,
                categories = work.workCategories,
                warnings = work.workWarnings,
                isComplete = work.knownCompletion,
                arrangement = HomeStatusArrangement.Strip,
                tileSize = 24.dp,
                announces = true,
                modifier = Modifier.fillMaxWidth()
            )
            if (metaLine != null || plusBadge != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = metaLine.orEmpty(),
                        color = tokens.secondaryInk,
                        fontSize = 12.sp,
                        maxLines = if (accessibility) Int.MAX_VALUE else 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    if (plusBadge != null) {
                        UpdateMarker(plusBadge, spoken = newChaptersSpoken(plusBadge))
                    }
                }
            }
            work.preservationBadge?.let { badge ->
                Text(
                    text = badge,
                    color = tokens.secondaryInk,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

/** Remote subscription / author card. Uses the same generated cover and slot layout as local cards. */
@Composable
fun SubjectRemoteCoverCard(
    summary: AO3WorkSummary,
    modifier: Modifier = Modifier,
    showsProvenance: Boolean = false,
    obscured: Boolean = false
) {
    val tokens = LocalKudosTokens.current
    val accessibility = isAccessibilityFontScale()
    val recipe = remember(summary) { summary.generatedCoverRecipe() }
    val remoteMeta = remember(summary.wordCount, summary.chapters, summary.updatedDate) {
        buildList {
            summary.wordCount?.takeIf { it > 0 }?.let { add("${it.compactCount()} words") }
            if (summary.chapters.isNotBlank()) add(summary.chapters)
            if (summary.updatedDate.isNotBlank()) add(summary.updatedDate)
        }.joinToString(" · ").ifEmpty { null }
    }

    WorkSummaryCoverSurface(
        recipe = recipe,
        modifier = modifier,
        obscured = obscured,
        showsProvenance = showsProvenance
    ) {
        if (obscured) {
            Text(
                text = "Hidden mature work",
                color = tokens.secondaryInk,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        } else {
            HomeStatusTray(
                rating = summary.rating,
                categories = summary.categories,
                warnings = summary.warnings,
                isComplete = summary.isComplete,
                arrangement = HomeStatusArrangement.Strip,
                tileSize = 24.dp,
                announces = true,
                modifier = Modifier.fillMaxWidth()
            )
            if (remoteMeta != null) {
                Text(
                    text = remoteMeta,
                    color = tokens.secondaryInk,
                    fontSize = 12.sp,
                    maxLines = if (accessibility) Int.MAX_VALUE else 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
private fun WorkSummaryCoverSurface(
    recipe: GeneratedCoverRecipe,
    modifier: Modifier = Modifier,
    epub: CoverEpub? = null,
    obscured: Boolean = false,
    isSelecting: Boolean = false,
    isSelected: Boolean = false,
    showsProvenance: Boolean = false,
    downloadFraction: Double? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    val cardSize = scaledHomeCardSize()
    val coverShape = RoundedCornerShape(HomeCardMetrics.radius)
    val dim by animateFloatAsState(
        targetValue = if (downloadFraction != null) 1f else 0f,
        animationSpec = tween(250),
        label = "coverDim"
    )
    BoxWithConstraints(
        modifier = modifier
            .padding(top = 2.dp, bottom = 8.dp)
            .downloadDimmed(dim)
    ) {
        val coverWidth = when {
            constraints.hasBoundedWidth && constraints.minWidth == constraints.maxWidth -> maxWidth
            constraints.hasBoundedWidth -> minOf(cardSize.width, maxWidth)
            else -> cardSize.width
        }
        val coverHeight = coverWidth * 1.42f
        Column(
            modifier = Modifier
                .width(coverWidth)
                .hiddenMatureWorkSemantics(obscured, isSelecting, isSelected),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Box(modifier = Modifier.size(coverWidth, coverHeight)) {
                GeneratedCoverView(
                    recipe = recipe,
                    width = coverWidth,
                    height = coverHeight,
                    epub = if (obscured) null else epub,
                    showsWords = !obscured,
                    showsArt = !obscured,
                    cornerRadius = HomeCardMetrics.radius,
                    modifier = if (obscured) Modifier.blur(6.dp) else Modifier
                )
                if (obscured && !isSelecting) {
                    RevealCapsule(Modifier.align(Alignment.Center))
                }
                if (showsProvenance && !obscured) {
                    Text(
                        text = "AO3",
                        color = Color.White.copy(alpha = 0.8f),
                        fontSize = 8.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 0.64.sp,
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .padding(10.dp)
                            .background(Color.Black.copy(alpha = 0.4f), CircleShape)
                            .padding(horizontal = 6.dp, vertical = 3.dp)
                            .clearAndSetSemantics { contentDescription = "From AO3" }
                    )
                }
                if (isSelecting) {
                    SelectionChrome(isSelected = isSelected, shape = coverShape)
                }
            }
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(6.dp),
                content = content
            )
        }
    }
}

@Composable
private fun CoverProgressBar(
    progress: Double,
    accessibilityLabel: String
) {
    val tokens = LocalKudosTokens.current
    val fraction = progress.coerceIn(0.0, 1.0).toFloat()
    val percent = (fraction * 100f).roundToInt()
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(3.dp)
            .clip(CircleShape)
            .background(tokens.glassFill(0.14))
            .clearAndSetSemantics { contentDescription = "$accessibilityLabel: $percent percent" }
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction)
                .height(3.dp)
                .clip(CircleShape)
                .background(tokens.accentInk)
        )
    }
}

private fun workCoverMetaLine(
    progress: Double?,
    chapters: String,
    footer: String?,
    words: Int
): String? {
    if (progress != null) {
        val posted = chapters.substringBefore('/').trim().toIntOrNull() ?: 0
        val total = chapters.substringAfter('/', "").trim().takeIf { it.isNotEmpty() && it != "?" }?.toIntOrNull()
        val fraction = progress.coerceIn(0.0, 1.0)
        val parts = buildList {
            if (posted > 0) {
                val current = (kotlin.math.round(fraction * (posted - 1)).toInt() + 1).coerceIn(1, posted)
                add(if (total != null) "Ch $current of $total" else "Ch $current")
            }
            add("${(fraction * 100.0).roundToInt()}%")
        }
        return parts.joinToString(" · ")
    }
    if (footer != null && updateMarkerText(footer) == null) return footer
    return buildList {
        if (words > 0) add("${words.compactCount()} words")
        if (chapters.isNotBlank()) add(chapters)
    }.joinToString(" · ").ifEmpty { null }
}

@Composable
fun HomeCoverSkeleton(modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(HomeCardMetrics.radius)
    val cardSize = scaledHomeCardSize()
    Box(
        modifier
            .padding(top = 2.dp, bottom = 8.dp)
            .size(cardSize.width, cardSize.height)
            .then(cardShadow(tokens.theme, shape, hero = false))
            .clip(shape)
            .background(tokens.cardFill)
    ) {
        SubjectCoverSkeletonContent()
    }
}

/** High-contrast white ink tokens for text layered over a scrimmed photo cover in any theme. */
internal fun photoOverlayTokens(tokens: KudosTokens): KudosTokens = tokens.copy(
    theme = ReaderTheme.Dark,
    primaryInk = Color.White,
    secondaryInk = Color.White.copy(alpha = 0.80f),
    tertiaryInk = Color.White.copy(alpha = 0.55f),
    accentInk = ReaderTheme.Dark.accentInk(tokens.accent)
)

@Composable
internal fun CoverSurface(
    palette: SubjectPalette,
    shape: RoundedCornerShape,
    hero: Boolean,
    modifier: Modifier = Modifier,
    coverArt: ImageBitmap? = null,
    content: @Composable () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Box(
        modifier
            .then(cardShadow(tokens.theme, shape, hero))
            .clip(shape)
            .background(tokens.cardFill)
            .background(palette.cardWash)
            .border(
                0.5.dp,
                if (coverArt != null) Color.White.copy(alpha = 0.14f) else palette.cardBorder,
                shape
            )
    ) {
        if (coverArt != null) {
            Image(
                bitmap = coverArt,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .matchParentSize()
                    .testTag(EMBEDDED_COVER_ART_IMAGE_TAG)
            )
            val scrim = if (hero) {
                Brush.verticalGradient(
                    0f to Color.Black.copy(alpha = 0.62f),
                    0.5f to Color.Black.copy(alpha = 0.56f),
                    1f to Color.Black.copy(alpha = 0.68f)
                )
            } else {
                Brush.verticalGradient(
                    0f to Color.Black.copy(alpha = 0.58f),
                    0.45f to Color.Black.copy(alpha = 0.32f),
                    1f to Color.Black.copy(alpha = 0.72f)
                )
            }
            Box(
                Modifier
                    .matchParentSize()
                    .background(scrim)
            )
            CompositionLocalProvider(LocalKudosTokens provides photoOverlayTokens(tokens)) {
                content()
            }
        } else {
            content()
        }
    }
}

/**
 * iOS `WorkStatusIconGrid`: four solid AO3 required-tag tiles.
 *
 * The full 2×2 sits on one rounded backing (T-479b / A-479b). A strip does not,
 * and a card that already paints a dark tray passes `backed = false`.
 * Purely decorative unless [announces] is true, so standard work rows do not
 * announce both the grid and the text chips below the summary.
 */
@Composable
fun HomeStatusTray(
    rating: String,
    categories: List<String>,
    warnings: List<String>,
    isComplete: Boolean?,
    arrangement: HomeStatusArrangement = HomeStatusArrangement.Grid,
    tileSize: Dp = 24.dp,
    modifier: Modifier = Modifier,
    announces: Boolean = false,
    backed: Boolean = true
) {
    val tokens = LocalKudosTokens.current
    val fontScale = LocalDensity.current.fontScale.coerceAtMost(1.8f)
    val scaledTileSize = tileSize * fontScale
    val tiles = listOf(
        io.github.cidy02.kudos.ui.components.WorkSymbolTile.rating(rating, tokens.theme.isDarkFamily),
        io.github.cidy02.kudos.ui.components.WorkSymbolTile.category(categories, tokens.theme.isDarkFamily),
        io.github.cidy02.kudos.ui.components.WorkSymbolTile.warnings(warnings, tokens.theme.isDarkFamily),
        io.github.cidy02.kudos.ui.components.WorkSymbolTile.completion(isComplete, tokens.theme.isDarkFamily)
    )
    val gap = scaledTileSize * io.github.cidy02.kudos.ui.components.WorkSymbolGeometry.GapRatio
    val accessibleModifier = if (announces) {
        val spoken = buildList {
            add(rating.ifBlank { "Not rated" })
            add(if (categories.isEmpty()) "No category" else "Categories: ${categories.joinToString(", ")}")
            add(statusChips("", emptyList(), warnings, isComplete).drop(1).first().accessibilityLabel.orEmpty())
            add(if (isComplete == true) "Status: complete" else if (isComplete == false) "Status: work in progress" else "Status: unknown")
        }.joinToString(", ")
        modifier.clearAndSetSemantics { contentDescription = spoken }
    } else {
        modifier.clearAndSetSemantics {}
    }
    val showBacking = io.github.cidy02.kudos.ui.components.WorkSymbolGeometry.drawsBacking(arrangement, backed)
    val framedModifier = if (showBacking) {
        val side = scaledTileSize.value
        val pad = io.github.cidy02.kudos.ui.components.WorkSymbolGeometry.backingPadding(side).dp
        val radius = io.github.cidy02.kudos.ui.components.WorkSymbolGeometry.backingCornerRadius(side).dp
        accessibleModifier
            .background(
                io.github.cidy02.kudos.ui.components.WorkSymbolGeometry.backingFill(tokens.theme),
                RoundedCornerShape(radius)
            )
            .padding(pad)
    } else {
        accessibleModifier
    }
    if (arrangement == HomeStatusArrangement.Grid) {
        Column(
            framedModifier,
            verticalArrangement = Arrangement.spacedBy(gap)
        ) {
            tiles.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                    pair.forEach {
                        io.github.cidy02.kudos.ui.components.WorkSymbolTileView(it, scaledTileSize)
                    }
                }
            }
        }
    } else {
        Row(
            framedModifier,
            horizontalArrangement = if (arrangement == HomeStatusArrangement.Row) {
                Arrangement.spacedBy(gap)
            } else {
                Arrangement.SpaceBetween
            },
            verticalAlignment = Alignment.CenterVertically
        ) {
            tiles.forEach { io.github.cidy02.kudos.ui.components.WorkSymbolTileView(it, scaledTileSize) }
        }
    }
}

/**
 * The app's update marker (owner, canvas v165, both apps; iOS `UpdateMarker`): the words, then
 * an 8dp dot, filled in [KudosTokens.accentInk] for a confirmed update and outlined for a hedge
 * ("Updated"). Primary ink: 13sp is not large text. Counts on an icon stay Material badges.
 */
@Composable
internal fun UpdateMarker(text: String, confirmed: Boolean = true, spoken: String = text) {
    val tokens = LocalKudosTokens.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.clearAndSetSemantics { contentDescription = spoken }
    ) {
        Text(text, color = tokens.primaryInk, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1)
        Box(
            Modifier
                .size(8.dp)
                .background(if (confirmed) tokens.accentInk else Color.Transparent, CircleShape)
                .then(if (confirmed) Modifier else Modifier.border(1.5.dp, tokens.secondaryInk, CircleShape))
        )
    }
}

/** iOS `WorkCoverMetadata.updateBadge(from:)`: a footer that starts with "+" shows as its "+N". */
internal fun updateMarkerText(footer: String): String? {
    if (!footer.startsWith("+")) return null
    val count = footer.drop(1).takeWhile { it.isDigit() }
    return if (count.isEmpty()) footer else "+$count"
}

internal fun newChaptersSpoken(plus: String): String =
    when (val count = plus.drop(1).toIntOrNull()) {
        null -> plus
        1 -> "1 new chapter"
        else -> "$count new chapters"
    }

@Composable
internal fun UpdateBadge(text: String) {
    val tokens = LocalKudosTokens.current
    Text(
        text = text.uppercase(),
        color = tokens.primaryInk,
        fontSize = 11.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 0.4.sp,
        maxLines = 1,
        modifier = Modifier
            .background(tokens.glassFill(0.16), CircleShape)
            .padding(horizontal = 9.dp, vertical = 4.dp)
    )
}

@Composable
internal fun RevealCapsule(modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier
            .background(tokens.glassFill(0.28), CircleShape)
            .border(0.5.dp, tokens.glassStroke(0.16), CircleShape)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(Icons.Outlined.VisibilityOff, contentDescription = null, tint = tokens.secondaryInk, modifier = Modifier.size(14.dp))
        Text("Tap to reveal", color = tokens.secondaryInk, fontSize = 12.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
internal fun BoxScope.SelectionChrome(isSelected: Boolean, shape: RoundedCornerShape) {
    val tokens = LocalKudosTokens.current
    if (isSelected) {
        Box(
            Modifier
                .matchParentSize()
                .border(2.dp, tokens.accent, shape)
        )
    }
    Box(
        Modifier
            .align(Alignment.TopEnd)
            .padding(8.dp)
            .size(22.dp)
            .background(if (isSelected) tokens.accent else tokens.glassFill(0.2), CircleShape)
            .border(1.dp, if (isSelected) tokens.accent else tokens.glassStroke(), CircleShape),
        contentAlignment = Alignment.Center
    ) {
        if (isSelected) {
            Icon(Icons.Filled.Check, contentDescription = "Selected", tint = Color.White, modifier = Modifier.size(14.dp))
        }
    }
}

private fun cardShadow(theme: ReaderTheme, shape: RoundedCornerShape, hero: Boolean): Modifier {
    val (color, elevation) = when (theme) {
        ReaderTheme.Oled -> return Modifier
        ReaderTheme.Dark -> Color.Black.withOpacity(0.34) to 8.dp
        ReaderTheme.Light -> Color.Black.withOpacity(0.13) to 8.dp
        ReaderTheme.Sepia -> Color(red = 0.34f, green = 0.22f, blue = 0.08f).withOpacity(0.22) to 8.dp
    }
    val raised = if (hero) elevation + 6.dp else elevation
    return Modifier.shadow(raised, shape, clip = false, ambientColor = color, spotColor = color)
}
