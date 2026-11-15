package io.github.cidy02.kudos.ui.subject

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
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
internal data class FandomKicker(val fandom: String, val text: String, val additional: Int) {
    /**
     * What TalkBack says for the whole label, once: the name and, as iOS `WorkFandomLabel` does
     * ("title, plus N more"), how many more there are. The drawn "+N" is not read again.
     */
    val spoken: String
        get() = "Fandom: $fandom" + if (additional > 0) ", plus $additional more" else ""
}

/**
 * Null when the work names no fandom: the row then draws no label at all, rather than an
 * invented "Library" or a blank line held open. [expanded] drops the "+N", as an unfolded
 * AO3 card lists the other fandoms as chips instead.
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

/** The least a label's target is, each way. */
internal val KickerTargetMinimum = 48.dp

/**
 * How far the label's box reaches up into the row's top padding (every row pads its top by 12 dp
 * or more, and nothing in that padding is interactive but the row itself).
 */
internal val KickerTargetReachUp = 12.dp

/**
 * Gives a fandom label a [KickerTargetMinimum] box in each direction, and a link to open it when
 * [onOpen] is set. The box is real layout, so it overlaps nothing: the title, byline and the
 * rest of the row sit below it and cannot lose a tap to it. The label's text stays where it was
 * and the box takes the row's top padding, then reaches down: a row with a label is about 16 dp
 * taller than one without. The box is the same with no link (a selecting or hidden row), so a
 * row does not change height when selection starts.
 *
 * The link reads out as [spoken] and nothing else, and its own text is cleared from the
 * semantics so the name and the "+N" are not announced a second time. The semantics sit inside
 * the box, so TalkBack's focus rectangle is the 48 dp one.
 */
internal fun Modifier.fandomKickerTarget(
    spoken: String,
    onOpen: (() -> Unit)?,
    reachUp: Dp = KickerTargetReachUp
): Modifier = this
    .layout { measurable, constraints ->
        val over = reachUp.roundToPx()
        val placeable = measurable.measure(constraints)
        layout(placeable.width, (placeable.height - over).coerceAtLeast(0)) {
            placeable.place(0, -over)
        }
    }
    .then(
        if (onOpen == null) Modifier
        else Modifier
            .clickable(onClickLabel = "search this fandom", onClick = onOpen)
            .clearAndSetSemantics { contentDescription = spoken }
    )
    .defaultMinSize(minWidth = KickerTargetMinimum, minHeight = KickerTargetMinimum)
    .padding(top = reachUp)

/**
 * The one fandom label every work row draws. [onOpenFandom] null leaves it plain text (a
 * hidden or selecting row, where a tap belongs to the card). [maxLines] defaults to iOS's
 * two lines, and to all of them at accessibility font scales, so the "+N" is never cut off.
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
    maxLines: Int = if (isAccessibilityFontScale()) Int.MAX_VALUE else 2
) {
    val kicker = fandomKicker(fandoms, expanded) ?: return
    SubjectKicker(
        text = kicker.text,
        palette = palette,
        trailingCount = kicker.additional,
        size = size,
        ruleSpacing = ruleSpacing,
        maxLines = maxLines,
        modifier = modifier.fandomKickerTarget(
            spoken = kicker.spoken,
            onOpen = onOpenFandom?.let { open -> { open(kicker.fandom) } }
        )
    )
}

/** What a tap on a row's fandom label does: search the fandom, unless the card owns the tap. */
internal fun fandomOpener(
    interactive: Boolean,
    search: (SearchSubjectField, String) -> Unit
): ((String) -> Unit)? =
    if (interactive) ({ fandom: String -> search(SearchSubjectField.FANDOM, fandom) }) else null
