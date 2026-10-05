package io.github.cidy02.kudos.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale

/** iOS's intro and raised action footer; large type scrolls the whole page. */
@Composable
fun OnboardingScaffold(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
    footer: @Composable ColumnScope.() -> Unit
) {
    val tokens = LocalKudosTokens.current
    val largeType = isAccessibilityFontScale()
    Column(
        modifier.fillMaxSize().background(tokens.theme.cardBackdrop).safeDrawingPadding()
            .then(if (largeType) Modifier.verticalScroll(rememberScrollState()) else Modifier)
    ) {
        Column(
            Modifier.then(if (largeType) Modifier else Modifier.weight(1f))
                .fillMaxWidth()
                .then(if (largeType) Modifier else Modifier.verticalScroll(rememberScrollState()))
                .padding(horizontal = 28.dp).padding(top = 44.dp, bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Column(
                Modifier.widthIn(max = 540.dp).fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(28.dp),
                content = content
            )
        }
        Column(
            Modifier.fillMaxWidth().background(tokens.theme.cardSurface)
                .padding(horizontal = 28.dp).padding(top = 14.dp, bottom = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Column(
                Modifier.widthIn(max = 540.dp).fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp),
                content = footer
            )
        }
    }
}

@Composable
fun OnboardingPoint(icon: ImageVector, title: String, body: String) {
    val tokens = LocalKudosTokens.current
    Row(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Icon(icon, contentDescription = null, tint = tokens.accent,
            modifier = Modifier.size(28.dp).padding(top = 2.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium,
                color = tokens.primaryInk, lineHeight = 24.sp)
            Text(body, style = MaterialTheme.typography.bodyMedium,
                color = tokens.secondaryInk, lineHeight = 21.sp)
        }
    }
}
