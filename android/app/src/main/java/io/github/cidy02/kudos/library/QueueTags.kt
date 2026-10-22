package io.github.cidy02.kudos.library

import io.github.cidy02.kudos.app.DebugShotEffect
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.github.cidy02.kudos.core.model.ReadingQueue
import io.github.cidy02.kudos.core.model.Tag
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import kotlinx.coroutines.launch

/** How much of a selection carries a tag (iOS `WorkBulkTagSheet.Coverage`). */
enum class TagCoverage { All, Some, None }

/** Every tag there is, and how much of the selection carries each. */
data class SharedTags(val all: List<Tag>, val coverage: Map<String, TagCoverage>)

object BulkTags {
    /** [tagIdsByItem]: for each selected thing, the ids of the tags on it. */
    fun coverage(tags: List<Tag>, tagIdsByItem: List<Set<String>>): SharedTags =
        SharedTags(tags, tags.associate { tag ->
            val tagged = tagIdsByItem.count { tag.id in it }
            tag.id to when {
                tagged == 0 -> TagCoverage.None
                tagged == tagIdsByItem.size -> TagCoverage.All
                else -> TagCoverage.Some
            }
        })

    /** What TalkBack says of a row (iOS's accessibility values). */
    fun spoken(coverage: TagCoverage, noun: String): String = when (coverage) {
        TagCoverage.All -> "on every selected $noun"
        TagCoverage.Some -> "on some selected ${noun}s"
        TagCoverage.None -> "not applied"
    }
}

/** Tags apply as they are toggled. Done is the only way out. */
@Composable
fun QueueTagSheet(
    repository: ReadingQueueRepository,
    queues: List<ReadingQueue>,
    palette: SubjectPalette,
    onDismiss: () -> Unit
) {
    SharedTagSheet(
        title = "Tags",
        footnote = (if (queues.size > 1) "Your changes apply to all ${queues.size} selected queues. " else "") +
            "A tag you use here is the same tag on your works.",
        emptyNote = "You have no tags yet. Add one above.",
        noun = "queue",
        palette = palette,
        key = queues.map { it.id },
        load = {
            val tags = runCatching { repository.allTags() }.getOrDefault(emptyList())
            val byQueue = runCatching { repository.tagsByQueue() }.getOrDefault(emptyMap())
            BulkTags.coverage(tags, queues.map { queue -> byQueue[queue.id].orEmpty().mapTo(mutableSetOf()) { it.id } })
        },
        toggle = { name -> repository.toggleSharedTag(queues.map { it.id }, name) },
        onDismiss = onDismiss
    )
}

/**
 * iOS `WorkBulkTagSheet` (artboard 1af): your own tags across a selection of works. A tag is
 * on every work, on some, or on none; a tap puts it on the rest, or takes it off them all.
 * Local only: nothing here touches AO3.
 */
@Composable
fun WorkBulkTagSheet(
    workRepository: io.github.cidy02.kudos.works.WorkRepository,
    workIds: List<String>,
    palette: SubjectPalette,
    onDismiss: () -> Unit
) {
    SharedTagSheet(
        title = "Tag",
        footnote = if (workIds.size == 1) "Your changes apply to the selected work."
            else "Your changes apply to all ${workIds.size} selected works.",
        emptyNote = "You have no tags yet. Add one above to organize your Library.",
        noun = "work",
        palette = palette,
        key = workIds,
        load = { BulkTags.coverage(workRepository.allUserTags(), workRepository.userTagIdsByWork(workIds)) },
        toggle = { name -> workRepository.toggleUserTag(workIds, name) },
        onDismiss = onDismiss
    )
}

