package io.github.cidy02.kudos.library

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.ReaderTheme
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.subjectPanel

/** iOS LibraryFilterCollisionCard, using the Library's subject surfaces and plain controls. */
@Composable
fun LibraryFilterCollisionCard(
    sectionTitle: String,
    works: List<LibraryDisplayItem>,
    filters: LibraryFilterState,
    onFiltersChange: (LibraryFilterState) -> Unit,
    onClear: () -> Unit,
    onEdit: () -> Unit,
    modifier: Modifier = Modifier,
    userTagNames: Map<String, String> = emptyMap(),
    collectionNames: Map<String, String> = emptyMap()
) {
    val tokens = LocalKudosTokens.current
    val drops = remember(works, filters, userTagNames, collectionNames) {
        filters.droppingEachActiveFilter(works, userTagNames, collectionNames)
    }
    val colliding = remember(works, filters, userTagNames, collectionNames) {
        filters.collidingFilterLabels(works, userTagNames, collectionNames)
    }
    val revealing = drops.filter { it.remainingCount > 0 }
    val errorColor = when (tokens.theme) {
        ReaderTheme.Light -> Color(red = 0.80f, green = 0.15f, blue = 0.15f)
        ReaderTheme.Sepia -> Color(red = 0.62f, green = 0.20f, blue = 0.14f)
        ReaderTheme.Dark, ReaderTheme.Oled -> Color(red = 0.95f, green = 0.38f, blue = 0.38f)
    }
    Column(
        modifier.fillMaxWidth().subjectPanel(cornerRadius = 18.dp).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(11.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Text(
                libraryCollisionTitle(drops.size), color = tokens.primaryInk,
                fontSize = 18.sp, fontWeight = FontWeight.SemiBold
            )
            Text(
                libraryCollisionDetail(sectionTitle, works.size, drops.size, colliding),
                color = tokens.secondaryInk, fontSize = 13.5.sp
            )
        }
        if (revealing.isNotEmpty()) {
            Box(Modifier.fillMaxWidth().height(0.5.dp).background(tokens.glassStroke(0.12)))
            Text(
                "Drop one filter".uppercase(), color = tokens.tertiaryInk,
                fontSize = 8.5.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.85.sp
            )
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                revealing.forEach { drop ->
                    val count = if (drop.remainingCount == 1) "1 work" else "${drop.remainingCount} works"
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(11.dp))
                            .background(tokens.glassFill(0.07))
                            .clickable(role = Role.Button) { onFiltersChange(drop.remainingFilters) }
                            .semantics(mergeDescendants = true) {
                                contentDescription = "Without ${drop.filterLabel}, $count"
                            }
                            .heightIn(min = 48.dp).padding(horizontal = 12.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(9.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            "Without ${drop.filterLabel}", modifier = Modifier.weight(1f),
                            color = tokens.primaryInk, fontSize = 13.5.sp, fontWeight = FontWeight.Medium
                        )
                        Text(
                            count, color = tokens.scopePalette.accent, fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace
                        )
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.CenterVertically) {
            LibraryEmptyAction(
                "Clear all filters", onClear, Modifier.weight(1f),
                fill = errorColor, ink = SubjectPalette.label(errorColor)
            )
            LibraryEmptyAction("Edit", onEdit)
        }
    }
}

/** Plain themed empty card for genuine absence and Home's quick-pill state. */
@Composable
fun LibraryPlainEmptyState(
    title: String,
    message: String = "",
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    icon: ImageVector? = null
) {
    val tokens = LocalKudosTokens.current
    Column(
        modifier.fillMaxWidth().subjectPanel(cornerRadius = 18.dp).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(11.dp)
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) Icon(icon, contentDescription = null, tint = tokens.tertiaryInk, modifier = Modifier.size(24.dp))
            Text(title, color = tokens.primaryInk, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
        }
        if (message.isNotEmpty()) Text(message, color = tokens.secondaryInk, fontSize = 13.5.sp)
        if (actionLabel != null && onAction != null) LibraryEmptyAction(actionLabel, onAction)
    }
}

@Composable
private fun LibraryEmptyAction(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    fill: Color = Color.Transparent,
    ink: Color = LocalKudosTokens.current.primaryInk
) {
    val tokens = LocalKudosTokens.current
    val shape = RoundedCornerShape(50)
    Box(
        modifier.clip(shape).background(fill)
            .border(0.5.dp, if (fill == Color.Transparent) tokens.glassStroke(0.24) else fill, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .heightIn(min = 48.dp).padding(horizontal = 18.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            label, color = ink, fontSize = 14.sp,
            fontWeight = if (fill == Color.Transparent) FontWeight.Medium else FontWeight.SemiBold
        )
    }
}
