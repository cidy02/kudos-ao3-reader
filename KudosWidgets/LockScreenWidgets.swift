import AppIntents
import SwiftUI
import WidgetKit

struct WritingEntry: TimelineEntry {
    let date: Date
    let snapshot: KudosWidgetSnapshot
}

/// Reads the snapshot the app writes; a new entry at midnight, when "today" starts again.
struct WritingProvider: TimelineProvider {
    func placeholder(in context: Context) -> WritingEntry {
        WritingEntry(date: Date(), snapshot: KudosWidgetSnapshot(workTitle: "What the Tide Keeps", chapterTitle: "Chapter 4"))
    }

    func getSnapshot(in context: Context, completion: @escaping (WritingEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WritingEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(24 * 60 * 60)
        completion(Timeline(entries: [entry(at: now)], policy: .after(midnight)))
    }

    private func entry(at date: Date) -> WritingEntry {
        WritingEntry(date: date, snapshot: KudosWidgetSnapshotStore.read(from: KudosAppGroup.snapshotURL))
    }
}

/// The Lock Screen's +: New Idea in one tap.
struct NewIdeaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KudosNewIdea", provider: WritingProvider()) { _ in
            Button(intent: NewIdeaIntent()) {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New Idea")
            .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("New Idea")
        .description("Write down an idea without hunting for the app.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// What you're writing: the work and chapter last open in Kudos, and today's sprint words.
struct WritingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KudosWriting", provider: WritingProvider()) { entry in
            WritingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Writing")
        .description("The chapter you were last writing, and today's sprint words.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct WritingWidgetView: View {
    let entry: WritingEntry
    @Environment(\.widgetFamily) private var family

    private var words: Int { entry.snapshot.sprintWordsToday(now: entry.date) }

    var body: some View {
        switch family {
        case .accessoryInline:
            if words > 0 {
                Text("\(words) words in sprints today")
            } else {
                Text(entry.snapshot.workTitle ?? "Kudos")
            }
        default:
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.snapshot.workTitle ?? "Kudos")
                        .font(.headline)
                        .widgetAccentable()
                        .lineLimit(1)
                    Text(entry.snapshot.chapterTitle ?? "Nothing open yet")
                        .lineLimit(1)
                    if words > 0 {
                        Text("\(words) words in sprints today")
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(intent: NewIdeaIntent()) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Idea")
            }
        }
    }
}

/// New Idea in Control Center, and on the Action button (Settings → Action Button → Controls).
struct NewIdeaControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "KudosNewIdeaControl") {
            ControlWidgetButton(action: NewIdeaIntent()) {
                Label("New Idea", systemImage: "lightbulb")
            }
        }
        .displayName("New Idea")
        .description("Write down an idea in Kudos.")
    }
}
