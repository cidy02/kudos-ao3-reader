package io.github.cidy02.kudos.home

import io.github.cidy02.kudos.ui.components.hiddenMatureWorkSemantics
import io.github.cidy02.kudos.ui.subject.SelectionChrome
import io.github.cidy02.kudos.ui.subject.RevealCapsule
import io.github.cidy02.kudos.ui.subject.CoverSurface
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.library.readingProgressFraction
import io.github.cidy02.kudos.ui.subject.HomeStatusArrangement
import io.github.cidy02.kudos.ui.subject.HomeStatusTray
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectKicker
import androidx.compose.ui.platform.LocalDensity
import io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale
import io.github.cidy02.kudos.ui.subject.SubjectMetrics
import io.github.cidy02.kudos.ui.subject.SubjectPalette
import io.github.cidy02.kudos.ui.subject.WorkReadingOrDownloadRing
import io.github.cidy02.kudos.ui.subject.downloadDimmed
import io.github.cidy02.kudos.ui.subject.withOpacity
import java.time.Instant

/**
 * The top in-progress work. Port of `HomeResumeHero` / `UnblurredHomeResumeHero`.
 * The Resume capsule is drawn, not its own button: the whole card opens the reader.
 * The author name is text. Android Home has no author route wired on this card.
 */
@Composable
fun HomeResumeHero(
    work: SavedWork,
    downloading: Boolean,
    obscured: Boolean,
    isSelecting: Boolean,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    now: Instant = Instant.now()
) {
    val tokens = LocalKudosTokens.current
    val hue = HomeFacts.workHue(work.workFandoms, work.title)
    val palette = SubjectPalette.fromHue(hue, tokens.theme)
    val shape = RoundedCornerShape(SubjectMetrics.heroRadius)
    val dim by animateFloatAsState(
        targetValue = if (downloading) 1f else 0f,
        animationSpec = tween(250),
        label = "heroDim"
    )
    Box(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(bottom = 4.dp)
            .downloadDimmed(dim)
    ) {
        Box(
            Modifier
                .then(if (obscured) Modifier.blur(6.dp) else Modifier)
                .hiddenMatureWorkSemantics(obscured, isSelecting)
        ) {
            CoverSurface(palette = palette, shape = shape, hero = true, modifier = Modifier.fillMaxWidth()) {
                HeroBody(work = work, palette = palette, downloading = downloading, now = now)
            }
        }
        if (obscured && !isSelecting) {
            RevealCapsule(Modifier.align(Alignment.Center))
        }
        if (isSelecting) {
            SelectionChrome(isSelected = isSelected, shape = shape)
        }
    }
}

@Composable
private fun HeroBody(
    work: SavedWork,
    palette: SubjectPalette,
    downloading: Boolean,
    now: Instant
) {
    val tokens = LocalKudosTokens.current
    val fraction = (work.readingProgressFraction() ?: 0.0).coerceIn(0.0, 1.0)
    val place = HomeFacts.locatorTitle(work.readiumLocator)
        ?: if (work.lastReadDate == null) "Ready to resume" else "Last opened"
    val whenText = work.lastReadDate?.let { HomeFacts.relativeNamed(it, now) }
    val figures = HomeFacts.localWorkMetadata(author = "", wordCount = work.wordCount, chapters = work.chapters)
    // iOS `HomeResumeHero`: at accessibility text sizes the status tray joins the column above
    // the kicker, the title is not limited to two lines, and the ring, the place and Resume
    // stack instead of sharing a row. The ring grows with the text (`@ScaledMetric`).
    val large = isAccessibilityFontScale()
    val trayReserve = if (large) 0.dp else 78.dp
    val tray: @Composable (Modifier) -> Unit = { trayModifier ->
        HomeStatusTray(
            rating = work.rating,
            categories = work.workCategories,
            warnings = work.workWarnings,
            isComplete = work.isComplete,
            arrangement = HomeStatusArrangement.Grid,
            tileSize = 22.dp,
            modifier = trayModifier
        )
    }
    val ring: @Composable () -> Unit = {
        WorkReadingOrDownloadRing(
            downloading = downloading,
            progress = fraction,
            state = if (fraction >= 1.0) "Finished" else "Reading",
            diameter = SubjectMetrics.ringDiameter * LocalDensity.current.fontScale
        )
    }
    val placeLines: @Composable (Modifier) -> Unit = { placeModifier ->
        Column(placeModifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                text = place,
                color = tokens.primaryInk,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = if (large) Int.MAX_VALUE else 2
            )
            if (whenText != null) {
                Text(
                    text = whenText,
                    color = tokens.primaryInk.withOpacity(0.6),
                    fontSize = 12.sp,
                    maxLines = if (large) Int.MAX_VALUE else 1
                )
            }
        }
    }
    val resume: @Composable () -> Unit = {
        Text(
            text = "Resume",
            color = palette.solidButtonLabel,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier
                .background(palette.solidButtonFill, RoundedCornerShape(percent = 50))
                .padding(horizontal = 18.dp, vertical = 10.dp)
        )
    }
    Box(Modifier.fillMaxWidth()) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (large) tray(Modifier)
            val fandom = HomeFacts.primaryFandom(work.workFandoms)
            if (fandom != null) {
                SubjectKicker(
                    text = fandom,
                    palette = palette,
                    size = 9.5.sp,
                    ruleSpacing = 7.dp,
                    modifier = Modifier.padding(end = trayReserve)
                )
            }
            Text(
                text = work.title,
                color = tokens.primaryInk,
                fontSize = 31.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = (-0.62).sp,
                maxLines = if (large) Int.MAX_VALUE else 2,
                modifier = Modifier.padding(end = trayReserve)
            )
            MetadataLine(author = work.author, figures = figures)
            if (large) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        ring()
                        placeLines(Modifier.fillMaxWidth())
                    }
                    resume()
                }
            } else {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    ring()
                    placeLines(Modifier.weight(1f))
                    resume()
                }
            }
        }
        if (!large) tray(Modifier.align(Alignment.TopEnd).padding(14.dp))
    }
}

@Composable
private fun MetadataLine(author: String, figures: List<String>) {
    val ink = LocalKudosTokens.current.primaryInk
    val name = author.trim()
    val segments = buildList {
        if (name.isNotEmpty()) add(name)
        addAll(figures)
    }
    if (segments.isEmpty()) return
    val line = buildAnnotatedString {
        segments.forEachIndexed { index, segment ->
            if (index > 0) {
                withStyle(SpanStyle(color = ink.withOpacity(0.35))) { append("  ·  ") }
            }
            withStyle(SpanStyle(color = ink.withOpacity(0.75))) { append(segment) }
        }
    }
    Text(text = line, fontSize = 13.sp)
}
