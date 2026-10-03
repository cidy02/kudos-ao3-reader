package io.github.cidy02.kudos.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.HelpOutline
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
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.displayMessage
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferencesRepository
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferencesSnapshot
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import io.github.cidy02.kudos.app.LocalPushedShellChrome
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
        chrome.customTitle = "My Preferences"
        chrome.hasSubjectHeader = true
    }

    var snapshot by remember { mutableStateOf<AO3PreferencesSnapshot?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    var hasEdits by remember { mutableStateOf(false) }
    
    val toggles = remember { mutableStateMapOf<String, Boolean>() }
    val selects = remember { mutableStateMapOf<String, String>() }
    val texts = remember { mutableStateMapOf<String, String>() }
    val collapsedSections = remember { mutableStateOf(setOf<String>()) }
    val scope = rememberCoroutineScope()

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

    LaunchedEffect(saving, loading, hasEdits, snapshot) {
        chrome.trailingContent = {
            Button(
                onClick = {
                    saving = true
                    status = null
                    scope.launch {
                        val snap = snapshot ?: return@launch
                        when (
                            val result = repository.save(
                                snap,
                                toggles.toMap(),
                                selects.toMap(),
                                texts.toMap()
                            )
                        ) {
                            is AO3Result.Success -> {
                                status = "Saved successfully."
                                hasEdits = false
                                // Reload to get fresh state
                                val reloadResult = repository.load(username)
                                if (reloadResult is AO3Result.Success) {
                                    snapshot = reloadResult.value
                                }
                            }
                            is AO3Result.Failure -> {
                                status = "Save failed: ${result.error.displayMessage()}"
                            }
                        }
                        saving = false
                    }
                },
                enabled = !saving && !loading && hasEdits && snapshot != null
            ) {
                Text(if (saving) "Saving…" else "Save")
            }
        }
    }

    when {
        loading -> LoadingStateCard("Loading AO3 preferences…")
        error != null && snapshot == null -> ErrorStateCard(
            title = "Preferences failed",
            message = error!!,
            primaryActionLabel = "Try Again",
            onPrimaryAction = { load() }
        )
        snapshot != null -> {
            val snap = snapshot!!
            val palette = LocalSubjectPalette.current
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .subjectScreenWash(palette),
                contentPadding = PaddingValues(bottom = 20.dp)
            ) {
                item {
                    SubjectHeaderBlock(
                        kicker = "AO3 Account",
                        title = "AO3 Preferences",
                        subtitle = "Stored on AO3 · applies everywhere you read",
                        palette = palette,
                        gutter = SubjectMetrics.accountGutter,
                        modifier = Modifier.padding(top = 20.dp)
                    )
                    
                    if (status != null) {
                        Text(
                            text = status!!,
                            color = if (status!!.startsWith("Saved")) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter, vertical = 8.dp)
                        )
                    }
                }

                item {
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
                            SubjectFormRow("Edit profile", showsDisclosure = true, onClick = { onOpenWeb("profile/edit") })
                            SubjectRowSeparator()
                            SubjectFormRow("Manage pseuds", showsDisclosure = true, onClick = { onOpenWeb("pseuds") })
                            SubjectRowSeparator()
                            SubjectFormRow("Change username", showsDisclosure = true, onClick = { onOpenWeb("change_username") })
                            SubjectRowSeparator()
                            SubjectFormRow("Change password", showsDisclosure = true, onClick = { onOpenWeb("change_password") })
                            SubjectRowSeparator()
                            SubjectFormRow("Change email", showsDisclosure = true, onClick = { onOpenWeb("change_email") })
                            SubjectRowSeparator()
                            SubjectFormRow("Blocked users", showsDisclosure = true, onClick = { onOpenWeb("blocked/users") })
                            SubjectRowSeparator()
                            SubjectFormRow("Muted users", showsDisclosure = true, onClick = { onOpenWeb("muted/users") })
                        }
                    }
                }

                itemsIndexed(snap.sections, key = { _, s -> s.title }) { _, section ->
                    Column(modifier = Modifier.padding(top = 18.dp)) {
                        Row(
                            modifier = Modifier.padding(horizontal = SubjectMetrics.accountGutter),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            SubjectFieldLabel(text = section.title)
                            Spacer(modifier = Modifier.weight(1f))
                        }
                        
                        Column(
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
                                            toggle.helpUrl?.let { helpUrl ->
                                                IconButton(onClick = { onOpenHelp(helpUrl) }) {
                                                    Icon(Icons.Outlined.HelpOutline, contentDescription = "Help")
                                                }
                                            }
                                            SubjectToggle(
                                                checked = toggles[toggle.name] ?: toggle.checked,
                                                onCheckedChange = { 
                                                    toggles[toggle.name] = it
                                                    hasEdits = true
                                                    status = null
                                                }
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
}
