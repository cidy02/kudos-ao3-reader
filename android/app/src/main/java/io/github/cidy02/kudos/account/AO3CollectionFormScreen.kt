package io.github.cidy02.kudos.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.ProvidePushedShellChrome
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields as Fields
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFormUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionNameAvailability
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteRepository
import io.github.cidy02.kudos.settings.SettingsActionRow
import io.github.cidy02.kudos.settings.SettingsFootnote
import io.github.cidy02.kudos.settings.SettingsPage
import io.github.cidy02.kudos.settings.SettingsSection
import io.github.cidy02.kudos.settings.SubjectTextFieldRow
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import kotlinx.coroutines.launch

@Composable
fun AO3CollectionFormScreen(
    slug: String?,
    repository: AO3CollectionDetailRepository,
    writes: AO3WriteRepository,
    onClose: () -> Unit,
    onDeleted: () -> Unit,
    onOpenWeb: (String) -> Unit
) {
    val scope = rememberCoroutineScope()
    val model = remember(slug, repository, writes) { AO3CollectionFormState(slug, repository, writes, scope) }
    val state by model.state.collectAsState()
    val tokens = LocalKudosTokens.current
    val palette = tokens.scopePalette
    val red = SubjectPalette.fromHue(0.0, tokens.theme).accent
    var deleting by remember(model) { mutableStateOf(false) }
    var typed by remember(model) { mutableStateOf("") }
    var challengeMenu by remember(model) { mutableStateOf(false) }
    val close = { model.close(); onClose() }
    LaunchedEffect(model) { model.load() }
    LaunchedEffect(state.deleted) { if (state.deleted) onDeleted() }
    DisposableEffect(model) { onDispose { model.close() } }
    val save = { scope.launch { model.confirmSave() }; Unit }
    val saveLabel = if (slug == null) "Create Collection" else "Save Changes"
    // No buttons of its own up here, as on iOS: Back leaves, and the one Save is at the end.
    ProvidePushedShellChrome(hasSubjectHeader = true, onBack = close)
    MaterialTheme(colorScheme = MaterialTheme.colorScheme.copy(error = red)) {
        SettingsPage(title = if (slug == null) "New collection" else "Edit collection",
            kicker = "AO3 Account › Collections", subtitle = "Your changes are saved to AO3") {
            if (state.loading || (state.form == null && state.loadError == null)) item {
                Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = palette.accent, trackColor = tokens.separator)
                }
            }
            state.loadError?.let { message -> item {
                SettingsSection(footnote = null, label = "Couldn't open the form") {
                    Text(message, color = red, fontSize = 13.sp, lineHeight = 19.sp, modifier = Modifier.padding(13.dp))
                    SettingsActionRow("Try Again", onClick = { scope.launch { model.load() } })
                }
            } }
            val form = state.form
            if (form != null) {
                state.notice?.let { notice -> item { SettingsFootnote(notice) } }
                if (form.generalErrors.isNotEmpty()) item {
                    SettingsSection(footnote = null, top = 12.dp) {
                        Text(form.generalErrors.joinToString("\n"), color = red, fontSize = 12.5.sp,
                            lineHeight = 18.sp, modifier = Modifier.padding(13.dp))
                    }
                }
                item {
                    SettingsSection(label = "Header", footnote = "The collection name is part of its web address. " +
                        "Use letters, numbers and underscores. You can't change it after creating the collection.") {
                        val rows = listOf(Fields.TITLE to "Display title", Fields.NAME to "Collection name",
                            Fields.PARENT to "Parent collection", Fields.EMAIL to "Contact email", Fields.DESCRIPTION to "Tagline")
                        rows.forEachIndexed { index, (key, label) ->
                            if (index > 0) SubjectRowSeparator()
                            SubjectTextFieldRow(label, form[key], when (key) {
                                Fields.TITLE, Fields.NAME -> "Required"
                                Fields.PARENT -> "None"
                                else -> "Optional"
                            }, onValueChange = { model.change(key, it) },
                                enabled = !state.saving && (key != Fields.NAME || slug == null),
                                error = form.fieldErrors[key], autocorrect = key != Fields.NAME)
                            if (key == Fields.NAME) state.availability?.let { availability ->
                                if (availability != AO3CollectionNameAvailability.Unknown) Text(when (availability) {
                                    AO3CollectionNameAvailability.Available -> "Name is available"
                                    AO3CollectionNameAvailability.Taken -> "Name is taken"
                                    else -> "Name is not a valid collection name"
                                }, color = when (availability) {
                                    AO3CollectionNameAvailability.Available -> SubjectPalette.fromHue(0.36, tokens.theme).accent
                                    AO3CollectionNameAvailability.Taken -> red
                                    else -> SubjectPalette.fromHue(0.10, tokens.theme).accent
                                }, fontSize = 11.5.sp, lineHeight = 17.sp,
                                    modifier = Modifier.padding(horizontal = 13.dp).padding(bottom = 8.dp))
                            }
                        }
                    }
                }
                item {
                    SettingsSection(label = "Images", footnote = null) {
                        listOf(Fields.HEADER_URL to "Header image URL", Fields.HEADER_ALT to "Header image alt text",
                            Fields.ICON_ALT to "Icon alt text", Fields.ICON_COMMENT to "Icon comment").forEachIndexed { index, (key, label) ->
                            if (index > 0) SubjectRowSeparator()
                            SubjectTextFieldRow(label, form[key], "Optional", { model.change(key, it) }, enabled = !state.saving,
                                error = form.fieldErrors[key].takeIf { key != Fields.HEADER_ALT })
                        }
                    }
                }
                item {
                    SettingsSection(label = "Preferences", footnote = "You can turn on any combination of these settings. " +
                        "Unrevealed shows each work as Mystery Work, Anonymous hides its creators, and new-item emails go to the contact email.") {
                        listOf("closed" to "Closed to new items", "moderated" to "Moderated", "unrevealed" to "Unrevealed",
                            "anonymous" to "Anonymous", "email_notify" to "Email new items").forEachIndexed { index, (suffix, label) ->
                            if (index > 0) SubjectRowSeparator()
                            val key = Fields.preference(suffix)
                            CollectionControlRow(label) {
                                SubjectToggle(form[key] == "1", { model.change(key, if (it) "1" else "0") },
                                    enabled = !state.saving, contentDescription = label)
                            }
                        }
                    }
                }
                if (form.challengeOptions.isNotEmpty()) item {
                    SettingsSection(label = "Challenge", footnote = null) {
                        Box(Modifier.fillMaxWidth()) {
                            SubjectFormRow("Set up a challenge", value = form.challengeOptions.firstOrNull {
                                it.first == form[Fields.CHALLENGE]
                            }?.second?.ifEmpty { "None" }.orEmpty(), valueMaxLines = Int.MAX_VALUE,
                                showsDisclosure = true, onClick = { if (!state.saving) challengeMenu = true })
                            DropdownMenu(expanded = challengeMenu, onDismissRequest = { challengeMenu = false },
                                containerColor = tokens.cardFill) {
                                form.challengeOptions.forEach { (value, label) ->
                                    DropdownMenuItem(text = { Text(label.ifEmpty { "None" }, color = tokens.primaryInk,
                                        fontSize = 14.5.sp, lineHeight = 20.sp) }, onClick = {
                                        challengeMenu = false; model.change(Fields.CHALLENGE, value)
                                    })
                                }
                            }
                        }
                    }
                }
                item {
                    SettingsSection(label = "Profile", footnote = null) {
                        listOf("intro" to "Introduction", "faq" to "FAQ", "rules" to "Rules").forEachIndexed { index, (suffix, label) ->
                            if (index > 0) SubjectRowSeparator()
                            val key = Fields.profile(suffix)
                            SubjectTextFieldRow(label, form[key], "Optional", { model.change(key, it) }, multiline = true,
                                enabled = !state.saving, error = form.fieldErrors[key])
                        }
                    }
                }
                item { SettingsSection(footnote = null, top = 18.dp) {
                    SettingsActionRow(saveLabel, onClick = save, enabled = state.canSave)
                } }
                if (slug != null) item {
                    SettingsSection(label = "Collection actions", footnote = null, top = 12.dp) {
                        Text("Open AO3 to close this collection. Deleting the collection leaves its works on AO3.",
                            color = tokens.secondaryInk, fontSize = 12.5.sp, lineHeight = 18.sp, modifier = Modifier.padding(13.dp))
                        SettingsActionRow("Open Collection Settings on AO3", onClick = { onOpenWeb(AO3CollectionFormUrls.form(slug)) })
                        if (form.allowsDelete) SettingsActionRow("Delete Collection", onClick = { typed = ""; deleting = true },
                            enabled = !state.saving, destructive = true)
                    }
                }
            }
        }
        if (deleting) state.form?.let { form ->
            AlertDialog(onDismissRequest = { deleting = false; typed = "" }, containerColor = tokens.cardFill,
                titleContentColor = tokens.primaryInk, textContentColor = tokens.secondaryInk,
                title = { Text("Delete “${form.deletionName}”?", lineHeight = 28.sp) },
                text = { Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(Fields.DELETE_MESSAGE, lineHeight = 22.sp)
                    SubjectTextFieldRow("Collection name", typed, form.deletionName, { typed = it }, autocorrect = false,
                        stackedLabel = true)
                } }, confirmButton = {
                    TextButton(enabled = form.confirmsDeletion(typed) && !state.saving, onClick = {
                        val confirmation = typed; deleting = false; typed = ""
                        scope.launch { model.confirmDelete(confirmation) }
                    }) { Text("Delete on AO3", color = if (form.confirmsDeletion(typed)) red else tokens.tertiaryInk, lineHeight = 20.sp) }
                }, dismissButton = {
                    TextButton(onClick = { deleting = false; typed = "" }) { Text("Cancel", color = palette.accent, lineHeight = 20.sp) }
                })
        }
    }
}

@Composable
private fun CollectionControlRow(label: String, control: @Composable () -> Unit) {
    if (isAccessibilityFontScale()) Column(Modifier.fillMaxWidth().padding(13.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label, color = LocalKudosTokens.current.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
        control()
    } else SubjectFormRow(label, trailing = control)
}
