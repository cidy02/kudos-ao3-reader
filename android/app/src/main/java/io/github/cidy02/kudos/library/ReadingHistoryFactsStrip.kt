package io.github.cidy02.kudos.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator

/** iOS ReadingHistoryFactsStrip: log facts belong only to visited History/Favorites rows. */
@Composable
internal fun ReadingHistoryFactsStrip(summary: WorkReadingSummary?, kind: LibrarySectionKind, postedChapterCount: Int) {
    if (summary == null || summary.visitCount <= 0 ||
        (kind != LibrarySectionKind.History && kind != LibrarySectionKind.Favorites)) return
    val tokens = LocalKudosTokens.current
    Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
        SubjectRowSeparator(inset = 0.dp)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.padding(top = 8.dp)) {
            if (summary.totalSeconds > 0) Text(ReadingInsights.durationLabel(summary.totalSeconds), color = tokens.secondaryInk,
                fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, style = TextStyle(fontFeatureSettings = "tnum"))
            if (summary.finishCount > 1) Text("Read ×${summary.finishCount}", color = tokens.favoriteGold,
                fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, style = TextStyle(fontFeatureSettings = "tnum"))
            val newChapters = if (summary.chapterCountAtLastVisit > 0) {
                (postedChapterCount - summary.chapterCountAtLastVisit).coerceAtLeast(0)
            } else 0
            if (kind == LibrarySectionKind.History && newChapters > 0) {
                Text(if (newChapters == 1) "1 new chapter" else "$newChapters new chapters", color = tokens.scopePalette.accent,
                    fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, style = TextStyle(fontFeatureSettings = "tnum"))
            }
        }
    }
}
