import SwiftUI

extension Date {
    /// "Nov 19", for "since Nov 19" and the chart's axis.
    var studioStatsShort: String { formatted(.dateTime.month(.abbreviated).day()) }
}

/// "+38", "-3"; empty for no change, which the caller words itself.
func studioStatsSigned(_ change: Int) -> String {
    change.formatted(.number.sign(strategy: .always()))
}

/// Pure cell and subtitle formatting for `StudioStatsWorksTable` (`Studio-Stats`).
nonisolated enum StudioStatsWorksFormatting {
    /// Formats a table figure (`19.2k` for four-digit+ hits matching `Studio-Stats`,
    /// grouped digits for kudos/comments, `"–"` when absent).
    static func figureText(
        _ value: Int?,
        metric: StudioStatsMetric,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let value else { return "–" }
        if metric == .hits, abs(value) >= 1_000 {
            return value.formatted(
                .number
                    .locale(locale)
                    .notation(.compactName)
                    .precision(.fractionLength(0...1))
            )
            .lowercased()
        }
        return value.formatted(.number.locale(locale))
    }

    static func workMeta(_ work: AO3UserStats.Work) -> String {
        var parts = [work.fandoms.joined(separator: " · ")].filter { !$0.isEmpty }
        if let words = work.wordCount {
            parts.append(StudioWorkItem.wordCountLabel(words))
        }
        return parts.joined(separator: " · ")
    }
}

/// A few small bars of a total's recent weeks. Decorative: the card's text says it all.
struct StudioStatsSparkline: View {
    let fractions: [Double]
    var isAccented = false

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                let lastFill: Color = isAccented ? theme.accentInk : Color.primary.opacity(0.75)
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == fractions.count - 1 ? lastFill : Color.primary.opacity(0.20))
                    .frame(height: max(2, CGFloat(fraction) * 22))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// One total: its name, value, change since the baseline look, and a sparkline.
