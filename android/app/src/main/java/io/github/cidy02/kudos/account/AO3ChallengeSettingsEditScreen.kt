package io.github.cidy02.kudos.account

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsPanel
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.components.KudosRefreshBox
import io.github.cidy02.kudos.ui.subject.*
import io.github.cidy02.kudos.ui.subject.dialogGround
import io.github.cidy02.kudos.writing.writingSuggestionPanel
import kotlinx.coroutines.launch

@Composable
internal fun AO3ChallengeSettingsEditScreen(slug: String, title: String, viewerIsOwner: Boolean,
    repository: AO3CollectionDetailRepository, writes: AO3WriteRepository,
    onOpenWeb: (String) -> Unit, onOpenTagSet: (Int, String) -> Unit, onOpenCollection: () -> Unit,
    onBack: () -> Unit, openingKey: Int = 0) {
    val auth = repository.authRepository
    val generation by auth.generation.collectAsState()
    val authState by auth.state.collectAsState()
    // The route owns the in-memory form across a pushed tag-set/collection/browser screen.
    val model: AO3ChallengeSettingsEditState = androidx.lifecycle.viewmodel.compose.viewModel(
        key = "challenge-edit:$slug:$generation:${authState.isSignedIn}:$openingKey",
        factory = object : androidx.lifecycle.ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
                AO3ChallengeSettingsEditState(slug, viewerIsOwner, repository, writes) as T
        }
    )
    val state by model.state.collectAsState()
    val scope = rememberCoroutineScope()
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val data = state.data
    val form = data?.form
    val collection = data?.collection
    val busy = state.loading || state.saving || state.terminal
    val effectiveTitle = title.ifEmpty { slug }
    var dateEditing by remember(model) { mutableStateOf<Pair<String, java.time.LocalDateTime>?>(null) }
    var choice by remember(model) { mutableStateOf<ChallengeEditChoice?>(null) }
    LaunchedEffect(model) { model.load() }
    val leave = { model.close(); onBack() }
    ProvidePushedShellChrome(hasSubjectHeader = true, onBack = leave)
    androidx.activity.compose.BackHandler(onBack = leave)
    if (state.confirmReveal) AlertDialog(
        onDismissRequest = model::cancelReveal,
        containerColor = tokens.cardFill, titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
        title = { Text("Reveal now?", lineHeight = 28.sp) },
        text = { Text("Turning off Unrevealed makes every work visible. Turning off Anonymous shows every creator. " +
            "You can't reverse either change in Kudos.", lineHeight = 22.sp) },
        confirmButton = { TextButton(onClick = { scope.launch { model.save(revealConfirmed = true) } }, enabled = !busy) {
            Text("Save and reveal", color = SubjectPalette.fromHue(0.0, tokens.theme).accent, lineHeight = 20.sp)
        } },
        dismissButton = { TextButton(onClick = model::cancelReveal) { Text("Cancel", color = palette.accent, lineHeight = 20.sp) } }
    )
    dateEditing?.let { (key, date) -> Dialog(onDismissRequest = { dateEditing = null }) {
        Column(Modifier.dialogGround().writingSuggestionPanel(first = true, last = true).padding(vertical = 12.dp)) {
            val labels = listOf("Year", "Month", "Day", "Hour", "Minute")
            val values = listOf(date.year, date.monthValue, date.dayOfMonth, date.hour, date.minute)
            val ranges = listOf(1..9999, 1..12, 1..date.toLocalDate().lengthOfMonth(), 0..23, 0..59)
            LazyColumn(Modifier.heightIn(max = 450.dp)) {
                items(labels.indices.toList()) { index ->
                    SubjectFormRow(labels[index], trailing = { ChallengeEditValue(values[index].toString()) }, onClick = {
                        choice = ChallengeEditChoice(labels[index], "", ranges[index].map { it.toString() to it.toString() }, pick = { chosen ->
                            val value = chosen.toInt()
                            dateEditing = key to when (index) {
                                0 -> date.withYear(value)
                                1 -> date.withMonth(value)
                                2 -> date.withDayOfMonth(value)
                                3 -> date.withHour(value)
                                else -> date.withMinute(value)
                            }
                        }, selected = values[index].toString())
                    })
                }
            }
            SettingsActionRow("Done", {
                model.change(key, challengeEditedDateText(form?.control(key)?.values?.firstOrNull().orEmpty(), date))
                dateEditing = null
            })
            SettingsActionRow("Cancel", { dateEditing = null })
        }
    } }
    choice?.let { picked -> Dialog(onDismissRequest = { choice = null }) {
        Column(Modifier.dialogGround().writingSuggestionPanel(first = true, last = true).padding(vertical = 12.dp)) {
            Text(picked.label, color = tokens.primaryInk, fontSize = 16.sp, lineHeight = 23.sp,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp))
            val choiceList = androidx.compose.foundation.lazy.rememberLazyListState(
                initialFirstVisibleItemIndex = picked.options.indexOfFirst { it.first == picked.selected }.coerceAtLeast(0))
            LazyColumn(Modifier.heightIn(max = 450.dp), state = choiceList) {
                items(picked.options) { (value, caption) ->
                    SubjectFormRow(caption, onClick = {
                        if (picked.pick != null) picked.pick.invoke(value) else model.change(picked.name, value)
                        choice = null
                    })
                }
            }
            SettingsActionRow("Cancel", { choice = null })
        }
    } }
    val list = androidx.compose.foundation.lazy.rememberLazyListState()
    LaunchedEffect(form?.generalErrors, form?.fieldErrors, state.notice) {
        if (form?.isValid == false || state.notice != null) list.animateScrollToItem(0)
    }
    Column(Modifier.fillMaxSize().subjectScreenWash(palette).imePadding()) {
        KudosRefreshBox(onRefresh = { model.load(refresh = true) }, modifier = Modifier.weight(1f)) {
            LazyColumn(Modifier.fillMaxSize().testTag("Challenge settings edit"), state = list,
                contentPadding = PaddingValues(bottom = 24.dp)) {
                item {
                    Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
                    Spacer(Modifier.height(76.dp))
                    SubjectHeaderBlock(kicker = if (form?.kind == AO3ChallengeKind.PromptMeme) "Prompt meme · moderator" else "Gift exchange · moderator",
                        title = "Challenge settings", subtitle = effectiveTitle + (data?.signUpTotal?.let {
                            " · $it ${if (it == 1) "sign-up" else "sign-ups"}"
                        } ?: ""), palette = palette, gutter = SubjectMetrics.accountGutter)
                }
                state.notice?.let { item { ChallengeEditMessage(it, error = false) } }
                form?.generalErrors.orEmpty().forEach { item { ChallengeEditMessage(it) } }
                when {
                    state.loading -> item { ChallengeEditLoading("Loading challenge settings…") }
                    state.failure != null -> item {
                        SettingsPanel(Modifier.padding(top = 14.dp)) {
                            Column(Modifier.padding(16.dp)) {
                                Text("Couldn't load challenge settings", color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp)
                                Text(state.failure.orEmpty(), color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 19.sp)
                                SettingsActionRow("Try Again", { scope.launch { model.load(refresh = true) } }, enabled = !state.terminal)
                            }
                        }
                    }
                    form != null -> {
                        item { ChallengeSection("Basics") }
                        val basics = if (collection == null) listOf("Collection settings" to "Couldn't load") else listOf(
                            "Name" to collection[AO3CollectionFields.TITLE],
                            "Tagline" to collection[AO3CollectionFields.DESCRIPTION].ifEmpty { "None" },
                            "Introduction" to challengeIntroductionCount(collection[AO3CollectionFields.profile("intro")]),
                            "FAQ" to if (collection[AO3CollectionFields.profile("faq")].isEmpty()) "None" else "Set")
                        items(basics) { (label, value) -> ChallengeEditPanel {
                            SubjectFormRow(label, value = value, valueMaxLines = Int.MAX_VALUE, showsDisclosure = true, onClick = onOpenCollection)
                        } }
                        item { ChallengeEditPanel {
                            val key = form.field("signup_instructions_general")
                            SubjectTextFieldRow("Sign-up instructions", form[key], "Describe the challenge for people signing up…",
                                { model.change(key, it) }, multiline = true, enabled = !busy && form.editable(key))
                        } }
                        item { ChallengeSection("Schedule") }
                        val labels = listOf("Sign-ups open", "Sign-ups close", "Works due", "Works revealed", "Creators revealed")
                        challengeDateKeys.forEachIndexed { index, date ->
                            if (index == 2) item { ChallengeEditPanel {
                                SubjectFormRow("Assignments sent", value = challengeSentText(form.value("assignments_sent_at")), valueMaxLines = Int.MAX_VALUE)
                            } }
                            form.dateField(date)?.let { key -> item { ChallengeEditPanel {
                                val date = challengeWallClock(form[key])
                                SubjectFormRow(labels[index], value = if (date == null) form[key].ifEmpty { "Not set" }
                                    else challengeSentText(form[key]), valueMaxLines = Int.MAX_VALUE,
                                    onClick = if (!busy && form.editable(key) && date != null) ({ dateEditing = key to date }) else null)
                                if (form[key].isEmpty() && form.editable(key)) SettingsActionRow("Set", {
                                    dateEditing = key to java.time.LocalDateTime.now(java.time.ZoneOffset.UTC)
                                }, enabled = !busy)
                                form.fieldErrors[key]?.let { ChallengeEditMessage(it) }
                            } } }
                        }
                        item {
                            ChallengeEditPanel { SubjectFormRow("Time zone", value = form.value("time_zone").ifEmpty { "Unavailable" }, valueMaxLines = Int.MAX_VALUE) }
                            ChallengeFootnote(if (form.scheduleIsEditable) "Dates use the challenge’s time zone shown on AO3. After a reveal happens, you can't move it to an earlier time in Kudos."
                                else "Kudos couldn't read the challenge's time zone. Dates are view-only and won't be saved.")
                            ChallengeSection("Sign-up limits")
                        }
                        for (noun in if (form.kind == AO3ChallengeKind.GiftExchange) listOf("Requests", "Offers") else listOf("Requests")) item {
                            ChallengeEditPanel {
                                val required = form.field("${noun.lowercase()}_num_required")
                                val allowed = form.field("${noun.lowercase()}_num_allowed")
                                SubjectFormRow(noun, trailing = {
                                    Column(horizontalAlignment = Alignment.End) {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            ChallengeCountChoice("$noun required", form[required].ifEmpty { "1" }, !busy && form.editable(required)) {
                                                choice = ChallengeEditChoice("$noun required", required, (0..20).map { it.toString() to it.toString() })
                                            }
                                            Text("to", color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 19.sp)
                                            ChallengeCountChoice("$noun allowed", form[allowed].ifEmpty { "1" }, !busy && form.editable(allowed)) {
                                                choice = ChallengeEditChoice("$noun allowed", allowed, (0..20).map { it.toString() to it.toString() })
                                            }
                                        }
                                    }
                                })
                                listOfNotNull(form.fieldErrors[required], form.fieldErrors[allowed]).forEach { ChallengeEditMessage(it) }
                            }
                        }
                        item { ChallengeFootnote("Request restrictions") }
                        val restrictions = listOf("URL allowed in a request" to "url_allowed", "Description required" to "description_required",
                            "Optional tags allowed" to "optional_tags_allowed")
                        items(restrictions) { (label, key) -> ChallengeEditPanel {
                            ChallengeEditToggle(label, form[form.field("request_restriction_attributes][$key")] == "1",
                                !busy && form.editable(form.field("request_restriction_attributes][$key"))) {
                                model.change(form.field("request_restriction_attributes][$key"), if (it) "1" else "0")
                            }
                        } }
                        if ((restrictions.map { it.second } + listOf("fandom_num_required", "fandom_num_allowed", "allow_any_fandom")).any {
                            form.control(form.field("request_restriction_attributes][$it"))?.disabled == true
                        }) item { ChallengeFootnote("Prompts have been added so these settings can no longer be changed.") }
                        if (data.tagSets.isNotEmpty()) {
                            item { ChallengeSection(if (data.tagSets.size == 1) "Tag set" else "Tag sets") }
                            items(data.tagSets) { link -> ChallengeEditPanel {
                                SubjectFormRow(link.title, showsDisclosure = true, onClick = { onOpenTagSet(link.id, link.title) })
                            } }
                        }
                        item { ChallengeSection("Matching") }
                        val match = "potential_match_settings_attributes]"
                        if (form.value("${match}[num_required_prompts").toIntOrNull() != null) {
                            item { ChallengeEditPanel {
                                val on = challengeMatchTypes.filter { form.value("${match}[num_required_$it").toIntOrNull()?.let { count -> count != 0 } == true }
                                SubjectFormRow("Match on", value = on.joinToString(", ", transform = ::challengeMatchLabel).ifEmpty { "Nothing required" }, valueMaxLines = Int.MAX_VALUE)
                            } }
                            val choices = listOf("Requests that must match" to "num_required_prompts") + challengeMatchTypes.map { challengeMatchLabel(it) to "num_required_$it" }
                            items(choices) { (label, field) -> ChallengeEditPanel {
                                val key = form.field("$match[$field")
                                val selected = form[key].ifEmpty { if (field == "num_required_prompts") "1" else "0" }
                                SubjectFormRow(label, onClick = {
                                    if (!busy && form.editable(key)) choice = ChallengeEditChoice(label, key,
                                        (listOf(-1) + (if (field == "num_required_prompts") 1..5 else 0..5)).map { it.toString() to if (it == -1) "All" else it.toString() })
                                }, trailing = { ChallengeEditValue(if (selected == "-1") "All" else selected) })
                            } }
                            item { ChallengeFootnote("Count optional tags for") }
                            items(challengeMatchTypes) { type -> ChallengeEditPanel {
                                val key = form.field("$match[include_optional_$type")
                                ChallengeEditToggle(challengeMatchLabel(type), form[key] == "1", !busy && form.editable(key)) {
                                    model.change(key, if (it) "1" else "0")
                                }
                            } }
                        }
                        item { ChallengeFootnote("Request fandoms") }
                        items(listOf("Fandoms required per request" to "fandom_num_required", "Fandoms allowed per request" to "fandom_num_allowed")) { (label, field) ->
                            ChallengeEditPanel {
                                val key = form.field("request_restriction_attributes][$field")
                                val count = form[key].toIntOrNull() ?: 0
                                SubjectFormRow(label, trailing = {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        ChallengeEditValue(count.toString())
                                        IconButton(onClick = { model.change(key, (count - 1).toString()) }, enabled = !busy && form.editable(key) && count > 0) {
                                            Icon(Icons.Default.Remove, "Decrease $label", tint = palette.accent)
                                        }
                                        IconButton(onClick = { model.change(key, (count + 1).toString()) }, enabled = !busy && form.editable(key) && count < 10) {
                                            Icon(Icons.Default.Add, "Increase $label", tint = palette.accent)
                                        }
                                    }
                                })
                            }
                        }
                        item {
                            ChallengeEditPanel {
                                val key = form.field("request_restriction_attributes][allow_any_fandom")
                                ChallengeEditToggle("Allow any fandom", form[key] == "1", !busy && form.editable(key)) { model.change(key, if (it) "1" else "0") }
                                Text("Choosing “any” can match you with anything in the tag set.", color = tokens.secondaryInk, fontSize = 11.5.sp,
                                    lineHeight = 17.sp, modifier = Modifier.padding(horizontal = 14.dp).padding(bottom = 11.dp))
                            }
                            ChallengeFootnote("AO3 does the matching. Save these settings here, then use Open on AO3 to run or rerun the match. " +
                                "If potential matches already exist, your changes take effect after you regenerate them on AO3.")
                            ChallengeSection("Anonymity and moderation")
                        }
                        items(listOf("Anonymous until reveal" to "anonymous", "Unrevealed until reveal" to "unrevealed",
                            "Moderated sign-ups" to "moderated", "Closed to new sign-ups" to "closed")) { (label, flag) -> ChallengeEditPanel {
                            val key = AO3CollectionFields.preference(flag)
                            ChallengeEditToggle(label, collection?.get(key) == "1", !busy && collection?.editable(key) == true) {
                                model.change(key, if (it) "1" else "0", collection = true)
                            }
                        } }
                        if (form.kind == AO3ChallengeKind.PromptMeme) item { ChallengeEditPanel {
                            val key = form.field("anonymous")
                            ChallengeEditToggle("Prompts posted anonymously", form[key] == "1", !busy && form.editable(key)) {
                                model.change(key, if (it) "1" else "0")
                            }
                        } }
                        item { ChallengeSection("At AO3") }
                        items(listOf("Run matching" to ChallengeSettingsDestinations.runMatching(slug),
                            "Delete challenge" to ChallengeSettingsDestinations.challengeSettingsEditView(slug, form.kind))) { (label, url) -> ChallengeEditPanel {
                            SubjectFormRow(label, showsDisclosure = true, onClick = { onOpenWeb(url) }, trailing = { ChallengeEditValue("Opens AO3") })
                        } }
                    }
                }
            }
        }
        SettingsPanel(Modifier.padding(top = 12.dp, bottom = 26.dp)) {
            if (state.saving) ChallengeEditLoading("Saving…")
            SettingsActionRow("Save changes", { scope.launch { model.save() } }, enabled = viewerIsOwner && form != null && !busy)
        }
    }
}

