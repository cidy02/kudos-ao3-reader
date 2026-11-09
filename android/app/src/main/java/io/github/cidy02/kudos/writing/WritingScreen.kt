package io.github.cidy02.kudos.writing

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CollectionsBookmark
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Drafts
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.account.AO3AccountListCountsCache
import io.github.cidy02.kudos.account.AccountListType
import io.github.cidy02.kudos.account.WritingDraftsRepository
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.AO3AuthState
import io.github.cidy02.kudos.auth.AO3PostingPseudStore
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.writing.AO3DraftsPage
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.ToolbarAddButton
import kotlinx.coroutines.launch

internal data class WritingRootState(
    val isSignedIn: Boolean,
    val draftsLoaded: Boolean,
    val latestDraft: AO3WorkSummary?
)

internal fun writingRootState(isSignedIn: Boolean, drafts: AO3DraftsPage?): WritingRootState =
    WritingRootState(
        isSignedIn,
        draftsLoaded = isSignedIn && drafts != null,
        latestDraft = if (isSignedIn) drafts?.page?.works?.firstOrNull() else null
    )

class WritingShellChrome {
    var mounted by mutableStateOf(false)
    var canCreateWork by mutableStateOf(false)
    var onNewWork: () -> Unit = {}

    fun reset() {
        mounted = false
        canCreateWork = false
        onNewWork = {}
    }
}

@Composable
fun WritingToolbarActions(chrome: WritingShellChrome) {
    if (chrome.canCreateWork) {
        ToolbarAddButton(onClick = chrome.onNewWork, accessibilityName = "New Work")
    }
}

