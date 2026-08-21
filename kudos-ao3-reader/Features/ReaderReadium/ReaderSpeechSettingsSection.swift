#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

/// Read-aloud controls for the shared `ReaderOptionsForm` (reader Display sheet
/// and Settings). Preferences persist via `@AppStorage` / UserDefaults and are
/// picked up by `ReaderSpeechController` on the next utterance.
struct ReaderSpeechSettingsSection: View {
    @AppStorage(ReaderSpeechPreferences.engineKey) private var engineID = ""
    @AppStorage(ReaderSpeechPreferences.voiceIDKey) private var voiceID = ""
    @AppStorage(ReaderSpeechPreferences.rateKey)
    private var rate = ReaderSpeechPreferences.defaultRate
    @AppStorage(ReaderSpeechPreferences.pitchKey)
    private var pitch = ReaderSpeechPreferences.defaultPitch

    @State private var voices: [TTSVoice] = []
    @State private var kokoroInstaller = CoreMLKokoroPackInstaller.shared
    @State private var kokoroService: TTSService?
    @State private var isShowingKokoroDownloadConfirmation = false

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
        downloadSection

        Section {
            Picker("Engine", selection: $engineID) {
                Text("Automatic").tag("")
                ForEach(ReaderTTSEngineKind.allCases, id: \.rawValue) { engine in
                    Text(engine.displayName).tag(engine.rawValue)
                }
            }

            if isKokoroAwaitingVoicePack {
                Label(
                    "Kokoro Neural Engine pack is not ready. Apple is used until it is.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            NavigationLink {
                voicePicker
            } label: {
                LabeledContent("Voice", value: selectedVoiceLabel)
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
                engineID = ""
                voiceID = ""
                rate = ReaderSpeechPreferences.defaultRate
                pitch = ReaderSpeechPreferences.defaultPitch
            }
        } header: {
            Text("Read Aloud")
        } footer: {
            Text(
                "Automatic uses Apple immediately, then Kokoro on the Neural Engine "
                    + "after the optional Core ML pack is installed. Kudos does not send "
                    + "reading data, library data, or telemetry."
            )
        }
        .onAppear {
            normalizeEngineID()
            updateVoices()
        }
        .onChange(of: kokoroInstaller.status) { _, _ in updateVoices() }
        .onChange(of: engineID) { _, _ in updateVoices() }
    }

    @ViewBuilder
    private var downloadSection: some View {
        Section {
            packStatusViews
        } header: {
            Text("Kokoro Neural Engine")
        } footer: {
            Text(
                "Kokoro runs as staged Core ML graphs on the Apple Neural Engine "
                    + "(FluidAudio), not Sherpa/ONNX. The pack is dense FP16 "
                    + "(no 8-bit palettes; Noise and Tail stay FP32). The first "
                    + "install downloads the zip from this project's GitHub Releases. "
                    + "Kudos sends no book text, audio, or library data; GitHub "
                    + "can receive your IP address and ordinary connection metadata."
            )
        }
        .confirmationDialog(
            "Download Kokoro for the Neural Engine?",
            isPresented: $isShowingKokoroDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Download") {
                kokoroInstaller.install()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Kudos will download the Core ML Kokoro zip from GitHub Releases "
                    + "(cidy02/kudos-ao3-reader). No reading or library data is sent, "
                    + "but GitHub can receive your IP address and standard connection "
                    + "metadata."
            )
        }
    }

    @ViewBuilder
    private var packStatusViews: some View {
        switch kokoroInstaller.status {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                HStack {
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(.caption)
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        kokoroInstaller.cancel()
                    }
                }
            }
        case .installing:
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text("Installing Core ML Kokoro…")
                Spacer()
            }
        case .completed:
            HStack {
                Text("Neural Engine pack ready")
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundColor(.green)
            }
        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                Button("Retry Download") {
                    isShowingKokoroDownloadConfirmation = true
                }
            }
        case .idle:
            Button("Download Kokoro (Neural Engine)") {
                isShowingKokoroDownloadConfirmation = true
            }
        }
    }

    private func updateVoices() {
        switch effectiveEngineKind {
        case .kokoro:
            if kokoroService == nil {
                kokoroService = CoreMLKokoroTTSService()
            }
            voices = kokoroService?.availableVoices ?? []
        case .system:
            kokoroService = nil
            voices = ReaderSpeechPreferences.catalogVoices()
        }
    }

    private func normalizeEngineID() {
        guard !engineID.isEmpty,
              ReaderTTSEngineKind(rawValue: engineID) == nil
        else { return }
        engineID = ""
    }

    private var effectiveEngineKind: ReaderTTSEngineKind {
        ReaderTTSEngineKind.effective(
            requestedRawValue: engineID,
            modelDownloaded: KokoroAneAvailability.isUsableForPlayback
        )
    }

    private var isKokoroAwaitingVoicePack: Bool {
        engineID == ReaderTTSEngineKind.kokoro.rawValue
            && !KokoroAneAvailability.isPackInstalled
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
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: updateVoices)
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

    private var rateLabel: String {
        if abs(rate - 1.0) < 0.001 { return "Default" }
        return String(format: "%.0f%%", rate * 100)
    }

    private var pitchLabel: String {
        if abs(pitch - 1.0) < 0.001 { return "Default" }
        return String(format: "%.2f×", pitch)
    }
}

#endif
