package io.github.cidy02.kudos.account

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxFilterField
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxFilterForm
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.subjectPanel

/**
 * Filter sheet for AO3 Inbox query values.
 * Mirrors iOS `AccountInboxFilterSheet.swift`.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountInboxFilterSheet(
    filterForm: AO3InboxFilterForm,
    selectedValues: Map<String, String>,
    onApplyFilter: (name: String, value: String) -> Unit,
    onDismiss: () -> Unit,
    palette: SubjectPalette
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val tokens = LocalKudosTokens.current

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = tokens.theme.cardBackdrop
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 32.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = SubjectMetrics.accountGutter, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Inbox Filters",
                    color = tokens.primaryInk,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold
                )
                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Done",
                        tint = tokens.secondaryInk
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = SubjectMetrics.accountGutter, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                filterForm.fields.forEach { field ->
                    FilterGroup(
                        field = field,
                        selectedValue = selectedValues[field.name] ?: field.selectedValue,
                        palette = palette,
                        onSelect = { value ->
                            onApplyFilter(field.name, value)
                            onDismiss()
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun FilterGroup(
    field: AO3InboxFilterField,
    selectedValue: String?,
    palette: SubjectPalette,
    onSelect: (String) -> Unit
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = field.title.uppercase(),
            color = tokens.secondaryInk,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = (11f * 0.127f).sp,
            modifier = Modifier.padding(start = 4.dp)
        )

        Column(modifier = Modifier.fillMaxWidth().subjectPanel()) {
            field.options.forEachIndexed { index, option ->
                val isSelected = selectedValue == option.value
                if (index > 0) {
                    SubjectRowSeparator(inset = 14.dp)
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onSelect(option.value) }
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = option.label,
                        color = tokens.primaryInk,
                        fontSize = 15.sp,
                        fontWeight = if (isSelected) FontWeight.Medium else FontWeight.Normal
                    )
                    if (isSelected) {
                        Icon(
                            imageVector = Icons.Default.Check,
                            contentDescription = "Selected",
                            tint = palette.accent,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            }
        }
    }
}
