package io.github.cidy02.kudos.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.reader.speech.SpeechStatus
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Bottom floating card matching iOS `ReaderPositionCard.swift`:
 * 24dp continuous rounded rectangle with glass surface, page-within-chapter readout,
 * time remaining in chapter, a scrub slider with an origin tick (`|`), and whole-work summary line.
 * When read-aloud is active, the mini player sits at the top of the card above a hairline separator.
 */
@Composable
fun ReaderPositionCard(
    page: Int,
    pageCount: Int,
    chapterRemainingMinutes: Int?,
    workLine: String,
    sliderValue: Float,
    sliderEnabled: Boolean = true,
    onSeek: (Float) -> Unit,
    onSeekEnd: () -> Unit = {},
    // Mini player parameters
    showsMiniPlayer: Boolean = false,
    speechStatus: SpeechStatus = SpeechStatus.STOPPED,
    speechDownloadProgress: Float? = null,
    spokenText: String = "",
    onPlay: () -> Unit = {},
    onPause: () -> Unit = {},
    onStopSpeech: () -> Unit = {},
    onSkipNext: () -> Unit = {},
    onSkipPrevious: () -> Unit = {},
    onSeekSpeech: (Int) -> Unit = {},
    onSpeechSeekStart: () -> Unit = {},
    onSpeechSeekEnd: () -> Unit = {},
    onDownloadVoiceModel: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val cardShape = RoundedCornerShape(24.dp)

    val interactionSource = remember { MutableInteractionSource() }
    var scrubOrigin by remember { mutableStateOf<Float?>(null) }
    var isDragging by remember { mutableStateOf(false) }
    var previewValue by remember { mutableStateOf(sliderValue) }
    val currentSliderValue by rememberUpdatedState(sliderValue)
    val currentOnSeekEnd by rememberUpdatedState(onSeekEnd)

    // Drag preview owns the thumb until release; navigator callbacks never fight it.
    LaunchedEffect(sliderValue, isDragging) {
        if (!isDragging) previewValue = sliderValue
    }

    LaunchedEffect(interactionSource) {
        interactionSource.interactions.collect { interaction ->
            when (interaction) {
                is DragInteraction.Start -> {
                    scrubOrigin = currentSliderValue
                    isDragging = true
                }
                is DragInteraction.Stop -> {
                    scrubOrigin = null
                    isDragging = false
                }
                is DragInteraction.Cancel -> {
                    scrubOrigin = null
                    isDragging = false
                    currentOnSeekEnd()
                }
            }
        }
    }

    val scrubValuesEmphasized = isDragging && scrubOrigin != null &&
        ReaderProgressDisplay.scrubPage(previewValue, pageCount) !=
        ReaderProgressDisplay.scrubPage(scrubOrigin ?: previewValue, pageCount)
    val pageA11y = ReaderProgressDisplay.pageLabel(page, pageCount)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .clip(cardShape)
            .background(tokens.cardFill.copy(alpha = 0.90f), cardShape)
            .background(tokens.glassFill(), cardShape)
            .border(0.5.dp, tokens.glassStroke(), cardShape)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth()
        ) {
            // Optional read-aloud mini player strip
            if (showsMiniPlayer) {
                PositionMiniPlayer(
                    status = speechStatus,
                    downloadProgress = speechDownloadProgress,
                    spokenText = spokenText,
                    onPlay = onPlay,
                    onPause = onPause,
                    onStop = onStopSpeech,
                    onSkipNext = onSkipNext,
                    onSkipPrevious = onSkipPrevious,
                    onSeek = onSeekSpeech,
                    onSeekStart = onSpeechSeekStart,
                    onSeekEnd = onSpeechSeekEnd,
                    onDownloadStart = onDownloadVoiceModel
                )

                // Hairline separator inside the same glass surface
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 18.dp)
                        .height(1.dp)
                        .background(tokens.glassStroke(0.12))
                )
            }

            // Chapter & whole-work reading progress
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(
                        start = 18.dp,
                        end = 18.dp,
                        top = if (showsMiniPlayer) 12.dp else 13.dp,
                        bottom = 15.dp
                    ),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // Top row: Page number & chapter time remaining. A row that wraps: at twice the text
                // size the two ran together ("Page 1 of 1" then "0 min" read "of 10 min"). When they
                // fit, as at ordinary sizes, it is the same one row with the time at the far end.
                @OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
                androidx.compose.foundation.layout.FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalArrangement = Arrangement.spacedBy(2.dp)
                ) {
                    // Page Title Label
                    if (page < 1 || pageCount < 1) {
                        Text(
                            text = "Page …",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold,
                            style = TextStyle(fontFeatureSettings = "tnum"), // iOS .monospacedDigit()
                            color = tokens.secondaryInk
                        )
                    } else {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "Page ",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                style = TextStyle(fontFeatureSettings = "tnum"), // iOS .monospacedDigit()
                                color = tokens.primaryInk
                            )
                            Text(
                                text = "$page",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                style = TextStyle(fontFeatureSettings = "tnum"), // iOS .monospacedDigit()
                                color = if (scrubValuesEmphasized) tokens.accentInk else tokens.primaryInk
                            )
                            Text(
                                text = " of $pageCount",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                                style = TextStyle(fontFeatureSettings = "tnum"), // iOS .monospacedDigit()
                                color = tokens.primaryInk
                            )
                        }
                    }

                    // Chapter Time Label
                    if (chapterRemainingMinutes != null) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = ReaderProgressDisplay.durationLabel(chapterRemainingMinutes),
                                fontSize = 13.sp,
                                style = TextStyle(fontFeatureSettings = "tnum"), // iOS .monospacedDigit()
                                color = if (scrubValuesEmphasized) tokens.accentInk else tokens.secondaryInk
                            )
                            Text(
                                text = " left in chapter",
                                fontSize = 13.sp,
                                style = TextStyle(fontFeatureSettings = "tnum"), // iOS .monospacedDigit()
                                color = tokens.secondaryInk
                            )
                        }
                    }
                }

                // Scrub Slider with Origin Tick
                BoxWithConstraints(
                    modifier = Modifier
                        .fillMaxWidth(),
                    contentAlignment = Alignment.CenterStart
                ) {
                    val fullWidth = maxWidth

                    Slider(
                        value = (if (isDragging) previewValue else sliderValue).coerceIn(0f, 1f),
                        onValueChange = { value ->
                            val origin = scrubOrigin
                            val snapped = if (origin != null &&
                                ReaderProgressDisplay.scrubPage(value, pageCount) ==
                                ReaderProgressDisplay.scrubPage(origin, pageCount)
                            ) origin else value
                            previewValue = snapped
                            onSeek(snapped)
                        },
                        onValueChangeFinished = onSeekEnd,
                        enabled = sliderEnabled,
                        interactionSource = interactionSource,
                        colors = SliderDefaults.colors(
                            thumbColor = tokens.accent,
                            activeTrackColor = tokens.accent,
                            inactiveTrackColor = tokens.glassStroke(0.3)
                        ),
                        modifier = Modifier.fillMaxWidth().semantics {
                            contentDescription = "Seek within chapter"
                            stateDescription = pageA11y
                        }
                    )

                    // Origin tick `|` marking where scrubbing began
                    scrubOrigin?.let { origin ->
                        val inset = 12.dp
                        val usableWidth = fullWidth - (inset * 2)
                        val tickOffset = inset + (usableWidth * origin.coerceIn(0f, 1f))

                        Box(
                            modifier = Modifier
                                .padding(start = tickOffset)
                                .size(width = 2.dp, height = 14.dp)
                                .background(
                                    tokens.secondaryInk.copy(alpha = 0.85f),
                                    RoundedCornerShape(1.dp)
                                )
                        )
                    }
                }

                // Whole-work progress summary line
                if (workLine.isNotBlank()) {
                    Text(
                        text = workLine,
                        fontSize = 13.sp,
                        color = tokens.secondaryInk,
                        textAlign = TextAlign.Center,
                        // "… · 0 min left" was cut off at twice the text size.
                        maxLines = if (io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()) 2 else 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        }
    }
}

