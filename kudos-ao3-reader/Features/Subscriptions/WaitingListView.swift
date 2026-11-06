import SwiftUI

/// The Subscriptions "Waiting" list: what changed, grouped by day, down a 40pt
/// gutter and a 14pt progress rail. Renders what it is handed; the caller owns
/// fetching.
///
/// A `.workOnly` update is a quieter row, not a lesser one: it says the work
/// updated and nothing more. Every chapter claim goes through
/// `canDeepLinkToChapter`, so a value the parser could not establish never
/// reaches the screen.
struct WaitingListView: View {
    let updates: [SubscriptionUpdate]
    /// Scanning has no event times, so the gutter counts places instead of
    /// showing a clock.
    var showsPosition = false

    private struct Day: Identifiable {
        let start: Date
        let updates: [SubscriptionUpdate]
        var id: Date { start }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        return Dictionary(grouping: updates.sorted { $0.at > $1.at }) { calendar.startOfDay(for: $0.at) }
            .map { Day(start: $0.key, updates: $0.value) }
            .sorted { $0.start > $1.start }
    }

    var body: some View {
        List {
            // Group so .appThemedRows() reaches every section's rows — it doesn't
            // propagate from the List container, only from a Group/Section/ForEach.
            Group {
                ForEach(days) { day in
                    Section {
                        ForEach(Array(day.updates.enumerated()), id: \.element.id) { index, update in
                            WaitingRow(
                                update: update,
                                position: index + 1,
                                showsPosition: showsPosition,
                                isFirst: index == 0,
                                isLast: index == day.updates.count - 1
                            )
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        WaitingDayHeader(start: day.start, count: day.updates.count)
                    }
                }
            }
            .appThemedRows()
        }
        .listStyle(.plain)
        .appThemedScroll()
        .overlay {
            if updates.isEmpty {
                ContentUnavailableView("Nothing waiting", systemImage: "tray")
            }
        }
        .navigationTitle("Waiting")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct WaitingDayHeader: View {
    let start: Date
    let count: Int

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(start) { return "Today" }
        if calendar.isDateInYesterday(start) { return "Yesterday" }
        return start.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .textCase(nil)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) waiting")
    }
}

private struct WaitingRow: View {
    let update: SubscriptionUpdate
    let position: Int
    let showsPosition: Bool
    let isFirst: Bool
    let isLast: Bool

    private var isConfirmed: Bool { update.certainty == .confirmed }

    /// The chapter number, only where a chapter can be offered at all.
    private var chapter: Int? {
        guard update.canDeepLinkToChapter, case let .newChapter(number) = update.change else { return nil }
        return number
    }

    private var title: String {
        update.workTitle.isEmpty ? "Work #\(update.workID)" : update.workTitle
    }

    private var whatChanged: String {
        guard isConfirmed else { return "This work updated. Open it to see what changed." }
        switch update.change {
        case .newChapter: return chapter.map { "Chapter \($0) posted" } ?? "A new chapter was posted"
        case .newWork: return "A new work was posted"
        case .unknown: return "This work updated."
        }
    }

