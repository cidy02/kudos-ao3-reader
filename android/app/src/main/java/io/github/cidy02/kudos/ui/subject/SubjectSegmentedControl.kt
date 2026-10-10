package io.github.cidy02.kudos.ui.subject

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * iOS `Picker` `.segmented` / `SubjectSegmentedControl`: a glass track with a
 * filled segment for the selection. Labels scale down instead of wrapping.
 *
 * At an accessibility text size four segments in one row cut their labels even at the
 * smallest step ("Bookma…" on the writer's profile, seen at twice the text size): more than
 * three then sit two to a row, and a label may take a second line.
 */
@Composable
fun <T> SubjectSegmentedControl(
    options: List<T>,
    selected: T,
    onSelect: (T) -> Unit,
    title: (T) -> String,
    modifier: Modifier = Modifier,
    contentDescription: String? = null
) {
    val tokens = LocalKudosTokens.current
    val track = RoundedCornerShape(9.dp)
    val segment = RoundedCornerShape(7.dp)
    val large = isAccessibilityFontScale()
    Column(
        modifier
            .fillMaxWidth()
            .semantics {
                if (contentDescription != null) this.contentDescription = contentDescription
            }
            .clip(track)
            .background(tokens.glassFill(0.09))
            .border(0.5.dp, tokens.glassStroke(0.13), track)
            .padding(2.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
      options.chunked(if (large && options.size > 3) 2 else options.size.coerceAtLeast(1)).forEach { row ->
      Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
        row.forEach { option ->
            val isSelected = option == selected
            Box(
                Modifier
                    .weight(1f)
                    .clip(segment)
                    .background(if (isSelected) tokens.glassFill(0.16) else Color.Transparent)
                    .clickable { onSelect(option) }
                    .semantics { this.selected = isSelected }
                    .padding(vertical = 6.dp, horizontal = 4.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = title(option),
                    color = if (isSelected) tokens.primaryInk else tokens.secondaryInk,
                    fontSize = 13.sp,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                    maxLines = if (large) 2 else 1,
                    textAlign = TextAlign.Center,
                    overflow = TextOverflow.Ellipsis,
                    autoSize = TextAutoSize.StepBased(minFontSize = 9.sp, maxFontSize = 13.sp)
                )
            }
        }
      }
      }
    }
}
