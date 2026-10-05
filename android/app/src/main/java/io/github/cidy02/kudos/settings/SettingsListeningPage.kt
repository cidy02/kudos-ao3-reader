package io.github.cidy02.kudos.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import io.github.cidy02.kudos.reader.speech.KokoroTTSController
import io.github.cidy02.kudos.reader.speech.SpeechStatus
import io.github.cidy02.kudos.reader.speech.TTSDownloadWorker
import io.github.cidy02.kudos.reader.speech.TTSService
import io.github.cidy02.kudos.reader.speech.applySpeechPreferences
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import java.util.Locale
import kotlinx.coroutines.launch

@Composable
fun SettingsListeningPage(repository: SettingsRepository) {
    val context = LocalContext.current.applicationContext
    val service = remember(context) { KokoroTTSController(context) }
    DisposableEffect(service) {
        onDispose { service.shutdown() }
    }
    SettingsListeningPage(repository, service, TTSDownloadWorker.isModelDownloaded(context))
}

/** The production page accepts the existing engine seam so tests can report real catalog-shaped data. */
@Composable
internal fun SettingsListeningPage(
    repository: SettingsRepository,
    service: TTSService,
    packInstalled: Boolean
) {
    val speech by repository.speechPreferences.collectAsState(initial = ReaderSpeechPreferences())
    val voices by service.availableVoices.collectAsState()
    val status by service.status.collectAsState()
    val scope = rememberCoroutineScope()
    var sample by remember { mutableStateOf(ListeningSample.PlainNarration) }
    var auditionRequested by remember { mutableStateOf(false) }
    val voiceName = voices.firstOrNull { it.id == speech.voiceIdentifier }?.name
        ?: if (speech.voiceIdentifier == null) voices.firstOrNull()?.name else null
    val updateRate: (Float) -> Unit = { scope.launch { repository.updateSpeechRate(it) } }

    // Like iOS's audition harness, changing the real settings restarts a playing sample.
    LaunchedEffect(service, speech, sample, auditionRequested) {
        if (auditionRequested) {
            try {
                service.applySpeechPreferences(speech.applyTo(ReaderPreferences()))
                service.speak(sample.text)
                auditionRequested = false
            } finally {
                service.stop()
            }
        }
    }
    DisposableEffect(service) {
        onDispose { service.stop() }
    }

    SettingsPage(title = "Listening") {
        item {
            SettingsSection(
                label = "Audition Voice",
                footnote = "Play a sample to hear your current Read Aloud settings without opening a work."
            ) {
                ListeningChoiceRow(
                    label = "Sample Text",
                    value = sample.label,
                    choices = ListeningSample.entries.map { it.name to it.label },
                    onSelect = { selected -> sample = ListeningSample.valueOf(selected) }
                )
                SubjectRowSeparator()
                SubjectSliderRow(
                    label = "Speed",
                    value = speech.rate,
                    valueRange = ReaderSpeechPreferences.RATE_RANGE,
                    steps = ReaderSpeechPreferences.RATE_STEPS,
                    formatValue = { speedLabel(it, audition = true) },
                    onValueChangeFinished = updateRate,
                    accessibilityLabel = "Audition speed"
                )
                listOf(0.9f to "0.9x", 1f to "1.0x (default)", 1.1f to "1.1x").forEach { (rate, label) ->
                    SettingsActionRow(label, onClick = { updateRate(rate) }, enabled = speech.rate != rate)
                }
                SubjectRowSeparator()
                if (auditionRequested) {
                    SubjectFormRow("Playing Sample")
                    SubjectFormRow("Engine", value = "Kokoro")
                    SubjectFormRow("Voice", value = voiceName ?: "Automatic")
                    SettingsActionRow("Stop", onClick = {
                        auditionRequested = false
                        service.stop()
                    }, destructive = true)
                } else {
                    SettingsActionRow(
                        "Play Sample",
                        enabled = status != SpeechStatus.UNAVAILABLE && voices.isNotEmpty(),
                        onClick = { auditionRequested = true }
                    )
                }
            }
        }
        item {
            SettingsSection(
                label = "Kokoro Pack",
                footnote = when {
                    !packInstalled -> "Download the Kokoro Voice Pack from the reader to use Read Aloud."
                    status == SpeechStatus.UNAVAILABLE -> "The installed voice pack could not be opened."
                    else -> null
                }
            ) {
                SubjectFormRow("Voice Pack", value = if (packInstalled) "Voice Pack Downloaded" else "Not downloaded")
            }
        }
        item {
            SettingsSection(
                label = "Read Aloud",
                footnote = "Kudos doesn't send your reading, your library or any usage data."
            ) {
                ListeningChoiceRow(
                    label = "Voice",
                    value = voices.firstOrNull { it.id == speech.voiceIdentifier }?.name
                        ?: "Automatic (best available)",
                    choices = listOf("" to "Automatic (best available)") + voices.map { it.id to "${it.name} · On device" },
                    onSelect = { id -> scope.launch { repository.updateSpeechVoiceIdentifier(id) } }
                )
                SubjectRowSeparator()
                SubjectSliderRow(
                    label = "Speed",
                    value = speech.rate,
                    valueRange = ReaderSpeechPreferences.RATE_RANGE,
                    steps = ReaderSpeechPreferences.RATE_STEPS,
                    formatValue = { speedLabel(it, audition = false) },
                    onValueChangeFinished = updateRate,
                    accessibilityLabel = "Read-aloud speed"
                )
                SubjectRowSeparator()
                SettingsActionRow("Reset Read Aloud", onClick = {
                    scope.launch { repository.resetSpeechPreferences() }
                })
            }
        }
    }
}

@Composable
private fun ListeningChoiceRow(
    label: String,
    value: String,
    choices: List<Pair<String, String>>,
    onSelect: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val tokens = LocalKudosTokens.current
    Box(Modifier.fillMaxWidth()) {
        SubjectFormRow(label, value = value, showsDisclosure = true, onClick = { expanded = true })
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            containerColor = tokens.theme.cardSurface
        ) {
            choices.forEach { (id, title) ->
                DropdownMenuItem(
                    text = { Text(title, color = tokens.primaryInk, fontSize = 16.sp, lineHeight = 22.sp) },
                    onClick = { expanded = false; onSelect(id) }
                )
            }
        }
    }
}

private fun speedLabel(rate: Float, audition: Boolean): String =
    if (kotlin.math.abs(rate - 1f) < 0.001f) {
        if (audition) "Default (1.0x)" else "Default"
    } else String.format(Locale.getDefault(), "%.0f%%", rate * 100)

/** Exact sample order and text from iOS ReaderSpeechAuditionHarness.swift. Not persisted. */
internal enum class ListeningSample(val label: String, val text: String) {
    DialogueHeavy("Dialogue-heavy", "\"Are you certain this is safe?\" she asked, stepping back. " +
        "\"Absolutely not,\" he replied without looking up from the monitor. \"But it's our only option.\""),
    NumbersNames("Numbers & Names", "Dr. Elara Vance noted that exactly 1,452 samples were processed " +
        "by the HX-7 system before 08:30 on November 4th, 2026."),
    PlainNarration("Plain Narration", "The afternoon sun cast long shadows across the empty hallway. " +
        "Dust motes danced in the fading light, settling slowly onto the " +
        "forgotten furniture as silence reclaimed the room.")
}
