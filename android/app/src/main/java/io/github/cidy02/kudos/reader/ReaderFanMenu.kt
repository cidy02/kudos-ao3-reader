package io.github.cidy02.kudos.reader

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.ChatBubbleOutline
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.FindInPage
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.ReadingAnnotation
import io.github.cidy02.kudos.works.WorkTags
import io.github.cidy02.kudos.reader.readium.ReadiumNavigatorController
import java.net.URI
import kotlin.math.abs

/** One labelled menu pill in the fanned-out menu (Contents, Find, Themes…). */
data class ReaderFanMenuPill(
    val id: String,
    val title: String,
    val icon: ImageVector,
    val isEnabled: Boolean = true,
    val action: () -> Unit
)

/** One round action in the fan's bottom row (Share, Kudos, Original, Read Aloud, Lock, Bookmark). */
data class ReaderFanRoundAction(
    val id: String,
    val icon: ImageVector,
    val accessibilityLabel: String,
    val isEnabled: Boolean = true,
    val isEmphasized: Boolean = false,
    val action: () -> Unit,
    val longPressAction: (() -> Unit)? = null
)

/** Menu contents only; the glass composables below stay unchanged. */
internal fun readerFanPills(
    percent: Int?,
    searchable: Boolean,
    ao3WorkId: Long?,
    commentsChapter: Int?,
    onContents: (Int) -> Unit,
    onFind: () -> Unit,
    onComments: (Long, Int?) -> Unit,
    onSettings: () -> Unit
): List<ReaderFanMenuPill> = buildList {
    add(ReaderFanMenuPill(
        id = "contents",
        title = percent?.let { "Contents · $it%" } ?: "Contents",
        icon = Icons.AutoMirrored.Filled.List,
        action = { onContents(0) }
    ))
    add(ReaderFanMenuPill(
        id = "bookmarks", title = "Bookmarks & Highlights", icon = Icons.Filled.Bookmark,
        action = { onContents(1) }
    ))
    add(ReaderFanMenuPill(
        id = "find", title = "Find in Work", icon = Icons.Filled.Search,
        isEnabled = searchable, action = onFind
    ))
    if (ao3WorkId != null) {
        add(ReaderFanMenuPill(
            id = "comments", title = "Comments", icon = Icons.Filled.ChatBubbleOutline,
            action = { onComments(ao3WorkId, commentsChapter) }
        ))
    }
    add(ReaderFanMenuPill(
        id = "settings", title = "Themes & Settings", icon = Icons.Filled.TextFields,
        action = onSettings
    ))
}

internal fun readerKudosAction(
    ao3WorkId: Long?,
    given: Boolean,
    working: Boolean,
    onKudos: () -> Unit
): ReaderFanRoundAction? = ao3WorkId?.let {
    ReaderFanRoundAction(
        id = "kudos",
        icon = if (given) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
        accessibilityLabel = if (given) "Kudos given" else "Give kudos",
        isEnabled = !working && !given,
        isEmphasized = given,
        action = onKudos
    )
}

/** iOS shareURL's first two choices; ReaderWorkActions supplies the EPUB fallback. */
internal fun readerShareUrl(work: SavedWork): String? {
    val ao3Id = work.ao3WorkID?.toLong() ?: WorkTags.ao3WorkIdFromUrl(work.sourceUrl)
    if (ao3Id != null) return "https://archiveofourown.org/works/$ao3Id"
    return work.sourceUrl.takeIf {
        runCatching { URI(it).scheme?.startsWith("http") == true }.getOrDefault(false)
    }
}

internal fun readerOriginalAction(available: Boolean, onOriginal: () -> Unit): ReaderFanRoundAction? =
    if (available) ReaderFanRoundAction(
        id = "original",
        icon = Icons.Filled.FindInPage,
        accessibilityLabel = "View the original file this work was converted from",
        action = onOriginal
    ) else null

/** Same near-position condition as AnnotationRepository.removeBookmarkNear. */
internal fun readerIsBookmarked(bookmarks: List<ReadingAnnotation>, progress: ReaderProgress?): Boolean {
    if (progress == null || !readerHasBookmarkPosition(progress)) return false
    val progression = progress.totalProgression ?: progress.scrollFraction
    return bookmarks.any {
        it.spineIndex == progress.spineIndex && abs(it.progression - progression) <= 0.02
    }
}

/** iOS requires an actual locator position, not just fallback spine/scroll progress. */
internal fun readerHasBookmarkPosition(progress: ReaderProgress?): Boolean =
    progress?.locatorJson?.let { ReadiumNavigatorController.locatorFromJson(it) }?.locations?.position != null

/**
 * Top-right reading options button that fans open into menu pills plus a row of round quick actions.
 * Matching iOS `ReaderFanMenu.swift`.
 */
