package io.github.cidy02.kudos.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.reader.settings.ReaderPreferences
import io.github.cidy02.kudos.reader.settings.ReaderSpeechPreferences
import io.github.cidy02.kudos.reader.settings.ReaderTTSEngineKind
import io.github.cidy02.kudos.reader.speech.AutomaticTTSService
import io.github.cidy02.kudos.reader.speech.SpeechStatus
import io.github.cidy02.kudos.reader.speech.TTSService
import io.github.cidy02.kudos.reader.speech.applySpeechPreferences
import io.github.cidy02.kudos.ui.subject.LocalKudosTokens
import io.github.cidy02.kudos.ui.subject.SubjectFormRow
import io.github.cidy02.kudos.ui.subject.SubjectToggle
import io.github.cidy02.kudos.ui.subject.SubjectRowSeparator
import java.util.Locale
import kotlinx.coroutines.launch

@Composable
fun SettingsListeningPage(repository: SettingsRepository) {
    val context = LocalContext.current.applicationContext
    val service = remember(context) { AutomaticTTSService(context) }
    DisposableEffect(service) {
        onDispose { service.shutdown() }
    }
    val voicePack = rememberVoicePackUi(context)
    SettingsListeningPage(repository, service, voicePack.installed, voicePack)
}

/** The production page accepts the existing engine seam so tests can report real catalog-shaped data. */
@Composable
internal fun SettingsListeningPage(
    repository: SettingsRepository,
    service: TTSService,
    packInstalled: Boolean = false,
    voicePack: VoicePackUi = VoicePackUi.fixed(packInstalled)
) {
    val installed = packInstalled || voicePack.installed
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
        service.setEngine(speech.engine)
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
                val speeds = listOf(0.9f to "0.9x", 1f to "1.0x (default)", 1.1f to "1.1x")
                // iOS sets the three side by side, the one in use dimmed. They were three lines
                // of text down the panel. At the large text sizes they stay lines: three do not
                // fit a row.
                if (io.github.cidy02.kudos.ui.subject.isAccessibilityFontScale()) speeds.forEach { (rate, label) ->
                    SettingsActionRow(label, onClick = { updateRate(rate) }, enabled = speech.rate != rate)
                } else androidx.compose.foundation.layout.Row(
                    Modifier.fillMaxWidth().padding(horizontal = 13.dp).padding(bottom = 10.dp),
                    horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(8.dp)
                ) {
                    val tokens = io.github.cidy02.kudos.ui.subject.LocalKudosTokens.current
                    speeds.forEach { (rate, label) ->
                        val inUse = speech.rate == rate
                        androidx.compose.foundation.layout.Box(
                            Modifier.weight(1f).heightIn(min = 44.dp)
                                // iOS's bordered buttons: tinted with the accent, the one in use dimmed (A70b).
                                .background(if (inUse) tokens.glassFill(0.05) else tokens.scopePalette.accent.copy(alpha = 0.15f),
                                    androidx.compose.foundation.shape.RoundedCornerShape(10.dp))
                                .clickable(enabled = !inUse, role = androidx.compose.ui.semantics.Role.Button) { updateRate(rate) }
                                .padding(horizontal = 6.dp, vertical = 8.dp),
                            contentAlignment = androidx.compose.ui.Alignment.Center
                        ) {
                            androidx.compose.material3.Text(label, fontSize = 13.sp, lineHeight = 17.sp,
                                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                                color = if (inUse) tokens.secondaryInk.copy(alpha = 0.45f) else tokens.scopePalette.accent)
                        }
                    }
                }
                SubjectRowSeparator()
                if (auditionRequested) {
                    SubjectFormRow("Playing Sample")
                    SubjectFormRow("Engine", value = ReaderTTSEngineKind.effective(speech.engine, installed).displayName)
                    SubjectFormRow("Voice", value = voiceName ?: "Automatic")
                    SettingsActionRow("Stop", onClick = {
                        auditionRequested = false
                        service.stop()
                    }, destructive = true)
                } else {
                    SettingsActionRow(
                        "Play Sample",
                        // The device's own voice reads without the pack, as iOS's Apple voice does.
                        enabled = status != SpeechStatus.UNAVAILABLE,
                        onClick = { auditionRequested = true }
                    )
                }
            }
        }
        item {
            ListeningVoicePackSection(
                voicePack = voicePack,
                packFailedToOpen = installed && status == SpeechStatus.UNAVAILABLE
            )
        }
        item {
            SettingsSection(
                label = "Read Aloud",
                footnote = "Automatic starts with your device's own voice, then uses Kokoro after you install " +
                    "its optional voice pack. Kudos doesn't send your reading, your library or any usage data."
            ) {
                ListeningEngineRow(speech.engine, installed) { engine ->
                    scope.launch { repository.updateSpeechEngine(engine) }
                }
                ListeningChoiceRow(
                    label = "Voice",
                    value = voices.firstOrNull { it.id == speech.voiceIdentifier }?.name
                        ?: "Automatic (best available)",
                    choices = listOf("" to "Automatic (best available)") + voices.map { it.id to "${it.name} · On device" },
                    onSelect = { id -> scope.launch { repository.updateSpeechVoiceIdentifier(id) } }
                )
                SubjectRowSeparator()
                PronunciationsRow()
                SubjectRowSeparator()
                SubjectFormRow(
                    "Read author's notes",
                    trailing = {
                        SubjectToggle(
                            checked = speech.readAuthorNotes,
                            onCheckedChange = { on -> scope.launch { repository.updateSpeechReadAuthorNotes(on) } },
                            // iOS's hint, said by TalkBack.
                            contentDescription = "Read author's notes. Author's notes often carry content " +
                                "warnings. Turn this off to hear only the story."
                        )
                    }
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
                ListeningPitchRow(speech.pitch) { pitch ->
                    scope.launch { repository.updateSpeechPitch(pitch) }
                }
                SubjectRowSeparator()
                SettingsActionRow("Reset Read Aloud", onClick = {
                    scope.launch { repository.resetSpeechPreferences() }
                })
            }
        }
    }
}

@Composable
internal fun ListeningChoiceRow(
    label: String,
    value: String,
    choices: List<Pair<String, String>>,
    onSelect: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val tokens = LocalKudosTokens.current
    Box(Modifier.fillMaxWidth()) {
        // iOS draws these as menu pickers: the value in the accent with a chevron (A70b).
        SubjectFormRow(label, value = value, showsChoice = true, onClick = { expanded = true })
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
