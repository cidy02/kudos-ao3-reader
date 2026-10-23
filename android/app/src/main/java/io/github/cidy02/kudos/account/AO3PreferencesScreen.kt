package io.github.cidy02.kudos.account

import androidx.compose.foundation.text.selection.SelectionContainer
import io.github.cidy02.kudos.app.DebugShotEffect
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.Snackbar
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.outlined.Close
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import kotlinx.coroutines.CancellationException
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import io.github.cidy02.kudos.ui.subject.cardRow
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.material.icons.outlined.AlternateEmail
import androidx.compose.material.icons.outlined.BackHand
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.VolumeOff
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.testTag
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferencesRepository
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferencesSnapshot
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectFieldLabel
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AO3PreferencesScreen(
    username: String,
    repository: AO3PreferencesRepository,
    onSaved: () -> Unit = {},
    onOpenHelp: (String) -> Unit = {},
    onOpenWeb: (String) -> Unit = {}
) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) {
        chrome.customTitle = null
        chrome.hasSubjectHeader = true
    }

    var snapshot by remember { mutableStateOf<AO3PreferencesSnapshot?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    var hasEdits by remember { mutableStateOf(false) }

    val toggles = remember { mutableStateMapOf<String, Boolean>() }
    val selects = remember { mutableStateMapOf<String, String>() }
    val texts = remember { mutableStateMapOf<String, String>() }
    val collapsedSections = remember { mutableStateOf(setOf<String>()) }
    val scope = rememberCoroutineScope()
    // iOS `openHelp`: a "?" reads AO3's help page and shows it here. It used to open the page
    // in the web view. `helpResult` is null while the page is being read.
    var helpRef by remember { mutableStateOf<io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpRef?>(null) }
    var helpResult by remember {
        mutableStateOf<AO3Result<io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpContent>?>(null) }
    fun openHelp(ref: io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpRef) {
        helpRef = ref
        helpResult = null
        scope.launch {
            val result = repository.loadHelp(ref)
            // A newer tap, or a closed sheet, owns the sheet now.
            if (helpRef == ref) helpResult = result
        }
    }

    fun load() {
        loading = true
        error = null
        hasEdits = false
        status = null
        scope.launch {
            when (val result = repository.load(username)) {
                is AO3Result.Success -> {
                    snapshot = result.value
                    result.value.sections.flatMap { it.toggles }.forEach {
                        toggles[it.name] = it.checked
                    }
                    result.value.selects.forEach { selects[it.name] = it.selectedValue }
                    result.value.textFields.forEach { texts[it.name] = it.value }
                }
                is AO3Result.Failure -> {
                    error = result.error.displayMessage()
                }
            }
            loading = false
        }
    }

    LaunchedEffect(username) { load() }
    DebugShotEffect("preferences", ready = snapshot != null) {
        snapshot?.sections?.firstNotNullOfOrNull { it.help }?.let(::openHelp)
    }

    fun save() {
        val snap = snapshot ?: return
        if (saving || loading || !hasEdits) return
        val submittedToggles = toggles.toMap()
        val submittedSelects = selects.toMap()
        val submittedTexts = texts.toMap()
        saving = true
        status = null
        scope.launch {
            try {
                when (val result = repository.save(snap, submittedToggles, submittedSelects, submittedTexts)) {
                    is AO3Result.Success -> {
                        status = "Saved successfully." to true
                        hasEdits = toggles.toMap() != submittedToggles || selects.toMap() != submittedSelects ||
                            texts.toMap() != submittedTexts
                        // A failed refresh cannot turn an already-confirmed save into a failure.
                        try {
                            val reloaded = repository.load(username)
                            if (reloaded is AO3Result.Success) snapshot = reloaded.value
                        } catch (cancelled: CancellationException) { throw cancelled }
                        catch (_: Exception) { /* Keep the confirmed save and the existing form. */ }
                    }
                    is AO3Result.Failure -> {
                        status = (if (result.error == AO3Error.AuthenticationRequired) {
                            "Your AO3 session expired. Sign in again from Account."
                        } else "Save failed: ${result.error.displayMessage()}") to false
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                status = "Couldn't save preferences. Try again." to false
            } finally { saving = false }
        }
    }

    LaunchedEffect(status) {
        if (status?.second == true) {
            kotlinx.coroutines.delay(3000)
            status = null
        }
    }
    LaunchedEffect(saving, loading, hasEdits, snapshot) {
        chrome.trailingContent = {
            Button(onClick = { save() }, enabled = !saving && !loading && hasEdits && snapshot != null) {
                Text(if (saving) "Saving…" else "Save")
            }
        }
    }

    // Below the status bar and the shell's floating back row, as the Settings hub does.
    val topInset = WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp
    Box(Modifier.fillMaxSize()) {
    when {
        loading -> Column {
            Spacer(Modifier.height(topInset))
            LoadingStateCard("Loading AO3 preferences…")
        }
        error != null && snapshot == null -> Column {
            Spacer(Modifier.height(topInset))
            ErrorStateCard(
                title = "Couldn't load preferences",
                message = error!!,
                primaryActionLabel = "Try Again",
                onPrimaryAction = { load() }
            )
        }
        snapshot != null -> {
            val snap = snapshot!!
            val palette = LocalSubjectPalette.current
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .testTag("AO3 preferences")
                    .subjectScreenWash(palette),
                contentPadding = PaddingValues(bottom = 20.dp)
            ) {
                item {
                    Spacer(Modifier.height(topInset))
                    SubjectHeaderBlock(
                        kicker = "AO3 Account",
                        title = "AO3 Preferences",
                        subtitle = "Stored on AO3 · applies everywhere you read",
                        palette = palette,
                        gutter = SubjectMetrics.accountGutter
                    )

                }

                if (snap.webLinks.isNotEmpty()) item {
                    Column(modifier = Modifier.padding(top = 18.dp)) {
                        SubjectFieldLabel(
                            text = "Account",
                            modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                        )
                        Column(
                            modifier = Modifier
                                .padding(top = 8.dp)
                                .padding(horizontal = SubjectMetrics.accountGutter)
                                .subjectPanel()
                        ) {
                            orderedPreferenceAccountLinks(snap.webLinks).forEachIndexed { index, link ->
                                if (index > 0) SubjectRowSeparator()
                                val icon = when (link.url.substringBefore('?').trimEnd('/').removeSuffix("/users").substringAfterLast('/')) {
                                    "edit" -> Icons.Outlined.Badge
                                    "pseuds" -> Icons.Outlined.Group
                                    "change_username" -> Icons.Outlined.AlternateEmail
                                    "change_password" -> Icons.Outlined.Key
                                    "change_email" -> Icons.Outlined.Email
                                    "blocked" -> Icons.Outlined.BackHand
                                    "muted" -> Icons.Outlined.VolumeOff
                                    else -> Icons.Outlined.ChevronRight
                                }
                                SubjectFormRow(link.title, leadingIcon = icon, showsDisclosure = true,
                                    onClick = { onOpenWeb(link.url) })
                            }
                        }
                    }
                }

                itemsIndexed(snap.sections, key = { _, s -> s.title }) { _, section ->
                    val collapsed = section.title in collapsedSections.value
                    Column(modifier = Modifier.padding(top = 18.dp)) {
                        Row(
                            modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            SubjectFieldLabel(text = section.title)
                            Spacer(modifier = Modifier.weight(1f))
                            section.help?.let { PreferenceHelpButton(it, ::openHelp) }
                            // iOS 1z: a section folds away. Kept for this visit only, as there.
                            IconButton(onClick = {
                                collapsedSections.value = if (collapsed) {
                                    collapsedSections.value - section.title
                                } else {
                                    collapsedSections.value + section.title
                                }
                            }) {
                                Icon(
                                    if (collapsed) Icons.Outlined.ChevronRight else Icons.Outlined.ExpandMore,
                                    contentDescription = "${if (collapsed) "Expand" else "Collapse"} ${section.title}",
                                    tint = LocalKudosTokens.current.tertiaryInk
                                )
                            }
                        }

                        if (!collapsed) Column(
                            modifier = Modifier
                                .padding(top = 8.dp)
                                .padding(horizontal = SubjectMetrics.accountGutter)
                                .subjectPanel()
                        ) {
                            section.toggles.forEachIndexed { index, toggle ->
                                if (index > 0) SubjectRowSeparator()
                                SubjectFormRow(
                                    label = toggle.label,
                                    trailing = {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            toggle.help?.let { PreferenceHelpButton(it, ::openHelp) }
                                            SubjectToggle(
                                                checked = toggles[toggle.name] ?: toggle.checked,
                                                onCheckedChange = {
                                                    toggles[toggle.name] = it
                                                    hasEdits = true
                                                    status = null
                                                },
                                                contentDescription = toggle.label
                                            )
                                        }
                                    }
                                )
                            }
                        }
                    }
                }

                if (snap.selects.isNotEmpty() || snap.textFields.isNotEmpty()) {
                    item {
                        Column(modifier = Modifier.padding(top = 18.dp)) {
                            SubjectFieldLabel(
                                text = "Display options",
                                modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter)
                            )
                            Column(
                                modifier = Modifier
                                    .padding(top = 8.dp)
                                    .padding(horizontal = SubjectMetrics.accountGutter)
                                    .subjectPanel()
                            ) {
                                snap.selects.forEachIndexed { index, select ->
                                    if (index > 0) SubjectRowSeparator()
                                    var expanded by remember { mutableStateOf(false) }
                                    val current = selects[select.name] ?: select.selectedValue
                                    val label = select.options.firstOrNull { it.first == current }?.second ?: current

                                    SubjectFormRow(
                                        label = select.label,
                                        trailing = {
                                            Row(verticalAlignment = Alignment.CenterVertically) {
                                                select.help?.let { PreferenceHelpButton(it, ::openHelp) }
                                                ExposedDropdownMenuBox(
                                                    expanded = expanded,
                                                    onExpandedChange = { expanded = !expanded }
                                                ) {
                                                    OutlinedTextField(
                                                        value = label,
                                                        onValueChange = {},
                                                        readOnly = true,
                                                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                                                        modifier = Modifier.menuAnchor(type = androidx.compose.material3.ExposedDropdownMenuAnchorType.PrimaryNotEditable).fillMaxWidth(0.6f)
                                                    )
                                                    ExposedDropdownMenu(
                                                        expanded = expanded,
                                                        onDismissRequest = { expanded = false }
                                                    ) {
                                                        select.options.forEach { (value, text) ->
                                                            DropdownMenuItem(
                                                                text = { Text(text) },
                                                                onClick = {
                                                                    selects[select.name] = value
                                                                    expanded = false
                                                                    hasEdits = true
                                                                    status = null
                                                                }
                                                            )
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    )
                                }

                                snap.textFields.forEachIndexed { index, field ->
                                    if (snap.selects.isNotEmpty() || index > 0) SubjectRowSeparator()
                                    SubjectFormRow(
                                        label = field.label,
                                        trailing = {
                                            Row(verticalAlignment = Alignment.CenterVertically) {
                                                field.help?.let { PreferenceHelpButton(it, ::openHelp) }
                                                OutlinedTextField(
                                                    value = texts[field.name] ?: field.value,
                                                    onValueChange = {
                                                        texts[field.name] = it
                                                        hasEdits = true
                                                        status = null
                                                    },
                                                    modifier = Modifier.fillMaxWidth(0.6f)
                                                )
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }

                item {
                    Text(
                        text = "These preferences are saved to your AO3 account and follow you on AO3. Settings that affect only Kudos are under Settings.",
                        style = MaterialTheme.typography.bodySmall,
                        color = LocalKudosTokens.current.secondaryInk,
                        modifier = Modifier
                            .padding(horizontal = SubjectMetrics.accountGutter)
                            .padding(top = 18.dp)
                    )
                }
            }
        }
    }
    status?.let { (message, success) ->
        Snackbar(
            modifier = Modifier.align(Alignment.BottomCenter).padding(16.dp)
                .semantics { liveRegion = LiveRegionMode.Polite },
            containerColor = LocalKudosTokens.current.cardFill,
            contentColor = LocalKudosTokens.current.primaryInk,
            actionOnNewLine = !success,
            action = if (success) null else { {
                TextButton(onClick = { save() }, enabled = !saving && !loading && hasEdits) { Text("Try Again") }
            } },
            dismissAction = {
                IconButton(onClick = { status = null }) { Icon(Icons.Outlined.Close, "Dismiss save result") }
            }
        ) { Text(message, lineHeight = 20.sp) }
    }
    }
    helpRef?.let { ref ->
        PreferenceHelpSheet(
            ref = ref,
            result = helpResult,
            onRetry = { openHelp(ref) },
            onOpenOnAO3 = { helpRef = null; onOpenHelp(ref.url) },
            onDismiss = { helpRef = null }
        )
    }
}

/** The "?" beside a heading or a field. Named for the page it opens, as on iOS. */
@Composable
private fun PreferenceHelpButton(
    help: io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpRef,
    onOpen: (io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpRef) -> Unit
) {
    IconButton(onClick = { onOpen(help) }) {
        Icon(Icons.Outlined.HelpOutline, contentDescription = "Help: ${help.title}",
            tint = LocalKudosTokens.current.secondaryInk)
    }
}

/**
 * iOS `helpSheetView`: AO3's help page for a preference, one card for each topic, read on the
 * tap. While it is being read, and when it cannot be, the sheet says so.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PreferenceHelpSheet(
    ref: io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpRef,
    result: AO3Result<io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpContent>?,
    onRetry: () -> Unit,
    onOpenOnAO3: () -> Unit,
    onDismiss: () -> Unit,
    presentSheet: @Composable (androidx.compose.ui.graphics.Color, @Composable () -> Unit) -> Unit = { ground, content ->
        androidx.compose.material3.ModalBottomSheet(onDismissRequest = onDismiss, containerColor = ground) { content() }
    }
) {
    presentSheet(LocalKudosTokens.current.sheetGround) {
        PreferenceHelpContent(ref, result, onRetry, onOpenOnAO3, onDone = onDismiss)
    }
}

@Composable
internal fun PreferenceHelpContent(
    ref: io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpRef,
    result: AO3Result<io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceHelpContent>?,
    onRetry: () -> Unit,
    onOpenOnAO3: () -> Unit,
    /** iOS's ✓ beside the title (A88d); the sheet passes its dismissal. */
    onDone: (() -> Unit)? = null
) {
    val tokens = LocalKudosTokens.current
    val title: @Composable (String) -> Unit = { text ->
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(text, style = MaterialTheme.typography.titleLarge, color = tokens.primaryInk, modifier = Modifier.weight(1f))
            if (onDone != null) io.github.cidy02.kudos.ui.subject.ToolbarCircleButton(onClick = onDone, accessibilityName = "Done") {
                Icon(Icons.Filled.Check, contentDescription = null, tint = tokens.scopePalette.accent)
            }
        }
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(bottom = 28.dp)
            .verticalScroll(androidx.compose.foundation.rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        when (result) {
            null -> {
                title(ref.title)
                io.github.cidy02.kudos.ui.components.LoadingStateCard("Loading help…")
            }
            is AO3Result.Failure -> {
                title(ref.title)
                io.github.cidy02.kudos.ui.components.ErrorStateCard(
                    title = "Couldn't load help",
                    message = result.error.displayMessage(),
                    primaryActionLabel = "Try Again",
                    onPrimaryAction = onRetry,
                    secondaryActionLabel = "Open on AO3",
                    onSecondaryAction = onOpenOnAO3
                )
            }
            is AO3Result.Success -> {
                val content = result.value
                title(content.title)
                content.entries.forEach { entry ->
                    Column(
                        modifier = Modifier.fillMaxWidth().cardRow().padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Text(entry.heading, style = MaterialTheme.typography.titleSmall, color = tokens.primaryInk)
                        if (entry.body.isNotEmpty()) {
                            SelectionContainer { Text(entry.body, style = MaterialTheme.typography.bodyMedium, color = tokens.secondaryInk) }
                        }
                    }
                }
                content.footer?.let {
                    SelectionContainer { Text(it, style = MaterialTheme.typography.bodySmall, color = tokens.secondaryInk) }
                }
            }
        }
    }
}

/** iOS's Account rows, retaining any additional links AO3 provides after the known rows. */
internal fun orderedPreferenceAccountLinks(
    links: List<io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceWebLink>
): List<io.github.cidy02.kudos.network.ao3.preferences.AO3PreferenceWebLink> {
    val rows = listOf(
        "profile/edit" to "Edit profile", "pseuds" to "Manage pseuds",
        "change_username" to "Change username", "change_password" to "Change password",
        "change_email" to "Change email", "blocked" to "Blocked users", "muted" to "Muted users"
    )
    fun row(url: String): Int {
        val path = url.substringBefore('?').trimEnd('/').removeSuffix("/users")
        return rows.indexOfFirst { path.endsWith("/${it.first}") }.let { if (it < 0) rows.size else it }
    }
    return links.sortedBy { row(it.url) }.map { link ->
        rows.getOrNull(row(link.url))?.let { link.copy(title = it.second) } ?: link
    }
}
