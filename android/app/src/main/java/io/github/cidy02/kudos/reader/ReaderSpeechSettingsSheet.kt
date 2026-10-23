package io.github.cidy02.kudos.reader

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import io.github.cidy02.kudos.settings.SettingsListeningContent
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSettingsFormGround
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.ToolbarCircleButton
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/** Same Listening controls, with an independent audition engine so the book keeps playing. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ReaderSpeechSettingsSheet(
    repository: SettingsRepository,
    onDismiss: (ReaderSpeechPreferences) -> Unit,
    listeningContent: @Composable (@Composable (@Composable () -> Unit) -> Unit) -> Unit = { frame ->
        SettingsListeningContent(repository, frame)
    }
) {
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    // Read the saved values, rather than a potentially older reader-state emission, on every close path.
    val dismiss = { scope.launch { onDismiss(repository.speechPreferences.first()) }; Unit }
    ModalBottomSheet(
        onDismissRequest = dismiss,
        // Half height first, as iOS's medium detent: a tweak-while-listening sheet (A85).
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false),
        containerColor = tokens.background,
        contentColor = tokens.primaryInk
    ) {
        CompositionLocalProvider(LocalSettingsFormGround provides true) {
            Column {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.accountGutter),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Read Aloud", color = tokens.primaryInk, fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    ToolbarCircleButton(onClick = dismiss, accessibilityName = "Done") {
                        Icon(Icons.Filled.Check, contentDescription = null, tint = tokens.scopePalette.accent)
                    }
                }
                listeningContent { content ->
                    LazyColumn(Modifier.fillMaxWidth().padding(bottom = 24.dp)) { item { content() } }
                }
            }
        }
    }
}
