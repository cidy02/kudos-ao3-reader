package io.github.cidy02.kudos.account

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.browse.FandomDisplayName
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.writing.writingSuggestionPanel
import kotlinx.coroutines.launch

@Composable
fun AO3ChallengeSignUpScreen(slug: String, title: String, existingID: Int? = null,
    repository: AO3CollectionDetailRepository, writes: AO3WriteRepository) {
    val auth = repository.authRepository
    val generation by auth.generation.collectAsState()
    val authState by auth.state.collectAsState()
    val model = remember(slug, existingID, repository, writes, generation, authState.isSignedIn) {
        AO3ChallengeSignUpState(slug, existingID, repository, writes)
    }
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val form = state.form
    var editing by remember(model) { mutableStateOf<Pair<SignUpPromptKind, Int>?>(null) }
    LaunchedEffect(model) { model.load() }
    DisposableEffect(model) { onDispose { model.close() } }
    val edit = editing
    val prompt = if (edit == null) null else form?.live(edit.first)?.firstOrNull { it.id == edit.second }
    if (prompt != null && form != null) {
        val position = form.live(prompt.kind).indexOf(prompt)
        SignUpTagsEditor(prompt, position, onDone = { tags -> model.update(prompt.copy(tags = tags)); editing = null },
            onBack = { editing = null })
        return
    }
    ProvidePushedShellChrome(hasSubjectHeader = true)
    val busy = state.loading || state.saving || state.terminal
    val takesOffers = form?.takesOffers ?: true
    val requests = form?.live(SignUpPromptKind.Request).orEmpty()
    val offers = form?.live(SignUpPromptKind.Offer).orEmpty()
    fun count(noun: String, size: Int, max: Int?) = if (max != null) "$noun $size of $max"
        else "$size ${noun.lowercase()}${if (size == 1) "" else "s"}"
    val subtitle = count("Request", requests.size, form?.limits?.requests?.last) + if (takesOffers)
        " · " + count("Offer", offers.size, form?.limits?.offers?.last) else ""
    Column(Modifier.fillMaxSize().subjectScreenWash(palette).imePadding()) {
        KudosRefreshBox(onRefresh = { model.load(refresh = true) }, modifier = Modifier.weight(1f)) {
            val list = androidx.compose.foundation.lazy.rememberLazyListState()
            LaunchedEffect(form?.generalErrors, form?.fieldErrors, state.notice) {
                if (form?.isValid == false || state.notice != null) list.animateScrollToItem(0)
            }
            LazyColumn(Modifier.fillMaxSize().testTag("Challenge sign-up"), state = list,
                contentPadding = PaddingValues(bottom = 20.dp)) {
                item {
                    Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                    Spacer(Modifier.height(76.dp))
                    SubjectHeaderBlock(kicker = title.ifEmpty { slug }, title = "Your sign-up", subtitle = subtitle,
                        palette = palette, gutter = SubjectMetrics.accountGutter)
                }
                state.notice?.let { message -> item { SignUpMessage(message, false) } }
                form?.generalErrors.orEmpty().forEach { message -> item { SignUpMessage(message) } }
                when {
                    state.loading -> item {
                        Row(Modifier.fillMaxWidth().padding(24.dp), horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator,
                                modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                            Text("Loading sign-up…", color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp,
                                modifier = Modifier.padding(start = 10.dp))
                        }
                    }
                    state.failure != null -> item {
                        SettingsPanel(Modifier.padding(top = 14.dp)) {
                            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("Couldn't load sign-up", color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp,
                                    fontWeight = FontWeight.SemiBold)
                                Text(state.failure.orEmpty(), color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 19.sp)
                                SettingsActionRow("Try Again", { scope.launch { model.load(refresh = true) } }, enabled = !state.terminal)
                            }
                        }
                    }
                    form != null -> {
                        form.fieldErrors["requests"]?.let { message -> item { SignUpMessage(message) } }
                        itemsIndexed(requests, key = { _, request -> "request:${request.id}" }) { index, request ->
                            ChallengeSection("Request ${index + 1}")
                            form.fieldErrors[request.errorKey]?.let { SignUpMessage(it) }
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                val types = listOf(SignUpTagType.Fandom, SignUpTagType.Relationship, SignUpTagType.Character, SignUpTagType.Freeform)
                                types.forEachIndexed { row, type ->
                                    if (row > 0) SubjectRowSeparator()
                                    val tags = request.tags[type].orEmpty()
                                    val caption = if (type == SignUpTagType.Fandom) tags.joinToString(", ").ifEmpty { "None chosen" }
                                        else if (tags.isEmpty()) "Optional" else "${tags.size} chosen"
                                    // A row with a trailing slot draws no value, even an empty slot: the
                                    // fandoms' names were missing from their row (seen on the emulator).
                                    if (type == SignUpTagType.Fandom) SubjectFormRow(type.label, value = caption,
                                        valueMaxLines = Int.MAX_VALUE, showsDisclosure = true,
                                        onClick = { if (!busy) editing = request.kind to request.id })
                                    else SubjectFormRow(type.label, showsDisclosure = true,
                                        onClick = { if (!busy) editing = request.kind to request.id },
                                        trailing = { SignUpSmallValue(caption) })
                                }
                                SubjectRowSeparator()
                                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    SubjectFormRow("Any of these is fine", trailing = {
                                        SubjectToggle(SignUpTagType.Relationship in request.any, enabled = !busy, accent = palette.accent,
                                            contentDescription = "Any of these is fine", onCheckedChange = { checked ->
                                                model.update(request.copy(any = if (checked) request.any + SignUpTagType.Relationship
                                                    else request.any - SignUpTagType.Relationship))
                                            })
                                    })
                                    Text("Any relationship matches, not only the ones chosen", color = tokens.secondaryInk,
                                        fontSize = 11.5.sp, lineHeight = 17.sp,
                                        modifier = Modifier.padding(horizontal = 14.dp).padding(bottom = 11.dp))
                                }
                            }
                            SettingsPanel(Modifier.padding(top = 8.dp)) {
                                SubjectTextFieldRow("Prompt", request.description, "Describe what you would love to receive…",
                                    { model.update(request.copy(description = it)) }, multiline = true, enabled = !busy)
                                Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text("Visible to your recipient only", color = tokens.secondaryInk.copy(alpha = 0.8f),
                                        fontSize = 10.5.sp, lineHeight = 16.sp, modifier = Modifier.weight(1f))
                                    Text("${signUpCharacterCount(request.description)} / 1000",
                                        color = tokens.secondaryInk.copy(alpha = 0.8f), fontSize = 10.5.sp, lineHeight = 16.sp)
                                }
                            }
                        }
                        item { ChallengeFootnote(signUpRequestsFootnote(form)) }
                        if (takesOffers) {
                            item { ChallengeSection("Offers") }
                            form.fieldErrors["offers"]?.let { message -> item { SignUpMessage(message) } }
                            offers.mapNotNull { form.fieldErrors[it.errorKey] }.forEach { message -> item { SignUpMessage(message) } }
                            itemsIndexed(offers, key = { _, offer -> "offer:${offer.id}" }) { index, offer ->
                                // One lazy offer per row; same screen panel and row parts as requests.
                                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                                    .padding(top = if (index == 0) 8.dp else 0.dp)
                                    .writingSuggestionPanel(first = index == 0, last = false)) {
                                    SubjectFormRow("Offer ${index + 1}", value = signUpOfferSummary(offer), valueMaxLines = Int.MAX_VALUE,
                                        showsDisclosure = true, onClick = { if (!busy) editing = offer.kind to offer.id })
                                    SubjectRowSeparator()
                                }
                            }
                            item {
                                Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                                    .writingSuggestionPanel(first = offers.isEmpty(), last = true)) {
                                    SettingsActionRow("Add an offer", { model.add(SignUpPromptKind.Offer) },
                                        enabled = !busy && offers.size < (form.limits?.offers?.last ?: Int.MAX_VALUE))
                                }
                                ChallengeFootnote("You can edit your sign-up until sign-ups close. After they close, you can only withdraw it.")
                            }
                        }
                    }
                }
            }
        }
        val requestAction: @Composable () -> Unit = {
            SettingsActionRow("Add request", { model.add(SignUpPromptKind.Request) }, enabled = form != null && !busy &&
                requests.size < (form?.limits?.requests?.last ?: Int.MAX_VALUE))
        }
        val submitAction: @Composable () -> Unit = {
            if (state.saving) Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.Center) {
                CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator,
                    modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
            }
            SettingsActionRow("Submit sign-up", { scope.launch { model.save() } }, enabled = form != null && !busy)
        }
        SettingsPanel(Modifier.padding(top = 12.dp, bottom = 26.dp)) {
            if (isAccessibilityFontScale()) {
                requestAction()
                SubjectRowSeparator()
                submitAction()
            } else Row(Modifier.fillMaxWidth()) {
                Column(Modifier.weight(1f)) { requestAction() }
                Column(Modifier.weight(1f)) { submitAction() }
            }
        }

    }
}