/** Cache-only creator launchpad. Opening it never asks AO3 for another page. */
@Composable
fun WritingScreen(
    authRepository: AO3AuthRepository,
    draftsRepository: WritingDraftsRepository,
    authorRepository: AO3AuthorRepository,
    inboxRepository: AO3InboxRepository,
    countsCache: AO3AccountListCountsCache,
    postingPseudStore: AO3PostingPseudStore,
    shellChrome: WritingShellChrome? = null,
    onNewWork: () -> Unit,
    onOpenDraft: (Long) -> Unit,
    onOpenDrafts: () -> Unit,
    onOpenWorks: () -> Unit,
    onOpenSeries: () -> Unit,
    onOpenCollections: () -> Unit,
    onOpenInbox: () -> Unit,
    onLogin: () -> Unit
) {
    val auth by authRepository.state.collectAsState()
    val generation by authRepository.generation.collectAsState()
    val cachedDrafts by draftsRepository.cachedPage.collectAsState()
    val cacheRevision by io.github.cidy02.kudos.network.ao3.AO3PageCache.shared.changes.collectAsState()
    val pseudNames by postingPseudStore.mapFlow.collectAsState(initial = emptyMap())
    val username = (auth as? AO3AuthState.SignedIn)?.username
    val drafts = cachedDrafts?.takeIf {
        it.username.equals(username, ignoreCase = true) && it.generation == generation
    }?.value
    val state = writingRootState(username != null, drafts)
    val scope = rememberCoroutineScope()
    val header = remember(username, cacheRevision, authorRepository) {
        username?.let { authorRepository.cachedDashboard(AO3AuthorRoute(it)) }
    }

    if (shellChrome != null) {
        SideEffect {
            shellChrome.mounted = true
            shellChrome.canCreateWork = state.isSignedIn
            shellChrome.onNewWork = onNewWork
        }
        DisposableEffect(shellChrome) { onDispose { shellChrome.reset() } }
    }

    if (!state.isSignedIn) {
        WritingSignedOut(onLogin)
        return
    }

    val scopeKey = AO3AccountListCountsCache.scope(username.orEmpty(), generation)
    val worksCount = countsCache.get(AccountListType.MyWorks, scopeKey)?.displayText
    val unreadCount = remember(username, cacheRevision, inboxRepository) {
        inboxRepository.cachedUnreadCount()
    }
    var pseudMenuOpen by remember { mutableStateOf(false) }
    val selectedPseud = pseudNames[username.orEmpty().trim().lowercase()]

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        item {
            Box {
                SettingsPanel {
                    SubjectFormRow(
                        label = "Posting as",
                        value = selectedPseud ?: "Account Default",
                        showsChoice = true,
                        onClick = { pseudMenuOpen = true }
                    )
                }
                DropdownMenu(expanded = pseudMenuOpen, onDismissRequest = { pseudMenuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text("Account Default") },
                        onClick = {
                            pseudMenuOpen = false
                            scope.launch { postingPseudStore.setPseudName(null, username.orEmpty()) }
                        }
                    )
                    header?.pseuds.orEmpty().forEach { pseud ->
                        DropdownMenuItem(
                            text = { Text(pseud.name) },
                            onClick = {
                                pseudMenuOpen = false
                                scope.launch { postingPseudStore.setPseudName(pseud.name, username.orEmpty()) }
                            }
                        )
                    }
                }
            }
        }

        item {
            SectionRuleHeader("Draft", gutter = SubjectMetrics.accountGutter)
            SettingsPanel(Modifier.padding(top = 8.dp)) {
                val draft = state.latestDraft
                SubjectFormRow(
                    label = draft?.title ?: if (state.draftsLoaded) "No drafts on AO3" else "Drafts",
                    value = draft?.updatedDate?.takeIf(String::isNotBlank)?.let { "Edited $it · Continue" }
                        ?: if (state.draftsLoaded) null else "Open Drafts to load this section",
                    leadingIcon = Icons.Outlined.Drafts,
                    showsDisclosure = true,
                    onClick = { if (draft == null) onOpenDrafts() else onOpenDraft(draft.id) }
                )
            }
        }

        item {
            SectionRuleHeader("This Week", gutter = SubjectMetrics.accountGutter)
            SettingsPanel(Modifier.padding(top = 8.dp)) {
                SubjectFormRow("Kudos", value = "Unavailable", leadingIcon = Icons.Outlined.BarChart)
                SubjectRowSeparator()
                SubjectFormRow("Hits", value = "Unavailable")
                SubjectRowSeparator()
                SubjectFormRow("Comments", value = "Unavailable")
            }
            Text(
                "Weekly figures are shown only when Android has them from AO3's Stats page.",
                color = LocalKudosTokens.current.secondaryInk,
                fontSize = 13.sp,
                lineHeight = 18.sp,
                modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter, vertical = 8.dp)
            )
        }

        item {
            SectionRuleHeader("New Comments", gutter = SubjectMetrics.accountGutter)
            SettingsPanel(Modifier.padding(top = 8.dp)) {
                SubjectFormRow(
                    label = "Inbox",
                    value = unreadCount?.let { if (it == 1) "1 unread" else "$it unread" } ?: "Open Inbox",
                    leadingIcon = Icons.Outlined.Inbox,
                    showsDisclosure = true,
                    onClick = onOpenInbox
                )
            }
        }

        item {
            SectionRuleHeader("Your Works", gutter = SubjectMetrics.accountGutter)
            SettingsPanel(Modifier.padding(top = 8.dp)) {
                SubjectFormRow(
                    label = "Your Works",
                    value = worksCount,
                    leadingIcon = Icons.Outlined.Description,
                    showsDisclosure = true,
                    onClick = onOpenWorks
                )
            }
        }

        item {
            SectionRuleHeader("Manage", gutter = SubjectMetrics.accountGutter)
            SettingsPanel(Modifier.padding(top = 8.dp)) {
                SubjectFormRow("Drafts", leadingIcon = Icons.Outlined.Drafts, showsDisclosure = true, onClick = onOpenDrafts)
                SubjectRowSeparator()
                SubjectFormRow("Series", leadingIcon = Icons.Outlined.Layers, showsDisclosure = true, onClick = onOpenSeries)
                SubjectRowSeparator()
                SubjectFormRow(
                    "Collections & Challenges",
                    leadingIcon = Icons.Outlined.CollectionsBookmark,
                    showsDisclosure = true,
                    onClick = onOpenCollections
                )
            }
        }
    }
}

@Composable
private fun WritingSignedOut(onLogin: () -> Unit) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = SubjectMetrics.accountGutter, vertical = 48.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(Icons.Outlined.Description, contentDescription = null, tint = tokens.secondaryInk)
        Text("Log in to write", color = tokens.primaryInk, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Text(
            "Sign in to AO3 to continue drafts, read comments, and manage your works.",
            color = tokens.secondaryInk,
            fontSize = 15.sp,
            lineHeight = 21.sp
        )
        SubjectFormRow("Log In", showsDisclosure = true, onClick = onLogin)
    }
}
