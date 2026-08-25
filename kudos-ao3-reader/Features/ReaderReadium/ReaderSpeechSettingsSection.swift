#if os(iOS)
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

/// Read-aloud controls for the shared `ReaderOptionsForm` (reader Display sheet
/// and Settings). Preferences persist via `@AppStorage` / UserDefaults and are
/// picked up by `ReaderSpeechController` on the next utterance.
struct ReaderSpeechSettingsSection: View {
    /// Passed through to the pronunciation list so it can rank the work's own
    /// cast first. Empty from global Settings.
    var characterTags: [String] = []

    /// Pre-flight scan of the open chapter. `nil` from global Settings.
    var onScanChapter: (() async -> KokoroCastPreflight.ScanResult?)?

    @AppStorage(ReaderSpeechPreferences.engineKey) private var engineID = ""
    @AppStorage(ReaderSpeechPreferences.voiceIDKey) private var voiceID = ""
    @AppStorage(ReaderSpeechPreferences.readAuthorNotesKey) private var readAuthorNotes = true
    @AppStorage(ReaderSpeechPreferences.rateKey)
    private var rate = ReaderSpeechPreferences.defaultRate
    @AppStorage(ReaderSpeechPreferences.pitchKey)
    private var pitch = ReaderSpeechPreferences.defaultPitch
    @AppStorage(ReaderSpeechPreferences.kokoroModelPackKey)
    private var kokoroModelPackID = KokoroModelPack.defaultPack.rawValue
    @AppStorage(ReaderSpeechPreferences.kokoroExecutionProviderKey)
    private var kokoroExecutionProviderID = KokoroExecutionProvider.defaultProvider.rawValue

    @State private var voices: [TTSVoice] = []
    @State private var downloadManager = TTSDownloadManager.shared
    @State private var kokoroInstaller = CoreMLKokoroPackInstaller.shared
    @State private var kokoroService: SherpaKokoroTTSService?
    @State private var coreMLKokoroService: CoreMLKokoroTTSService?
    @State private var isShowingCoreMLDownloadConfirmation = false
    @State private var cachedKokoroRuntimeConfiguration: KokoroRuntimeConfiguration?
    @State private var isShowingKokoroDownloadConfirmation = false

    private var sortedVoices: [TTSVoice] {
        voices.sorted()
    }