/** One sheet for both: what differs is whose tags are read and what a tap changes. */
@Composable
private fun SharedTagSheet(
    title: String,
    footnote: String,
    emptyNote: String,
    noun: String,
    palette: SubjectPalette,
    key: Any,
    load: suspend () -> SharedTags,
    toggle: suspend (String) -> Unit,
    onDismiss: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    var all by remember { mutableStateOf<List<Tag>>(emptyList()) }
    var coverage by remember { mutableStateOf<Map<String, TagCoverage>>(emptyMap()) }
    var draft by remember { mutableStateOf("") }
    var reload by remember { mutableIntStateOf(0) }

    LaunchedEffect(reload, key) {
        val shared = load()
        all = shared.all
        coverage = shared.coverage
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier
                .fillMaxSize()
                .subjectScreenWash(palette)
                .windowInsetsPadding(WindowInsets.safeDrawing)
        ) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = title,
                    modifier = Modifier.weight(1f).padding(start = 12.dp),
                    color = tokens.primaryInk,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold
                )
                TextButton(onClick = onDismiss) { Text("Done", color = palette.accent) }
            }
            Column(
                Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SubjectFieldLabel("Add")
                Row(
                    Modifier.fillMaxWidth().subjectPanel().padding(horizontal = 12.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Filled.Add, contentDescription = null, tint = palette.accent)
                    OutlinedTextField(
                        value = draft,
                        onValueChange = { draft = it },
                        modifier = Modifier.weight(1f),
                        placeholder = { Text("New tag") },
                        singleLine = true
                    )
                    TextButton(
                        onClick = {
                            val name = draft.trim()
                            if (name.isEmpty()) return@TextButton
                            val existing = all.firstOrNull { it.name.equals(name, ignoreCase = true) }
                            scope.launch {
                                // Typing a tag only ever adds it: one already on everything stays.
                                if (existing == null || coverage[existing.id] != TagCoverage.All) toggle(name)
                                draft = ""
                                reload += 1
                            }
                        },
                        enabled = draft.isNotBlank()
                    ) { Text("Add", color = palette.accent) }
                }
                FormFootnote(footnote)
                SubjectFieldLabel("Your tags", Modifier.padding(top = 12.dp))
                if (all.isEmpty()) {
                    FormFootnote(emptyNote)
                } else {
                    Column(Modifier.fillMaxWidth().subjectPanel()) {
                        all.forEachIndexed { index, tag ->
                            if (index > 0) SubjectRowSeparator()
                            val state = coverage[tag.id] ?: TagCoverage.None
                            SubjectFormRow(
                                label = tag.name,
                                modifier = Modifier.semantics { stateDescription = BulkTags.spoken(state, noun) },
                                onClick = {
                                    scope.launch {
                                        toggle(tag.name)
                                        reload += 1
                                    }
                                },
                                trailing = {
                                    Text(
                                        text = when (state) {
                                            TagCoverage.All -> "All"
                                            TagCoverage.Some -> "Some"
                                            TagCoverage.None -> ""
                                        },
                                        color = if (state == TagCoverage.All) palette.accent else tokens.secondaryInk,
                                        fontSize = 13.sp
                                    )
                                    if (state == TagCoverage.All) {
                                        Icon(Icons.Filled.Check, contentDescription = null, tint = palette.accent)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

/** Shared vocabulary for one queue. Counts are works in this queue only. */
@Composable
fun QueueTagManager(
    repository: ReadingQueueRepository,
    queue: ReadingQueue,
    palette: SubjectPalette,
    workCount: Int,
    onBack: () -> Unit,
    onShowOnlyTag: (String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    var tags by remember { mutableStateOf<List<Tag>>(emptyList()) }
    var counts by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var others by remember { mutableStateOf<List<ReadingQueue>>(emptyList()) }
    var reload by remember { mutableIntStateOf(0) }
    var editing by remember { mutableStateOf<Tag?>(null) }
    DebugShotEffect("queue-tag-manager", ready = tags.any { it.name == "Rereads" }) {
        editing = tags.first { it.name == "Rereads" }
    }

    var copying by remember { mutableStateOf<Tag?>(null) }
    var pending by remember { mutableStateOf<Tag?>(null) }
    var draft by remember { mutableStateOf("") }

    LaunchedEffect(queue.id, reload) {
        tags = runCatching { repository.tagsForQueue(queue.id) }.getOrDefault(emptyList())
        counts = runCatching { repository.workTagCounts(queue.id) }.getOrDefault(emptyMap())
        others = runCatching {
            repository.listQueues().filter { it.id != queue.id && !it.isDeleted }
        }.getOrDefault(emptyList())
    }

    val used = tags.filter { (counts[it.id] ?: 0) > 0 }.sortedByDescending { counts[it.id] ?: 0 }
    val unused = tags.filter { (counts[it.id] ?: 0) == 0 }.sortedBy { it.name.lowercase() }
    val tally = if (tags.isEmpty()) {
        "No tags on this queue yet"
    } else {
        val n = tags.size
        "$n tag${if (n == 1) "" else "s"} across $workCount work${if (workCount == 1) "" else "s"}"
    }

    Column(
        Modifier
            .fillMaxSize()
            .subjectScreenWash(palette)
            .verticalScroll(rememberScrollState())
    ) {
        Spacer(Modifier.height(WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp))
        SubjectHeaderBlock(
            kicker = queue.displayName,
            title = "Tags",
            subtitle = tally,
            palette = palette
        )
        if (used.isNotEmpty()) {
            SubjectFieldLabel("In this queue", Modifier.padding(start = 16.dp, top = 18.dp))
            TagRows(used, counts) { tag, action ->
                when (action) {
                    TagAction.Edit -> editing = tag
                    TagAction.Copy -> copying = tag
                    TagAction.Remove -> pending = tag
                    TagAction.Show -> onShowOnlyTag(tag.name)
                }
            }
        }
        if (unused.isNotEmpty()) {
            SubjectFieldLabel("Unused", Modifier.padding(start = 16.dp, top = 18.dp))
            TagRows(unused, counts) { tag, action ->
                when (action) {
                    TagAction.Edit -> editing = tag
                    TagAction.Copy -> copying = tag
                    TagAction.Remove -> pending = tag
                    TagAction.Show -> onShowOnlyTag(tag.name)
                }
            }
            FormFootnote("Unused tags stay here until you remove them. You can apply them later.")
        }
        SubjectFieldLabel("Add", Modifier.padding(start = 16.dp, top = 18.dp))
        Row(
            Modifier
                .padding(horizontal = 16.dp)
                .fillMaxWidth()
                .subjectPanel()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = palette.accent)
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("New tag") },
                singleLine = true
            )
            TextButton(
                onClick = {
                    val name = draft.trim()
                    if (name.isEmpty()) return@TextButton
                    scope.launch {
                        if (tags.none { it.name.equals(name, ignoreCase = true) }) {
                            repository.toggleSharedTag(listOf(queue.id), name)
                        }
                        draft = ""
                        reload += 1
                    }
                },
                enabled = draft.isNotBlank()
            ) { Text("Add", color = palette.accent) }
        }
        FormFootnote("A tag you use here is the same tag on your works.")
    }

    editing?.let { tag ->
        QueueTagEditDialog(
            repository = repository,
            queueId = queue.id,
            tag = tag,
            siblings = tags.filter { it.id != tag.id },
            count = counts[tag.id] ?: 0,
            onDismiss = { editing = null },
            onRemove = { editing = null; pending = tag },
            onChanged = { editing = null; reload += 1 }
        )
    }
    copying?.let { tag ->
        AlertDialog(
            onDismissRequest = { copying = null },
            title = { Text("Copy tag to another queue") },
            text = {
                Column {
                    if (others.isEmpty()) Text("No other queues.")
                    others.forEach { destination ->
                        Text(
                            text = destination.displayName,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    scope.launch {
                                        repository.copyTagToQueue(tag.name, destination.id)
                                        copying = null
                                    }
                                }
                                .padding(vertical = 10.dp),
                            color = tokens.primaryInk
                        )
                    }
                }
            },
            confirmButton = { TextButton(onClick = { copying = null }) { Text("Cancel") } }
        )
    }
    pending?.let { tag ->
        val count = counts[tag.id] ?: 0
        AlertDialog(
            onDismissRequest = { pending = null },
            title = {
                Text(
                    if (count == 0) "Remove “${tag.name}” from this queue?"
                    else "Remove “${tag.name}” from $count work${if (count == 1) "" else "s"}?"
                )
            },
            text = {
                Text(
                    when (count) {
                        0 -> "This tag stays on your other works and queues."
                        1 -> "That work keeps its other tags. Works outside this queue keep this tag."
                        else -> "Those works keep their other tags. Works outside this queue keep this tag."
                    }
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    pending = null
                    scope.launch {
                        repository.stripQueueTag(queue.id, tag.id)
                        reload += 1
                    }
                }) { Text("Remove") }
            },
            dismissButton = { TextButton(onClick = { pending = null }) { Text("Cancel") } }
        )
    }
}

private enum class TagAction { Edit, Copy, Remove, Show }

@Composable
private fun TagRows(
    tags: List<Tag>,
    counts: Map<String, Int>,
    onAction: (Tag, TagAction) -> Unit
) {
    val tokens = LocalKudosTokens.current
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp).fillMaxWidth().subjectPanel()) {
        tags.forEachIndexed { index, tag ->
            if (index > 0) SubjectRowSeparator()
            var open by remember(tag.id) { mutableStateOf(false) }
            val count = counts[tag.id] ?: 0
            BoxMenuRow(
                label = tag.name,
                value = count.toString(),
                open = open,
                onOpen = { open = true },
                onDismiss = { open = false },
                tokensInk = tokens.secondaryInk
            ) {
                DropdownMenuItem(text = { Text("Rename") }, onClick = { open = false; onAction(tag, TagAction.Edit) })
                DropdownMenuItem(text = { Text("Merge into…") }, onClick = { open = false; onAction(tag, TagAction.Edit) })
                DropdownMenuItem(text = { Text("Show only this tag") }, onClick = { open = false; onAction(tag, TagAction.Show) })
                DropdownMenuItem(text = { Text("Copy tag to another queue") }, onClick = { open = false; onAction(tag, TagAction.Copy) })
                DropdownMenuItem(
                    text = { Text("Remove from $count work${if (count == 1) "" else "s"}") },
                    onClick = { open = false; onAction(tag, TagAction.Remove) }
                )
            }
        }
    }
}

@Composable
private fun BoxMenuRow(
    label: String,
    value: String,
    open: Boolean,
    onOpen: () -> Unit,
    onDismiss: () -> Unit,
    tokensInk: androidx.compose.ui.graphics.Color,
    menu: @Composable () -> Unit
) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, modifier = Modifier.weight(1f).padding(start = 8.dp), color = LocalKudosTokens.current.primaryInk)
        Text(value, color = tokensInk, fontSize = 15.sp)
        Icon(Icons.Filled.MoreVert, contentDescription = "Tag actions", tint = tokensInk)
        DropdownMenu(expanded = open, onDismissRequest = onDismiss) { menu() }
    }
}

