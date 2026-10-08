package io.github.cidy02.kudos.writing

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.theme.LocalKudosTokens
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectMetrics

import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient

@Composable
fun WritingChaptersScreen(
    workID: Long,
    workTitle: String,
    client: AO3AuthenticatedClient,
    auth: AO3AuthRepository,
    onBack: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val model = remember(workID) { WritingChaptersState(workID, client, auth, scope) }
    val state by model.state.collectAsState()
    val tokens = LocalKudosTokens.current

    LaunchedEffect(auth.sessionGeneration) {
        model.reload()
    }

    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = onBack) {
        LazyColumn() {
            item {
                SubjectHeaderBlock(
                    kicker = "AO3 Account",
                    title = "Chapters",
                    subtitle = subtitle(workTitle, state.chapters?.size),
                    palette = tokens.scopePalette,
                    gutter = SubjectMetrics.accountGutter
                )
            }
            if (state.chapters != null && state.loadedGeneration == auth.sessionGeneration) {
                item {
                    SettingsPanel(Modifier.padding(top = 20.dp)) {
                        state.chapters!!.forEachIndexed { index, chapter ->
                            SubjectFormRow(
                                label = chapter.displayName,
                                value = chapter.dateText,
                                valueMaxLines = Int.MAX_VALUE,
                                showsDisclosure = false
                            )
                            if (index < state.chapters!!.size - 1) {
                                SubjectRowSeparator()
                            }
                        }
                    }
                }
            } else if (state.errorMessage != null) {
                item {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 18.dp, start = SubjectMetrics.accountGutter, end = SubjectMetrics.accountGutter),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(state.errorMessage!!)
                        Button(onClick = { model.reload() }, modifier = Modifier.padding(top = 8.dp)) {
                            Text("Try Again")
                        }
                    }
                }
            } else {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 18.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator()
                        Text("Loading chapters…", modifier = Modifier.padding(top = 48.dp))
                    }
                }
            }
        }
    }
}

private fun subtitle(workTitle: String, count: Int?): String {
    if (count == null) return workTitle
    return "$workTitle · $count ${if (count == 1) "chapter" else "chapters"}"
}
