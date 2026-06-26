package io.github.cidy02.kudos.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.components.PlaceholderScreen
import io.github.cidy02.kudos.ui.components.WorkCardPlaceholder

@Composable
fun SearchScreen(onOpenWork: () -> Unit) {
    var query by remember { mutableStateOf("") }

    PlaceholderScreen(
        title = "Search",
        subtitle = "Search UI shell only. AO3 query building and parsing are not implemented.",
        sections = listOf(
            "Current Apple sort enum is documented in AO3_BEHAVIOR_CONTRACT.md.",
            "Phase 4 adds the polite AO3 networking foundation, but this screen stays static until Phase 5."
        )
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("Query") },
                singleLine = true
            )
            WorkCardPlaceholder(
                title = "Search Result Placeholder",
                author = "Search Author",
                metadata = "General - 5,400 words - 11 comments",
                summary = "Static result used to verify navigation into the work detail route.",
                onOpenWork = onOpenWork
            )
        }
    }
}