@Composable
private fun PositionMiniPlayer(
    status: SpeechStatus,
    downloadProgress: Float?,
    spokenText: String,
    onPlay: () -> Unit,
    onPause: () -> Unit,
    onStop: () -> Unit,
    onSkipNext: () -> Unit,
    onSkipPrevious: () -> Unit,
    onSeek: (Int) -> Unit,
    onSeekStart: () -> Unit,
    onSeekEnd: () -> Unit,
    onDownloadStart: () -> Unit
) {
    val tokens = LocalKudosTokens.current

    if (status == SpeechStatus.MODEL_NOT_DOWNLOADED) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "High-quality voice model needed (~45MB)",
                style = MaterialTheme.typography.bodyMedium,
                color = tokens.primaryInk
            )
            if (downloadProgress != null) {
                LinearProgressIndicator(
                    progress = { downloadProgress },
                    color = tokens.accentInk,
                    trackColor = tokens.glassStroke(0.3),
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    text = "${(downloadProgress * 100).toInt()}%",
                    style = MaterialTheme.typography.bodySmall,
                    color = tokens.secondaryInk
                )
            } else {
                Button(
                    onClick = onDownloadStart,
                    colors = ButtonDefaults.buttonColors(containerColor = tokens.accent)
                ) {
                    Text("Download Model", color = Color.White)
                }
            }
            TextButton(onClick = onStop) {
                Text("Close", color = tokens.secondaryInk)
            }
        }
    } else {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            // Transport controls row (44dp high)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Leading Waveform Icon
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.VolumeUp,
                    contentDescription = null,
                    tint = tokens.accentInk,
                    modifier = Modifier.size(24.dp)
                )

                // Transport: Skip Previous, Play/Pause, Skip Next
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SpeechSkipButton(
                        icon = Icons.Filled.SkipPrevious, label = "Previous paragraph", delta = -1,
                        onClick = onSkipPrevious, onSeek = onSeek,
                        onSeekStart = onSeekStart, onSeekEnd = onSeekEnd
                    )

                    IconButton(
                        onClick = if (status == SpeechStatus.PLAYING) onPause else onPlay,
                        modifier = Modifier.size(44.dp)
                    ) {
                        Icon(
                            imageVector = if (status == SpeechStatus.PLAYING) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = if (status == SpeechStatus.PLAYING) "Pause" else "Play",
                            tint = tokens.primaryInk,
                            modifier = Modifier.size(28.dp)
                        )
                    }

                    SpeechSkipButton(
                        icon = Icons.Filled.SkipNext, label = "Next paragraph", delta = 1,
                        onClick = onSkipNext, onSeek = onSeek,
                        onSeekStart = onSeekStart, onSeekEnd = onSeekEnd
                    )
                }

                // Trailing Stop Button
                IconButton(
                    onClick = onStop,
                    modifier = Modifier.size(44.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Stop,
                        contentDescription = "Stop reading aloud",
                        tint = tokens.primaryInk
                    )
                }
            }

            // Spoken text caption preview (2 lines reserved)
            if (spokenText.isNotBlank()) {
                Text(
                    text = spokenText,
                    fontSize = 13.sp,
                    color = tokens.secondaryInk,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}

/** Tap skips; a hold steps through chapter positions and preserves paused playback on release. */
@Composable
private fun SpeechSkipButton(
    icon: ImageVector,
    label: String,
    delta: Int,
    onClick: () -> Unit,
    onSeek: (Int) -> Unit,
    onSeekStart: () -> Unit,
    onSeekEnd: () -> Unit
) {
    val click by rememberUpdatedState(onClick)
    val seek by rememberUpdatedState(onSeek)
    val start by rememberUpdatedState(onSeekStart)
    val end by rememberUpdatedState(onSeekEnd)
    Box(
        modifier = Modifier.size(44.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = label
                role = Role.Button
                onClick { click(); true }
            }
            .pointerInput(delta) {
                coroutineScope {
                    var repeating: Job? = null
                    detectTapGestures(
                        onTap = { click() },
                        onLongPress = {
                            start()
                            repeating = launch {
                                while (isActive) {
                                    seek(delta)
                                    delay(180)
                                }
                            }
                        },
                        onPress = {
                            try {
                                tryAwaitRelease()
                            } finally {
                                repeating?.let { it.cancel(); end() }
                                repeating = null
                            }
                        }
                    )
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = LocalKudosTokens.current.primaryInk)
    }
}