@Composable
private fun SignUpSmallValue(text: String) {
    Text(text, color = LocalKudosTokens.current.secondaryInk, fontSize = 13.sp, lineHeight = 19.sp)
}

@Composable
private fun SignUpMessage(message: String, error: Boolean = true) {
    val tokens = LocalKudosTokens.current
    SettingsPanel(Modifier.padding(top = 8.dp)) {
        Text(message, color = if (error) SubjectPalette.fromHue(0.0, tokens.theme).accent else tokens.scopePalette.accent,
            fontSize = 12.5.sp, lineHeight = 18.sp, modifier = Modifier.fillMaxWidth().padding(12.dp))
    }
}

@Composable
private fun SignUpTagsEditor(prompt: SignUpPrompt, position: Int, onDone: (Map<SignUpTagType, List<String>>) -> Unit,
    onBack: () -> Unit) {
    val tokens = LocalKudosTokens.current
    var text by remember(prompt.kind, prompt.id) { mutableStateOf(SignUpTagType.entries.associateWith {
        prompt.tags[it].orEmpty().joinToString(", ")
    }) }
    BackHandler(onBack = onBack)
    ProvidePushedShellChrome(hasSubjectHeader = true, hideTabBar = true, onBack = onBack, trailingContent = {
        IconButton(onClick = { onDone(text.mapValues { splitSignUpTags(it.value) }) }) {
            Icon(Icons.Default.Check, "Done", tint = tokens.scopePalette.accent)
        }
    })
    LazyColumn(Modifier.fillMaxSize().subjectScreenWash(tokens.scopePalette).imePadding(),
        contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
            Spacer(Modifier.height(76.dp))
            SubjectHeaderBlock(kicker = "${prompt.kind.label} ${position + 1}", title = "Tags", subtitle = "Comma-separated tag names",
                palette = tokens.scopePalette, gutter = SubjectMetrics.accountGutter)
        }
        itemsIndexed(listOf(SignUpTagType.Fandom, SignUpTagType.Relationship, SignUpTagType.Character, SignUpTagType.Freeform)) { _, type ->
            ChallengeSection(type.label)
            SettingsPanel(Modifier.padding(top = 8.dp)) {
                // The work tags editor's undecorated field, with iOS's comma input and placeholders.
                SubjectTextFieldRow(type.label, text[type].orEmpty(), type.placeholder,
                    { text = text + (type to it) }, fieldOnly = true, multiline = true, autocorrect = false)
            }
        }
    }
}

