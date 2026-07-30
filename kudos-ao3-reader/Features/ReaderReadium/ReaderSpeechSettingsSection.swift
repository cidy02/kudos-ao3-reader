#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

/// Read-aloud controls for the shared `ReaderOptionsForm` (reader Display sheet
/// and Settings). Preferences persist via `@AppStorage` / UserDefaults and are
/// picked up by `ReaderSpeechController` on the next utterance.
struct ReaderSpeechSettingsSection: View {
    @AppStorage(ReaderSpeechPreferences.voiceIDKey) private var voiceID = ""
    @AppStorage(ReaderSpeechPreferences.rateKey)
    private var rate = ReaderSpeechPreferences.defaultRate
    @AppStorage(ReaderSpeechPreferences.pitchKey)
    private var pitch = ReaderSpeechPreferences.defaultPitch

    @State private var voices: [TTSVoice] = []

    private var sortedVoices: [TTSVoice] {
        voices.sorted()
    }

    private var selectedVoiceLabel: String {
        if voiceID.isEmpty {
            return "Automatic (best available)"
        }
        if let voice = voices.first(where: { $0.identifier == voiceID }) {
            return ReaderSpeechPreferences.displayName(for: voice)
        }
        return "Automatic (best available)"
    }

    var body: some View {
        Section {
            NavigationLink {
                voicePicker
            } label: {
                LabeledContent("Voice", value: selectedVoiceLabel)
            }

            Button {
                SystemSpokenContentSettings.open()
            } label: {
                Label("Open Settings for More Voices…", systemImage: "arrow.up.forward.app")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(rateLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $rate, in: ReaderSpeechPreferences.rateRange, step: 0.05)
                    .accessibilityLabel("Read-aloud speed")
                    .accessibilityValue(rateLabel)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pitch")
                    Spacer()
                    Text(pitchLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $pitch, in: ReaderSpeechPreferences.pitchRange, step: 0.05)
                    .accessibilityLabel("Read-aloud pitch")
                    .accessibilityValue(pitchLabel)
            }

            Button("Reset Read Aloud") {
                voiceID = ""
                rate = ReaderSpeechPreferences.defaultRate
                pitch = ReaderSpeechPreferences.defaultPitch
            }
        } header: {
            Text("Read Aloud")
        } footer: {
            Text(
                "Automatic picks the highest-quality voice for the book’s language. "
                    + "Open Settings jumps to this app’s own Settings page — iOS doesn’t let "
                    + "apps deep-link any further than that. From there, go to Settings → "
                    + "Accessibility → Read & Speak → Voices → (Language) → Voice to download "
                    + "Enhanced or Premium voices. After installing one, return here and choose "
                    + "it — or leave Automatic. Personal Voice is not used."
            )
        }
        .onAppear { voices = ReaderSpeechPreferences.catalogVoices() }
    }

    private var voicePicker: some View {
        List {
            Section {
                voiceRow(
                    id: "",
                    title: "Automatic (best available)",
                    subtitle: automaticSubtitle
                )
            }

            Section {
                ForEach(sortedVoices, id: \.identifier) { voice in
                    voiceRow(
                        id: voice.identifier,
                        title: voice.name,
                        subtitle: voiceSubtitle(voice)
                    )
                }
            } header: {
                Text("Installed Voices")
            } footer: {
                if !hasEnhancedOrBetter {
                    Text(
                        "Only compact voices are installed. Use Open Settings for More Voices, "
                            + "then Accessibility → Read & Speak → Voices → (Language) to add "
                            + "higher-quality voices, then return here."
                    )
                }
            }

            Section {
                Button {
                    SystemSpokenContentSettings.open()
                } label: {
                    Label("Download Enhanced & Premium Voices…", systemImage: "arrow.up.forward.app")
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        // Returning from Settings: refresh so newly installed voices appear.
        .onAppear { voices = ReaderSpeechPreferences.catalogVoices() }
    }
    private func voiceRow(id: String, title: String, subtitle: String) -> some View {
        Button {
            voiceID = id
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if voiceID == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var automaticSubtitle: String {
        let language = Language(code: .bcp47(Locale.current.identifier))
        if let best = ReaderSpeechPreferences.bestVoice(for: language, from: voices) {
            return "Currently \(ReaderSpeechPreferences.displayName(for: best))"
        }
        return "Uses the best installed voice for the book’s language"
    }

    private func voiceSubtitle(_ voice: TTSVoice) -> String {
        let quality = ReaderSpeechPreferences.qualityLabel(for: voice.quality)
        let lang = voice.language.code.bcp47
        return "\(quality) · \(lang)"
    }

    private var hasEnhancedOrBetter: Bool {
        voices.contains { voice in
            switch voice.quality {
            case .high, .higher: true
            default: false
            }
        }
    }

    private var rateLabel: String {
        if abs(rate - 1.0) < 0.001 { return "Default" }
        return String(format: "%.0f%%", rate * 100)
    }

    private var pitchLabel: String {
        if abs(pitch - 1.0) < 0.001 { return "Default" }
        return String(format: "%.2f×", pitch)
    }
}

/// Opens Settings so the reader can find Read & Speak (formerly "Spoken
/// Content") and download Enhanced / Premium voices.
///
/// **Tried and confirmed wrong on-device (iOS 26.5):** the undocumented
/// `App-prefs:root=ACCESSIBILITY&path=SPEECH` / `prefs:` deep links do not
/// error out — `UIApplication.open(_:)` reports `success == true` — but they
/// land on Settings' **Apps** section, not Accessibility. A "successful" deep
/// link to the wrong screen is worse than no deep link at all: the user has
/// no signal anything went sideways. Do not resurrect them without re-testing
/// on a real device; a scheme that silently mis-routes is not a working
/// fallback candidate.
///
/// The only navigation a third-party app is actually allowed to make into
/// Settings is `UIApplication.openSettingsURLString`, which opens *this app's
/// own* Settings page — not Accessibility, not Read & Speak. That's still
/// useful: it puts the user inside Settings.app one back-tap from its root,
/// instead of making them find and open Settings themselves. The honest
/// manual path from there — **Settings → Accessibility → Read & Speak →
/// Voices → (Language) → Voice** — lives in `ReaderSpeechSettingsSection`'s
/// footer text, not in this deep link, because this deep link cannot reach it.
@MainActor
enum SystemSpokenContentSettings {
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif
