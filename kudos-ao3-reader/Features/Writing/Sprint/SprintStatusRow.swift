import SwiftUI

/// The sprint's time left and words, shown above the editor's status line while it runs.
/// `Text(timerInterval:)` counts down on its own, so nothing re-renders each second.
struct SprintStatusRow: View {
    let info: SprintStatusInfo

    var body: some View {
        // Two shapes, not one: a long time-and-words line doesn't fit beside AX5 text.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                timeLeft
                Text("·").foregroundStyle(.secondaryInk)
                words
            }
            VStack(alignment: .leading, spacing: 2) {
                timeLeft
                words
            }
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var timeLeft: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .foregroundStyle(.accentInk)
                .accessibilityHidden(true)
            Text("Sprint \(Text(timerInterval: info.startedAt...info.endsAt, pauseTime: nil, countsDown: true, showsHours: false)) left")
        }
    }

    private var words: some View {
        Text("\(info.words.formatted()) \(info.words == 1 ? "word" : "words")")
            .foregroundStyle(.secondaryInk)
    }
}
