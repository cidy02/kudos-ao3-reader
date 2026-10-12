package io.github.cidy02.kudos.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens

/**
 * The reader's floating top chrome matching iOS `ReaderChromeTopBar.swift`:
 * A 44pt close button at the leading edge, a title/author capsule pill centered
 * between it and the trailing fan-menu toggle button (whose 44pt width is reserved
 * via an invisible spacer so the pill stays optically centered).
 */
@Composable
fun ReaderChromeTopBar(
    title: String,
    author: String,
    titleHidden: Boolean = false,
    onClose: () -> Unit,
    onOpenDetails: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current

    Row(
        modifier = modifier
            .fillMaxWidth()
            .statusBarsPadding()
            // Every other page's bar: 4dp in from the edges and 6dp under the status bar.
            .padding(horizontal = 4.dp)
            .padding(top = 6.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        ReaderChromeButton(onClick = onClose, name = "Close reader") {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = tokens.primaryInk)
        }

        Spacer(modifier = Modifier.weight(1f, fill = true))

        if (!titleHidden) {
            // Centered title pill
            // As tall as its two lines need: at twice the text size the 44dp pill hid the author.
            Box(
                modifier = Modifier
                    .heightIn(min = 44.dp)
                    .widthIn(max = 260.dp)
                    .clip(RoundedCornerShape(22.dp))
                    .background(tokens.cardFill.copy(alpha = 0.90f), RoundedCornerShape(22.dp))
                    .background(tokens.glassFill(), RoundedCornerShape(22.dp))
                    .border(0.5.dp, tokens.glassStroke(), RoundedCornerShape(22.dp))
                    .then(
                        if (onOpenDetails != null) {
                            Modifier
                                .clickable(onClick = onOpenDetails)
                                .semantics {
                                    contentDescription = "$title${if (author.isNotBlank()) ", by $author" else ""}. Opens work details"
                                    role = Role.Button
                                }
                        } else Modifier
                    )
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleSmall.copy(
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 15.sp
                        ),
                        color = tokens.primaryInk,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (author.isNotBlank()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Person,
                                contentDescription = null,
                                tint = tokens.secondaryInk,
                                modifier = Modifier.size(9.dp)
                            )
                            Text(
                                text = author,
                                style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp),
                                color = tokens.secondaryInk,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }
                }
            }
        }

        Spacer(modifier = Modifier.weight(1f, fill = true))

        // Placeholder reserving the fan menu toggle's place
        Spacer(modifier = Modifier.size(48.dp))
    }
}

/**
 * One of the reader's two round bar buttons: Material's icon button where every other page's
 * bar has one (48dp to touch, a 24dp mark), on a 40dp backing because it floats over the page's
 * text. They were 44dp circles 12dp in and 4dp down, the back arrow 17dp: lower and further in
 * than every other page's back arrow, and smaller (owner, 2026-10-12).
 */
@Composable
internal fun ReaderChromeButton(
    onClick: () -> Unit,
    name: String,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val tokens = LocalKudosTokens.current
    Box(
        modifier = modifier
            .size(48.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick)
            .semantics {
                contentDescription = name
                role = Role.Button
            },
        contentAlignment = Alignment.Center
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(tokens.cardFill.copy(alpha = 0.90f), CircleShape)
                .background(tokens.glassFill(), CircleShape)
                .border(0.5.dp, tokens.glassStroke(), CircleShape),
            contentAlignment = Alignment.Center
        ) { content() }
    }
}
