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
    @State private var downloadManager = TTSDownloadManager()
    @State private var kokoroService: SherpaKokoroTTSService?

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
            NavigationLink {
                voicePicker
            } label: {
                LabeledContent("Voice", value: selectedVoiceLabel)
            }
            .disabled(!downloadManager.isModelDownloaded())

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
            Text("Automatic uses the bundled Kokoro voice pack for high-quality offline speech. The voice pack is a one-time ~200MB download.")
        }
        .onAppear(perform: updateVoices)
        .onChange(of: downloadManager.status) { _, _ in updateVoices() }
    }

    @ViewBuilder
    private var downloadSection: some View {
        Section {
            switch downloadManager.status {
            case .idle:
                Button("Download Voice Pack") {
                    Task { try? await downloadManager.downloadModel() }
                }
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                    Text("Downloading... \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .extracting:
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Extracting...")
                }
            case .completed:
                HStack {
                    Text("Voice Pack Downloaded")
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                }
            case .failed(let error):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download failed: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                    Button("Retry Download") {
                        Task { try? await downloadManager.downloadModel() }
                    }
                }
            }
        } header: {
            Text("Voice Pack")
        }
    }
    
    private func updateVoices() {
        if downloadManager.isModelDownloaded() {
            if kokoroService == nil {
                kokoroService = SherpaKokoroTTSService(modelDirectory: downloadManager.modelDirectory)
            }
            voices = kokoroService?.availableVoices ?? []
        } else {
            voices = []
        }
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
