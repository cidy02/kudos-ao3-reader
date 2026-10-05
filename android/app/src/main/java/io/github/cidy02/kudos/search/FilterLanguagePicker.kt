package io.github.cidy02.kudos.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.network.ao3.search.AO3Language
import io.github.cidy02.kudos.ui.components.GlassFieldBar
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.works.WorkSearchIndex

internal fun matchingFilterLanguages(query: String): List<AO3Language> {
    val needle = WorkSearchIndex.normalize(query)
    if (needle.isEmpty()) return AO3Language.entries
    return AO3Language.entries.filter {
        WorkSearchIndex.normalize(it.title).contains(needle) ||
            WorkSearchIndex.normalize(it.code.orEmpty()).contains(needle)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FilterLanguageRow(selection: AO3Language, onChange: (AO3Language) -> Unit) {
    var picking by remember { mutableStateOf(false) }
    SubjectFormRow("Language", value = selection.title, showsDisclosure = true, valueMaxLines = 3,
        onClick = { picking = true })
    if (picking) {
        val tokens = LocalKudosTokens.current
        var query by remember { mutableStateOf("") }
        val matches = remember(query) { matchingFilterLanguages(query) }
        ModalBottomSheet(
            onDismissRequest = { picking = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            containerColor = tokens.background
        ) {
            Column(
                Modifier.fillMaxWidth().padding(horizontal = SubjectMetrics.headerGutter).padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Language", Modifier.weight(1f), color = tokens.primaryInk,
                        fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    IconButton(onClick = { picking = false }) {
                        Icon(Icons.Outlined.Check, "Done", tint = tokens.accent)
                    }
                }
                GlassFieldBar(query, { query = it }, "Search ${AO3Language.entries.size - 1} languages",
                    Modifier.fillMaxWidth())
                LazyColumn(Modifier.fillMaxWidth().heightIn(max = 520.dp).subjectPanel()) {
                    itemsIndexed(matches, key = { _, language -> language.name }) { index, language ->
                        if (index > 0) SubjectRowSeparator()
                        SubjectFormRow(language.title,
                            modifier = Modifier.semantics { selected = language == selection },
                            onClick = { onChange(language) },
                            trailing = {
                                if (language == selection) Icon(Icons.Outlined.Check, null, tint = tokens.accent)
                            })
                    }
                }
            }
        }
    }
}
