package io.github.cidy02.kudos.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.works.WorkRepository
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import io.github.cidy02.kudos.network.ao3.browse.FandomCatalogCache
import io.github.cidy02.kudos.core.model.KudosSettings
import io.github.cidy02.kudos.ui.components.DestructiveConfirmation
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.launch

@Composable
fun PrivacyDataScreen(
    workRepository: WorkRepository?,
    fandomCatalogCache: FandomCatalogCache?,
    settings: KudosSettings
) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) {
        chrome.customTitle = null
        chrome.hasSubjectHeader = true
    }

    val palette = LocalSubjectPalette.current
    val tokens = LocalKudosTokens.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val effectiveFandomCatalogCache = remember(fandomCatalogCache, context) {
        fandomCatalogCache ?: FandomCatalogCache(context.cacheDir.toPath())
    }

    // Observe works to count
    val works by (workRepository?.observeSavedWorks() ?: kotlinx.coroutines.flow.flowOf(emptyList())).collectAsState(initial = emptyList())
    val historyOnlyWorks by (workRepository?.observeHistoryOnlyWorks() ?: kotlinx.coroutines.flow.flowOf(emptyList())).collectAsState(initial = emptyList())
    val positionedWorks by (workRepository?.observePositionedWorks() ?: kotlinx.coroutines.flow.flowOf(emptyList())).collectAsState(initial = emptyList())
    var showClearPositionsConfirm by remember { mutableStateOf(false) }
    val freeableCopies by (workRepository?.observeFreeableCopies() ?: kotlinx.coroutines.flow.flowOf(emptyList())).collectAsState(initial = emptyList())

    val readingCopies = works.size
    var browseCacheCleared by remember { mutableStateOf(false) }

    var showFreeUpSpaceConfirm by remember { mutableStateOf(false) }
    var showClearHistoryConfirm by remember { mutableStateOf(false) }
    var showClearBrowseCacheConfirm by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .subjectScreenWash(palette),
        contentPadding = PaddingValues(bottom = 20.dp)
    ) {
        item {
            Spacer(Modifier.height(WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp))
            SubjectHeaderBlock(
                kicker = "AO3 Account › Settings",
                title = "Privacy",
                subtitle = "Your reading data stays on this device",
                palette = palette,
                gutter = SubjectMetrics.accountGutter
            )
        }

        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(
                    modifier = Modifier
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                        .padding(16.dp)
                ) {
                    Text(
                        "No ads or tracking, and no separate Kudos account",
                        style = MaterialTheme.typography.titleMedium,
                        color = tokens.primaryInk
                    )
                    Text(
                        "Kudos connects to AO3. After you approve a Voice Pack download, it also connects to the service providing the pack. Your library, reading positions, tags, collections, and AO3 sign-in stay on this device.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = tokens.secondaryInk,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }
            }
        }

        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                SectionRuleHeader("Stored on this device")
                Column(
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    SubjectFormRow("Reading copies", value = "$readingCopies works")
                    SubjectRowSeparator()
                    SubjectFormRow("Caches", value = if (browseCacheCleared) "0 MB" else "Unknown")
                    SubjectRowSeparator()
                    SubjectFormRow("Reading positions", value = "0")
                    SubjectRowSeparator()
                    SubjectFormRow("Local collections", value = "0")
                    SubjectRowSeparator()
                    SubjectFormRow("Saved searches", value = "0")
                    SubjectRowSeparator()
                    SubjectFormRow("Search history", value = "Not recorded")
                }
            }
        }

        item {
            Column(modifier = Modifier.padding(top = 18.dp)) {
                Column(
                    modifier = Modifier
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .subjectPanel()
                ) {
                    SubjectFormRow("Free up space", value = "${freeableCopies.size} files", showsDisclosure = true, onClick = { if (freeableCopies.isNotEmpty()) showFreeUpSpaceConfirm = true })
                    SubjectRowSeparator()
                    SubjectFormRow("Clear reading positions", value = countLabel(positionedWorks.size, "work"), showsDisclosure = true,
                        onClick = { if (positionedWorks.isNotEmpty()) showClearPositionsConfirm = true })
                    SubjectRowSeparator()
                    SubjectFormRow("Clear reading history", value = countLabel(historyOnlyWorks.size, "work"), showsDisclosure = true,
                        onClick = { if (historyOnlyWorks.isNotEmpty()) showClearHistoryConfirm = true })
                    SubjectRowSeparator()
                    SubjectFormRow(if (browseCacheCleared) "Browse Cache Cleared" else "Clear browse cache", showsDisclosure = true, onClick = { if (!browseCacheCleared) showClearBrowseCacheConfirm = true })
                }
                
                Text(
                    text = "The sizes shown are measured on this device. Browse keeps fandom and category lists so it opens faster; it rebuilds them when needed, and your device may remove them to free space.\n\nEach option asks before it clears anything and tells you what will change on this device. Your AO3 reading history is separate; clear it from History or turn it off in AO3 Preferences.",
                    style = MaterialTheme.typography.bodySmall,
                    color = tokens.secondaryInk,
                    modifier = Modifier
                        .padding(horizontal = SubjectMetrics.accountGutter)
                        .padding(top = 8.dp)
                )
            }
        }
    }

    DestructiveConfirmation(
        show = showFreeUpSpaceConfirm,
        title = "Free Up Space?",
        text = "Removes the copies of works you've finished reading and didn't download, favourite or queue. Kudos gets them again from AO3 if you open them.",
        confirmText = "Free ${freeableCopies.size} ${if (freeableCopies.size == 1) "File" else "Files"}",
        confirmBeforeDelete = settings.app.confirmBeforeDelete,
        onConfirm = {
            showFreeUpSpaceConfirm = false
            scope.launch { workRepository?.freeFinishedCopies() }
        },
        onDismissRequest = { showFreeUpSpaceConfirm = false }
    )

    DestructiveConfirmation(
        show = showClearHistoryConfirm,
        title = "Clear Reading History?",
        text = "Moves works that only remain in your reading history to Recently Deleted for 90 days. Your saved and downloaded works stay where they are, and you can download these works from AO3 again.",
        confirmText = "Clear ${countLabel(historyOnlyWorks.size, "Work")}",
        confirmBeforeDelete = settings.app.confirmBeforeDelete,
        onConfirm = {
            showClearHistoryConfirm = false
            scope.launch { workRepository?.softDeleteHistoryOnly() }
        },
        onDismissRequest = { showClearHistoryConfirm = false }
    )

    DestructiveConfirmation(
        show = showClearPositionsConfirm,
        title = "Clear Reading Positions?",
        text = "Clears your place in every work. Your works and their order in Continue Reading stay the same.",
        confirmText = "Clear ${countLabel(positionedWorks.size, "Position")}",
        confirmBeforeDelete = settings.app.confirmBeforeDelete,
        onConfirm = {
            showClearPositionsConfirm = false
            scope.launch { workRepository?.clearReadingPositions() }
        },
        onDismissRequest = { showClearPositionsConfirm = false }
    )

    DestructiveConfirmation(
        show = showClearBrowseCacheConfirm,
        title = "Clear Browse Cache?",
        text = "Removes saved fandom and category lists. Your reading, saved works, and downloads stay untouched; Browse rebuilds the lists next time you open it.",
        confirmText = "Clear",
        confirmBeforeDelete = settings.app.confirmBeforeDelete,
        onConfirm = {
            showClearBrowseCacheConfirm = false
            scope.launch {
                effectiveFandomCatalogCache.clear()
                browseCacheCleared = true
            }
        },
        onDismissRequest = { showClearBrowseCacheConfirm = false }
    )
}

/** iOS `PrivacyDataView.countLabel`. */
private fun countLabel(count: Int, noun: String): String = "$count $noun${if (count == 1) "" else "s"}"