internal fun signUpOfferSummary(offer: SignUpPrompt): String {
    val fandom = offer.tags[SignUpTagType.Fandom].orEmpty().firstOrNull()?.let(FandomDisplayName::bareTitle) ?: "Any Fandom"
    val count = listOf(SignUpTagType.Relationship, SignUpTagType.Character, SignUpTagType.Freeform).sumOf { offer.tags[it].orEmpty().size }
    return fandom + if (count > 0) " · $count ${if (count == 1) "tag" else "tags"}" else ""
}

internal fun signUpRequestsFootnote(form: AO3ChallengeSignUpForm) = buildList {
    form.limits?.let { limits ->
        val offers = if (form.takesOffers) " and ${limits.offers.first} to ${limits.offers.last} offers" else ""
        add("The challenge asks for ${limits.requests.first} to ${limits.requests.last} requests$offers per sign-up.")
    }
    val tags = SignUpTagType.entries.mapNotNull { type -> form.requestTagLimits?.get(type)?.takeIf { it.last > 0 }?.let {
        if (it.first == it.last) "${it.first} ${type.plural}" else "${it.first} to ${it.last} ${type.plural}"
    } }
    if (tags.isNotEmpty()) add("Each request takes ${tags.joinToString(", ")}.")
    add("Kudos checks these limits before you submit your sign-up.")
}.joinToString(" ")

/** Swift String.count counts graphemes, not UTF-16 units or code points. */
private fun signUpCharacterCount(text: String): Int {
    val iterator = android.icu.text.BreakIterator.getCharacterInstance(java.util.Locale.ROOT)
    iterator.setText(text)
    var count = 0
    iterator.first()
    while (iterator.next() != android.icu.text.BreakIterator.DONE) count++
    return count
}
