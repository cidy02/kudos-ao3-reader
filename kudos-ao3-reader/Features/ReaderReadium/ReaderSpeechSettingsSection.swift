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
    @AppStorage(ReaderSpeechPreferences.kokoroModelPackKey)
    private var kokoroModelPackID = KokoroModelPack.defaultPack.rawValue
    @AppStorage(ReaderSpeechPreferences.kokoroExecutionProviderKey)
    private var kokoroExecutionProviderID = KokoroExecutionProvider.defaultProvider.rawValue

    @State private var voices: [TTSVoice] = []
    @State private var downloadManager = TTSDownloadManager()
    @State private var kokoroService: SherpaKokoroTTSService?
    @State private var cachedKokoroRuntimeConfiguration: KokoroRuntimeConfiguration?

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

            Picker("Kokoro model", selection: $kokoroModelPackID) {
                ForEach(KokoroModelPack.allCases, id: \.rawValue) { pack in
                    Text(pack.displayName).tag(pack.rawValue)
                }
            }

            Picker("Kokoro compute", selection: $kokoroExecutionProviderID) {
                ForEach(KokoroExecutionProvider.allCases, id: \.rawValue) { provider in
                    Text(provider.displayName).tag(provider.rawValue)
                }
            }

            if selectedKokoroExecutionProvider == .coreML {
                Label(
                    "Core ML is requested experimentally; it does not guarantee Neural Engine use.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if selectedKokoroModelPack.requiresDeveloperInstallation &&
                !isSelectedKokoroModelPackDownloaded {
                Label(
                    "FP32 is a developer-installed test pack. Kudos uses the available Int8 pack "
                        + "or Apple until it is verified; no compatible FP16 pack is available.",
                    systemImage: "wrench.and.screwdriver"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if isKokoroAwaitingVoicePack {
                Label(
                    "Kokoro requires the Voice Pack. Apple is used until it finishes.",
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
                kokoroModelPackID = KokoroModelPack.defaultPack.rawValue
                kokoroExecutionProviderID = KokoroExecutionProvider.defaultProvider.rawValue
            }
        } header: {
            Text("Read Aloud")
        } footer: {
            Text(
                "Automatic uses Apple immediately, then Kokoro after its optional offline "
                    + "Int8 Voice Pack is downloaded. FP32 is an on-device benchmark pack."
            )
        }
        .onAppear {
            normalizeEngineID()
            normalizeKokoroConfiguration()
            downloadManager.refreshStatus(for: selectedKokoroModelPack)
            updateVoices()
        }
        .onChange(of: downloadManager.status) { _, _ in
            if downloadManager.statusPack != selectedKokoroModelPack {
                downloadManager.refreshStatus(for: selectedKokoroModelPack)
            }
            updateVoices()
        }
        .onChange(of: engineID) { _, _ in updateVoices() }
        .onChange(of: kokoroModelPackID) { _, _ in
            normalizeKokoroConfiguration()
            downloadManager.refreshStatus(for: selectedKokoroModelPack)
            updateVoices()
        }
        .onChange(of: kokoroExecutionProviderID) { _, _ in
            normalizeKokoroConfiguration()
            updateVoices()
        }
    }

    @ViewBuilder
    private var downloadSection: some View {
        Section {
            if selectedKokoroModelPack.requiresDeveloperInstallation {
                switch downloadManager.status {
                case .verifying where downloadManager.statusPack == selectedKokoroModelPack:
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Verifying FP32 Test Pack...")
                    }
                case .completed where isSelectedKokoroModelPackDownloaded:
                    HStack {
                        Text("FP32 Test Pack Verified")
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    }
                case .failed(let error) where downloadManager.statusPack == selectedKokoroModelPack:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FP32 verification failed: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                        Button("Verify Side-Loaded FP32 Pack") {
                            Task {
                                await downloadManager.verifyDeveloperInstalledModelPack(
                                    selectedKokoroModelPack
                                )
                            }
                        }
                    }
                default:
                    Label(
                        "FP32 must be side-loaded then verified; the app will not unpack its 320 MB archive in memory.",
                        systemImage: "externaldrive"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Button("Verify Side-Loaded FP32 Pack") {
                        Task {
                            await downloadManager.verifyDeveloperInstalledModelPack(
                                selectedKokoroModelPack
                            )
                        }
                    }
                }
            } else {
                switch downloadManager.status {
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
                case .verifying:
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Verifying side-loaded pack...")
                    }
                case .completed where isSelectedKokoroModelPackDownloaded:
                    HStack {
                        Text("Voice Pack Downloaded")
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    }
                case .idle, .completed:
                    Button("Download Voice Pack") {
                        Task {
                            try? await downloadManager.downloadModel(for: selectedKokoroModelPack)
                        }
                    }
                case .failed(let error) where downloadManager.statusPack == selectedKokoroModelPack:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Download failed: \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                        Button("Retry Download") {
                            Task {
                                try? await downloadManager.downloadModel(for: selectedKokoroModelPack)
                            }
                        }
                    }
                case .failed:
                    Button("Download Voice Pack") {
                        Task {
                            try? await downloadManager.downloadModel(for: selectedKokoroModelPack)
                        }
                    }
                }
            }
        } header: {
            Text("Kokoro Pack")
        }
    }

    private func updateVoices() {
        switch effectiveEngineKind {
        case .kokoro:
            guard let runtimeConfiguration = effectiveKokoroRuntimeConfiguration else {
                voices = []
                return
            }
            if cachedKokoroRuntimeConfiguration != runtimeConfiguration {
                kokoroService = SherpaKokoroTTSService(
                    modelDirectory: downloadManager.modelDirectory(for: runtimeConfiguration.modelPack),
                    modelPack: runtimeConfiguration.modelPack,
                    executionProvider: runtimeConfiguration.executionProvider
                )
                cachedKokoroRuntimeConfiguration = runtimeConfiguration
            }
            voices = kokoroService?.availableVoices ?? []
        case .system:
            kokoroService = nil
            cachedKokoroRuntimeConfiguration = nil
            voices = ReaderSpeechPreferences.catalogVoices()
        }
    }

    private func normalizeEngineID() {
        guard !engineID.isEmpty,
              ReaderTTSEngineKind(rawValue: engineID) == nil
        else { return }
        engineID = ""
    }

    private func normalizeKokoroConfiguration() {
        let modelPack = KokoroModelPack.resolving(kokoroModelPackID)
        if kokoroModelPackID != modelPack.rawValue {
            kokoroModelPackID = modelPack.rawValue
        }
        let provider = KokoroExecutionProvider.resolving(kokoroExecutionProviderID)
        if kokoroExecutionProviderID != provider.rawValue {
            kokoroExecutionProviderID = provider.rawValue
        }
    }

    private var effectiveEngineKind: ReaderTTSEngineKind {
        ReaderTTSEngineKind.effective(
            requestedRawValue: engineID,
            modelDownloaded: effectiveKokoroRuntimeConfiguration != nil
        )
    }

    private var isKokoroAwaitingVoicePack: Bool {
        engineID == ReaderTTSEngineKind.kokoro.rawValue
            && effectiveKokoroRuntimeConfiguration == nil
    }

    private var selectedKokoroModelPack: KokoroModelPack {
        KokoroModelPack.resolving(kokoroModelPackID)
    }

    private var selectedKokoroExecutionProvider: KokoroExecutionProvider {
        KokoroExecutionProvider.resolving(kokoroExecutionProviderID)
    }

    private var isSelectedKokoroModelPackDownloaded: Bool {
        downloadManager.isModelDownloaded(for: selectedKokoroModelPack)
    }

    private var effectiveKokoroRuntimeConfiguration: KokoroRuntimeConfiguration? {
        KokoroRuntimeConfiguration.resolved(
            requested: KokoroRuntimeConfiguration(
                modelPack: selectedKokoroModelPack,
                executionProvider: selectedKokoroExecutionProvider
            ),
            isModelDownloaded: { pack in
                downloadManager.isModelDownloaded(for: pack)
            }
        )
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
