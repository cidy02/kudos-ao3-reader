package io.github.cidy02.kudos.ui.subject

import io.github.cidy02.kudos.ui.components.hiddenMatureWorkSemantics
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.library.readingProgressFraction
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.components.AO3StatusTint
import io.github.cidy02.kudos.works.DownloadQueue
import io.github.cidy02.kudos.works.DownloadQueueStatus
import io.github.cidy02.kudos.works.WorkTags

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

enum class HomeStatusArrangement { Grid, Strip }

@Composable
fun rememberWorkDownloading(work: SavedWork, queue: DownloadQueue?): Boolean {
    if (queue == null) return false
    val items by queue.items.collectAsState()
    val ao3Id = WorkTags.ao3WorkIdFromUrl(work.sourceUrl) ?: return false
    return items.any { item ->
        item.ao3WorkId == ao3Id &&
            (item.status == DownloadQueueStatus.Queued || item.status == DownloadQueueStatus.Downloading)
    }
}

/**
 * Shared portrait cover. Port of iOS `WorkCoverCard` / `WorkSummaryCardSurface`,
 * shared across Home and Library.
 */
@Composable
fun SubjectWorkCoverCard(
    work: SavedWork,
    obscured: Boolean,
    downloading: Boolean,
    modifier: Modifier = Modifier,
    footer: String? = null,
    progress: Double? = null,
    isSelecting: Boolean = false,
    isSelected: Boolean = false
) {
    val tokens = LocalKudosTokens.current
    val cardSize = scaledHomeCardSize()
    val ringDiameter = SubjectMetrics.ringDiameter * LocalDensity.current.fontScale
    val hue = HomeFacts.workHue(work.workFandoms, work.title)
    val palette = SubjectPalette.fromHue(hue, tokens.theme)
    val shape = RoundedCornerShape(HomeCardMetrics.radius)
    val dim by animateFloatAsState(
        targetValue = if (downloading) 1f else 0f,
        animationSpec = tween(250),
        label = "coverDim"
    )
    val resolved = HomeFacts.resolvedCoverProgress(
        explicit = progress,
        footer = footer,
        isFinished = work.isFinished,
        saved = work.readingProgressFraction()
    )
    Box(
        modifier
            .padding(top = 2.dp, bottom = 8.dp)
            .size(cardSize.width, cardSize.height)
            .downloadDimmed(dim)
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .then(if (obscured) Modifier.blur(8.dp) else Modifier)
                .hiddenMatureWorkSemantics(obscured, isSelecting)
        ) {
            CoverSurface(palette = palette, shape = shape, hero = false) {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(5.dp)
                ) {
                    val fandom = HomeFacts.primaryFandom(work.workFandoms)
                    if (fandom != null) {
                        SubjectKicker(text = fandom, palette = palette, size = 9.sp)
                    }
                    Text(
                        text = work.title,
                        color = tokens.primaryInk,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        // iOS caps the title at two lines without reserving the second,
                        // so a one-line title leaves the ring its full 68dp.
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        when {
                            resolved != null || downloading -> WorkReadingOrDownloadRing(
                                downloading = downloading,
                                progress = resolved,
                                state = if ((resolved ?: 0.0) >= 1.0) "Finished" else "Reading",
                                diameter = ringDiameter
                            )
                            footer != null -> UpdateBadge(footer)
                        }
                    }
                    if (work.author.isNotBlank()) {
                        Text(
                            text = work.author,
                            color = tokens.primaryInk.withOpacity(0.78),
                            fontSize = 12.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                    HomeStatusTray(
                        rating = work.rating,
                        categories = work.workCategories,
                        warnings = work.workWarnings,
                        isComplete = work.isComplete,
                        arrangement = HomeStatusArrangement.Strip,
                        tileSize = 24.dp,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        }
        if (obscured && !isSelecting) {
            RevealCapsule(Modifier.align(Alignment.Center))
        }
        if (isSelecting) {
            SelectionChrome(isSelected = isSelected, shape = shape)
        }
    }
}

/** Remote subscription card. Centre slot is the AO3 updated date, not a reading ring. */
@Composable
fun SubjectRemoteCoverCard(
    summary: AO3WorkSummary,
    modifier: Modifier = Modifier,
    showsProvenance: Boolean = false
) {
    val tokens = LocalKudosTokens.current
    val cardSize = scaledHomeCardSize()
    val hue = HomeFacts.workHue(summary.fandoms, summary.title)
    val palette = SubjectPalette.fromHue(hue, tokens.theme)
    val shape = RoundedCornerShape(HomeCardMetrics.radius)
    Box(modifier.padding(top = 2.dp, bottom = 8.dp).size(cardSize.width, cardSize.height)) {
        CoverSurface(palette = palette, shape = shape, hero = false) {
            Column(
                Modifier
                    .fillMaxSize()
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(5.dp)
            ) {
                val fandom = HomeFacts.primaryFandom(summary.fandoms)
                if (fandom != null) {
                    SubjectKicker(
                        text = fandom,
                        palette = palette,
                        size = 9.sp,
                        modifier = Modifier.padding(end = if (showsProvenance) 36.dp else 0.dp)
                    )
                }
                Text(
                    text = summary.title,
                    color = tokens.primaryInk,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    minLines = 2,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(end = if (showsProvenance && fandom == null) 36.dp else 0.dp)
                )
                Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                    if (summary.updatedDate.isNotBlank()) {
                        UpdateBadge(summary.updatedDate)
                    }
                }
                Text(
                    text = summary.authorText,
                    color = tokens.primaryInk.withOpacity(0.78),
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                HomeStatusTray(
                    rating = summary.rating,
                    categories = summary.categories,
                    warnings = summary.warnings,
                    isComplete = summary.isComplete == true,
                    arrangement = HomeStatusArrangement.Strip,
                    tileSize = 24.dp,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
        if (showsProvenance) {
            Text(
                text = "AO3",
                color = tokens.secondaryInk,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(10.dp)
                    .background(tokens.glassFill(0.16), CircleShape)
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            )
        }
    }
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
    )
}

@Composable
internal fun CoverSurface(
    palette: SubjectPalette,
    shape: RoundedCornerShape,
    hero: Boolean,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Box(
        modifier
            .then(cardShadow(tokens.theme, shape, hero))
            .clip(shape)
            .background(tokens.cardFill)
            .background(palette.cardWash)
            .border(0.5.dp, palette.cardBorder, shape)
    ) {
        content()
    }
}

@Composable
fun HomeStatusTray(
    rating: String,
    categories: List<String>,
    warnings: List<String>,
    isComplete: Boolean,
    arrangement: HomeStatusArrangement,
    tileSize: Dp,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val fontScale = LocalDensity.current.fontScale
    val scaledTileSize = tileSize * fontScale
    val ratingTint = AO3StatusTint.rating(rating) ?: AO3StatusTint.gray
    val category = categories.firstOrNull { AO3StatusTint.category(it) != null }
    val categoryTint = category?.let { AO3StatusTint.category(it) } ?: AO3StatusTint.gray
    val warningTint = if (HomeFacts.hasRealArchiveWarning(warnings)) AO3StatusTint.orange else AO3StatusTint.gray
    val completeTint = if (isComplete) AO3StatusTint.green else AO3StatusTint.gray
    val marks: @Composable () -> Unit = {
        StatusTile(scaledTileSize, ratingTint) { RatingMark(rating, ratingTint, scaledTileSize) }
        StatusTile(scaledTileSize, categoryTint) { CategoryMark(categories, categoryTint, scaledTileSize) }
        StatusTile(scaledTileSize, warningTint) {
            Icon(
                Icons.Filled.Error,
                contentDescription = "Warnings",
                tint = warningTint,
                modifier = Modifier.size(scaledTileSize * 0.58f)
            )
        }
        StatusTile(scaledTileSize, completeTint) { CompletionMark(isComplete, completeTint, scaledTileSize) }
    }
    val trayShape = RoundedCornerShape(SubjectMetrics.trayRadius)
    if (arrangement == HomeStatusArrangement.Grid) {
        Column(
            modifier.background(tokens.glassFill(0.16), trayShape).padding(4.dp * fontScale),
            verticalArrangement = Arrangement.spacedBy(3.dp * fontScale)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp * fontScale)) {
                StatusTile(scaledTileSize, ratingTint) { RatingMark(rating, ratingTint, scaledTileSize) }
                StatusTile(scaledTileSize, categoryTint) { CategoryMark(categories, categoryTint, scaledTileSize) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp * fontScale)) {
                StatusTile(scaledTileSize, warningTint) {
                    Icon(
                        Icons.Filled.Error,
                        contentDescription = "Warnings",
                        tint = warningTint,
                        modifier = Modifier.size(scaledTileSize * 0.58f)
                    )
                }
                StatusTile(scaledTileSize, completeTint) { CompletionMark(isComplete, completeTint, scaledTileSize) }
            }
        }
    } else {
        Row(
            modifier.background(tokens.glassFill(0.16), trayShape).padding(
                horizontal = 6.dp * fontScale,
                vertical = 4.dp * fontScale
            ),
            horizontalArrangement = Arrangement.spacedBy(4.dp * fontScale, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically
        ) {
            marks()
        }
    }
}

@Composable
private fun RatingMark(rating: String, tint: Color, tileSize: Dp) {
    val letter = when (rating.trim()) {
        "General Audiences" -> "G"
        "Teen And Up Audiences" -> "T"
        "Mature" -> "M"
        "Explicit" -> "E"
        else -> "?"
    }
    Box(Modifier.size(tileSize * 0.72f), contentAlignment = Alignment.Center) {
        Icon(
            Icons.Outlined.Shield,
            contentDescription = rating.ifBlank { "Not Rated" },
            tint = tint,
            modifier = Modifier.fillMaxSize()
        )
        Text(
            text = letter,
            color = tint,
            fontSize = with(LocalDensity.current) { (tileSize * 0.34f).toSp() },
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            style = CenteredGlyph
        )
    }
}

/**
 * Centres a single glyph on its box. Without trimming the font padding and
 * line height, the letter sat at the bottom of the shield and the category
 * symbols shrank to dots (owner report, 2026-10-02).
 */
private val CenteredGlyph = TextStyle(
    platformStyle = PlatformTextStyle(includeFontPadding = false),
    lineHeightStyle = LineHeightStyle(
        alignment = LineHeightStyle.Alignment.Center,
        trim = LineHeightStyle.Trim.Both
    )
)

@Composable
private fun CategoryMark(categories: List<String>, tint: Color, tileSize: Dp) {
    val named = categories.firstOrNull { AO3StatusTint.category(it) != null }?.trim()
    if (named == "Multi") {
        Canvas(
            Modifier
                .size(tileSize * 0.55f)
                .clip(RoundedCornerShape(2.dp))
        ) {
            val w = size.width / 2f
            val h = size.height / 2f
            drawRect(AO3StatusTint.green, Offset.Zero, Size(w, h))
            drawRect(AO3StatusTint.purple, Offset(w, 0f), Size(w, h))
            drawRect(AO3StatusTint.red, Offset(0f, h), Size(w, h))
            drawRect(AO3StatusTint.blue, Offset(w, h), Size(w, h))
        }
        return
    }
    val glyph = when (named) {
        "F/F" -> "⚢"
        "M/M" -> "⚣"
        "F/M" -> "⚤"
        "Gen" -> "☉"
        "Other" -> "♅"
        else -> "–"
    }
    // iOS sizes the sun larger than the pairing signs (its ink reads smaller).
    val scale = if (named == "Gen") 0.78f else 0.62f
    Text(
        text = glyph,
        color = tint,
        fontSize = with(LocalDensity.current) { (tileSize * scale).toSp() },
        textAlign = TextAlign.Center,
        style = CenteredGlyph
    )
}

@Composable
private fun CompletionMark(isComplete: Boolean, tint: Color, tileSize: Dp) {
    if (isComplete) {
        Icon(
            Icons.Outlined.Verified,
            contentDescription = "Complete",
            tint = tint,
            modifier = Modifier.size(tileSize * 0.58f)
        )
    } else {
        Canvas(Modifier.size(tileSize * 0.5f)) {
            drawCircle(
                color = tint,
                style = Stroke(
                    width = 1.5.dp.toPx(),
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 2.dp.toPx()))
                )
            )
        }
    }
}

@Composable
private fun StatusTile(size: Dp, tint: Color, content: @Composable () -> Unit) {
    Box(
        Modifier
            .size(size)
            .background(tint.withOpacity(0.20), RoundedCornerShape(5.dp)),
        contentAlignment = Alignment.Center
    ) {
        content()
    }
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
