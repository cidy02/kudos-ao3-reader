package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens

/**
 * "Previous", the page and "Next" at an accessibility text size: the page above, the two buttons
 * side by side under it. Six screens draw the three in one row of their own; at twice the text
 * size that row broke "Previous" mid-word and made "Next" a column of single letters. Each keeps
 * its own row at ordinary sizes and hands over to this one when `isAccessibilityFontScale()`.
 */
@Composable
fun LargeTextPager(
    page: Int,
    totalPages: Int,
    onPage: (Int) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    Column(
        modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text("Page $page of $totalPages", color = LocalKudosTokens.current.secondaryInk, fontSize = 13.sp)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            OutlinedButton(onClick = { onPage(page - 1) }, enabled = enabled && page > 1) { Text("Previous") }
            OutlinedButton(onClick = { onPage(page + 1) }, enabled = enabled && page < totalPages) { Text("Next") }
        }
    }
}
