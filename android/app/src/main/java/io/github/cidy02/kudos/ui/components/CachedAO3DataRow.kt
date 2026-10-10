package io.github.cidy02.kudos.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.subjectPanel

/** One status line in the screen's own panel. Wraps naturally at accessibility sizes. */
@Composable
fun CachedAO3DataRow(modifier: Modifier = Modifier, inPanel: Boolean = true) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier.fillMaxWidth().then(if (inPanel) Modifier.subjectPanel() else Modifier)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Outlined.WifiOff, null, tint = tokens.scopePalette.accent, modifier = Modifier.size(18.dp))
        Text("Showing cached AO3 data", color = tokens.secondaryInk, fontSize = 14.sp,
            lineHeight = 20.sp, modifier = Modifier.weight(1f))
    }
}
