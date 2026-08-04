package io.github.cidy02.kudos.account

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
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
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferencesRepository
import io.github.cidy02.kudos.network.ao3.preferences.AO3PreferencesSnapshot
import io.github.cidy02.kudos.ui.components.ErrorStateCard
import io.github.cidy02.kudos.ui.components.LoadingStateCard
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AO3PreferencesScreen(
    username: String,
    repository: AO3PreferencesRepository,
    onSaved: () -> Unit = {}
) {
    var snapshot by remember { mutableStateOf<AO3PreferencesSnapshot?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }
    val toggles = remember { mutableStateMapOf<String, Boolean>() }
    val selects = remember { mutableStateMapOf<String, String>() }
    val texts = remember { mutableStateMapOf<String, String>() }
    val scope = rememberCoroutineScope()

    fun load() {
        loading = true
        error = null
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
                    error = result.error.toString()
                }
            }
            loading = false
        }
    }

    LaunchedEffect(username) { load() }

    when {
        loading -> LoadingStateCard("Loading AO3 preferences…")
        error != null && snapshot == null -> ErrorStateCard(
            title = "Preferences failed",
            message = error!!,
            primaryActionLabel = "Retry",
            onPrimaryAction = { load() }
        )
        snapshot != null -> {
            val snap = snapshot!!
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                item {
                    Text("AO3 Preferences", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Changes are saved to archiveofourown.org for @$username.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    status?.let {
                        Text(it, color = MaterialTheme.colorScheme.primary)
                    }
                }
                items(snap.sections, key = { it.title }) { section ->
                    Text(section.title, style = MaterialTheme.typography.titleMedium)
                    section.toggles.forEach { toggle ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 4.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                toggle.label,
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier.weight(1f)
                            )
                            Switch(
                                checked = toggles[toggle.name] ?: toggle.checked,
                                onCheckedChange = { toggles[toggle.name] = it },
                                enabled = !saving
                            )
                        }
                    }
                }
                items(snap.selects, key = { it.name }) { select ->
                    var expanded by remember { mutableStateOf(false) }
                    val current = selects[select.name] ?: select.selectedValue
                    val label = select.options.firstOrNull { it.first == current }?.second
                        ?: current
                    ExposedDropdownMenuBox(
                        expanded = expanded,
                        onExpandedChange = { expanded = !expanded }
                    ) {
                        OutlinedTextField(
                            value = label,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text(select.label) },
                            trailingIcon = {
                                ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded)
                            },
                            modifier = Modifier
                                .menuAnchor(type = androidx.compose.material3.ExposedDropdownMenuAnchorType.PrimaryNotEditable)
                                .fillMaxWidth(),
                            enabled = !saving
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
                                    }
                                )
                            }
                        }
                    }
                }
                items(snap.textFields, key = { it.name }) { field ->
                    OutlinedTextField(
                        value = texts[field.name] ?: field.value,
                        onValueChange = { texts[field.name] = it },
                        label = { Text(field.label) },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !saving
                    )
                }
                item {
                    Button(
                        enabled = !saving,
                        onClick = {
                            saving = true
                            status = null
                            scope.launch {
                                when (
                                    val result = repository.save(
                                        snap,
                                        toggles.toMap(),
                                        selects.toMap(),
                                        texts.toMap()
                                    )
                                ) {
                                    is AO3Result.Success -> {
                                        status = "Saved."
                                        onSaved()
                                        load()
                                    }
                                    is AO3Result.Failure -> {
                                        status = "Save failed: ${result.error}"
                                    }
                                }
                                saving = false
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(if (saving) "Saving…" else "Save preferences")
                    }
                }
            }
        }
    }
}
