package io.github.cidy02.kudos.ui.components

import io.github.cidy02.kudos.ui.subject.SubjectPalette
import androidx.compose.foundation.text.TextAutoSize
import io.github.cidy02.kudos.app.DebugShotEffect
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowUp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.size
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.imePadding
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.material3.TextButton
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue

/**
 * Shared pagination control for Search / Browse / Account lists.
 * iOS SearchPaginationBar's capsule: previous, Page X / Y with a page-picker caret, next.
 * Long presses retain First / Last; the centre opens the existing exact-page sheet.
 *
 * The field addresses any page exactly; nearby tiles stage a draft before Go loads it.
 */
@Composable
fun KudosPaginationBar(
    currentPage: Int,
    totalPages: Int,
    onPageChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    palette: SubjectPalette = LocalKudosTokens.current.scopePalette
) {
    if (totalPages <= 1) return

    var showPageJump by remember { mutableStateOf(false) }
    DebugShotEffect("pagination", ready = enabled) { showPageJump = true }

    val tokens = LocalKudosTokens.current
    val textMeasurer = rememberTextMeasurer()
    val density = LocalDensity.current

    if (showPageJump) {
        PageJumpSheet(
            currentPage = currentPage,
            totalPages = totalPages,
            onSelect = onPageChange,
            onDismiss = { showPageJump = false },
            palette = palette
        )
    }

    val leading: @Composable () -> Unit = {
        val navEnabled = enabled && currentPage > 1
        Box(
            modifier = Modifier
                .minimumInteractiveComponentSize()
                .size(40.dp)
                .clip(CircleShape)
                .combinedClickable(
                    enabled = navEnabled,
                    role = Role.Button,
                    onClick = { onPageChange(navigationPage(PaginationDirection.BACKWARD, false, currentPage, totalPages)) },
                    onLongClick = { onPageChange(navigationPage(PaginationDirection.BACKWARD, true, currentPage, totalPages)) },
                    onLongClickLabel = "First page"
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowLeft,
                contentDescription = "Previous Page",
                tint = if (navEnabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
            )
        }
    }
    val position: @Composable (String) -> Unit = { positionText ->
        // iOS's hint, "Opens the page picker.", as TalkBack says it: "double-tap to open the page picker".
        TextButton(
            onClick = { showPageJump = true },
            enabled = enabled && totalPages > 1,
            modifier = Modifier.semantics {
                contentDescription = "Page $currentPage of $totalPages"
                onClick(label = "open the page picker", action = null)
            }
        ) {
            Text(
                text = positionText,
                lineHeight = 20.sp,
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
                color = tokens.primaryInk
            )
            Icon(Icons.Default.KeyboardArrowUp, contentDescription = null,
                tint = tokens.secondaryInk, modifier = Modifier.padding(start = 5.dp).size(12.dp))
        }
    }
    val trailing: @Composable () -> Unit = {
        val navEnabled = enabled && currentPage < totalPages
        Box(
            modifier = Modifier
                .minimumInteractiveComponentSize()
                .size(40.dp)
                .clip(CircleShape)
                .background(if (navEnabled) palette.controlChipFill else Color.Transparent)
                .combinedClickable(
                    enabled = navEnabled,
                    role = Role.Button,
                    onClick = { onPageChange(navigationPage(PaginationDirection.FORWARD, false, currentPage, totalPages)) },
                    onLongClick = { onPageChange(navigationPage(PaginationDirection.FORWARD, true, currentPage, totalPages)) },
                    onLongClickLabel = "Last page"
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = "Next Page",
                tint = if (navEnabled) palette.controlInk else tokens.secondaryInk.copy(alpha = 0.38f)
            )
        }
    }
    // All hosts keep the capsule at AX sizes too. Try the same whole label variants as iOS.
    BoxWithConstraints(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val labelWidth = (constraints.maxWidth - with(density) { 160.dp.roundToPx() }).coerceAtLeast(0)
        val labelStyle = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        val label = listOf("Page $currentPage / $totalPages", "$currentPage / $totalPages", "$currentPage")
            .firstOrNull { textMeasurer.measure(it, labelStyle, softWrap = false).size.width <= labelWidth }
            ?: "$currentPage"
        Row(Modifier.clip(CircleShape)
            .background(if (tokens.theme.isDarkFamily) Color(0xFF787880).copy(alpha = 0.34f) else tokens.glassFill(0.24))
            .border(0.5.dp, tokens.glassStroke(0.14), CircleShape)
            .padding(horizontal = 6.dp, vertical = 5.dp),
            horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
            leading()
            position(label)
            trailing()
        }
    }
}

/** Exact page entry and nearby tiles; only Go commits the draft (iOS PageJumpSheet). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PageJumpSheet(
    currentPage: Int,
    totalPages: Int,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit,
    palette: SubjectPalette
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState,
        containerColor = LocalKudosTokens.current.background) {
        PageJumpContent(currentPage, totalPages, onSelect, onDismiss, palette)
    }
}

@Composable
internal fun PageJumpContent(currentPage: Int, totalPages: Int, onSelect: (Int) -> Unit, onDismiss: () -> Unit,
    palette: SubjectPalette = LocalKudosTokens.current.scopePalette) {
    val tokens = LocalKudosTokens.current
    var pageInput by remember(currentPage) { mutableStateOf(currentPage.toString()) }
    val enteredPage = pageInput.toIntOrNull()?.takeIf { it > 0 }?.coerceAtMost(maxOf(totalPages, 1))
    val draftPage = enteredPage ?: currentPage.coerceIn(1, maxOf(totalPages, 1))
    fun go() {
        val target = draftPage
        if (target != currentPage) onSelect(target)
        onDismiss()
    }

    Column(Modifier.fillMaxWidth().fillMaxHeight(0.9f).imePadding().padding(bottom = 24.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, contentDescription = "Cancel") }
            Text("Go to page", Modifier.weight(1f), fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            IconButton(onClick = { go() }, enabled = draftPage != currentPage) {
                Icon(Icons.Default.Check, contentDescription = "Go to page $draftPage")
            }
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            SubjectFieldLabel("Page number")
            OutlinedTextField(
                value = pageInput, onValueChange = { pageInput = it.filter { char -> char in '0'..'9' } }, singleLine = true,
                placeholder = { Text("Page") },
                trailingIcon = { Text("of ${"%,d".format(totalPages)}", Modifier.padding(horizontal = 12.dp)) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { if (draftPage != currentPage) go() }),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Page number" }
            )

            // Tiles stage a draft; nothing loads until Go.
            val nearby = nearbyPageWindow(draftPage, totalPages)
            if (nearby.size > 1) {
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SubjectFieldLabel("Nearby")
                    nearby.chunked(5).forEach { rowPages ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            rowPages.forEach { page ->
                                val selected = page == draftPage
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .heightIn(min = 44.dp)
                                        .clip(RoundedCornerShape(11.dp))
                                        .background(
                                            if (selected) palette.controlChipFill
                                            else tokens.glassFill(0.08)
                                        )
                                        .border(0.5.dp, if (selected) palette.controlChipStroke
                                            else tokens.glassStroke(0.13), RoundedCornerShape(11.dp))
                                        .selectable(selected = selected, role = Role.RadioButton) { pageInput = page.toString() }
                                        .semantics { contentDescription = "Page $page" },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = "%,d".format(page),
                                        maxLines = 1,
                                        autoSize = TextAutoSize.StepBased(minFontSize = 9.sp, maxFontSize = 16.sp),
                                        lineHeight = 20.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        color = if (selected) palette.controlInk
                                        else tokens.primaryInk
                                    )
                                }
                            }
                            repeat(5 - rowPages.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                TextButton(onClick = { pageInput = "1" }, enabled = draftPage > 1,
                    colors = androidx.compose.material3.ButtonDefaults.textButtonColors(contentColor = tokens.primaryInk)) {
                    Text("First page", lineHeight = 20.sp)
                }
                TextButton(
                    onClick = { pageInput = maxOf(totalPages, 1).toString() },
                    enabled = draftPage < totalPages,
                    colors = androidx.compose.material3.ButtonDefaults.textButtonColors(contentColor = tokens.primaryInk)
                ) {
                    Text("Last (${"%,d".format(totalPages)})", lineHeight = 20.sp)
                }
            }
        }
    }
}

enum class PaginationDirection { BACKWARD, FORWARD }

/**
 * Port of iOS SearchPaginationBar.navigationPage.
 * Arrow taps go adjacent; long presses jump to the first/last page.
 */
internal fun navigationPage(
    direction: PaginationDirection,
    longPress: Boolean,
    currentPage: Int,
    totalPages: Int
): Int = when (direction) {
    PaginationDirection.BACKWARD -> if (longPress) 1 else maxOf(1, currentPage - 1)
    PaginationDirection.FORWARD -> if (longPress) totalPages else minOf(totalPages, currentPage + 1)
}

/**
 * The pages the jump sheet offers as tiles: [count] of them, centred on [page] and slid back
 * inside the range at either end rather than cut off, so page 2 of 3,216 still offers ten
 * (iOS `SearchPaginationBar.nearbyPageWindow`).
 */
internal fun nearbyPageWindow(page: Int, totalPages: Int, count: Int = 10): List<Int> {
    if (totalPages <= 0) return emptyList()
    val windowSize = minOf(count, totalPages)
    val centred = page - (windowSize - 1) / 2
    val start = maxOf(1, minOf(centred, totalPages - windowSize + 1))
    return (start until start + windowSize).toList()
}