    private var badge: String {
        guard isConfirmed else { return "Updated" }
        switch update.change {
        case .newChapter: return chapter.map { "+1 · Ch. \($0)" } ?? "Updated"
        case .newWork: return "New"
        case .unknown: return "Updated"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if showsPosition {
                    Text("\(position)")
                } else {
                    Text(update.at, format: .dateTime.hour().minute())
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 40, alignment: .trailing)
            .padding(.top, 12)

            WaitingRail(isConfirmed: isConfirmed, isFirst: isFirst, isLast: isLast)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(update.source.kind)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(update.source.color, in: Capsule())
                    Text(update.source.line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(badge)
                        .font(.caption.bold())
                        .foregroundStyle(isConfirmed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .fixedSize()
                }

                // Nothing here for a row whose byline could not be read.
                if !update.author.isEmpty || showsPosition {
                    HStack(spacing: 12) {
                        if !update.author.isEmpty {
                            // Truncating: a pseud is free text, unlike the bounded
                            // stats this label usually carries.
                            WorkStatLabel(text: update.author, symbol: "person", truncates: true)
                        }
                        if showsPosition {
                            WorkStatLabel(text: update.at.formatted(.dateTime.hour().minute()), symbol: "clock")
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(whatChanged)
                    .font(.subheadline)
                    .foregroundStyle(isConfirmed ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The 14pt rail beside the gutter. Segments stop at the dot, so a row's own
/// line never runs through it; the dot is solid for a confirmed update and an
/// outline for a work-only one.
///
/// The dot deliberately does not take the source colour. Those are saturated
/// fills chosen to carry white chip text, and against the dark themes' card
/// background the work red reads at about 1.35:1 — invisible. `.tint` and
/// `.secondary` are `colorScheme`-dynamic, so the one distinction the dot
/// actually carries survives on all five themes. The kind is still colour-coded,
/// on the chip beside it, where the contrast holds.
private struct WaitingRail: View {
    @Environment(ThemeManager.self) private var theme
    let isConfirmed: Bool
    let isFirst: Bool
    let isLast: Bool

    private var line: some View {
        Rectangle()
            .fill(theme.appTheme.threadSpine)
            .frame(width: 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            line.frame(height: 12).opacity(isFirst ? 0 : 1)
            Group {
                if isConfirmed {
                    Circle().fill(.tint)
                } else {
                    Circle().strokeBorder(.secondary, lineWidth: 2)
                }
            }
            .frame(width: 10, height: 10)
            line.frame(maxHeight: .infinity).opacity(isLast ? 0 : 1)
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }
}

private extension SubscriptionUpdate.Source {
    var kind: String {
        switch self {
        case .work: "Work"
        case .series: "Series"
        case .author: "Author"
        }
    }

    var line: String {
        switch self {
        case .work: "Following this work"
        case let .series(name): "Following \(name)"
        case let .author(name): "Following \(name)"
        }
    }

    /// The chip's fill. Fixed rather than themed because the chip carries white
    /// text: each of these clears 5.7:1 against white, which a theme-derived
    /// colour would not guarantee. Only the chip uses it — see `WaitingRail`.
    var color: Color {
        switch self {
        case .work: Color(red: 0x82 / 255, green: 0x10 / 255, blue: 0x19 / 255)
        case .series: Color(red: 0x1E / 255, green: 0x63 / 255, blue: 0xC8 / 255)
        case .author: Color(red: 0x7B / 255, green: 0x3F / 255, blue: 0xA0 / 255)
        }
    }
}

#Preview {
    let now = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now

    func update(
        _ id: UInt64, chapter: Int? = 9, isNew: Bool = false, contested: Bool = false,
        anchored: Bool = true, title: String, author: String, at: Date,
        source: SubscriptionUpdate.Source = .work
    ) -> SubscriptionUpdate {
        SubscriptionUpdate(
            workID: id, chapterID: id * 10, chapterNumber: chapter, isNewWork: isNew,
            isContested: contested, isAnchoredToWork: anchored,
            workTitle: title, author: author, at: at, source: source
        )
    }

    return NavigationStack {
        WaitingListView(updates: [
            update(1, title: "The Lantern Keeper", author: "saltwindow", at: now - 600),
            update(2, isNew: true, title: "Salt and Ember", author: "quietfern", at: now - 3_600,
                   source: .series("Winter Court")),
            update(3, chapter: 3, title: "A Quiet Harbour", author: "marrowlight", at: now - 7_200,
                   source: .author("marrowlight")),
            update(4, contested: true, title: "", author: "", at: yesterday),
            update(5, chapter: nil, anchored: false, title: "Paper Boats", author: "wrenfield",
                   at: yesterday - 3_600, source: .author("wrenfield"))
        ])
    }
    .environment(ThemeManager())
}
