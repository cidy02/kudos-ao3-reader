package io.github.cidy02.kudos.search

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.network.ao3.search.AO3SearchFilters
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SectionRuleHeader
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash

private val IncludedGreen = Color(0xFF34C759)
private val ExcludedRed = Color(0xFFFF3B30)

private enum class SaveChipKind { Included, Excluded, Facet }

private data class SaveChip(val text: String, val kind: SaveChipKind)

/**
 * Artboard 1ax. Names the search and lists the filters that will be stored,
 * instead of a bare naming alert.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SaveSearchSheet(
    filters: AO3SearchFilters,
    name: String,
    onNameChange: (String) -> Unit,
    onSave: () -> Unit,
    onDismiss: () -> Unit
) {
    val tokens = LocalKudosTokens.current
    val palette = SubjectPalette.fromHue(HomeFacts.workHue(emptyList(), name), tokens.theme)
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    val chips = saveSearchChips(filters)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color.Transparent,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .subjectScreenWash(palette)
                .padding(bottom = 28.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TextButton(onClick = onDismiss) { Text("Cancel") }
                Text(
                    text = "Save Search",
                    modifier = Modifier.weight(1f),
                    color = tokens.primaryInk,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
                TextButton(
                    onClick = onSave,
                    enabled = name.trim().isNotEmpty()
                ) { Text("Save") }
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = SubjectMetrics.accountGutter)
                    .padding(top = 14.dp)
                    .subjectPanel()
                    .padding(horizontal = 14.dp, vertical = 12.dp)
            ) {
                BasicTextField(
                    value = name,
                    onValueChange = onNameChange,
                    singleLine = true,
                    textStyle = TextStyle(color = tokens.primaryInk, fontSize = 17.sp),
                    modifier = Modifier.fillMaxWidth(),
                    decorationBox = { inner ->
                        Box(Modifier.fillMaxWidth()) {
                            if (name.isEmpty()) {
                                Text("Name", color = tokens.secondaryInk, fontSize = 17.sp)
                            }
                            inner()
                        }
                    }
                )
            }
            Text(
                text = "The name comes from your search. You can change it to anything.",
                color = tokens.secondaryInk,
                fontSize = 11.5.sp,
                modifier = Modifier.padding(
                    start = SubjectMetrics.accountGutter,
                    end = SubjectMetrics.accountGutter,
                    top = 6.dp
                )
            )
            SectionRuleHeader(
                title = "What gets saved",
                modifier = Modifier.padding(top = 20.dp)
            )
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = SubjectMetrics.accountGutter)
                    .padding(top = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (chips.isEmpty()) {
                    Text(
                        text = "You haven't chosen any filters, so only the name will be saved.",
                        color = tokens.secondaryInk,
                        fontSize = 12.5.sp,
                        modifier = Modifier
                            .fillMaxWidth()
                            .subjectPanel()
                            .padding(horizontal = 14.dp, vertical = 12.dp)
                    )
                } else {
                    FlowRow(
                        modifier = Modifier
                            .fillMaxWidth()
                            .subjectPanel()
                            .padding(horizontal = 14.dp, vertical = 13.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        chips.forEach { SaveSearchSummaryChip(it) }
                    }
                }
                Text(
                    text = "Only the choices you changed are saved.",
                    color = tokens.secondaryInk,
                    fontSize = 11.5.sp
                )
            }
        }
    }
}

@Composable
private fun SaveSearchSummaryChip(chip: SaveChip) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(percent = 50)
    val foreground = when (chip.kind) {
        SaveChipKind.Included -> IncludedGreen
        SaveChipKind.Excluded -> ExcludedRed
        SaveChipKind.Facet -> tokens.primaryInk
    }
    val fill = when (chip.kind) {
        SaveChipKind.Included -> IncludedGreen.copy(alpha = 0.15f)
        SaveChipKind.Excluded -> ExcludedRed.copy(alpha = 0.15f)
        SaveChipKind.Facet -> tokens.glassFill(0.10)
    }
    val stroke = when (chip.kind) {
        SaveChipKind.Included -> IncludedGreen.copy(alpha = 0.35f)
        SaveChipKind.Excluded -> ExcludedRed.copy(alpha = 0.35f)
        SaveChipKind.Facet -> tokens.glassStroke(0.16)
    }
    Text(
        text = chip.text,
        color = foreground,
        fontSize = 12.sp,
        maxLines = 1,
        modifier = Modifier
            .background(fill, shape)
            .border(0.5.dp, stroke, shape)
            .padding(horizontal = 9.dp, vertical = 4.dp)
    )
}

private fun saveSearchChips(filters: AO3SearchFilters): List<SaveChip> {
    val chips = mutableListOf<SaveChip>()
    val query = filters.query.trim()
    if (query.isNotEmpty()) chips += SaveChip("\u201C$query\u201D", SaveChipKind.Included)
    summaryLabels(filters).forEach { label ->
        val kind = when {
            label.text.startsWith("−") -> SaveChipKind.Excluded
            label.icon == null -> SaveChipKind.Facet
            else -> SaveChipKind.Included
        }
        chips += SaveChip(label.text, kind)
    }
    return chips
}
