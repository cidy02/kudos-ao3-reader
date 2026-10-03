package io.github.cidy02.kudos.library

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.core.model.WorkCollection
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.works.WorkRepository
import kotlinx.coroutines.launch

/**
 * Artboard **1bk**'s "Reorder works".
 * Reads works in reader order and lets the user adjust their sequence.
 * The order is committed on Done rather than on every move to avoid continuous database writes.
 */
@Composable
fun CollectionReorderSheet(
    collection: WorkCollection,
    works: List<SavedWork>,
    workRepository: WorkRepository,
    onDismiss: () -> Unit,
    onSaved: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    var ordered by remember(works) { mutableStateOf(works) }
    var saving by remember { mutableStateOf(false) }

    val palette = collectionDraftPalette(tokens.theme, tokens.scopePalette, collection.hue, collection.colorHex)

    fun moveWork(fromIndex: Int, toIndex: Int) {
        if (fromIndex !in ordered.indices || toIndex !in ordered.indices) return
        val list = ordered.toMutableList()
        val item = list.removeAt(fromIndex)
        list.add(toIndex, item)
        ordered = list
    }

    Dialog(
        onDismissRequest = { if (!saving) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .subjectScreenWash(palette)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .windowInsetsPadding(WindowInsets.ime)
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onDismiss, enabled = !saving) { Text("Cancel") }
                Text(
                    text = "Reorder works",
                    modifier = Modifier.weight(1f),
                    color = tokens.primaryInk,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold
                )
                TextButton(
                    onClick = {
                        saving = true
                        scope.launch {
                            workRepository.setCollectionReadingOrder(
                                collectionId = collection.id,
                                orderedWorkIds = ordered.map { it.id }
                            )
                            saving = false
                            onSaved()
                        }
                    },
                    enabled = !saving
                ) {
                    Text(
                        text = "Done",
                        color = palette.accent,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                item {
                    SubjectHeaderBlock(
                        kicker = "Library › Collections",
                        title = "Reorder",
                        subtitle = collection.name,
                        palette = palette,
                        modifier = Modifier.padding(top = 12.dp, bottom = 10.dp)
                    )
                }

                item {
                    SubjectFieldLabel("Reading order", Modifier.padding(top = 8.dp, bottom = 4.dp))
                }

                itemsIndexed(ordered, key = { _, work -> work.id }) { index, work ->
                    val position = index + 1
                    val shape = RoundedCornerShape(12.dp)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(shape)
                            .background(tokens.glassFill(0.09))
                            .border(0.5.dp, tokens.glassStroke(0.13), shape)
                            .padding(horizontal = 12.dp, vertical = 10.dp)
                            .semantics {
                                contentDescription = if (work.author.isEmpty()) {
                                    "$position. ${work.title}"
                                } else {
                                    "$position. ${work.title}, ${work.author}"
                                }
                            },
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Text(
                            text = "$position",
                            color = palette.accent,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                            fontFamily = FontFamily.Monospace,
                            modifier = Modifier.widthIn(min = 24.dp)
                        )
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                text = work.title,
                                color = tokens.primaryInk,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis
                            )
                            if (work.author.isNotEmpty()) {
                                Text(
                                    text = work.author,
                                    color = tokens.secondaryInk,
                                    fontSize = 12.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            IconButton(
                                onClick = { moveWork(index, index - 1) },
                                enabled = index > 0 && !saving,
                                modifier = Modifier.size(36.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.KeyboardArrowUp,
                                    contentDescription = "Move up",
                                    tint = if (index > 0) tokens.primaryInk else tokens.tertiaryInk
                                )
                            }
                            IconButton(
                                onClick = { moveWork(index, index + 1) },
                                enabled = index < ordered.size - 1 && !saving,
                                modifier = Modifier.size(36.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.KeyboardArrowDown,
                                    contentDescription = "Move down",
                                    tint = if (index < ordered.size - 1) tokens.primaryInk else tokens.tertiaryInk
                                )
                            }
                        }
                    }
                }

                item {
                    Spacer(Modifier.padding(top = 8.dp))
                    FormFootnote(
                        "This order is used when no filter is on. Works you add later, or restore from " +
                            "Recently Deleted after tapping Done, appear at the end."
                    )
                    Spacer(Modifier.padding(bottom = 24.dp))
                }
            }
        }
    }
}
