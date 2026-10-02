package io.github.cidy02.kudos.home

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Book
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Queue
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.hsb

private val SectionMotion = tween<Float>(durationMillis = 220)

/** Header, optional collapse, and a horizontal row. Empty copy replaces the row. */
@Composable
fun <T> HomeCarouselSection(
    title: String,
    items: List<T>,
    collapsed: Boolean,
    onToggleCollapse: (() -> Unit)?,
    onSeeAll: (() -> Unit)?,
    count: Int? = if (items.isEmpty()) null else items.size,
    emptyIcon: ImageVector,
    emptyMessage: String,
    modifier: Modifier = Modifier,
    card: @Composable (T) -> Unit
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        SectionRuleHeader(
            title = title,
            count = count,
            isCollapsed = collapsed,
            onToggleCollapse = onToggleCollapse,
            onSeeAll = onSeeAll
        )
        AnimatedVisibility(
            visible = !collapsed,
            enter = expandVertically(animationSpec = tween(220)) + fadeIn(SectionMotion),
            exit = shrinkVertically(animationSpec = tween(220)) + fadeOut(SectionMotion)
        ) {
            if (items.isEmpty()) {
                HomeSectionEmpty(message = emptyMessage, icon = emptyIcon)
            } else {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items.forEach { card(it) }
                }
            }
        }
    }
}

@Composable
fun HomeSectionEmpty(message: String, icon: ImageVector, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        androidx.compose.material3.Icon(
            imageVector = icon,
            contentDescription = null,
            tint = tokens.tertiaryInk,
            modifier = Modifier.size(18.dp)
        )
        Text(text = message, color = tokens.secondaryInk, fontSize = 15.sp)
    }
}

/** Preset hues from `SubjectHueSwatches.all`. Tap again clears the pick. No system colour picker. */
object HomeQueueSwatches {
    val all = listOf(
        "Violet" to 0.7194,
        "Mint" to 0.4424,
        "Rose" to 0.0,
        "Amber" to 0.0663,
        "Blue" to 0.5395
    )
}

@Composable
fun NewQueueDialog(
    onDismiss: () -> Unit,
    onCreate: (name: String, hue: Double?, keepOffline: Boolean) -> Unit
) {
    var name by remember { mutableStateOf("") }
    var hue by remember { mutableStateOf<Double?>(null) }
    var keepOffline by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New Queue") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Text("Colour", color = LocalKudosTokens.current.secondaryInk, fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    HomeQueueSwatches.all.forEach { (label, value) ->
                        val selected = hue == value
                        Box(
                            Modifier
                                .size(28.dp)
                                .clip(CircleShape)
                                .background(hsb(value, 0.55, 0.78))
                                .border(
                                    width = if (selected) 2.dp else 0.dp,
                                    color = LocalKudosTokens.current.primaryInk,
                                    shape = CircleShape
                                )
                                .clickable { hue = if (selected) null else value }
                                .semantics { contentDescription = label }
                        )
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = keepOffline, onCheckedChange = { keepOffline = it })
                    Text("Keep works offline", fontSize = 14.sp)
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = name.isNotBlank(),
                onClick = { onCreate(name.trim(), hue, keepOffline) }
            ) { Text("Create") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}

@Composable
fun ContinueReadingActions(onOpenBrowse: () -> Unit, onOpenLibrary: () -> Unit) {
    Row(
        Modifier.padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Button(onClick = onOpenBrowse) { Text("Browse AO3") }
        OutlinedButton(onClick = onOpenLibrary) { Text("Open Library") }
    }
}

/** Icons the empty rows use, kept here so call sites don't each pick a different one. */
object HomeEmptyIcons {
    val reading: ImageVector = Icons.Outlined.Book
    val queues: ImageVector = Icons.Outlined.Queue
    val collections: ImageVector = Icons.Outlined.CollectionsBookmark
    val updated: ImageVector = Icons.Outlined.Book
    val subscriptions: ImageVector = Icons.Outlined.Notifications
}
