package io.github.cidy02.kudos.home

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.readingProgressFraction
import io.github.cidy02.kudos.ui.components.CardMetaLine
import io.github.cidy02.kudos.ui.components.CardMetaSeparator
import io.github.cidy02.kudos.ui.components.WorkStatIcons
import io.github.cidy02.kudos.ui.components.WorkStatItem
import io.github.cidy02.kudos.ui.components.WorkStatLabel
import io.github.cidy02.kudos.ui.components.coverContainerColor
import io.github.cidy02.kudos.ui.components.ratingDisplayName
import kotlin.math.roundToInt

@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
fun HomeResumeHero(
    work: SavedWork,
    obscured: Boolean,
    onOpen: () -> Unit,
    onOpenDetails: () -> Unit,
    onReveal: () -> Unit,
    isSelecting: Boolean,
    isSelected: Boolean,
    onToggleSelection: (() -> Unit)?,
    modifier: Modifier = Modifier
) {
    val a11y = if (obscured) {
        "Hidden mature work. Activate to reveal."
    } else {
        buildString {
            append(work.title)
            if (work.author.isNotBlank()) append(", by ${work.author}")
        }
    }
    ElevatedCard(
        modifier = modifier
            .fillMaxWidth()
            .combinedClickable(
                onClick = {
                    if (isSelecting) {
                        onToggleSelection?.invoke()
                    } else if (obscured) {
                        onReveal()
                    } else {
                        onOpen()
                    }
                }
            )
            .semantics { contentDescription = a11y },
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.elevatedCardColors(
            containerColor = coverContainerColor(work.title)
        ),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp)
    ) {
        if (obscured) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(200.dp)
                    .clipToBounds()
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .blur(16.dp)
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = work.title,
                        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                    CardMetaLine(
                        text = work.author.ifBlank { "Anonymous" },
                        icon = Icons.Outlined.Person,
                        accessibilityLabel = "Author: ${work.author.ifBlank { "Anonymous" }}"
                    )
                    val fandom = work.workFandoms.firstOrNull { it.isNotBlank() }
                    if (!fandom.isNullOrBlank()) {
                        CardMetaLine(
                            text = fandom,
                            icon = Icons.AutoMirrored.Outlined.MenuBook,
                            accessibilityLabel = "Fandom: $fandom"
                        )
                    }
                }
                Surface(
                    shape = RoundedCornerShape(50),
                    color = MaterialTheme.colorScheme.scrim.copy(alpha = 0.55f),
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.align(Alignment.Center)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.Filled.VisibilityOff,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                        Text(
                            text = "Tap to reveal",
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 1
                        )
                    }
                }
            }
            return@ElevatedCard
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Top
            ) {
                Text(
                    text = work.title,
                    style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                io.github.cidy02.kudos.ui.components.WorkDetailsIconButton(onClick = onOpenDetails)
            }

            CardMetaLine(
                text = work.author.ifBlank { "Anonymous" },
                icon = Icons.Outlined.Person,
                accessibilityLabel = "Author: ${work.author.ifBlank { "Anonymous" }}"
            )

            val fandom = work.workFandoms.firstOrNull { it.isNotBlank() }
            if (!fandom.isNullOrBlank()) {
                CardMetaLine(
                    text = fandom,
                    icon = Icons.AutoMirrored.Outlined.MenuBook,
                    accessibilityLabel = "Fandom: $fandom"
                )
            }

            CardMetaSeparator()

            val compactStats = buildList {
                val ratingDisplay = ratingDisplayName(work.rating)
                if (ratingDisplay != null) {
                    add(WorkStatItem(text = ratingDisplay, icon = WorkStatIcons.rating))
                }
                if (work.chapters.isNotBlank()) {
                    add(WorkStatItem(text = io.github.cidy02.kudos.ui.components.chapterStatText(work.chapters), icon = WorkStatIcons.chapters))
                }
                val completionLabel = io.github.cidy02.kudos.ui.components.completionStatText(work.isComplete)
                if (completionLabel != null) {
                    add(WorkStatItem(text = completionLabel, icon = if (work.isComplete) WorkStatIcons.complete else WorkStatIcons.inProgress))
                }
                if (work.wordCount > 0) {
                    add(WorkStatItem(text = io.github.cidy02.kudos.ui.components.wordStatText(work.wordCount), icon = WorkStatIcons.words))
                }
            }

            if (compactStats.isNotEmpty()) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    compactStats.forEach { WorkStatLabel(item = it) }
                }
            }

            Spacer(Modifier.height(8.dp))

            val progress = work.readingProgressFraction()
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.Bottom
            ) {
                Text(
                    text = if (work.lastSpineIndex > 0) "Ch ${work.lastSpineIndex + 1}" else "Reading",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (progress != null) {
                    Text(
                        text = "${(progress.coerceIn(0.0, 1.0) * 100).roundToInt()}%",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            LinearProgressIndicator(
                progress = { (progress ?: 0.0).toFloat().coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth(),
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HomeResumeStripCard(
    work: SavedWork,
    obscured: Boolean,
    onOpen: () -> Unit,
    onReveal: () -> Unit,
    isSelecting: Boolean,
    isSelected: Boolean,
    onToggleSelection: (() -> Unit)?,
    modifier: Modifier = Modifier
) {
    val a11y = if (obscured) {
        "Hidden mature work. Activate to reveal."
    } else {
        buildString {
            append(work.title)
            if (work.author.isNotBlank()) append(", by ${work.author}")
        }
    }
    ElevatedCard(
        modifier = modifier
            .width(280.dp)
            .height(92.dp)
            .combinedClickable(
                onClick = {
                    if (isSelecting) {
                        onToggleSelection?.invoke()
                    } else if (obscured) {
                        onReveal()
                    } else {
                        onOpen()
                    }
                }
            )
            .semantics { contentDescription = a11y },
        shape = MaterialTheme.shapes.large,
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp)
    ) {
        Row(modifier = Modifier.fillMaxSize()) {
            Box(
                modifier = Modifier
                    .width(64.dp)
                    .fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = coverContainerColor(work.title)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Outlined.MenuBook,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f),
                            modifier = Modifier.size(24.dp)
                        )
                    }
                }
            }
            
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxSize()
                    .padding(12.dp)
            ) {
                if (obscured) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .blur(8.dp),
                        verticalArrangement = Arrangement.Center
                    ) {
                        Text(
                            text = work.title,
                            style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
                            maxLines = 2
                        )
                    }
                    Surface(
                        shape = RoundedCornerShape(50),
                        color = MaterialTheme.colorScheme.scrim.copy(alpha = 0.55f),
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                        modifier = Modifier.align(Alignment.Center)
                    ) {
                        Text(
                            text = "Tap to reveal",
                            style = MaterialTheme.typography.labelSmall,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                        )
                    }
                } else {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column {
                            Text(
                                text = work.title,
                                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
                                color = MaterialTheme.colorScheme.onSurface,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = work.author.ifBlank { "Anonymous" },
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                        val progress = work.readingProgressFraction()
                        Text(
                            text = if (progress != null) "Reading · ${(progress.coerceIn(0.0, 1.0) * 100).roundToInt()}%" else "Reading",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
            }
        }
    }
}