@Composable
fun ReaderFanMenu(
    isOpen: Boolean,
    onOpenChange: (Boolean) -> Unit,
    pills: List<ReaderFanMenuPill>,
    roundActions: List<ReaderFanRoundAction>,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val roundActionWidth = 52.dp
    val roundActionHeight = 46.dp
    val rowSpacing = 9.dp

    // iOS's rule: the pills span the circle row. iOS always has four circles or more. Android
    // may have three if the file has gone missing, and three circles' width cuts
    // the pills' labels, so the pills never go narrower than four.
    val count = maxOf(roundActions.size, 4)
    val pillWidth = (roundActionWidth * count) + (rowSpacing * (count - 1))

    Box(
        modifier = modifier
            .statusBarsPadding()
            .padding(top = 4.dp, end = 12.dp),
        contentAlignment = Alignment.TopEnd
    ) {
        if (!isOpen) {
            // Closed toggle button (44x44pt glass circle)
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(tokens.cardFill.copy(alpha = 0.90f), CircleShape)
                    .background(tokens.glassFill(), CircleShape)
                    .border(0.5.dp, tokens.glassStroke(), CircleShape)
                    .clickable { onOpenChange(true) }
                    .semantics {
                        contentDescription = "More"
                        role = Role.Button
                    },
                contentAlignment = Alignment.Center
            ) {
                // Apple Books style glyph: 3 horizontal bars over 3 dots
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(2.5.dp)
                    ) {
                        repeat(3) {
                            Box(
                                modifier = Modifier
                                    .size(width = 20.dp, height = 2.dp)
                                    .background(tokens.primaryInk, RoundedCornerShape(1.dp))
                            )
                        }
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        repeat(3) {
                            Box(
                                modifier = Modifier
                                    .size(2.5.dp)
                                    .background(tokens.primaryInk, CircleShape)
                            )
                        }
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = isOpen,
            enter = fadeIn(spring(dampingRatio = 0.88f, stiffness = 400f)) +
                scaleIn(spring(dampingRatio = 0.88f, stiffness = 400f), initialScale = 0.85f),
            exit = fadeOut(spring(dampingRatio = 0.88f, stiffness = 400f)) +
                scaleOut(spring(dampingRatio = 0.88f, stiffness = 400f), targetScale = 0.85f)
        ) {
            Column(
                horizontalAlignment = Alignment.End,
                verticalArrangement = Arrangement.spacedBy(rowSpacing)
            ) {
                // Stack of pills
                pills.forEach { pill ->
                    FanMenuPillItem(
                        pill = pill,
                        width = pillWidth,
                        height = roundActionHeight,
                        onClick = {
                            onOpenChange(false)
                            pill.action()
                        }
                    )
                }

                // Round actions row
                Row(
                    horizontalArrangement = Arrangement.spacedBy(rowSpacing),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    roundActions.forEach { action ->
                        FanRoundActionButton(
                            action = action,
                            width = roundActionWidth,
                            height = roundActionHeight
                        )
                    }
                }
            }
        }
    }
}

/**
 * Invisible full-screen tap target that closes the open fan menu when tapping outside,
 * without dismissing the reader chrome.
 */
@Composable
fun ReaderFanMenuDismissBackdrop(
    isOpen: Boolean,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (isOpen) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    // The page behind the open menu: TalkBack read an unnamed button (audit A43).
                    onClickLabel = "Close menu",
                    onClick = onDismiss
                )
        )
    }
}

@Composable
private fun FanMenuPillItem(
    pill: ReaderFanMenuPill,
    width: androidx.compose.ui.unit.Dp,
    height: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val pillShape = RoundedCornerShape(23.dp)
    // At an accessibility text size a pill is as wide as the screen lets it be and as tall as its
    // words: at twice the size "Bookmarks & Highlights" was cut to "Bookmarks &" and "Themes &
    // Settings" ran under its icon.
    val large = io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()
    val roomy = (androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp.dp - 24.dp).coerceAtLeast(width)

    Box(
        modifier = Modifier
            .width(if (large) roomy else width)
            .heightIn(min = height)
            .clip(pillShape)
            .background(tokens.cardFill.copy(alpha = 0.90f), pillShape)
            .background(tokens.glassFill(), pillShape)
            .border(0.5.dp, tokens.glassStroke(), pillShape)
            .then(
                if (pill.isEnabled) {
                    Modifier.clickable(onClick = onClick)
                } else Modifier
            )
            .padding(horizontal = 18.dp, vertical = if (large) 6.dp else 0.dp)
            .semantics {
                contentDescription = pill.title
                role = Role.Button
            },
        contentAlignment = Alignment.CenterStart
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = pill.title,
                fontSize = 15.5.sp,
                fontWeight = FontWeight.Normal,
                color = if (pill.isEnabled) tokens.primaryInk else tokens.secondaryInk,
                modifier = Modifier.weight(1f)
            )
            Icon(
                imageVector = pill.icon,
                contentDescription = null,
                tint = if (pill.isEnabled) tokens.primaryInk else tokens.secondaryInk,
                modifier = Modifier.size(17.dp)
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FanRoundActionButton(
    action: ReaderFanRoundAction,
    width: androidx.compose.ui.unit.Dp,
    height: androidx.compose.ui.unit.Dp
) {
    val tokens = LocalKudosTokens.current
    val haptics = LocalHapticFeedback.current
    val shape = RoundedCornerShape(23.dp)

    val glyphColor = if (action.isEmphasized) {
        Color.White
    } else if (action.isEnabled) {
        tokens.primaryInk
    } else {
        tokens.secondaryInk
    }

    Box(
        modifier = Modifier
            .size(width = width, height = height)
            .clip(shape)
            .then(
                if (action.isEmphasized) {
                    Modifier.background(tokens.accent, shape)
                } else {
                    Modifier
                        .background(tokens.cardFill.copy(alpha = 0.90f), shape)
                        .background(tokens.glassFill(), shape)
                        .border(0.5.dp, tokens.glassStroke(), shape)
                }
            )
            .then(
                if (action.isEnabled) {
                    Modifier.combinedClickable(
                        onClick = {
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            action.action()
                        },
                        onLongClick = if (action.longPressAction != null) {
                            {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                action.longPressAction.invoke()
                            }
                        } else null
                    )
                } else Modifier
            )
            .semantics {
                contentDescription = action.accessibilityLabel
                role = Role.Button
                if (action.isEmphasized) selected = true
            },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = action.icon,
            contentDescription = null,
            tint = glyphColor,
            modifier = Modifier.size(17.dp)
        )
    }
}
