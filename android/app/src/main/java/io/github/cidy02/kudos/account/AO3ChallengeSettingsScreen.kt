package io.github.cidy02.kudos.account

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeKind
import io.github.cidy02.kudos.network.ao3.account.ChallengeSettingsDestinations
import io.github.cidy02.kudos.network.ao3.account.challengeDateText
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.*
import kotlinx.coroutines.launch

@Composable
fun AO3ChallengeSettingsScreen(
    slug: String,
    title: String,
    viewerIsOwner: Boolean,
    repository: AO3CollectionDetailRepository,
    onOpenWeb: (String) -> Unit,
    onOpenExternal: (String) -> Unit,
    onOpenTagSet: (Int, String) -> Unit,
    onOpenPrompts: (String, String) -> Unit,
    onOpenSignUps: (String, String) -> Unit = { _, _ -> }
) {
    val auth = repository.authRepository
    val generation by auth.generation.collectAsState()
    val authState by auth.state.collectAsState()
    val model = remember(slug, repository, generation, authState.isSignedIn) { AO3ChallengeSettingsState(slug, repository) }
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val effectiveTitle = title.ifEmpty { slug }
    val palette = remember(effectiveTitle, tokens.theme) {
        SubjectPalette.fromHue(HomeFacts.workHue(emptyList(), effectiveTitle), tokens.theme)
    }
    val kind = state.data?.settings?.kind ?: AO3ChallengeKind.GiftExchange
    val large = isAccessibilityFontScale()
    LaunchedEffect(model) { model.load() }
    DisposableEffect(model) { onDispose { model.close() } }
    ProvidePushedShellChrome(hasSubjectHeader = true)
    CompositionLocalProvider(LocalKudosTokens provides tokens.copy(accent = palette.accent)) {
        // Refresh chrome is the only Material surface; every colour comes from subject tokens.
        MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(
            primary = palette.accent, onPrimary = SubjectPalette.label(palette.accent),
            primaryContainer = palette.chipFill, onPrimaryContainer = palette.accentOnFill,
            surface = tokens.cardFill, onSurface = tokens.primaryInk,
            surfaceContainerHigh = tokens.cardFill, surfaceContainerHighest = tokens.cardFill,
            surfaceVariant = tokens.cardFill, onSurfaceVariant = tokens.secondaryInk,
            background = tokens.background, onBackground = tokens.primaryInk,
            outline = tokens.separator, outlineVariant = tokens.separator, surfaceTint = palette.accent
        )) {
            KudosRefreshBox(onRefresh = { model.load() }, modifier = Modifier.fillMaxSize().subjectScreenWash(palette)) {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                    item {
                        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                        Spacer(Modifier.height(56.dp))
                        SubjectHeaderBlock(kicker = "AO3 Account", title = "Challenge", subtitle = "$effectiveTitle · ${kind.displayName}",
                            palette = palette, gutter = SubjectMetrics.accountGutter)
                        ChallengeFootnote("An AO3 challenge belongs to a collection and has its own sign-ups, assignments and " +
                            "deadlines. This page shows its settings in the same order as AO3.")
                    }
                    when {
                        state.loading || (state.data == null && state.failure == null && authState.isSignedIn) -> item {
                            Row(Modifier.fillMaxWidth().padding(vertical = 24.dp), horizontalArrangement = Arrangement.Center,
                                verticalAlignment = Alignment.CenterVertically) {
                                CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator,
                                    modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                                Text("Loading challenge settings…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp,
                                    modifier = Modifier.padding(start = 10.dp))
                            }
                        }
                        state.failure != null || !authState.isSignedIn -> item {
                            SettingsPanel(Modifier.padding(top = 14.dp)) {
                                Column(Modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text("Couldn't load challenge settings", color = tokens.primaryInk, fontSize = 15.sp,
                                        lineHeight = 21.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                                    Text(state.failure ?: "Log in to AO3 before using this feature.", color = tokens.secondaryInk,
                                        fontSize = 13.sp, lineHeight = 19.sp, textAlign = TextAlign.Center)
                                    TextButton(onClick = { scope.launch { model.load() } }) {
                                        Text("Try Again", color = palette.accent, fontSize = 14.sp, lineHeight = 20.sp)
                                    }
                                }
                            }
                        }
                        else -> state.data?.let { data ->
                            val settings = data.settings
                            val meme = kind == AO3ChallengeKind.PromptMeme
                            if (viewerIsOwner) item {
                                SettingsPanel(Modifier.padding(top = 14.dp)) {
                                    SubjectFormRow("Edit settings", showsDisclosure = true,
                                        onClick = { onOpenWeb(ChallengeSettingsDestinations.challengeSettingsEditView(slug, kind)) })
                                }
                            }
                            item {
                                ChallengeSection("Type")
                                SettingsPanel(Modifier.padding(top = 8.dp)) {
                                    AO3ChallengeKind.entries.forEachIndexed { index, type ->
                                        if (index > 0) SubjectRowSeparator()
                                        Row(Modifier.padding(horizontal = 14.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                                Text(type.displayName, color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp)
                                                Text(if (type == AO3ChallengeKind.GiftExchange) "Sign-ups are matched into assignments" else "Prompts are claimed freely",
                                                    color = tokens.secondaryInk, fontSize = 11.5.sp, lineHeight = 17.sp)
                                            }
                                            if (kind == type) Icon(Icons.Filled.Check, contentDescription = "Selected", tint = palette.accent,
                                                modifier = Modifier.size(18.dp))
                                        }
                                    }
                                }
                                ChallengeSection("Dates")
                                SettingsPanel(Modifier.padding(top = 8.dp)) {
                                    listOf("Sign-ups open", "Sign-ups close", "Works due", "Works revealed", "Creators revealed")
                                        .forEachIndexed { index, label ->
                                            if (index > 0) SubjectRowSeparator()
                                            SubjectFormRow(label, value = challengeDateText(settings.dates[index]), valueMaxLines = Int.MAX_VALUE)
                                        }
                                }
                                ChallengeFootnote("AO3 doesn't close the collection when a deadline passes. You close it yourself with the Closed setting.")
                                ChallengeSection(if (meme) "Prompt requirements" else "Sign-up requirements")
                                SettingsPanel(Modifier.padding(top = 8.dp)) {
                                    val noun = if (meme) "prompt" else "request"
                                    if (meme) {
                                        SubjectFormRow("Prompts per sign-up", value = settings.promptsPerSignup, valueMaxLines = Int.MAX_VALUE)
                                        SubjectRowSeparator()
                                    }
                                    listOf("Fandoms per $noun" to settings.fandoms, "Relationships per $noun" to settings.relationships,
                                        "Characters per $noun" to settings.characters, "Additional tags" to if (settings.optionalTags) "Optional" else "Not allowed")
                                        .forEachIndexed { index, (label, value) ->
                                            if (index > 0) SubjectRowSeparator()
                                            SubjectFormRow(label, value = value, valueMaxLines = Int.MAX_VALUE)
                                        }
                                    SubjectRowSeparator()
                                    ChallengeReadOnlyToggle("Allow any prompt", settings.allowAnyPrompt, palette, large)
                                    if (!meme) {
                                        SubjectRowSeparator()
                                        ChallengeReadOnlyToggle("Require a fandom match", settings.requireFandomMatch, palette, large)
                                    }
                                }
                            }
                            if (data.tagSets.isNotEmpty()) item {
                                ChallengeSection(if (data.tagSets.size == 1) "Tag set" else "Tag sets")
                                SettingsPanel(Modifier.padding(top = 8.dp)) {
                                    data.tagSets.forEachIndexed { index, link ->
                                        if (index > 0) SubjectRowSeparator()
                                        SubjectFormRow(link.title, showsDisclosure = true,
                                            onClick = { onOpenTagSet(link.id, link.title) })
                                    }
                                }
                            }
                            item {
                                if (meme) {
                                    ChallengeSection("Prompts")
                                    SettingsPanel(Modifier.padding(top = 8.dp)) {
                                        SubjectFormRow("Prompts", value = "Claim and fill", showsDisclosure = true, valueMaxLines = Int.MAX_VALUE,
                                            onClick = { onOpenPrompts(slug, effectiveTitle) })
                                        SubjectRowSeparator()
                                        SubjectFormRow("Prompts posted anonymously", value = if (settings.anonymous) "Yes" else "No", valueMaxLines = Int.MAX_VALUE)
                                    }
                                    ChallengeFootnote("A Prompt Meme has no matching or assignments. People post prompts and others claim them.")
                                } else {
                                    ChallengeSection("Assignments")
                                    SettingsPanel(Modifier.padding(top = 8.dp)) {
                                        SubjectFormRow("Sign-ups", value = data.signUpTotal?.toString() ?: "Couldn't load", showsDisclosure = true,
                                            valueMaxLines = Int.MAX_VALUE, onClick = { onOpenSignUps(slug, effectiveTitle) })
                                        SubjectRowSeparator()
                                        // Corrected brief: no assignment read, count, failed-count label or invented placeholder.
                                        SubjectFormRow("Assignments", showsDisclosure = true,
                                            onClick = { onOpenWeb(ChallengeSettingsDestinations.challengeAssignmentsView(slug)) })
                                        SubjectRowSeparator()
                                        SubjectFormRow("Defaults and pinch hits", showsDisclosure = true,
                                            onClick = { onOpenWeb(ChallengeSettingsDestinations.challengeAssignmentsView(slug)) })
                                    }
                                    ChallengeFootnote("AO3 matches participants.")
                                    ChallengeSection("At AO3")
                                    SettingsPanel(Modifier.padding(top = 8.dp)) {
                                        SubjectFormRow("Run matching", value = "Opens AO3", showsDisclosure = true, valueMaxLines = Int.MAX_VALUE,
                                            onClick = { onOpenExternal(ChallengeSettingsDestinations.runMatching(slug)) })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable internal fun ChallengeSection(title: String, count: Int? = null) {
    SectionRuleHeader(title, count = count, modifier = Modifier.padding(top = 18.dp))
}

@Composable internal fun ChallengeFootnote(text: String) {
    Text(text, color = LocalKudosTokens.current.secondaryInk.copy(alpha = 0.7f), fontSize = 11.5.sp, lineHeight = 17.sp,
        modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter + 4.dp).padding(top = 8.dp))
}

@Composable internal fun ChallengeReadOnlyToggle(label: String, checked: Boolean, palette: SubjectPalette, large: Boolean) {
    if (large) Column(Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 11.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, color = LocalKudosTokens.current.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
        SubjectToggle(checked, onCheckedChange = {}, enabled = false, accent = palette.accent, contentDescription = label)
    } else SubjectFormRow(label, trailing = {
        SubjectToggle(checked, onCheckedChange = {}, enabled = false, accent = palette.accent, contentDescription = label)
    })
}