private data class ChallengeEditChoice(val label: String, val name: String, val options: List<Pair<String, String>>,
    val pick: ((String) -> Unit)? = null, val selected: String? = null)
@Composable private fun ChallengeCountChoice(label: String, value: String, enabled: Boolean, onClick: () -> Unit) {
    TextButton(onClick = onClick, enabled = enabled, modifier = Modifier.testTag(label)) {
        Text(value, color = if (enabled) LocalKudosTokens.current.scopePalette.accent else LocalKudosTokens.current.secondaryInk,
            fontSize = 13.sp, lineHeight = 19.sp)
    }
}
@Composable private fun ChallengeEditValue(text: String) {
    Text(text, color = LocalKudosTokens.current.secondaryInk, fontSize = 13.sp, lineHeight = 19.sp)
}
@Composable private fun ChallengeEditPanel(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.padding(horizontal = SubjectMetrics.accountGutter).padding(top = 8.dp).writingSuggestionPanel(first = true, last = true), content = content)
}
@Composable private fun ChallengeEditToggle(label: String, checked: Boolean, enabled: Boolean, change: (Boolean) -> Unit) {
    val tokens = LocalKudosTokens.current
    val toggle: @Composable () -> Unit = {
        SubjectToggle(checked, onCheckedChange = change, enabled = enabled, accent = tokens.scopePalette.accent, contentDescription = label)
    }
    if (isAccessibilityFontScale()) Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 11.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, color = tokens.primaryInk, fontSize = 15.sp, lineHeight = 21.sp)
        toggle()
    } else SubjectFormRow(label, trailing = toggle)
}
@Composable private fun ChallengeEditMessage(message: String, error: Boolean = true) {
    val tokens = LocalKudosTokens.current
    ChallengeEditPanel {
        Text(message, color = if (error) SubjectPalette.fromHue(0.0, tokens.theme).accent else tokens.scopePalette.accent,
            fontSize = 12.5.sp, lineHeight = 18.sp, modifier = Modifier.padding(12.dp))
    }
}
@Composable private fun ChallengeEditLoading(message: String) {
    val tokens = LocalKudosTokens.current
    Row(Modifier.fillMaxWidth().padding(24.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(color = tokens.scopePalette.accent, trackColor = tokens.separator, modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
        Text(message, color = tokens.secondaryInk, fontSize = 14.sp, lineHeight = 20.sp, modifier = Modifier.padding(start = 10.dp))
    }
}
internal fun challengeIntroductionCount(html: String): String {
    val count = html.replace(Regex("<[^>]+>"), " ").split(Regex("\\s+")).count { word -> word.any(Char::isLetterOrDigit) }
    return if (count == 0) "None" else "$count ${if (count == 1) "word" else "words"}"
}

private fun challengeSentText(raw: String): String = challengeWallClock(raw)?.format(
    java.time.format.DateTimeFormatter.ofLocalizedDateTime(java.time.format.FormatStyle.MEDIUM, java.time.format.FormatStyle.SHORT)
) ?: "Manual"

/** Keep the served precision, separators and zone suffix when the picker changes the digits. */
internal fun challengeEditedDateText(original: String, date: java.time.LocalDateTime): String {
    if (original.isEmpty()) return date.format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))
    val match = Regex("^(\\d{4}-\\d{2}-\\d{2})(?:([ T])(\\d{2}:\\d{2})(:\\d{2})?(\\.\\d+)?)?(.*)$").matchEntire(original.trim())
        ?: return original
    val pattern = "yyyy-MM-dd" + if (match.groupValues[2].isEmpty()) "" else
        "'${match.groupValues[2]}'HH:mm" + if (match.groupValues[4].isEmpty()) "" else ":ss"
    return date.format(java.time.format.DateTimeFormatter.ofPattern(pattern)) + match.groupValues[5] + match.groupValues[6]
}
