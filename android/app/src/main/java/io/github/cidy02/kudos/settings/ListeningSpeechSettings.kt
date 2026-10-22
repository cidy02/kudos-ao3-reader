package io.github.cidy02.kudos.settings

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.work.WorkManager
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import io.github.cidy02.kudos.reader.settings.ReaderTTSEngineKind
import io.github.cidy02.kudos.reader.speech.TTSDownloadWorker
import io.github.cidy02.kudos.reader.speech.VoicePackState
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import java.util.Locale

/*
 * Settings › Listening's voice pack, Engine and Pitch (brief 3gd; A66 #15, #16), after iOS
 * Features/ReaderReadium/ReaderSpeechSettingsSection.swift. Kept apart from
 * SettingsListeningPage.kt so the page itself changes by a few call sites.
 *
 * Not ported: iOS's "Developer Settings" row (pause, chunk and boundary tuning). Android has no
 * speech-tuning pipeline for it to change; the owner's recorded decision leaves it out.
 */

/** The Listening page's view of the pack download and the two things it can do to it. */
internal class VoicePackUi(
    val state: VoicePackState,
    /** The pack's files are on the device (TTSDownloadWorker.isModelDownloaded). */
    val installed: Boolean,
    val onDownload: () -> Unit,
    val onCancel: () -> Unit
) {
    companion object {
        /** A pack that is or is not here, with nothing under way and nothing to start. */
        fun fixed(installed: Boolean) = VoicePackUi(
            state = if (installed) VoicePackState.Downloaded else VoicePackState.NotDownloaded,
            installed = installed,
            onDownload = {},
            onCancel = {}
        )
    }
}

/**
 * Watches the reader's own download ([TTSDownloadWorker]'s unique work, as
 * ReaderSpeechController does), so a download started in either place shows in both. The disk
 * is read again whenever the work changes: the pack it installs shows at once.
 */
@Composable
internal fun rememberVoicePackUi(context: Context): VoicePackUi {
    val infos by remember(context) {
        WorkManager.getInstance(context).getWorkInfosForUniqueWorkFlow(TTSDownloadWorker.WORK_NAME)
    }.collectAsState(initial = emptyList())
    val info = infos.firstOrNull()
    var cancelling by remember { mutableStateOf(false) }
    val installed = remember(info?.state) { TTSDownloadWorker.isModelDownloaded(context) }
    LaunchedEffect(info?.state) {
        if (info == null || info.state.isFinished) cancelling = false
    }
    return VoicePackUi(
        state = VoicePackState.from(info, installed, cancelling),
        installed = installed,
        onDownload = {
            cancelling = false
            TTSDownloadWorker.enqueue(context)
        },
        onCancel = {
            cancelling = true
            TTSDownloadWorker.cancel(context)
        }
    )
}

/** iOS `selectedPackSizeLabel` for the Int8 pack, the one pack Android has. */
internal const val VOICE_PACK_SIZE_LABEL = "103 MB"

/** iOS's confirmation for the Int8 pack (`KokoroModelPack.int8V019.displayName`, host GitHub). */
internal const val VOICE_PACK_CONFIRM_TITLE = "Download Efficient (Int8) Voice Pack?"
internal const val VOICE_PACK_CONFIRM_MESSAGE = "Kudos downloads this public Voice Pack from GitHub. Nothing " +
    "about your reading or library is sent, but the provider or its delivery " +
    "service can receive your IP address and basic connection details."

/** iOS `downloadDisclosure` for the Int8 pack: the section's footer, always shown. */
internal const val VOICE_PACK_DISCLOSURE = "The Int8 Voice Pack downloads its public files from GitHub." +
    " Kudos sends no book text, audio, AO3 login details, library, reading " +
    "history, usage data, or anything that identifies your account. The provider or its delivery service " +
    "can receive your IP address and basic connection details under its privacy policy."

/**
 * iOS `coreMLDownloadSection`: "Kokoro Neural Engine", with Download (confirmed first), progress and
 * Cancel, Retry after a failure, and the installed state. [packFailedToOpen] keeps Android's
 * note for a pack that is here but would not open.
 */
