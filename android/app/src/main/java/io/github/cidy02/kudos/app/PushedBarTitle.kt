package io.github.cidy02.kudos.app

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.material3.Text
import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens

/** The writing editor's buttons take priority over a title that cannot fit whole. */
@Composable
internal fun PushedBarTitle(title: String, wholeOnly: Boolean, modifier: Modifier = Modifier) {
    val style = LocalTextStyle.current.copy(fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    val measurer = rememberTextMeasurer()
    BoxWithConstraints(modifier) {
        if (!wholeOnly || measurer.measure(title, style, softWrap = false).size.width <= constraints.maxWidth) {
            Text(title, color = LocalKudosTokens.current.primaryInk, style = style,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
