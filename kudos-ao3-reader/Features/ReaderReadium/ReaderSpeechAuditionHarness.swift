#if os(iOS)
import ReadiumShared
import ReadiumNavigator
import SwiftUI

enum AuditionSample: String, CaseIterable, Identifiable {
    case dialogue = "Dialogue-heavy"
    case numbersNames = "Numbers & Names"
    case narration = "Plain Narration"

    var id: String {
        rawValue
    }

    var text: String {
        switch self {
        case .dialogue:
            return "\"Are you certain this is safe?\" she asked, stepping back. "
                 + "\"Absolutely not,\" he replied without looking up from the monitor. "
                 + "\"But it's our only option.\""
        case .numbersNames:
            return "Dr. Elara Vance noted that exactly 1,452 samples were processed "
                 + "by the HX-7 system before 08:30 on November 4th, 2026."
        case .narration:
            return "The afternoon sun cast long shadows across the empty hallway. "
                 + "Dust motes danced in the fading light, settling slowly onto the "
                 + "forgotten furniture as silence reclaimed the room."
        }
    }
}

struct ReaderSpeechAuditionHarness: View {
    @State private var controller = ReaderSpeechController()
    @State private var selectedSample: AuditionSample = .narration

    @AppStorage(ReaderSpeechPreferences.engineKey) private var engineID = ""
    @AppStorage(ReaderSpeechPreferences.voiceIDKey) private var voiceID = ""
    @AppStorage(ReaderSpeechPreferences.rateKey) private var rate = ReaderSpeechPreferences.defaultRate

    var body: some View {
        Section {
            Picker("Sample Text", selection: $selectedSample) {
                ForEach(AuditionSample.allCases) { sample in
                    Text(sample.rawValue).tag(sample)
                }
            }

            // Bound to the real `rateKey`, not a preview-only copy: what you
            // audition has to be what you get. The main Read Aloud slider is
            // further down the page, and scrolling away to change speed and
            // back to replay is exactly the friction this harness exists to
            // remove.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(rateLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $rate, in: ReaderSpeechPreferences.rateRange, step: 0.05)
                    .accessibilityLabel("Audition speed")
                    .accessibilityValue(rateLabel)

                // The open question is specifically 0.9 (widely recommended for
                // audiobook narration) against our 1.0 default, so make that
                // one comparison a single tap rather than a slider hunt.
                HStack(spacing: 8) {
                    ForEach(Self.comparisonRates, id: \.self) { candidate in
                        Button {
                            rate = candidate
                        } label: {
                            Text(Self.label(for: candidate))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(abs(rate - candidate) < 0.001)
                    }
                }
            }
            .padding(.vertical, 4)

            if controller.isPlaying {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playing Sample")
                        .font(.headline)
                    Text("Engine: \(controller.activeEngineName)")
                        .font(.caption)
                    Text("Voice: \(activeVoiceName)")
                        .font(.caption)

                    Button("Stop", role: .destructive) {
                        controller.stop()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            } else {
                Button("Play Sample") {
                    controller.audition(text: selectedSample.text)
                }
            }
        } header: {
            Text("Audition Voice")
        } footer: {
            Text("Test current speech settings without opening a book.")
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: engineID) { _, _ in restartIfPlaying() }
        .onChange(of: voiceID) { _, _ in restartIfPlaying() }
        .onChange(of: rate) { _, _ in restartIfPlaying() }
        .onChange(of: selectedSample) { _, _ in restartIfPlaying() }
    }

    /// 0.9 is the widely recommended audiobook-narration rate; 1.0 is what
    /// Kudos currently defaults to. 1.1 gives the comparison a third point so
    /// the middle is not just an endpoint.
    private static let comparisonRates: [Double] = [0.9, 1.0, 1.1]

    private static func label(for value: Double) -> String {
        abs(value - 1.0) < 0.001 ? "1.0x (default)" : String(format: "%.2gx", value)
    }

    private var rateLabel: String {
        abs(rate - 1.0) < 0.001 ? "Default (1.0x)" : String(format: "%.0f%%", rate * 100)
    }

    private func restartIfPlaying() {
        if controller.isPlaying {
            controller.audition(text: selectedSample.text)
        }
    }

    private var activeVoiceName: String {
        let voices = controller.availableVoices
        let language = Language(code: .bcp47(Locale.current.identifier))
        let selected = voiceID.isEmpty
            ? ReaderSpeechPreferences.bestVoice(for: language, from: voices)
            : voices.first { $0.identifier == voiceID }
        return selected.map { ReaderSpeechPreferences.displayName(for: $0) } ?? "Automatic"
    }
}
#endif