@Composable
internal fun ListeningVoicePackSection(voicePack: VoicePackUi, packFailedToOpen: Boolean) {
    var confirming by remember { mutableStateOf(false) }
    val tokens = LocalKudosTokens.current
    SettingsSection(
        label = "Kokoro Neural Engine",
        footnote = if (packFailedToOpen) {
            "The installed voice pack could not be opened. $VOICE_PACK_DISCLOSURE"
        } else VOICE_PACK_DISCLOSURE
    ) {
        when (val state = voicePack.state) {
            is VoicePackState.Downloading -> Column(
                Modifier.fillMaxWidth().padding(horizontal = 13.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                LinearProgressIndicator(
                    progress = { state.progress },
                    modifier = Modifier.fillMaxWidth(),
                    color = tokens.accentInk,
                    trackColor = tokens.glassStroke(0.13)
                )
                Text(
                    "Downloading... ${(state.progress * 100).toInt()}%",
                    color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 18.sp
                )
                VoicePackCancelButton(voicePack.onCancel)
            }
            VoicePackState.Extracting -> VoicePackBusyRow("Extracting...", onCancel = voicePack.onCancel)
            VoicePackState.Cancelling -> VoicePackBusyRow("Cancelling…", onCancel = null)
            VoicePackState.Downloaded -> SubjectFormRow(
                "Voice Pack Downloaded",
                trailing = {
                    Icon(
                        Icons.Filled.Check,
                        contentDescription = null,
                        tint = Color(0xFF34C759), // iOS .green
                        modifier = Modifier.size(18.dp)
                    )
                }
            )
            is VoicePackState.Failed -> {
                Text(
                    state.message,
                    modifier = Modifier.fillMaxWidth().padding(start = 13.dp, end = 13.dp, top = 10.dp),
                    color = MaterialTheme.colorScheme.error, fontSize = 13.sp, lineHeight = 18.sp
                )
                SettingsActionRow("Retry Download", onClick = { confirming = true })
            }
            VoicePackState.NotDownloaded ->
                SettingsActionRow("Download Kokoro (Neural Engine)", onClick = { confirming = true })
        }
    }
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            containerColor = tokens.theme.cardSurface,
            titleContentColor = tokens.primaryInk,
            textContentColor = tokens.secondaryInk,
            title = { Text(VOICE_PACK_CONFIRM_TITLE) },
            text = { Text(VOICE_PACK_CONFIRM_MESSAGE) },
            confirmButton = {
                TextButton(onClick = { confirming = false; voicePack.onDownload() }) {
                    Text("Download $VOICE_PACK_SIZE_LABEL", color = tokens.scopePalette.accent)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirming = false }) {
                    Text("Cancel", color = tokens.scopePalette.accent)
                }
            }
        )
    }
}

/** iOS `busyRow`: a spinner, what is happening and, while it can still stop, Cancel. */
@Composable
private fun VoicePackBusyRow(title: String, onCancel: (() -> Unit)?) {
    val tokens = LocalKudosTokens.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 13.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        CircularProgressIndicator(Modifier.size(18.dp), color = tokens.accentInk, strokeWidth = 2.dp)
        Text(title, color = tokens.primaryInk, fontSize = 14.5.sp, lineHeight = 20.sp)
        Spacer(Modifier.weight(1f))
        if (onCancel != null) VoicePackCancelButton(onCancel)
    }
}

@Composable
private fun VoicePackCancelButton(onCancel: () -> Unit) {
    TextButton(onClick = onCancel) {
        Text("Cancel", color = LocalKudosTokens.current.scopePalette.accent, fontSize = 15.sp)
    }
}

/** iOS's Engine picker: Automatic, then each engine in `ReaderTTSEngineKind.allCases` order. */
internal val speechEngineChoices: List<Pair<String, String>> =
    listOf(ReaderSpeechPreferences.AUTOMATIC_ENGINE to "Automatic") +
        ReaderTTSEngineKind.entries.map { it.rawValue to it.displayName }

internal fun speechEngineLabel(engine: String): String =
    speechEngineChoices.firstOrNull { it.first == engine }?.second ?: "Automatic"

/**
 * iOS `Picker("Engine")`, with iOS's note when Kokoro is chosen before its pack is here
 * (`isKokoroAwaitingVoicePack`). Ends with the separator before the next row.
 */
@Composable
internal fun ListeningEngineRow(engine: String, packInstalled: Boolean, onSelect: (String) -> Unit) {
    ListeningChoiceRow(
        label = "Engine",
        value = speechEngineLabel(engine),
        choices = speechEngineChoices,
        onSelect = onSelect
    )
    if (engine == ReaderTTSEngineKind.KOKORO.rawValue && !packInstalled) {
        val tokens = LocalKudosTokens.current
        Row(
            Modifier.fillMaxWidth().padding(start = 13.dp, end = 13.dp, bottom = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(Icons.Outlined.Info, contentDescription = null, tint = tokens.secondaryInk, modifier = Modifier.size(16.dp))
            Text(
                "Download the Kokoro Voice Pack to use Kokoro. Until then, you hear your device's own voice.",
                color = tokens.secondaryInk, fontSize = 13.sp, lineHeight = 18.sp
            )
        }
    }
    SubjectRowSeparator()
}

/** iOS `pitchLabel`: "Default" at 1.0, else two places and ×. */
internal fun speechPitchLabel(pitch: Float): String =
    if (kotlin.math.abs(pitch - ReaderSpeechPreferences.DEFAULT_PITCH) < 0.001f) "Default"
    else String.format(Locale.getDefault(), "%.2f×", pitch)

/**
 * iOS's Pitch slider (0.75–1.25, step 0.05), after Speed. The device's voice follows it;
 * Kokoro cannot (sherpa-onnx has no pitch control, as on iOS). Starts with its separator.
 */
@Composable
internal fun ListeningPitchRow(pitch: Float, onChange: (Float) -> Unit) {
    SubjectRowSeparator()
    SubjectSliderRow(
        label = "Pitch",
        value = pitch,
        valueRange = ReaderSpeechPreferences.PITCH_RANGE,
        steps = ReaderSpeechPreferences.PITCH_STEPS,
        formatValue = ::speechPitchLabel,
        onValueChangeFinished = onChange,
        accessibilityLabel = "Read-aloud pitch"
    )
}
