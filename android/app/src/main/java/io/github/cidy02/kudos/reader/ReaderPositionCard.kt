package io.github.cidy02.kudos.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.reader.speech.SpeechStatus
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens

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
    onDownloadVoiceModel: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    val tokens = LocalKudosTokens.current
    val cardShape = RoundedCornerShape(24.dp)

    val interactionSource = remember { MutableInteractionSource() }
    var scrubOrigin by remember { mutableStateOf<Float?>(null) }
    var isDragging by remember { mutableStateOf(false) }

    LaunchedEffect(interactionSource) {
        interactionSource.interactions.collect { interaction ->
            when (interaction) {
                is DragInteraction.Start -> {
                    scrubOrigin = sliderValue
                    isDragging = true
                }
                is DragInteraction.Stop, is DragInteraction.Cancel -> {
                    scrubOrigin = null
                    isDragging = false
                    onSeekEnd()
                }
            }
        }
    }

    val scrubValuesEmphasized = isDragging && scrubOrigin != null && kotlin.math.abs(sliderValue - (scrubOrigin ?: 0f)) > 0.01f

    val pageA11y = if (page < 1 || pageCount < 1) "Measuring pages" else "Page $page of $pageCount"

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
                // Top row: Page number & chapter time remaining
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
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
                                color = if (scrubValuesEmphasized) tokens.accent else tokens.primaryInk
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
                                text = "$chapterRemainingMinutes min",
                                fontSize = 13.sp,
                                style = TextStyle(fontFeatureSettings = "tnum"), // iOS .monospacedDigit()
                                color = if (scrubValuesEmphasized) tokens.accent else tokens.secondaryInk
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
                        .fillMaxWidth()
                        .semantics {
                            contentDescription = "Seek within chapter: $pageA11y"
                        },
                    contentAlignment = Alignment.CenterStart
                ) {
                    val fullWidth = maxWidth

                    Slider(
                        value = sliderValue.coerceIn(0f, 1f),
                        onValueChange = onSeek,
                        enabled = sliderEnabled,
                        interactionSource = interactionSource,
                        colors = SliderDefaults.colors(
                            thumbColor = tokens.accent,
                            activeTrackColor = tokens.accent,
                            inactiveTrackColor = tokens.glassStroke(0.3)
                        ),
                        modifier = Modifier.fillMaxWidth()
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
                        maxLines = 1,
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
                    color = tokens.accent,
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
                    tint = tokens.accent,
                    modifier = Modifier.size(24.dp)
                )

                // Transport: Skip Previous, Play/Pause, Skip Next
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(
                        onClick = onSkipPrevious,
                        modifier = Modifier.size(44.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.SkipPrevious,
                            contentDescription = "Previous paragraph",
                            tint = tokens.primaryInk
                        )
                    }

                    IconButton(
                        onClick = if (status == SpeechStatus.PLAYING) onPause else onPlay,
                        modifier = Modifier.size(44.dp)
                    ) {
                        Icon(
                            imageVector = if (status == SpeechStatus.PLAYING) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = if (status == SpeechStatus.PLAYING) "Pause TTS" else "Play TTS",
                            tint = tokens.primaryInk,
                            modifier = Modifier.size(28.dp)
                        )
                    }

                    IconButton(
                        onClick = onSkipNext,
                        modifier = Modifier.size(44.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Filled.SkipNext,
                            contentDescription = "Next paragraph",
                            tint = tokens.primaryInk
                        )
                    }
                }

                // Trailing Stop Button
                IconButton(
                    onClick = onStop,
                    modifier = Modifier.size(44.dp)
                ) {
                    Icon(
                        imageVector = Icons.Filled.Stop,
                        contentDescription = "Stop TTS",
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
