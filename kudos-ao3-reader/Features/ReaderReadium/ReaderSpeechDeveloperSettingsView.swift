#if os(iOS)
import SwiftUI

/// The knobs that measurement could not settle, exposed so they can be settled
/// by ear.
///
/// Everything here changes **real playback**, not the audition sample — a
/// control that only moved the preview would answer a question nobody asked.
/// Values apply to the next utterance, so a change made mid-chapter is audible
/// within a sentence or two without restarting.
///
/// Every default is the shipped constant, and the header says plainly when
/// anything has been moved — a listening report is worthless if it is unclear
/// which build it describes.
struct ReaderSpeechDeveloperSettingsView: View {
    @AppStorage(ReaderSpeechTuning.continuationPauseKey)
    private var continuationPause = ReaderSpeechTuning.defaultContinuationPause
    @AppStorage(ReaderSpeechTuning.linePauseKey)
    private var linePause = ReaderSpeechTuning.defaultLinePause
    @AppStorage(ReaderSpeechTuning.paragraphPauseKey)
    private var paragraphPause = ReaderSpeechTuning.defaultParagraphPause
    @AppStorage(ReaderSpeechTuning.scenePauseKey)
    private var scenePause = ReaderSpeechTuning.defaultScenePause
    @AppStorage(ReaderSpeechTuning.chapterPauseKey)
    private var chapterPause = ReaderSpeechTuning.defaultChapterPause

    @AppStorage(ReaderSpeechTuning.packTargetKey)
    private var packTarget = ReaderSpeechTuning.defaultPackTarget
    @AppStorage(ReaderSpeechTuning.packMinKey)
    private var packMin = ReaderSpeechTuning.defaultPackMin
    @AppStorage(ReaderSpeechTuning.packMaxKey)
    private var packMax = ReaderSpeechTuning.defaultPackMax
    @AppStorage(ReaderSpeechTuning.splitThresholdKey)
    private var splitThreshold = ReaderSpeechTuning.defaultSplitThreshold

    @AppStorage(ReaderSpeechTuning.dialogueBarrierKey) private var dialogueBarrier = true
    @AppStorage(ReaderSpeechTuning.lineBreakPausesKey) private var lineBreakPauses = true

    var body: some View {
        List {
            Section {
                pause("Between chunks", $continuationPause,
                      note: "Mid-sentence split. Shipped 0.14s.")
                pause("Line break", $linePause,
                      note: "A <br> inside one paragraph. Shipped 0.22s — chosen "
                          + "only because it sits between the two around it.")
                pause("Paragraph", $paragraphPause, note: "Shipped 0.32s.")
                pause("Scene break", $scenePause, note: "Shipped 0.85s.")
                pause("Chapter", $chapterPause, note: "Shipped 1.25s.")
            } header: {
                Text("Pauses")
            } footer: {
                Text("Applies to the next utterance, so changes are audible "
                    + "without restarting playback.")
            }

            Section {
                phonemes("Target", $packTarget, range: ReaderSpeechTuning.packRange)
                phonemes("Minimum", $packMin, range: ReaderSpeechTuning.packRange)
                phonemes("Maximum", $packMax, range: ReaderSpeechTuning.packRange)
                phonemes("Split above", $splitThreshold, range: ReaderSpeechTuning.splitRange)
            } header: {
                Text("Chunk size")
            } footer: {
                // The reason this is a knob at all.
                Text("The voice pack is indexed by phoneme count, so chunk "
                    + "length selects the voice's prosodic character. Upstream "
                    + "calls 100–200 the sweet spot; Kokoro-FastAPI ships "
                    + "175–250. Estimates run about 15% high, so a target of "
                    + "175 lands near 152 real phonemes.")
            }

            Section {
                Toggle("Break at dialogue", isOn: $dialogueBarrier)
                Toggle("Pause at line breaks", isOn: $lineBreakPauses)
            } header: {
                Text("Boundaries")
            } footer: {
                Text("Off restores the older behaviour of merging these into "
                    + "the surrounding prose, for comparison.")
            }

            Section {
                Button("Reset to shipped defaults", role: .destructive) {
                    ReaderSpeechTuning.resetAll()
                }
            } footer: {
                Text(ReaderSpeechTuning.isModified
                    ? "Some values differ from the shipped defaults."
                    : "Everything matches the shipped defaults.")
            }
        }
        .appThemedScroll()
        .appThemedRows()
        .navigationTitle("Developer Settings")
        .navigationBarTitleDisplayMode(.inline)
        // Any write invalidates the cached snapshot the playback path reads.
        .onChange(of: continuationPause) { ReaderSpeechTuning.invalidate() }
        .onChange(of: linePause) { ReaderSpeechTuning.invalidate() }
        .onChange(of: paragraphPause) { ReaderSpeechTuning.invalidate() }
        .onChange(of: scenePause) { ReaderSpeechTuning.invalidate() }
        .onChange(of: chapterPause) { ReaderSpeechTuning.invalidate() }
        .onChange(of: packTarget) { ReaderSpeechTuning.invalidate() }
        .onChange(of: packMin) { ReaderSpeechTuning.invalidate() }
        .onChange(of: packMax) { ReaderSpeechTuning.invalidate() }
        .onChange(of: splitThreshold) { ReaderSpeechTuning.invalidate() }
        .onChange(of: dialogueBarrier) { ReaderSpeechTuning.invalidate() }
        .onChange(of: lineBreakPauses) { ReaderSpeechTuning.invalidate() }
    }

    private func pause(
        _ title: String, _ value: Binding<Double>, note: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2fs", value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: ReaderSpeechTuning.pauseRange, step: 0.01)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: "%.2f seconds", value.wrappedValue))
            Text(note).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func phonemes(
        _ title: String, _ value: Binding<Int>, range: ClosedRange<Double>
    ) -> some View {
        let proxy = Binding(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = Int($0.rounded()) }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: proxy, in: range, step: 5)
                .accessibilityLabel(title)
                .accessibilityValue("\(value.wrappedValue) phonemes")
        }
    }
}
#endif
