import SwiftUI

/// A local-only dashboard summarizing reading progress from `SavedWork`.
struct ReadingStatisticsView: View {
    let works: [SavedWork]

    private var statistics: ReadingStatistics {
        ReadingStatistics(works: works)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12)
    ]

    var body: some View {
        List {
            Section("Overview") {
                LazyVGrid(columns: columns, spacing: 12) {
                    metric(
                        title: "Works Read",
                        value: statistics.startedWorks.formatted(),
                        detail: "\(statistics.totalWorks.formatted()) in your library",
                        icon: "books.vertical"
                    )
                    metric(
                        title: "Words Read",
                        value: statistics.wordsRead.formatted(.number.notation(.compactName)),
                        detail: "From finished works",
                        icon: "text.word.spacing"
                    )
                    metric(
                        title: "Finished",
                        value: statistics.finishedWorks.formatted(),
                        detail: completionPercent,
                        icon: "checkmark.circle"
                    )
                    metric(
                        title: "In Progress",
                        value: statistics.inProgressWorks.formatted(),
                        detail: "Started, not finished",
                        icon: "book.pages"
                    )
                }
                .cardRow()
            }

            Section("Reading Activity") {
                activityRow(
                    title: "Past 7 days",
                    value: worksOpenedText(statistics.openedLast7Days),
                    icon: "calendar"
                )
                activityRow(
                    title: "Past 30 days",
                    value: worksOpenedText(statistics.openedLast30Days),
                    icon: "calendar.badge.clock"
                )
                activityRow(
                    title: "Last read",
                    value: latestReadText,
                    icon: "clock"
                )
            }
            .cardRow()

            Section("Completion") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Finished works")
                        Spacer()
                        Text(completionPercent)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    ProgressView(value: statistics.completionRate)
                        .tint(.accentColor)
                    Text(completionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .cardRow()

            Section("Top Fandoms") {
                if statistics.topFandoms.isEmpty {
                    ContentUnavailableView {
                        Label("No fandom insights yet", systemImage: "sparkles")
                    } description: {
                        Text("Fandoms appear after a started work has categorized AO3 tags.")
                    }
                } else {
                    ForEach(
                        Array(statistics.topFandoms.prefix(6).enumerated()),
                        id: \.element.id
                    ) { index, fandom in
                        fandomRow(fandom, rank: index + 1)
                    }
                }
            }
            .cardRow()

            Section {
                Text(
                    "Statistics stay on this device. Words Read includes finished works "
                        + "with a known AO3 word count; recent activity counts distinct works opened."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .cardRow()
        }
        .cardList()
        .navigationTitle("Reading Insights")
    }

    private var completionPercent: String {
        statistics.completionRate.formatted(
            .percent.precision(.fractionLength(0))
        )
    }

    private var completionDetail: String {
        guard statistics.startedWorks > 0 else {
            return "Open a work in the reader to begin tracking progress."
        }
        return "\(statistics.finishedWorks.formatted()) of \(statistics.startedWorks.formatted()) started works"
    }

    private var latestReadText: String {
        guard let date = statistics.latestReadDate else { return "Not yet" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func worksOpenedText(_ count: Int) -> String {
        "\(count.formatted()) work\(count == 1 ? "" : "s") opened"
    }

    private func metric(
        title: String,
        value: String,
        detail: String,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }

    private func activityRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func fandomRow(_ fandom: ReadingStatistics.FandomCount, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(rank)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
                Text(fandom.name)
                    .lineLimit(2)
                Spacer()
                Text(fandom.count.formatted())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(.tint.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.tint)
                            .frame(width: proxy.size.width * fandomFraction(fandom))
                    }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 2)
    }

    private func fandomFraction(_ fandom: ReadingStatistics.FandomCount) -> Double {
        guard let maximum = statistics.topFandoms.first?.count, maximum > 0 else { return 0 }
        return Double(fandom.count) / Double(maximum)
    }
}