struct StudioStatsTotalCard: View {
    let metric: StudioStatsMetric
    let value: Int
    let change: Int?
    let since: Date?
    let sparkline: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.title)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
            Text(value.formatted())
                .font(.title2.bold())
                .monospacedDigit()
            if let changeText {
                Text(changeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(change == 0 ? AnyShapeStyle(SecondaryInkStyle()) : AnyShapeStyle(AccentInkStyle()))
            }
            if !sparkline.isEmpty {
                StudioStatsSparkline(fractions: sparkline, isAccented: metric == .kudos)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .subjectPanel(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private var changeText: String? {
        guard let change, let since else { return nil }
        if change == 0 { return "No change since \(since.studioStatsShort)" }
        return "\(studioStatsSigned(change)) since \(since.studioStatsShort)"
    }
}

/// Your Works: each work's hits, kudos and comment threads with their change, the
/// columns sortable. Reads the page's own figures; the stats page has no chapter
/// status, so the second line is the fandom and word count.
struct StudioStatsWorksTable: View {
    let works: [AO3UserStats.Work]
    let baseline: StudioStatsSnapshot?
    @Binding var sort: AO3UserStats.Sort
    let open: (AO3UserStats.Work) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // The figure columns grow with the text so "1,804" never truncates.
    @ScaledMetric(relativeTo: .subheadline) private var scale: CGFloat = 1

    private struct Column: Identifiable {
        let sort: AO3UserStats.Sort
        let title: String
        let metric: StudioStatsMetric
        let width: CGFloat
        var id: String { title }
    }

    private static let columns = [
        Column(sort: .hits, title: "Hits", metric: .hits, width: 60),
        Column(sort: .kudos, title: "Kudos", metric: .kudos, width: 60),
        Column(sort: .commentThreads, title: "Cmts", metric: .comments, width: 48)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                sortMenu
            } else {
                headerRow
            }
            ForEach(works) { work in
                Divider()
                row(work)
            }
        }
    }

    // MARK: Sorting

    private var sortMenu: some View {
        Menu {
            ForEach(Self.columns) { column in
                Button(column.title) { sort = column.sort }
            }
        } label: {
            Label("Sorted by \(Self.columns.first { $0.sort == sort }?.title ?? "Kudos")", systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.accentInk)
                .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityLabel("Sort works")
        .accessibilityValue(Self.columns.first { $0.sort == sort }?.metric.title ?? "Kudos")
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Text("Work")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Self.columns) { column in
                let isSelected = sort == column.sort
                Button { sort = column.sort } label: {
                    Text(isSelected ? "\(column.title) ▾" : column.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isSelected ? AnyShapeStyle(AccentInkStyle()) : AnyShapeStyle(SecondaryInkStyle()))
                        .frame(width: column.width * scale, alignment: .trailing)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sort by \(column.metric.title)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    // MARK: Rows

    private func row(_ work: AO3UserStats.Work) -> some View {
        Button { open(work) } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    stackedRow(work)
                } else {
                    columnRow(work)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spokenLabel(work))
    }

    private func titleBlock(_ work: AO3UserStats.Work) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(work.title)
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            Text(StudioStatsWorksFormatting.workMeta(work))
                .font(.caption2)
                .foregroundStyle(.secondaryInk)
        }
    }

    private func columnRow(_ work: AO3UserStats.Work) -> some View {
        HStack(spacing: 6) {
            titleBlock(work)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Self.columns) { column in
                let delta = changeText(column, work)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(StudioStatsWorksFormatting.figureText(figure(column, work), metric: column.metric))
                        .font(.subheadline.weight(column.metric == .kudos ? .bold : .semibold))
                        .monospacedDigit()
                        .foregroundStyle(
                            column.metric == .kudos
                                ? AnyShapeStyle(AccentInkStyle())
                                : AnyShapeStyle(Color.primary)
                        )
                    if !delta.isEmpty {
                        Text(delta)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(
                                column.metric == .kudos
                                    ? AnyShapeStyle(AccentInkStyle())
                                    : AnyShapeStyle(SecondaryInkStyle())
                            )
                    }
                }
                .frame(width: column.width * scale, alignment: .trailing)
            }
        }
    }

    private func stackedRow(_ work: AO3UserStats.Work) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            titleBlock(work)
            ForEach(Self.columns) { column in
                let delta = changeText(column, work)
                HStack(alignment: .firstTextBaseline) {
                    Text(column.metric.title)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                    Spacer(minLength: 8)
                    Text(StudioStatsWorksFormatting.figureText(figure(column, work), metric: column.metric))
                        .font(.subheadline.weight(column.metric == .kudos ? .bold : .semibold))
                        .monospacedDigit()
                        .foregroundStyle(
                            column.metric == .kudos
                                ? AnyShapeStyle(AccentInkStyle())
                                : AnyShapeStyle(Color.primary)
                        )
                    if !delta.isEmpty {
                        Text(delta)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(
                                column.metric == .kudos
                                    ? AnyShapeStyle(AccentInkStyle())
                                    : AnyShapeStyle(SecondaryInkStyle())
                            )
                    }
                }
            }
        }
    }

    // MARK: Figures

    private func figure(_ column: Column, _ work: AO3UserStats.Work) -> Int? {
        column.metric.value(in: work)
    }

    /// Nil when the work is new since the baseline look or the figure is unknown.
    private func change(_ column: Column, _ work: AO3UserStats.Work) -> Int? {
        StudioStatsHistory.change(
            figure(column, work),
            since: baseline?.work(id: work.id)?.figure(column.metric)
        )
    }

    private func changeText(_ column: Column, _ work: AO3UserStats.Work) -> String {
        guard let change = change(column, work), change != 0 else { return "" }
        return studioStatsSigned(change)
    }

    private func spokenLabel(_ work: AO3UserStats.Work) -> String {
        var parts = [work.title]
        for column in Self.columns {
            guard let value = figure(column, work) else { continue }
            var text = "\(value.formatted()) \(column.metric.title)"
            if let change = change(column, work), change != 0 {
                text += change > 0 ? ", up \(change.formatted())" : ", down \((-change).formatted())"
            }
            parts.append(text)
        }
        if let baseline { parts.append("Changes since \(baseline.date.studioStatsShort)") }
        return parts.joined(separator: ". ")
    }
}
