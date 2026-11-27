import ActivityKit
import SwiftUI
import WidgetKit

/// The sprint on the Lock Screen and in the Dynamic Island (`Phone-Sprint.dc.html`): the time left counting down on its
/// own, and the words written as the app last reported them.
struct SprintLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SprintActivityAttributes.self) { context in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isFinished ? "Sprint done" : "Sprint")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    SprintTimeText(context: context)
                        .font(.title.weight(.bold).monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("+\(context.state.words)")
                        .font(.title.weight(.bold).monospacedDigit())
                    Text(context.state.words == 1 ? "word" : "words")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .accessibilityElement(children: .combine)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        SprintTimeText(context: context).monospacedDigit()
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("+\(context.state.words)")
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.isFinished ? "Sprint done" : "Writing sprint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                Text("+\(context.state.words)")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.isFinished ? "checkmark" : "timer")
            }
        }
    }
}

/// The countdown, or the sprint's length once it's over. The range starts at the sprint's start, so it is never empty.
private struct SprintTimeText: View {
    let context: ActivityViewContext<SprintActivityAttributes>

    var body: some View {
        if context.state.isFinished {
            Text("\(context.attributes.plannedMinutes) min")
        } else {
            Text(timerInterval: context.attributes.startedAt...max(context.attributes.startedAt, context.state.endsAt),
                 countsDown: true)
        }
    }
}
