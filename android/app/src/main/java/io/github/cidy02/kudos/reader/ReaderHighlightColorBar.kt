package io.github.cidy02.kudos.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.subjectPanel

/** One tap refines the new mark and dismisses, as iOS ReaderHighlightColorBar. */
@Composable
internal fun ReaderHighlightColorBar(
    selected: ReadingAnnotationColor,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier.fillMaxWidth().padding(horizontal = 16.dp)
            .background(LocalKudosTokens.current.background, androidx.compose.foundation.shape.RoundedCornerShape(24.dp))
            .subjectPanel(cornerRadius = 24.dp).padding(horizontal = 4.dp)
            .semantics { contentDescription = "Highlight colour" },
        verticalAlignment = Alignment.CenterVertically
    ) {
        androidx.compose.foundation.layout.Box(Modifier.weight(1f, fill = false)) {
            ReadingAnnotationColorPicker(selected, onSelect)
        }
        IconButton(onClick = onDismiss) {
            Icon(Icons.Filled.Close, contentDescription = "Dismiss colour picker",
                tint = LocalKudosTokens.current.secondaryInk)
        }
    }
}
