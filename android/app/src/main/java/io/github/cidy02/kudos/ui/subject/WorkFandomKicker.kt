package io.github.cidy02.kudos.ui.subject

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.home.HomeFacts
import io.github.cidy02.kudos.search.SearchSubjectField

/**
 * The fandom label above a work's title (iOS `WorkFandomLabel`, T-509): the first named fandom
 * and how many more there are. [text] is the bare title drawn in the label; [fandom] is the name
 * a tap searches for.
 */
internal data class FandomKicker(val fandom: String, val text: String, val additional: Int)

/**
 * Null when the work names no fandom: the row then draws no label at all, rather than an
 * invented "Library" or a blank line held open. [expanded] drops the "+N", as an unfolded row
 * names every fandom itself.
 */
internal fun fandomKicker(fandoms: List<String>, expanded: Boolean = false): FandomKicker? {
    val named = fandoms.filter { it.isNotBlank() }
    val first = named.firstOrNull() ?: return null
    return FandomKicker(
        fandom = first,
        text = HomeFacts.primaryFandom(named) ?: first,
        additional = if (expanded) 0 else named.size - 1
    )
}

/** A kicker is about 20 dp tall; this much is added above and below it for a 48 dp target. */
private val KickerTouchOverhang = 14.dp

/**
 * Makes a fandom label a link that opens that fandom, with a 48 dp touch target that leaves
 * the label where it sits: the box grows by [overhang] above and below it, and the layout then
 * reports the original size and places the box back over it, so neighbours do not move.
 * The semantics sit inside the grown box, so TalkBack's focus rectangle is the 48 dp one.
 */
internal fun Modifier.fandomKickerLink(
    fandom: String,
    overhang: Dp = KickerTouchOverhang,
    onOpen: () -> Unit
): Modifier = this
    .layout { measurable, constraints ->
        val over = overhang.roundToPx()
        val placeable = measurable.measure(constraints)
        layout(placeable.width, (placeable.height - 2 * over).coerceAtLeast(0)) {
            placeable.place(0, -over)
        }
    }
    .semantics { contentDescription = "Fandom: $fandom" }
    .clickable(onClickLabel = "search this fandom", onClick = onOpen)
    .padding(vertical = overhang)

/**
 * The one fandom label every work row draws. [onOpenFandom] null leaves it plain text (a
 * hidden or selecting row, where a tap belongs to the card).
 */
@Composable
internal fun WorkFandomKicker(
    fandoms: List<String>,
    palette: SubjectPalette,
    onOpenFandom: ((String) -> Unit)?,
    modifier: Modifier = Modifier,
    expanded: Boolean = false,
    size: TextUnit = 9.sp,
    ruleSpacing: Dp = 5.dp,
    maxLines: Int = 1
) {
    val kicker = fandomKicker(fandoms, expanded) ?: return
    SubjectKicker(
        text = kicker.text,
        palette = palette,
        trailingCount = kicker.additional,
        size = size,
        ruleSpacing = ruleSpacing,
        maxLines = maxLines,
        modifier = if (onOpenFandom == null) modifier
        else modifier.fandomKickerLink(kicker.fandom) { onOpenFandom(kicker.fandom) }
    )
}

/** What a tap on a row's fandom label does: search the fandom, unless the card owns the tap. */
internal fun fandomOpener(
    interactive: Boolean,
    search: (SearchSubjectField, String) -> Unit
): ((String) -> Unit)? = if (interactive) { fandom -> search(SearchSubjectField.FANDOM, fandom) } else null
