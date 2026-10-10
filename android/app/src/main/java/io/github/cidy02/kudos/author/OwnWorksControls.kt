package io.github.cidy02.kudos.author

import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.writing.workFormFailure
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal fun isOwnWorks(username: String?, routeUsername: String): Boolean = username?.equals(routeUsername, true) == true
internal fun offersOwnWorkChapter(work: AO3WorkSummary) = work.isComplete != true
internal fun ownWorksDeleteTitle(works: List<AO3WorkSummary>) = if (works.size == 1) "Delete “${works.first().title}”?" else "Delete ${works.size} works?"
internal fun ownWorksDeleteMessage(works: List<AO3WorkSummary>): String {
    if (works.size == 1) return "This permanently removes the work and its chapters, kudos, comments and bookmarks from AO3 for everyone."
    val titles = android.icu.text.ListFormatter.getInstance().format(works.map { "“${it.title}”" })
    return "This permanently removes $titles and their chapters, kudos, comments and bookmarks from AO3 for everyone."
}
internal data class OwnWorksDeleteUi(val pending: List<AO3WorkSummary>? = null, val busy: Boolean = false,
    val error: String? = null, val confirmed: Int = 0)
internal class OwnWorksDeleteState(private val writes: AO3WriteRepository, private val generation: Int) {
    private val mutable = MutableStateFlow(OwnWorksDeleteUi())
    val state = mutable.asStateFlow()
    private var active = true
    private var bulk = true
    fun ask(works: List<AO3WorkSummary>, multiple: Boolean = true) {
        if (active && !state.value.busy && works.isNotEmpty()) { bulk = multiple; mutable.value = state.value.copy(pending = works.toList()) }
    }
    fun cancel() { mutable.value = state.value.copy(pending = null) }
    fun dismissError() { mutable.value = state.value.copy(error = null) }
    suspend fun confirm() {
        val old = state.value
        val works = old.pending ?: return
        if (!active || old.busy) return
        mutable.value = old.copy(pending = null, busy = true, error = null)
        try {
            val answer = if (bulk) writes.deleteWorks(works.map { it.id }, generation) else writes.deleteWork(works.single().id, generation)
            if (active) mutable.value = when (answer) {
                is AO3Result.Success -> state.value.copy(confirmed = state.value.confirmed + 1)
                is AO3Result.Failure -> state.value.copy(error = workFormFailure(answer.error))
            }
        } catch (_: CancellationException) {
            if (active) mutable.value = state.value.copy(error = "Your AO3 session changed, so nothing was deleted.")
        } catch (error: Exception) {
            if (active) mutable.value = state.value.copy(error = workFormFailure(
                if (error is java.io.IOException) AO3Error.networkFromTransport(error) else AO3Error.Network(error.message.orEmpty(), error)))
        } finally { if (active) mutable.value = state.value.copy(busy = false) }
    }
    fun close() { active = false }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun OwnWorksBulkBar(count: Int, busy: Boolean, onEdit: (String?) -> Unit, onDelete: () -> Unit, modifier: Modifier = Modifier) {
    val tokens = LocalKudosTokens.current
    FlowRow(modifier.fillMaxWidth().subjectPanel().padding(8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        for ((title, focus) in listOf((if (count > 0) "Edit $count" else "Edit") to null,
            "Collections" to "Collections and gifts", "Visibility" to "Comments and visibility", "Delete" to "delete")) {
            TextButton(enabled = count > 0 && !busy, onClick = { if (focus == "delete") onDelete() else onEdit(focus) },
                colors = ButtonDefaults.textButtonColors(contentColor = if (focus == "delete") SubjectPalette.fromHue(0.0, tokens.theme).accent else tokens.scopePalette.accent,
                    disabledContentColor = tokens.tertiaryInk)) { Text(title, fontSize = 14.sp, lineHeight = 20.sp) }
        }
        if (busy) CircularProgressIndicator(color = tokens.scopePalette.accent, trackColor = tokens.separator, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
    }
}

/** Android menu and trailing swipe reveal the same four actions; swiping never writes. */
@Composable
internal fun OwnWorkRow(work: AO3WorkSummary, onAction: (String) -> Unit, content: @Composable () -> Unit) {
    val tokens = LocalKudosTokens.current
    var expanded by remember(work.id) { mutableStateOf(false) }
    Box(Modifier.pointerInput(work.id) {
        var distance = 0f
        detectHorizontalDragGestures(onDragStart = { distance = 0f }, onDragEnd = { if (distance < -48f) expanded = true }) { _, amount -> distance += amount }
    }) {
        Column(Modifier.padding(top = 40.dp)) { content() }
        Box(Modifier.align(androidx.compose.ui.Alignment.TopEnd)) {
            IconButton(onClick = { expanded = true }) { Icon(Icons.Default.MoreVert, "Actions for ${work.title}", tint = tokens.scopePalette.accent) }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = tokens.cardFill) {
                for ((label, action) in listOf("Delete" to "delete", "Chapter" to "chapter", "Tags" to "tags", "Edit" to "edit")) {
                    if (action == "chapter" && !offersOwnWorkChapter(work)) continue
                    DropdownMenuItem(text = { Text(label, color = if (action == "delete") SubjectPalette.fromHue(0.0, tokens.theme).accent else tokens.primaryInk, lineHeight = 22.sp) },
                        onClick = { expanded = false; onAction(action) })
                }
            }
        }
    }
}