    /// Count of global overrides, so the row shows whether anything is set
    /// without opening it. Read on each render rather than cached: the list
    /// behind it writes to disk, and a stale count is worse than a cheap read
    /// of a file that is empty for most readers.
    private var pronunciationCountLabel: String {
        let count = KokoroPronunciationStore().overrides().count
        return count == 0 ? "None" : "\(count)"
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
        ReaderSpeechAuditionHarness()

        downloadSection

        Section {
            Picker("Engine", selection: $engineID) {
                Text("Automatic").tag("")
                ForEach(ReaderTTSEngineKind.allCases, id: \.rawValue) { engine in
                    Text(engine.displayName).tag(engine.rawValue)
                }
            }

            // Model-pack and execution-provider choices are sherpa-onnx
            // concepts. On the Core ML line the stage placement is decided by
            // measurement inside FluidAudio, so there is nothing to pick.
            if !KokoroAnePlayback.supportsCoreML() {
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

                if selectedKokoroModelPack.requiresInt8SupportFiles &&
                    !isSelectedKokoroModelPackDownloaded {
                    Label(
                        "FP32 downloads only the official model.onnx from Hugging Face "
                            + "and reuses the Int8 Voice Pack voices, tokens, and eSpeak data. "
                            + "Kudos uses Int8 or Apple until that finishes.",
                        systemImage: "externaldrive"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Toggle("Read author's notes", isOn: $readAuthorNotes)
                .accessibilityHint(
                    "Author's notes often carry content warnings. "
                        + "Turn this off to hear only the story."
                )

            if isKokoroAwaitingVoicePack {
                Label(
                    KokoroAnePlayback.supportsCoreML()
                        ? "Kokoro Neural Engine pack is not ready. Apple is used until it is."
                        : "Kokoro requires the Voice Pack. Apple is used until it finishes.",
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

            NavigationLink {
                ReaderPronunciationSettingsView(
                    characterTags: characterTags,
                    onScanChapter: onScanChapter
                )
            } label: {
                LabeledContent("Pronunciations", value: pronunciationCountLabel)
            }

            NavigationLink {
                ReaderSpeechDeveloperSettingsView()
            } label: {
                LabeledContent(
                    "Developer Settings",
                    value: ReaderSpeechTuning.isModified ? "Modified" : "Default"
                )
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
            Text(readAloudFooter)
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
        .onChange(of: kokoroInstaller.status) { _, _ in updateVoices() }
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

    /// iOS 27+ runs Kokoro on Core ML; iOS 26.x runs it on Sherpa/ONNX because
    /// of the libBNNS `SIGSEGV` (see `KokoroAnePlayback`). Only the pack the
    /// device can actually use is offered — showing both would invite the user
    /// to download ~180 MB that will never be loaded.
    @ViewBuilder
    private var downloadSection: some View {
        if KokoroAnePlayback.supportsCoreML() {
            coreMLDownloadSection
        } else {
            sherpaDownloadSection
        }
    }

    @ViewBuilder
    private var coreMLDownloadSection: some View {
        Section {
            coreMLPackStatusViews
        } header: {
            Text("Kokoro Neural Engine")
        } footer: {
            Text(
                "Kokoro runs as staged Core ML graphs, with each stage on the "
                    + "Neural Engine, GPU, or CPU — whichever is fastest for it. "
                    + "The pack is dense FP16 (Noise and Tail stay FP32). The first "
                    + "install downloads the zip from this project's GitHub Releases. "
                    + "Kudos sends no book text, audio, or library data; GitHub "
                    + "can receive your IP address and ordinary connection metadata."
            )
        }
        .confirmationDialog(
            "Download Kokoro for the Neural Engine?",
            isPresented: $isShowingCoreMLDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Download") { kokoroInstaller.install() }
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
    private var coreMLPackStatusViews: some View {
        switch kokoroInstaller.status {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                HStack {
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Cancel", role: .cancel) { kokoroInstaller.cancel() }
                }
            }
        case .installing:
            busyRow("Installing Core ML Kokoro…")
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
                Button("Retry Download") { isShowingCoreMLDownloadConfirmation = true }
            }
        case .idle:
            Button("Download Kokoro (Neural Engine)") {
                isShowingCoreMLDownloadConfirmation = true
            }
        }
    }

    @ViewBuilder
    private var sherpaDownloadSection: some View {
        Section {
            if selectedKokoroModelPack.requiresInt8SupportFiles,
               !downloadManager.isModelDownloaded(for: .int8V019),
               !isBusyWithSelectedPack {
                Label(
                    "Download the Int8 Voice Pack first. FP32 reuses its voices, "
                        + "tokens, and eSpeak data and never unpacks the 320 MB tar.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            packStatusViews
        } header: {
            Text("Kokoro Pack")
        } footer: {
            Text(downloadDisclosure)
        }
        .confirmationDialog(
            "Download \(selectedKokoroModelPack.displayName) Voice Pack?",
            isPresented: $isShowingKokoroDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Download \(selectedPackSizeLabel)") {
                startSelectedPackDownload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Kudos will request this public Voice Pack from \(selectedPackHostName). No "
                    + "reading or library data is sent, but the host/CDN can receive your IP "
                    + "address and standard "
                    + "connection metadata."
            )
        }
    }

    @ViewBuilder
    private var packStatusViews: some View {
        switch downloadManager.status {
        case .downloading(let progress) where isBusyWithSelectedPack:
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                Text(selectedKokoroModelPack.requiresInt8SupportFiles
                     ? "Downloading official FP32 model from Hugging Face… \(Int(progress * 100))%"
                     : "Downloading... \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Cancel", role: .cancel) {
                    downloadManager.cancel()
                }
            }
        case .extracting where isBusyWithSelectedPack:
            busyRow("Extracting...")
        case .installing where isBusyWithSelectedPack:
            busyRow("Installing official FP32 model…")
        case .verifying where isBusyWithSelectedPack:
            busyRow(
                selectedKokoroModelPack.requiresInt8SupportFiles
                    ? "Verifying official FP32 runtime…"
                    : "Verifying side-loaded pack..."
            )
        case .cancelling where isBusyWithSelectedPack:
            HStack {
                ProgressView()
                    .padding(.trailing, 8)
                Text("Cancelling…")
                Spacer()
            }
        case .completed where isSelectedKokoroModelPackDownloaded:
            HStack {
                Text(selectedKokoroModelPack.requiresInt8SupportFiles
                     ? "FP32 Pack Installed"
                     : "Voice Pack Downloaded")
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundColor(.green)
            }
        case .failed(let error) where downloadManager.statusPack == selectedKokoroModelPack:
            VStack(alignment: .leading, spacing: 8) {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                downloadOrRetryButton(title: "Retry Download")
            }
        case .idle, .completed, .failed, .downloading, .extracting, .installing, .verifying,
             .cancelling:
            downloadOrRetryButton(
                title: selectedKokoroModelPack.requiresInt8SupportFiles
                    ? "Download Official FP32 Model"
                    : "Download Voice Pack"
            )
        }
    }

    private func busyRow(_ title: String) -> some View {
        HStack {
            ProgressView()
                .padding(.trailing, 8)
            Text(title)
            Spacer()
            Button("Cancel", role: .cancel) {
                downloadManager.cancel()
            }
        }
    }

    private func downloadOrRetryButton(title: String) -> some View {
        Button(title) {
            isShowingKokoroDownloadConfirmation = true
        }
        .disabled(
            selectedKokoroModelPack.requiresInt8SupportFiles
                && !downloadManager.isModelDownloaded(for: .int8V019)
        )
    }

    private func startSelectedPackDownload() {
        let pack = selectedKokoroModelPack
        Task {
            try? await downloadManager.downloadModel(for: pack)
        }
    }

    private func updateVoices() {
        switch effectiveEngineKind {
        case .kokoro:
            if KokoroAnePlayback.supportsCoreML() {
                guard KokoroAneAvailability.isUsableForPlayback else {
                    voices = []
                    return
                }
                if coreMLKokoroService == nil {
                    coreMLKokoroService = CoreMLKokoroTTSService()
                }
                voices = coreMLKokoroService?.availableVoices ?? []
                return
            }
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
            coreMLKokoroService = nil
            cachedKokoroRuntimeConfiguration = nil
            voices = ReaderSpeechPreferences.catalogVoices()
        }
    }

    /// Whether *any* Kokoro engine can run: Core ML on iOS 27+, sherpa-onnx
    /// on 26.x. `ReaderSpeechController` applies the same rule.
    private var isAnyKokoroAvailable: Bool {
        KokoroAnePlayback.supportsCoreML()
            ? KokoroAneAvailability.isUsableForPlayback
            : effectiveKokoroRuntimeConfiguration != nil
    }

    private var readAloudFooter: String {
        if KokoroAnePlayback.supportsCoreML() {
            return "Automatic uses Apple immediately, then Kokoro on the Neural Engine "
                + "once the optional Core ML pack is installed. Kudos does not send "
                + "reading data, library data, or telemetry."
        }
        return "Automatic uses Apple immediately, then Kokoro after its optional offline "
            + "Int8 Voice Pack is downloaded. Full precision (FP32) is an explicit "
            + "Hugging Face download of csukuangfj/kokoro-en-v0_19 model.onnx; "
            + "Kudos does not send reading data, library data, or telemetry."
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
            modelDownloaded: isAnyKokoroAvailable
        )
    }

    private var isKokoroAwaitingVoicePack: Bool {
        engineID == ReaderTTSEngineKind.kokoro.rawValue && !isAnyKokoroAvailable
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

    private var isBusyWithSelectedPack: Bool {
        downloadManager.statusPack == selectedKokoroModelPack
    }

    private var selectedPackSizeLabel: String {
        switch selectedKokoroModelPack {
        case .int8V019:
            return "103 MB"
        case .fp32V019:
            let megabytes = KokoroModelPack.fp32V019.expectedModelByteCount / 1_000_000
            return "\(megabytes) MB"
        }
    }

    private var selectedPackHostName: String {
        selectedKokoroModelPack.requiresInt8SupportFiles ? "Hugging Face" : "GitHub"
    }

    private var downloadDisclosure: String {
        let prefix: String
        if selectedKokoroModelPack.requiresInt8SupportFiles {
            prefix = "FP32 downloads the \(selectedPackSizeLabel) public model from Hugging Face "
                + "at a pinned revision. Allow up to 900 MB free during install."
        } else {
            prefix = "The Int8 Voice Pack downloads its public archive from GitHub."
        }
        return prefix + " Kudos sends no book text, audio, AO3 credentials, library, reading "
            + "history, analytics, or account identifier. The host or its CDN can receive your "
            + "IP address and standard connection/request metadata under its privacy policy."
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
