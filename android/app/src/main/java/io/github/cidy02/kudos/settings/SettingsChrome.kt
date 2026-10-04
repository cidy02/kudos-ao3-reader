package io.github.cidy02.kudos.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.app.LocalPushedShellChrome
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectHeaderBlock
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.subjectPanel
import io.github.cidy02.kudos.ui.subject.subjectScreenWash

/**
 * The frame every Settings page shares with the hub: no bar title (the header
 * names the page), then a status-bar inset plus 56.dp, then the kicker and title.
 */
@Composable
fun SettingsPage(
    title: String,
    content: LazyListScope.() -> Unit
) {
    val chrome = LocalPushedShellChrome.current
    LaunchedEffect(Unit) {
        chrome.customTitle = null
        chrome.hasSubjectHeader = true
    }
    val palette = LocalSubjectPalette.current
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .subjectScreenWash(palette),
        contentPadding = PaddingValues(bottom = 32.dp)
    ) {
        item {
            Spacer(Modifier.height(WindowInsets.systemBars.asPaddingValues().calculateTopPadding() + 56.dp))
            SubjectHeaderBlock(
                kicker = "SETTINGS",
                title = title,
                palette = palette,
                gutter = SubjectMetrics.accountGutter
            )
        }
        content()
    }
}

/** iOS grouped-form section label: sentence case, secondary, above the panel. */
@Composable
fun SettingsGroupLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier
            .padding(horizontal = SubjectMetrics.accountGutter)
            .padding(bottom = 8.dp),
        color = LocalKudosTokens.current.secondaryInk,
        fontSize = 15.sp
    )
}

@Composable
fun SettingsPanel(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier
            .padding(horizontal = SubjectMetrics.accountGutter)
            // A panel spans the page whatever it holds: one with a single short line of
            // text used to shrink to that line.
            .fillMaxWidth()
            .subjectPanel(),
        content = content
    )
}

@Composable
fun SettingsFootnote(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        modifier = modifier
            .padding(horizontal = SubjectMetrics.accountGutter)
            .padding(top = 8.dp),
        color = LocalKudosTokens.current.secondaryInk,
        fontSize = 13.sp,
        lineHeight = 18.sp
    )
}

@Composable
fun SettingsSection(
    footnote: String?,
    label: String? = null,
    top: Dp = 22.dp,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(Modifier.padding(top = top)) {
        if (label != null) SettingsGroupLabel(label)
        SettingsPanel(content = content)
        if (footnote != null) SettingsFootnote(footnote)
    }
}

/** An accent action row: the iOS form button (destructive or tinted). */
@Composable
fun SettingsActionRow(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    contentDescription: String? = null,
    destructive: Boolean = false
) {
    val tokens = LocalKudosTokens.current
    val color = when {
        !enabled -> tokens.secondaryInk.copy(alpha = 0.45f)
        destructive -> MaterialTheme.colorScheme.error
        else -> tokens.accent
    }
    SettingsIconRow(
        label = label,
        color = color,
        icon = icon,
        iconTint = color,
        enabled = enabled,
        onClick = onClick,
        modifier = modifier,
        contentDescription = contentDescription
    )
}

/** A disclosure row. The icon, when present, is the accent glyph iOS draws. */
@Composable
fun SettingsLinkRow(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    value: String? = null
) {
    val tokens = LocalKudosTokens.current
    Row(
        modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = tokens.accent, modifier = Modifier.size(22.dp))
        }
        Text(
            text = label,
            modifier = Modifier.weight(1f),
            color = tokens.primaryInk,
            fontSize = 16.sp
        )
        if (value != null) {
            Text(text = value, color = tokens.secondaryInk, fontSize = 16.sp)
        }
        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = tokens.tertiaryInk,
            modifier = Modifier.size(18.dp)
        )
    }
}

@Composable
private fun SettingsIconRow(
    label: String,
    color: Color,
    icon: ImageVector?,
    iconTint: Color,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier,
    contentDescription: String?
) {
    Row(
        modifier
            .fillMaxWidth()
            .semantics {
                if (contentDescription != null) this.contentDescription = contentDescription
            }
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 13.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(22.dp))
        }
        Text(text = label, color = color, fontSize = 16.sp)
    }
}
