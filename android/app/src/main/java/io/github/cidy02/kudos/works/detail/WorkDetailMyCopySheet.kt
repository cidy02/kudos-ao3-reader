package io.github.cidy02.kudos.works.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.core.model.WorkDownloadAction
import io.github.cidy02.kudos.core.model.WorkDownloadSemantics
import io.github.cidy02.kudos.core.model.publicationProgress
import io.github.cidy02.kudos.library.ReadingQueueFacts
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.ui.subject.KudosTokens
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectStatCell
import io.github.cidy02.kudos.ui.subject.SubjectStatStrip
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

data class WorkQueueLine(
    val queueId: String,
    val name: String,
    val position: String?
)

/**
 * Artboard 1a's "My copy" native sheet (`WorkDetailSections.swift:188` / `WorkDetailView.swift:370`).
 * Everything local and private to this device is organized here.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkDetailMyCopySheet(
    work: SavedWork?,
    remote: AO3WorkSummary?,
    userTags: List<Tag>,
    collections: List<WorkCollection>,
    queueMemberships: List<WorkQueueLine>,
    inSavedForLater: Boolean,
    isWorking: Boolean,
    canRebuildFromOriginal: Boolean,
    palette: SubjectPalette,
    newTagName: String,
    onNewTagName: (String) -> Unit,
    onAddTag: () -> Unit,
    onRemoveTag: (Tag) -> Unit,
    onSuggestTag: (String) -> Unit,
    onToggleSaved: () -> Unit,
    onToggleSavedForLater: () -> Unit,
    onToggleFinished: () -> Unit,
    onAddToQueue: () -> Unit,
    onAddToCollection: () -> Unit,
    onRebuildFromOriginal: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val tokens = LocalKudosTokens.current
    val context = LocalContext.current

    val epubFile = remember(work?.id) {
        work?.id?.let { id ->
            File(File(context.filesDir, "works"), "$id.epub")
        }
    }
    val fileSizeString = remember(epubFile) {
        if (epubFile != null && epubFile.exists() && epubFile.length() > 0) {
            ReadingQueueFacts.byteCountString(epubFile.length())
        } else null
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = tokens.background,
        modifier = modifier
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
        ) {
            // Header bar: "My copy" (19sp), "Private to this device" (12sp), round glass "x"
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 22.dp)
                    .padding(top = 10.dp, bottom = 14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Text(
                        text = "My copy",
                        fontSize = 19.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = tokens.primaryInk
                    )
                    Text(
                        text = "Private to this device",
                        fontSize = 12.sp,
                        color = tokens.secondaryInk
                    )
                }

                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(tokens.glassFill(0.12))
                        .clickable(onClick = onDismiss),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "Close",
                        tint = tokens.secondaryInk,
                        modifier = Modifier.size(14.dp)
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 22.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                if (work != null) {
                    // 1a's three figures under the title: Progress, On device, Preserved
                    MyCopyStrip(
                        work = work,
                        fileSizeString = fileSizeString,
                        palette = palette
                    )

                    // Status group
                    MyCopyStatusSection(
                        work = work,
                        inSavedForLater = inSavedForLater,
                        isWorking = isWorking,
                        palette = palette,
                        onToggleSaved = onToggleSaved,
                        onToggleSavedForLater = onToggleSavedForLater,
                        onToggleFinished = onToggleFinished
                    )

                    // Queues group
                    MyCopyQueuesSection(
                        memberships = queueMemberships,
                        isWorking = isWorking,
                        palette = palette,
                        onAddToQueue = onAddToQueue
                    )

                    // Collections group
                    MyCopyCollectionsSection(
                        collections = collections,
                        isWorking = isWorking,
                        palette = palette,
                        onAddToCollection = onAddToCollection
                    )

                    // Storage group
                    MyCopyStorageSection(
                        work = work,
                        fileSizeString = fileSizeString
                    )

                    // Activity group
                    MyCopyActivitySection(work = work)

                    // Origin & Conversion
                    MyCopyOriginSection(
                        work = work,
                        canRebuildFromOriginal = canRebuildFromOriginal,
                        isWorking = isWorking,
                        palette = palette,
                        onRebuildFromOriginal = onRebuildFromOriginal
                    )
                } else {
                    RemoteEmptyNotice(tokens = tokens)
                }

                // My Tags group
                val tagSuggestions = remember(work, remote, userTags) {
                    val existing = userTags.map { it.normalizedName.lowercase() }.toSet()
                    val fandoms = work?.workFandoms?.takeIf { it.isNotEmpty() } ?: remote?.fandoms.orEmpty()
                    val relationships = work?.workRelationships?.takeIf { it.isNotEmpty() } ?: remote?.relationships.orEmpty()
                    (fandoms + relationships)
                        .map { it.trim() }
                        .filter { it.isNotBlank() && it.lowercase() !in existing }
                        .distinct()
                        .take(6)
                }

                MyTagsSection(
                    userTags = userTags,
                    tagSuggestions = tagSuggestions,
                    newTagName = newTagName,
                    onNewTagName = onNewTagName,
                    onAddTag = onAddTag,
                    onRemoveTag = onRemoveTag,
                    onSuggestTag = onSuggestTag,
                    palette = palette,
                    isWorking = isWorking
                )
            }
        }
    }
}

@Composable
private fun MyCopyStrip(
    work: SavedWork,
    fileSizeString: String?,
    palette: SubjectPalette
) {
    val progressLabel = work.publicationProgress?.let { fraction ->
        "${(fraction.coerceIn(0.0, 1.0) * 100.0).roundToInt()}%"
    } ?: "—"
    val onDeviceLabel = fileSizeString ?: "—"
    val kept = work.hasEpub && work.isProtected

    SubjectStatStrip(
        cells = listOf(
            SubjectStatCell(value = progressLabel, label = "Progress"),
            SubjectStatCell(value = onDeviceLabel, label = "On device"),
            SubjectStatCell(
                value = if (kept) "Kept" else "No",
                label = "Preserved",
                tint = if (kept) Color(0xFF35C46A) else null
            )
        ),
        palette = palette
    )
}

@Composable
private fun MyCopyStatusSection(
    work: SavedWork,
    inSavedForLater: Boolean,
    isWorking: Boolean,
    palette: SubjectPalette,
    onToggleSaved: () -> Unit,
    onToggleSavedForLater: () -> Unit,
    onToggleFinished: () -> Unit
) {
    val downloadAction = WorkDownloadSemantics.action(
        work.hasEpub,
        work.isDownloaded,
        work.hasAo3WorkId,
        work.keptOfflineBy
    ) ?: WorkDownloadAction.Download

    val (downloadTitle, downloadIsOn, downloadIsEnabled) = when (downloadAction) {
        WorkDownloadAction.Download -> Triple("Download", false, true)
        WorkDownloadAction.RemoveDownload -> Triple("Downloaded", true, true)
        is WorkDownloadAction.KeptBy -> Triple("Kept Offline", true, false)
    }

    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        MyCopyGroupHeader(title = "Status")

        MyCopyToggleRow(
            title = downloadTitle,
            isOn = downloadIsOn,
            enabled = !isWorking && downloadIsEnabled,
            onClick = onToggleSaved,
            palette = palette
        )

        MyCopyToggleRow(
            title = "Saved for Later",
            isOn = inSavedForLater,
            enabled = !isWorking,
            onClick = onToggleSavedForLater,
            palette = palette
        )

        MyCopyToggleRow(
            title = "Finished",
            isOn = work.isFinished,
            enabled = !isWorking,
            onClick = onToggleFinished,
            palette = palette
        )
    }
}

@Composable
private fun MyCopyQueuesSection(
    memberships: List<WorkQueueLine>,
    isWorking: Boolean,
    palette: SubjectPalette,
    onAddToQueue: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        MyCopyGroupHeader(title = "Queues")

        memberships.forEach { line ->
            MyCopyValueRow(
                title = line.name,
                value = line.position.orEmpty()
            )
        }

        MyCopyAddLabel(
            title = "Add to queue",
            onClick = onAddToQueue,
            palette = palette,
            enabled = !isWorking
        )
    }
}

@Composable
private fun MyCopyCollectionsSection(
    collections: List<WorkCollection>,
    isWorking: Boolean,
    palette: SubjectPalette,
    onAddToCollection: () -> Unit
) {
    val names = remember(collections) { collections.map { it.name }.sorted() }
    val tokens = LocalKudosTokens.current

    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        MyCopyGroupHeader(title = "Collections")

        names.forEach { name ->
            Text(
                text = name,
                fontSize = 14.5.sp,
                color = tokens.primaryInk,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp)
            )
        }

        MyCopyAddLabel(
            title = "Add to collection",
            onClick = onAddToCollection,
            palette = palette,
            enabled = !isWorking
        )
    }
}

@Composable
private fun MyCopyStorageSection(
    work: SavedWork,
    fileSizeString: String?
) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        MyCopyGroupHeader(title = "Storage")

        val statusText = when {
            work.isDownloaded && work.hasEpub -> {
                if (fileSizeString != null) "Downloaded · $fileSizeString" else "Downloaded"
            }
            work.hasEpub -> "Not downloaded"
            work.hasAo3WorkId -> "Removed to save space. Kudos gets it again when you read it"
            else -> "File missing. An imported work can't be downloaded again"
        }

        MyCopyValueRow(title = "Download", value = statusText)

        val sourceText = if (work.hasAo3WorkId) "Archive of Our Own" else "Imported file"
        MyCopyValueRow(title = "Source", value = sourceText)
    }
}

@Composable
private fun MyCopyActivitySection(work: SavedWork) {
    val tokens = LocalKudosTokens.current
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        MyCopyGroupHeader(title = "Activity")

        MyCopyValueRow(
            title = "Added",
            value = formatInstant(work.dateAdded)
        )

        val lastReadText = work.lastReadDate?.let { formatInstant(it) } ?: "Never"
        MyCopyValueRow(title = "Last opened", value = lastReadText)

        val progress = work.publicationProgress
        if (progress != null) {
            val percent = (progress.coerceIn(0.0, 1.0) * 100.0).roundToInt()
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Progress",
                        fontSize = 14.5.sp,
                        color = tokens.primaryInk
                    )
                    Text(
                        text = "$percent%",
                        fontSize = 13.sp,
                        color = tokens.secondaryInk
                    )
                }
                LinearProgressIndicator(
                    progress = { progress.toFloat().coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth(),
                    color = tokens.accent,
                    trackColor = tokens.glassStroke(0.18)
                )
            }
        }
    }
}

@Composable
private fun MyCopyOriginSection(
    work: SavedWork,
    canRebuildFromOriginal: Boolean,
    isWorking: Boolean,
    palette: SubjectPalette,
    onRebuildFromOriginal: () -> Unit
) {
    val tokens = LocalKudosTokens.current

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        MyCopyGroupHeader(title = "Origin")

        val originSentence = if (work.hasAo3WorkId) {
            "From Archive of Our Own."
        } else {
            "Imported EPUB file."
        }
        Text(
            text = originSentence,
            fontSize = 14.5.sp,
            color = tokens.primaryInk
        )

        if (work.sourceUrl.isNotBlank()) {
            SelectionContainer {
                Text(
                    text = work.sourceUrl,
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    color = tokens.secondaryInk
                )
            }
        }

        if (!work.hasAo3WorkId) {
            Text(
                text = "Kudos can't update this work's tags, stats, or availability from an imported file. You also can't leave kudos or comments here.",
                fontSize = 12.sp,
                color = tokens.secondaryInk
            )
        }

        if (canRebuildFromOriginal) {
            MyCopyGroupHeader(title = "Conversion")
            Text(
                text = "The original file stays on your device, so you can rebuild this work without downloading it again.",
                fontSize = 12.sp,
                color = tokens.secondaryInk
            )

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = !isWorking, onClick = onRebuildFromOriginal)
                    .padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.Outlined.Refresh,
                    contentDescription = null,
                    tint = if (!isWorking) palette.accent else tokens.tertiaryInk,
                    modifier = Modifier.size(16.dp)
                )
                Text(
                    text = if (isWorking) "Rebuilding…" else "Rebuild from Original",
                    fontSize = 14.5.sp,
                    fontWeight = FontWeight.Medium,
                    color = if (!isWorking) palette.accent else tokens.tertiaryInk
                )
            }

            Text(
                text = "Rebuilding reads the original file again. Your progress, tags, and collections are kept.",
                fontSize = 12.sp,
                color = tokens.secondaryInk
            )
        }
    }
}

@Composable
private fun RemoteEmptyNotice(tokens: KudosTokens) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            text = "This work isn't in your Library yet. Save, queue, or start reading it to see its download, progress, and tags here.",
            fontSize = 14.sp,
            color = tokens.secondaryInk
        )
        Text(
            text = "Reading downloads this work to your device. When you finish, the file is freed unless you save or favorite it.",
            fontSize = 12.sp,
            color = tokens.tertiaryInk
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MyTagsSection(
    userTags: List<Tag>,
    tagSuggestions: List<String>,
    newTagName: String,
    onNewTagName: (String) -> Unit,
    onAddTag: () -> Unit,
    onRemoveTag: (Tag) -> Unit,
    onSuggestTag: (String) -> Unit,
    palette: SubjectPalette,
    isWorking: Boolean
) {
    val tokens = LocalKudosTokens.current

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        MyCopyGroupHeader(title = "My tags", note = "private")

        if (userTags.isNotEmpty()) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                userTags.forEach { tag ->
                    MyTagChip(
                        name = tag.normalizedName,
                        onRemove = { onRemoveTag(tag) },
                        palette = palette,
                        enabled = !isWorking
                    )
                }
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .background(tokens.glassFill(0.08))
                .border(0.5.dp, tokens.glassStroke(0.12), RoundedCornerShape(10.dp))
                .padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            BasicTextField(
                value = newTagName,
                onValueChange = onNewTagName,
                singleLine = true,
                textStyle = TextStyle(
                    fontSize = 14.sp,
                    color = tokens.primaryInk
                ),
                cursorBrush = SolidColor(palette.accent),
                modifier = Modifier.weight(1f),
                decorationBox = { innerTextField ->
                    if (newTagName.isEmpty()) {
                        Text("Add a tag", fontSize = 14.sp, color = tokens.secondaryInk)
                    }
                    innerTextField()
                }
            )
            Text(
                text = "Add",
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = if (newTagName.isNotBlank() && !isWorking) palette.accent else tokens.tertiaryInk,
                modifier = Modifier.clickable(
                    enabled = newTagName.isNotBlank() && !isWorking,
                    onClick = onAddTag
                )
            )
        }

        if (tagSuggestions.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(7.dp)
            ) {
                tagSuggestions.forEach { suggestion ->
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(tokens.glassFill(0.08))
                            .border(0.5.dp, tokens.glassStroke(0.12), RoundedCornerShape(8.dp))
                            .clickable(enabled = !isWorking) { onSuggestTag(suggestion) }
                            .padding(horizontal = 11.dp, vertical = 6.dp)
                    ) {
                        Text(
                            text = suggestion,
                            fontSize = 13.5.sp,
                            color = tokens.primaryInk
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MyTagChip(
    name: String,
    onRemove: () -> Unit,
    palette: SubjectPalette,
    enabled: Boolean
) {
    val shape = RoundedCornerShape(8.dp)
    Row(
        modifier = Modifier
            .clip(shape)
            .background(palette.accent.copy(alpha = 0.16f))
            .border(0.5.dp, palette.accent.copy(alpha = 0.22f), shape)
            .padding(start = 11.dp, end = 9.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp)
    ) {
        Text(
            text = name,
            fontSize = 13.5.sp,
            fontWeight = FontWeight.Medium,
            color = palette.accent
        )
        Box(
            modifier = Modifier
                .size(16.dp)
                .clickable(enabled = enabled, onClick = onRemove),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Filled.Remove,
                contentDescription = "Remove tag $name",
                tint = palette.accent.copy(alpha = 0.6f),
                modifier = Modifier.size(12.dp)
            )
        }
    }
}

@Composable
fun MyCopyGroupHeader(
    title: String,
    modifier: Modifier = Modifier,
    note: String? = null
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 16.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        SubjectFieldLabel(text = title)
        if (note != null) {
            Text(
                text = "· $note",
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = LocalKudosTokens.current.tertiaryInk
            )
        }
    }
}

@Composable
private fun MyCopyToggleRow(
    title: String,
    isOn: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    palette: SubjectPalette
) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            text = title,
            fontSize = 14.5.sp,
            color = if (enabled) tokens.primaryInk else tokens.tertiaryInk,
            modifier = Modifier.weight(1f)
        )
        if (isOn) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = "On",
                tint = palette.accent,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

@Composable
private fun MyCopyValueRow(
    title: String,
    value: String,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            text = title,
            fontSize = 14.5.sp,
            color = tokens.primaryInk,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = value,
            fontSize = 13.sp,
            color = tokens.secondaryInk,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun MyCopyAddLabel(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    palette: SubjectPalette,
    enabled: Boolean = true
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(
            imageVector = Icons.Filled.Add,
            contentDescription = null,
            tint = if (enabled) palette.accent else LocalKudosTokens.current.tertiaryInk,
            modifier = Modifier.size(14.dp)
        )
        Text(
            text = title,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = if (enabled) palette.accent else LocalKudosTokens.current.tertiaryInk
        )
    }
}

private fun formatInstant(instant: Instant): String {
    val formatter = DateTimeFormatter
        .ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withZone(ZoneId.systemDefault())
    return formatter.format(instant)
}