@Composable
private fun QueueTagEditDialog(
    repository: ReadingQueueRepository,
    queueId: String,
    tag: Tag,
    siblings: List<Tag>,
    count: Int,
    onRemove: () -> Unit,
    onDismiss: () -> Unit,
    onChanged: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var name by remember(tag.id) { mutableStateOf(tag.name) }
    var conflict by remember { mutableStateOf<Tag?>(null) }
    var mergeTarget by remember { mutableStateOf<Tag?>(null) }
    val trimmed = name.trim()
    val blocked = trimmed.isEmpty() || trimmed == tag.name || (conflict != null && conflict?.name != trimmed)

    LaunchedEffect(trimmed) {
        conflict = if (trimmed.isEmpty() || trimmed == tag.name) null
        else runCatching { repository.tagRenameConflict(tag.id, trimmed) }.getOrNull()
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit tag") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = name, onValueChange = { name = it }, label = { Text("Name") }, singleLine = true)
                Text(
                    text = if (conflict?.name == trimmed) {
                        "Saving merges these tags on all works and queues."
                    } else if (conflict != null) {
                        "You already have a tag called “${conflict?.name}”."
                    } else {
                        "Renaming this tag also renames it on your works and other queues."
                    },
                    fontSize = 12.sp,
                    color = LocalKudosTokens.current.secondaryInk
                )
                TextButton(onClick = onRemove) {
                    Text(if (count == 0) "Remove from this queue" else "Remove tag from $count work${if (count == 1) "" else "s"}",
                        color = androidx.compose.material3.MaterialTheme.colorScheme.error)
                }
                if (siblings.isNotEmpty()) {
                    SubjectFieldLabel("Merge into another tag")
                    siblings.forEach { sibling ->
                        Text(
                            text = sibling.name,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { mergeTarget = sibling }
                                .padding(vertical = 8.dp)
                        )
                    }
                    Text(
                        text = when (count) {
                            0 -> "No work in this queue uses “${tag.name}”. Merging removes the tag from this queue."
                            1 -> "The 1 work in this queue gets the tag you pick, and “${tag.name}” leaves the queue. You can't undo this in Kudos."
                            else -> "All $count works in this queue get the tag you pick, and “${tag.name}” leaves the queue. You can't undo this in Kudos."
                        },
                        fontSize = 12.sp,
                        color = LocalKudosTokens.current.secondaryInk
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    scope.launch {
                        repository.renameUserTag(tag.id, trimmed)
                        onChanged()
                    }
                },
                enabled = !blocked
            ) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
    mergeTarget?.let { target ->
        AlertDialog(
            onDismissRequest = { mergeTarget = null },
            title = { Text("Merge “${tag.name}” into “${target.name}”?") },
            text = { Text("You can't undo this in Kudos.") },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch {
                        repository.mergeQueueTag(queueId, tag.id, target.id)
                        mergeTarget = null
                        onChanged()
                    }
                }) { Text("Merge") }
            },
            dismissButton = { TextButton(onClick = { mergeTarget = null }) { Text("Cancel") } }
        )
    }
}
