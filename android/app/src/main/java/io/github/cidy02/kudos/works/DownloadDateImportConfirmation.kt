package io.github.cidy02.kudos.works

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.subjectPanel
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadDateImportConfirmation(
    imports: List<PendingDocumentImport>,
    onCancel: () -> Unit,
    onImport: (List<SelectedDocumentImport>) -> Unit,
    now: Instant = Instant.now()
) {
    if (imports.isEmpty()) return
    val tokens = LocalKudosTokens.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val today = remember { now }
    var useToday by remember(imports) { mutableStateOf(false) }
    var selectedDate by remember(imports) { mutableStateOf(imports.singleOrNull()?.detection?.date) }
    var showDatePicker by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onCancel,
        sheetState = sheetState,
        containerColor = tokens.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 22.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                if (imports.size == 1) "Confirm Import" else "Confirm Imports",
                style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
                color = tokens.primaryInk
            )

            if (imports.size > 1) {
                Column(modifier = Modifier.fillMaxWidth().subjectPanel()) {
                    BatchChoiceRow(
                        label = "Use each file's download date",
                        selected = !useToday,
                        onClick = { useToday = false }
                    )
                    BatchChoiceRow(
                        label = "Use today",
                        selected = useToday,
                        onClick = { useToday = true }
                    )
                }
            }

            Column(
                modifier = Modifier.fillMaxWidth().subjectPanel().padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                imports.forEach { item ->
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        if (imports.size > 1) {
                            Text(
                                item.displayName.orEmpty(),
                                fontWeight = FontWeight.Medium,
                                color = tokens.primaryInk,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                        Text(
                            downloadDateExplanation(item.detection),
                            color = tokens.secondaryInk
                        )
                    }
                }

                if (imports.size == 1) {
                    TextButton(onClick = { showDatePicker = true }) {
                        Text("Change date · ${formatDownloadDate(selectedDate ?: today)}")
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.End)
            ) {
                TextButton(onClick = onCancel) { Text("Cancel") }
                Button(
                    onClick = {
                        onImport(imports.map { item ->
                            SelectedDocumentImport(
                                pending = item,
                                downloadedAt = when {
                                    useToday -> today
                                    imports.size == 1 -> selectedDate ?: item.detection.date
                                    else -> item.detection.date
                                }
                            )
                        })
                    }
                ) { Text("Import") }
            }
        }
    }

    if (showDatePicker) {
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = instantToPickerMillis(selectedDate ?: today),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long): Boolean =
                    utcTimeMillis <= instantToPickerMillis(today)
            }
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { selectedDate = pickerMillisToInstant(it) }
                    showDatePicker = false
                }) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) { Text("Cancel") }
            }
        ) { DatePicker(state = pickerState) }
    }
}

@Composable
private fun BatchChoiceRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        RadioButton(selected = selected, onClick = onClick)
        Text(label)
    }
}

fun downloadDateExplanation(detection: DownloadDateDetection): String {
    val date = formatDownloadDate(detection.date)
    return when (detection.source) {
        DownloadDateSource.File -> "Downloaded $date · from the file"
        DownloadDateSource.Ao3Generated -> "AO3 generated this copy $date"
        DownloadDateSource.ImportTime -> "Couldn't tell. Using today"
    }
}

private fun formatDownloadDate(instant: Instant): String = DateTimeFormatter
    .ofLocalizedDate(FormatStyle.MEDIUM)
    .withZone(ZoneId.systemDefault())
    .format(instant)

private fun instantToPickerMillis(instant: Instant): Long = instant
    .atZone(ZoneId.systemDefault())
    .toLocalDate()
    .atStartOfDay(ZoneOffset.UTC)
    .toInstant()
    .toEpochMilli()

private fun pickerMillisToInstant(millis: Long): Instant = Instant.ofEpochMilli(millis)
    .atZone(ZoneOffset.UTC)
    .toLocalDate()
    .atStartOfDay(ZoneId.systemDefault())
    .toInstant()
