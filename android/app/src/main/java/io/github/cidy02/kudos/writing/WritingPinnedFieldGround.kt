package io.github.cidy02.kudos.writing

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import io.github.cidy02.kudos.ui.subject.SubjectPalette

/** Before pinning the page owns the wash; after pinning an opaque ground hides scrolling rows. */
internal fun Modifier.writingPinnedFieldGround(list: LazyListState, index: Int, palette: SubjectPalette): Modifier =
    drawBehind {
        if (list.firstVisibleItemIndex >= index) drawRect(palette.theme.cardBackdrop)
    }
