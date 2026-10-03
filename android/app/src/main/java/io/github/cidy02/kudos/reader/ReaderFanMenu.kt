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

/** One labelled menu pill in the fanned-out menu (Contents, Find, Themes…). */
data class ReaderFanMenuPill(
    val id: String,
    val title: String,
    val icon: ImageVector,
    val isEnabled: Boolean = true,
    val action: () -> Unit
)

/** One round action button in the fan's bottom row (Share, Kudos, Read Aloud, Lock, Bookmark). */
data class ReaderFanRoundAction(
    val id: String,
    val icon: ImageVector,
    val accessibilityLabel: String,
    val isEnabled: Boolean = true,
    val isEmphasized: Boolean = false,
    val action: () -> Unit,
    val longPressAction: (() -> Unit)? = null
)

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

    val count = maxOf(roundActions.size, 1)
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

    Box(
        modifier = Modifier
            .size(width = width, height = height)
            .clip(pillShape)
            .background(tokens.cardFill.copy(alpha = 0.90f), pillShape)
            .background(tokens.glassFill(), pillShape)
            .border(0.5.dp, tokens.glassStroke(), pillShape)
            .then(
                if (pill.isEnabled) {
                    Modifier.clickable(onClick = onClick)
                } else Modifier
            )
            .padding(horizontal = 18.dp)
            .semantics {
                contentDescription = pill.title
                role = Role.Button
            },
        contentAlignment = Alignment.CenterStart
    ) {
        Row(
            modifier = Modifier.fillMaxSize(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = pill.title,
                fontSize = 15.5.sp,
                fontWeight = FontWeight.Normal,
                color = if (pill.isEnabled) tokens.primaryInk else tokens.secondaryInk
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
