package io.github.cidy02.kudos.writing

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterRef
import io.github.cidy02.kudos.ui.subject.*

/** iOS WritingChaptersView.subtitle. */
internal fun writingChaptersSubtitle(workTitle: String, count: Int?): String =
    if (count == null) workTitle else "$workTitle · $count ${if (count == 1) "chapter" else "chapters"}"

/**
 * iOS WritingChaptersView (part of 1bo): the work's chapters from AO3's own index, one read per
 * opening and per Try Again. Reading only: on iOS a row opens the chapter's edit form, which
 * Android has not got yet, so a row here has no mark and no action.
 */
@Composable
internal fun WritingChaptersScreen(
    workTitle: String,
    load: suspend () -> AO3Result<List<AO3ChapterRef>>,
    onBack: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    var chapters by remember { mutableStateOf<List<AO3ChapterRef>?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(attempt) {
        failure = null
        when (val result = load()) {
            is AO3Result.Success -> chapters = result.value
            // iOS keeps rows already shown when a later read fails.
            is AO3Result.Failure -> if (chapters == null) failure = workFormFailure(result.error)
        }
    }
    BackHandler(onBack = onBack)
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = onBack)
    LazyColumn(Modifier.fillMaxSize().subjectScreenWash(palette).testTag("Writing chapters"),
        contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            Spacer(Modifier.height(76.dp))
            SubjectHeaderBlock(kicker = "AO3 Account", title = "Chapters",
                subtitle = writingChaptersSubtitle(workTitle, chapters?.size), palette = palette,
                gutter = SubjectMetrics.accountGutter)
            Spacer(Modifier.height(12.dp))
        }
        val rows = chapters
        val message = failure
        when {
            rows != null -> itemsIndexed(rows, key = { _, chapter -> chapter.chapterId }) { index, chapter ->
                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                    .writingSuggestionPanel(first = index == 0, last = index == rows.lastIndex)) {
                    // The date as trailing content keeps its own width and the title wraps beside it. As a
                    // `value`, the shared row gave a long title the width and the date one letter to a line.
                    if (isAccessibilityFontScale()) SubjectFormRow(chapter.displayName, value = chapter.dateText,
                        valueMaxLines = Int.MAX_VALUE)
                    else SubjectFormRow(chapter.displayName, trailing = {
                        Text(chapter.dateText, color = tokens.secondaryInk, fontSize = 14.5.sp, lineHeight = 20.sp, maxLines = 1)
                    })
                    if (index < rows.lastIndex) SubjectRowSeparator()
                }
            }
            message != null -> item {
                Column(Modifier.fillMaxWidth().padding(top = 18.dp).padding(horizontal = SubjectMetrics.accountGutter),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(message, color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp, textAlign = TextAlign.Center)
                    TextButton(onClick = { attempt++ }, colors = ButtonDefaults.textButtonColors(contentColor = palette.accent)) {
                        Text("Try Again", color = palette.accent, fontSize = 14.sp, lineHeight = 20.sp)
                    }
                }
            }
            else -> item {
                Row(Modifier.fillMaxWidth().padding(top = 18.dp), horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator,
                        modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    Text("Loading chapters…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp,
                        modifier = Modifier.padding(start = 10.dp))
                }
            }
        }
    }
}
