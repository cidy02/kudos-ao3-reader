package io.github.cidy02.kudos.search

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import kotlinx.coroutines.delay

/**
 * Comma-separated tag text field with **local-only** and **AO3** autocomplete suggestions.
 *
 * Selecting a suggestion replaces the current token (or appends after committed
 * tags) and leaves a trailing `", "` for the next tag. Does not touch the
 * [io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters] model shape —
 * callers still own the string fields.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagSuggestField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    candidates: List<String>,
    modifier: Modifier = Modifier,
    maxSuggestions: Int = 8,
    ao3Kind: String? = null,
    autocompleteRepository: AO3TagAutocompleteRepository? = null
) {
    var expanded by remember { mutableStateOf(false) }
    var remoteSuggestions by remember { mutableStateOf<List<String>>(emptyList()) }
    
    val currentToken = remember(value) {
        val lastComma = value.lastIndexOf(',')
        if (lastComma < 0) value.trim() else value.substring(lastComma + 1).trim()
    }

    val localSuggestions = remember(currentToken, candidates, maxSuggestions) {
        if (currentToken.isEmpty()) emptyList()
        else candidates.filter { it.contains(currentToken, ignoreCase = true) }.take(maxSuggestions)
    }

    LaunchedEffect(currentToken, ao3Kind, autocompleteRepository) {
        if (ao3Kind != null && autocompleteRepository != null && currentToken.length >= 2) {
            delay(300) // Debounce
            val result = autocompleteRepository.autocomplete(ao3Kind, currentToken)
            if (result is AO3Result.Success) {
                remoteSuggestions = result.value
            }
        } else {
            remoteSuggestions = emptyList()
        }
    }

    val allSuggestions = remember(localSuggestions, remoteSuggestions) {
        (localSuggestions + remoteSuggestions).distinct().take(maxSuggestions)
    }
    
    val showMenu = expanded && allSuggestions.isNotEmpty()

    ExposedDropdownMenuBox(
        expanded = showMenu,
        onExpandedChange = { next ->
            expanded = next && (candidates.isNotEmpty() || ao3Kind != null)
        },
        modifier = modifier.fillMaxWidth()
    ) {
        OutlinedTextField(
            value = value,
            onValueChange = { next ->
                onValueChange(next)
                expanded = true
            },
            label = { Text(label) },
            singleLine = true,
            trailingIcon = {
                if (candidates.isNotEmpty() || ao3Kind != null) {
                    ExposedDropdownMenuDefaults.TrailingIcon(expanded = showMenu)
                }
            },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(
                    type = ExposedDropdownMenuAnchorType.PrimaryEditable,
                    enabled = true
                )
        )
        ExposedDropdownMenu(
            expanded = showMenu,
            onDismissRequest = { expanded = false },
            modifier = Modifier.heightIn(max = 240.dp)
        ) {
            allSuggestions.forEach { suggestion ->
                DropdownMenuItem(
                    text = { Text(suggestion) },
                    onClick = {
                        onValueChange(applyTagSuggestion(value, suggestion))
                        // Keep open so multi-tag entry stays fast.
                        expanded = true
                    },
                    contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding
                )
            }
        }
    }
}
