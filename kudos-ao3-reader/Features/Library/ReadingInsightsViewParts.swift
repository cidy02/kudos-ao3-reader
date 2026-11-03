import SwiftData
import SwiftUI

// MARK: - Overview Cards

struct WordsReadHeroCard: View {
    let insights: ReadingInsights
    let periodName: String
    let previousPeriodName: String
    let hideReadingTime: Bool
    let totalDaysElapsed: Int
    let palette: SubjectPalette
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Words read")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(insights.totalWordsRead.formatted())
                    .font(.system(size: 38, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let prevWords = insights.previousPeriodWordsRead, prevWords > 0 {
                    let delta = insights.totalWordsRead - prevWords
                    let pct = Int((Double(abs(delta)) / Double(prevWords) * 100).rounded())
                    HStack(spacing: 3) {
                        Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(pct)% vs \(previousPeriodName)")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(delta >= 0 ? Color.green : Color.secondary)
                }
            }

            if let novelStr = ReadingInsights.novelsWorthLabel(words: insights.totalWordsRead) {
                Text(novelStr)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .overlay(theme.appTheme.cardBorder)
                .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time reading")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(hideReadingTime ? "—" : ReadingInsights.durationLabel(insights.totalSeconds))
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Finished")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(insights.finishedWorksCount.formatted())
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading days")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(insights.readingDaysCount) of \(totalDaysElapsed)")
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct WordsPerDayCard: View {
    let days: [ReadingInsights.DailyWordsBucket]
    let totalDays: Int
    @Environment(ThemeManager.self) private var theme

    private var maxWords: Int {
        max(1, days.map(\.words).max() ?? 1)
    }

    private var avgWordsK: String {
        guard !days.isEmpty else { return "0.0k" }
        let sum = days.reduce(0) { $0 + $1.words }
        let avg = Double(sum) / Double(days.count) / 1000.0
        return String(format: "%.1fk", avg)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Words per Day")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("avg \(avgWordsK)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Bar chart container
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    // Dashed reference line
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                        .offset(y: -48)

                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(days) { day in
                            let height = max(4.0, (Double(day.words) / Double(maxWords)) * 96.0)
                            VStack(spacing: 2) {
                                if day.isMax && day.words > 0 {
                                    Text(formatK(day.words))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                } else {
                                    Spacer(minLength: 0)
                                }

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(day.words > 0 ? theme.effectiveTint : Color.primary.opacity(0.08))
                                    .frame(height: height)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 112)
                }

                // Date ticks below chart
                HStack {
                    if let first = days.first {
                        Text("Day \(first.dayNumber)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if days.count >= 15 {
                        let mid = days[days.count / 2]
                        Text("\(mid.dayNumber)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let last = days.last {
                        Text("\(last.dayNumber)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Words read per day chart. Average \(avgWordsK) words per day.")
    }

    private func formatK(_ words: Int) -> String {
        String(format: "%.1fk", Double(words) / 1000.0)
    }
}

struct WhereTheWordsWentCard: View {
    let fandoms: [ReadingInsights.FandomWordsShare]
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where the Words Went")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(fandoms.count) \(fandoms.count == 1 ? "fandom" : "fandoms")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Stacked bar
            if !fandoms.isEmpty {
                HStack(spacing: 2) {
                    ForEach(fandoms) { f in
                        let color = fandomColor(for: f)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Fandom words distribution bar")
            }

            // Rows
            VStack(spacing: 0) {
                ForEach(Array(fandoms.enumerated()), id: \.element.id) { index, f in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(fandomColor(for: f))
                            .frame(width: 10, height: 10)

                        let displayName = discreetMode && !f.isRemainder ? "Fandom \(index + 1)" : f.name
                        Text(displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(formatK(f.words)) · \(f.worksCount) \(f.worksCount == 1 ? "work" : "works")")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        Text("\(Int((f.share * 100).rounded()))%")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                    .frame(minHeight: 34)
                }
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func fandomColor(for share: ReadingInsights.FandomWordsShare) -> Color {
        if share.isRemainder { return Color.secondary.opacity(0.4) }
        let hue = CoverArt.workHue(fandoms: [share.name], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }

    private func formatK(_ words: Int) -> String {
        String(format: "%.1fk", Double(words) / 1000.0)
    }
}

struct ReadingAndListeningCard: View {
    let readingSeconds: Double
    let hideReadingTime: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        // The log records time in the reader, not Read Aloud, so this is reading time only.
        HStack(alignment: .firstTextBaseline) {
            Text("Time Reading")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(hideReadingTime ? "—" : ReadingInsights.durationLabel(readingSeconds))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct RecordsGridCard: View {
    let streakDays: Int
    let biggestDayWords: Int
    let medianSessionSeconds: Double
    let wordsPerHour: Double
    let hideReadingTime: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            recordTile(
                title: "Longest streak",
                value: "\(streakDays) day\(streakDays == 1 ? "" : "s")",
                detail: streakDays > 0 ? "consecutive days" : "no sessions yet"
            )

            recordTile(
                title: "Biggest day",
                value: biggestDayWords > 0 ? String(format: "%.1fk", Double(biggestDayWords) / 1000.0) : "—",
                detail: biggestDayWords > 0 ? "words read" : "no data"
            )

            recordTile(
                title: "Typical sitting",
                value: hideReadingTime ? "—" : ReadingInsights.durationLabel(medianSessionSeconds),
                detail: "median sitting"
            )

            recordTile(
                title: "Pace",
                value: wordsPerHour > 0 ? String(format: "%.1fk", wordsPerHour / 1000.0) : "—",
                detail: "words an hour"
            )
        }
    }

    private func recordTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct LengthOfWhatYouReadCard: View {
    let mix: ReadingInsights.LengthMixCounts
    @Environment(ThemeManager.self) private var theme

    private let ramp: [Color] = [
        Color(red: 0.92, green: 0.76, blue: 0.76),
        Color(red: 0.84, green: 0.50, blue: 0.50),
        Color(red: 0.71, green: 0.23, blue: 0.23),
        Color(red: 0.49, green: 0.06, blue: 0.06)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Length of What You Read")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(mix.totalWorks) works")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Stacked bar
            HStack(spacing: 2) {
                segment(count: mix.under5k, color: ramp[0])
                segment(count: mix.from5kTo50k, color: ramp[1])
                segment(count: mix.from50kTo150k, color: ramp[2])
                segment(count: mix.over150k, color: ramp[3])
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Breakdown
            HStack(alignment: .top, spacing: 6) {
                tierItem(label: "Under 5k", count: mix.under5k, color: ramp[0])
                tierItem(label: "5k–50k", count: mix.from5kTo50k, color: ramp[1])
                tierItem(label: "50k–150k", count: mix.from50kTo150k, color: ramp[2])
                tierItem(label: "150k+", count: mix.over150k, color: ramp[3])
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func segment(count: Int, color: Color) -> some View {
        let total = max(1, mix.totalWorks)
        let flex = max(0.1, Double(count) / Double(total))
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(height: 14)
            .frame(maxWidth: .infinity)
            .opacity(count > 0 ? 1 : 0.2)
    }

    private func tierItem(label: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FinishedInPeriodSection: View {
    let works: [SavedWork]
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Finished \(works.count)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("See All")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.effectiveTint)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                let shownWorks = Array(works.prefix(3))
                ForEach(Array(shownWorks.enumerated()), id: \.element.id) { index, work in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    NavigationLink(value: work) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                if let fandom = work.workFandoms.first, !fandom.isEmpty {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(fandomColor(for: fandom))
                                            .frame(width: 8, height: 8)
                                        let displayName = discreetMode ? "Fandom" : fandom
                                        Text(displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text(discreetMode ? "Work \(index + 1)" : work.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                let wordStr = work.wordCount > 0 ? "\(work.wordCount.formatted()) words" : ""
                                Text(wordStr)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }

                if works.count > 3 {
                    Divider()
                        .overlay(theme.appTheme.cardBorder)
                    HStack(spacing: 4) {
                        Text("\(works.count - 3) more")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.effectiveTint)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.effectiveTint)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }
}


// MARK: - Taste Cards

struct YourUsualFicCard: View {
    let taste: ReadingTasteInsights
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Usual Fic")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("from \(taste.totalWorksCount) works")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(taste.usualFicSummary)
                .font(.system(.title3, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(.primary)

            if !taste.usualFicTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(taste.usualFicTags.enumerated()), id: \.offset) { index, tag in
                        Text(discreetMode ? "Tag \(index + 1)" : tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(theme.appTheme.cardBackdrop)
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [theme.appTheme.cardSurface, theme.effectiveTint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct TasteFandomsCard: View {
    let fandoms: [ReadingInsights.FandomWordsShare]
    let rankByWorks: Bool
    let onToggleRank: () -> Void
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    private var sortedFandoms: [ReadingInsights.FandomWordsShare] {
        if rankByWorks {
            return fandoms.sorted { $0.worksCount > $1.worksCount }
        }
        return fandoms
    }

    private var peakMetric: Double {
        if rankByWorks {
            return Double(max(1, fandoms.map(\.worksCount).max() ?? 1))
        }
        return Double(max(1, fandoms.map(\.words).max() ?? 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fandoms")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    onToggleRank()
                } label: {
                    HStack(spacing: 4) {
                        Text(rankByWorks ? "By Works" : "By Words")
                            .font(.footnote.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(sortedFandoms.enumerated()), id: \.element.id) { index, f in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            let name = discreetMode && !f.isRemainder ? "Fandom \(index + 1)" : f.name
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(f.worksCount) \(f.worksCount == 1 ? "work" : "works")")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(formatK(f.words))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }

                        // Progress bar
                        GeometryReader { proxy in
                            let currentVal = rankByWorks ? Double(f.worksCount) : Double(f.words)
                            let ratio = min(1.0, max(0.04, currentVal / peakMetric))
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(fandomColor(for: f))
                                        .frame(width: proxy.size.width * ratio)
                                }
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 16)
                }
            }
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func fandomColor(for share: ReadingInsights.FandomWordsShare) -> Color {
        if share.isRemainder { return Color.secondary.opacity(0.4) }
        let hue = CoverArt.workHue(fandoms: [share.name], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }

    private func formatK(_ words: Int) -> String {
        String(format: "%.1fk", Double(words) / 1000.0)
    }
}

struct TasteRelationshipsCard: View {
    let relationships: [RelationshipShare]
    let shipConcentrations: [ShipConcentration]
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Relationships")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                let shown = Array(relationships.prefix(4))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, rel in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    HStack(spacing: 12) {
                        // Tile with / or &
                        Text(rel.isRomantic ? "/" : "&")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            let name = discreetMode ? "Ship \(index + 1)" : rel.name
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(fandomColor(for: rel.fandom))
                                    .frame(width: 6, height: 6)
                                Text("\(rel.isRomantic ? "Romantic" : "Platonic") · \(discreetMode ? "Fandom" : rel.fandom) · \(rel.worksCount) \(rel.worksCount == 1 ? "work" : "works")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(formatK(rel.words))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                if !shipConcentrations.isEmpty {
                    Divider()
                        .overlay(theme.appTheme.cardBorder)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ship Concentration")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)

                        ForEach(shipConcentrations) { ship in
                            HStack(spacing: 8) {
                                let displayName = discreetMode ? "Fandom" : ship.fandom
                                Text(displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 110, alignment: .leading)

                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                        .overlay(alignment: .leading) {
                                            Capsule()
                                                .fill(fandomColor(for: ship.fandom))
                                                .frame(width: proxy.size.width * CGFloat(ship.percentage) / 100.0)
                                        }
                                }
                                .frame(height: 6)

                                Text(ship.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 100, alignment: .trailing)
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }

    private func formatK(_ words: Int) -> String {
        String(format: "%.1fk", Double(words) / 1000.0)
    }
}

struct TasteCharactersCard: View {
    let characters: [ReadingTasteInsights.CharacterShare]
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Characters")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            FlowLayout(spacing: 8) {
                ForEach(Array(characters.prefix(9).enumerated()), id: \.element.id) { index, char in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(fandomColor(for: char.fandom))
                            .frame(width: 7, height: 7)
                        let displayName = discreetMode ? "Character \(index + 1)" : char.name
                        Text(displayName)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                        Text("\(char.count)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(theme.appTheme.cardSurface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                    )
                }
            }
        }
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }
}

struct TasteTagsCard: View {
    let tags: [ReadingTasteInsights.TagShare]
    let oftenTogether: [TagPair]
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    private var maxWords: Int {
        max(1, tags.map(\.words).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                let shownTags = Array(tags.prefix(6))
                ForEach(Array(shownTags.enumerated()), id: \.element.id) { index, tag in
                    if index > 0 {
                        Divider()
                            .overlay(theme.appTheme.cardBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            let name = discreetMode ? "Tag \(index + 1)" : tag.name
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text("\(tag.words / 1000)k")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }

                        GeometryReader { proxy in
                            let ratio = min(1.0, max(0.04, Double(tag.words) / Double(maxWords)))
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(theme.effectiveTint)
                                        .frame(width: proxy.size.width * ratio)
                                }
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                if !oftenTogether.isEmpty {
                    Divider()
                        .overlay(theme.appTheme.cardBorder)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Often Together")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)

                        ForEach(oftenTogether) { pair in
                            HStack {
                                Text("\(pair.tagA) + \(pair.tagB)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(pair.worksCount) works")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}

struct TasteRatingsCategoriesWarningsCard: View {
    let ratings: [ReadingTasteInsights.CountBreakdown]
    let categories: [ReadingTasteInsights.CountBreakdown]
    let warnings: [ReadingTasteInsights.CountBreakdown]
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 12) {
            breakdownCard(title: "Rating", items: ratings)
            breakdownCard(title: "Category", items: categories)
            breakdownCard(title: "Warnings", items: warnings)
        }
    }

    private func breakdownCard(title: String, items: [ReadingTasteInsights.CountBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            let total = max(1, items.reduce(0) { $0 + $1.count })
            VStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Text(item.label)
                            .font(.caption)
                            .frame(width: 110, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { proxy in
                            let ratio = min(1.0, max(0.04, Double(item.count) / Double(total)))
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(theme.effectiveTint)
                                        .frame(width: proxy.size.width * ratio)
                                }
                        }
                        .frame(height: 5)

                        Text("\(item.count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct TasteWhenPostedCard: View {
    let yearCounts: [ReadingTasteInsights.YearCount]
    let medianYear: Int?
    @Environment(ThemeManager.self) private var theme

    private var maxCount: Int {
        max(1, yearCounts.map(\.count).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("When They Were Posted")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("median \(medianYear.map(String.init) ?? "—")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Year histogram
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(yearCounts) { item in
                    let height = max(4.0, (Double(item.count) / Double(maxCount)) * 52.0)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.count > 0 ? Color.secondary : Color.primary.opacity(0.08))
                        .frame(height: height)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56)

            HStack {
                Text("2010")
                Spacer()
                Text("2014")
                Spacer()
                Text("2018")
                Spacer()
                Text("2022")
                Spacer()
                Text("2026")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct TasteCrossoversLanguagesGrid: View {
    let crossoverCount: Int
    let totalWorks: Int
    let languages: [ReadingTasteInsights.CountBreakdown]
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Crossovers")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\(crossoverCount) of \(totalWorks)")
                    .font(.title3.weight(.bold))
                Text(crossoverCount > 0 ? "works with 2+ fandoms" : "none")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Languages")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\(languages.count)")
                    .font(.title3.weight(.bold))
                let langStr = languages.prefix(2).map { "\($0.label) \($0.count)" }.joined(separator: " · ")
                Text(langStr.isEmpty ? "English" : langStr)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Habits Cards

struct HabitsTimeOfDayCard: View {
    let hourly: [ReadingInsights.HourlyBucket]
    let lateNightDuration: Double
    let lateNightSharePercent: Int
    @Environment(ThemeManager.self) private var theme

    private var maxSeconds: Double {
        max(1, hourly.map(\.seconds).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Time of Day")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("24-hour reading pattern")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // 24-hour bar chart
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(hourly) { item in
                        let height = max(3.0, (item.seconds / maxSeconds) * 86.0)
                        let isLateNight = item.hour >= 1 && item.hour < 5
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.seconds > 0 ? (isLateNight ? theme.effectiveTint.opacity(0.6) : theme.effectiveTint) : Color.primary.opacity(0.08))
                            .frame(height: height)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 90)

                HStack {
                    Text("0:00")
                    Spacer()
                    Text("6:00")
                    Spacer()
                    Text("12:00")
                    Spacer()
                    Text("18:00")
                    Spacer()
                    Text("24:00")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Text("Late night, 1:00–5:00: \(ReadingInsights.durationLabel(lateNightDuration)) (\(lateNightSharePercent)%)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct HabitsCalendarCard: View {
    let days: [ReadingInsights.DailyWordsBucket]
    let longestStreak: Int
    @Environment(ThemeManager.self) private var theme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reading Days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                let readingDays = days.filter { $0.words > 0 }.count
                Text("\(readingDays) of \(days.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Weekday initials
            HStack {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Days grid
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(days) { day in
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(heatColor(for: day.words))
                            .frame(height: 32)

                        Text("\(day.dayNumber)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(day.words > 10_000 ? Color.white : Color.secondary)
                            .padding(4)
                    }
                }
            }

            // Legend & Streak
            HStack {
                Text("Longest streak \(longestStreak) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 3) {
                    Text("Less")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    swatch(heatColor(for: 0))
                    swatch(heatColor(for: 3000))
                    swatch(heatColor(for: 8000))
                    swatch(heatColor(for: 15000))
                    Text("More")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private func heatColor(for words: Int) -> Color {
        if words == 0 { return Color.primary.opacity(0.06) }
        if words < 5_000 { return theme.effectiveTint.opacity(0.25) }
        if words < 10_000 { return theme.effectiveTint.opacity(0.50) }
        if words < 20_000 { return theme.effectiveTint.opacity(0.75) }
        return theme.effectiveTint
    }
}

struct HabitsSittingsCard: View {
    let sittings: [ReadingInsights.SittingBucket]
    let typicalSeconds: Double
    @Environment(ThemeManager.self) private var theme

    private var maxCount: Int {
        max(1, sittings.map(\.count).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sittings")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                let total = sittings.reduce(0) { $0 + $1.count }
                Text("\(total) this month")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Duration distribution bars
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(sittings) { sit in
                    let height = max(4.0, (Double(sit.count) / Double(maxCount)) * 64.0)
                    VStack(spacing: 2) {
                        Text("\(sit.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(sit.count > 0 ? Color.primary : Color.secondary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(sit.count > 0 ? theme.effectiveTint : Color.primary.opacity(0.08))
                            .frame(height: height)
                        Text(sit.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90)

            Divider()
                .overlay(theme.appTheme.cardBorder)

            HStack {
                statColumn(label: "Typical sitting", value: ReadingInsights.durationLabel(typicalSeconds))
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HabitsSavedToFinishedCard: View {
    let savedToOpenedDays: Int?
    let openedToFinishedDays: Int?
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("From Saved to Finished")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            // Flow dots
            HStack(spacing: 0) {
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 2)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 2)
                Circle()
                    .fill(theme.effectiveTint.opacity(0.5))
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(theme.effectiveTint)
                    .frame(height: 2)
                Circle()
                    .fill(theme.effectiveTint)
                    .frame(width: 12, height: 12)
            }

            HStack {
                Text("Saved")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Opened")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Finished")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let days = savedToOpenedDays {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(days) days")
                            .font(.headline)
                        Text("saved to opened, median")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let days = openedToFinishedDays {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(days) days")
                            .font(.headline)
                        Text("opened to finished, median")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct HabitsRereadsCard: View {
    let rereads: [ReadingHabitsInsights.RereadWork]
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rereads")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if rereads.isEmpty {
                    Text("Works you complete multiple times will appear here as rereads.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(16)
                } else {
                    ForEach(Array(rereads.prefix(3).enumerated()), id: \.element.id) { index, work in
                        if index > 0 {
                            Divider()
                                .overlay(theme.appTheme.cardBorder)
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(discreetMode ? "Work \(index + 1)" : work.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(discreetMode ? "Fandom" : work.fandom) · \(work.totalWordsAcrossReads.formatted()) words across reads")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("×\(work.finishCount)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(theme.effectiveTint)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}

struct HabitsFandomTimelineCard: View {
    let lanes: [ReadingHabitsInsights.FandomTimelineLane]
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fandom Timeline")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if lanes.isEmpty {
                Text("Monthly activity by fandom will appear here as you log reading sessions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(lanes.enumerated()), id: \.element.id) { index, lane in
                        HStack(spacing: 6) {
                            Text(discreetMode ? "Fandom \(index + 1)" : lane.name)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(width: 90, alignment: .leading)

                            HStack(spacing: 3) {
                                ForEach(0..<12, id: \.self) { monthIdx in
                                    let tier = monthIdx < lane.monthlyActivity.count ? lane.monthlyActivity[monthIdx] : 0
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(timelineColor(tier: tier, fandom: lane.name))
                                        .frame(height: 16)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func timelineColor(tier: Int, fandom: String) -> Color {
        if tier == 0 { return Color.primary.opacity(0.06) }
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        let base = theme.appTheme.subjectPalette(hue: hue).accent
        if tier == 1 { return base.opacity(0.3) }
        if tier == 2 { return base.opacity(0.65) }
        return base
    }
}

struct HabitsStoppedCard: View {
    let stoppedCount: Int
    let medianProgress: Double?
    let commonTags: [(name: String, count: Int)]
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stopped Reading")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(stoppedCount) in all")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let medianProgress {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int((medianProgress * 100).rounded()))%")
                        .font(.title2.weight(.bold))
                    Text("of the way in, typically")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !commonTags.isEmpty {
                Divider()
                    .overlay(theme.appTheme.cardBorder)

                Text("Common in Stopped Works")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                FlowLayout(spacing: 6) {
                    ForEach(Array(commonTags.enumerated()), id: \.offset) { index, tag in
                        Text("\(discreetMode ? "Tag \(index + 1)" : tag.name) \(tag.count)")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Library Cards

struct LibraryUnreadCard: View {
    let unreadWords: Int
    let unreadCount: Int
    let monthsToClear: Int?
    let addedWords: Int
    let readWords: Int
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unread in your library")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatWords(unreadWords))
                    .font(.system(size: 38, weight: .bold))
                    .monospacedDigit()
                Text("words · \(unreadCount) works")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let m = monthsToClear, m > 0 {
                Text("About \(m) month\(m == 1 ? "" : "s") at your recent pace")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .overlay(theme.appTheme.cardBorder)

            // Added vs Read
            VStack(spacing: 6) {
                let maxW = max(1, max(addedWords, readWords))
                barRow(label: "Added", words: addedWords, color: Color.secondary, maxVal: maxW)
                barRow(label: "Read", words: readWords, color: theme.effectiveTint, maxVal: maxW)
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func barRow(label: String, words: Int, color: Color, maxVal: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)

            GeometryReader { proxy in
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: proxy.size.width * CGFloat(words) / CGFloat(maxVal))
                    }
            }
            .frame(height: 10)

            Text(formatK(words))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func formatWords(_ words: Int) -> String {
        if words >= 1_000_000 {
            return String(format: "%.2fM", Double(words) / 1_000_000.0)
        }
        return "\(words / 1000)k"
    }

    private func formatK(_ words: Int) -> String {
        String(format: "%.1fk", Double(words) / 1000.0)
    }
}

struct LibraryWhereEverythingStandsCard: View {
    let partition: ReadingStatusPartition
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where Everything Stands")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                statusRow(icon: "book.fill", color: theme.effectiveTint, label: "Reading", count: partition.readingCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "clock.fill", color: Color(red: 0.17, green: 0.43, blue: 0.69), label: "Caught Up", detail: "every posted chapter read", count: partition.caughtUpCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "square.stack.3d.up.fill", color: Color(red: 0.37, green: 0.36, blue: 0.90), label: "Letting Chapters Stack", detail: "back when 3 more are posted", count: partition.stackingCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "pause.circle.fill", color: Color.secondary, label: "On Hold", count: partition.onHoldCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "bookmark.fill", color: Color(red: 0.69, green: 0.49, blue: 0.07), label: "Saved for Later", count: partition.savedForLaterCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "checkmark.circle.fill", color: Color(red: 0.18, green: 0.48, blue: 0.29), label: "Finished", count: partition.finishedCount)
                Divider().overlay(theme.appTheme.cardBorder)
                statusRow(icon: "xmark.circle.fill", color: Color(red: 0.39, green: 0.39, blue: 0.40), label: "Stopped", count: partition.stoppedCount)
            }
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    private func statusRow(icon: String, color: Color, label: String, detail: String? = nil, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct LibraryStillReadingCard: View {
    let candidate: ReadingLibraryInsights.StillReadingCandidate
    let discreetMode: Bool
    let onStillReading: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(fandomColor(for: candidate.fandom))
                        .frame(width: 8, height: 8)
                    Text("\(discreetMode ? "Fandom" : candidate.fandom) · untouched for \(candidate.daysUntouched / 7) weeks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Still reading \(discreetMode ? "this work" : candidate.title)?")
                    .font(.subheadline.weight(.semibold))

                Text(candidate.chapterProgress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    onStillReading()
                } label: {
                    Text("Still Reading")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                NavigationLink(value: candidate.work) {
                    Text("Open Work")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(theme.effectiveTint)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }
}

struct LibraryWIPFreshnessCard: View {
    let freshness: WIPFreshness
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Works in Progress")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(freshness.total) saved")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Freshness bar
            HStack(spacing: 2) {
                let total = max(1, freshness.total)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.8))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                    .opacity(freshness.active > 0 ? 1 : 0.2)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary)
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                    .opacity(freshness.quiet > 0 ? 1 : 0.2)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.2))
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
                    .opacity(freshness.dormant > 0 ? 1 : 0.2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack {
                freshnessCol(label: "Active", count: freshness.active, detail: "in 6 months")
                freshnessCol(label: "Quiet", count: freshness.quiet, detail: "6–12 months")
                freshnessCol(label: "Dormant", count: freshness.dormant, detail: "over a year")
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func freshnessCol(label: String, count: Int, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LibraryNoLongerOnAO3Card: View {
    let count: Int
    let words: Int
    let lastCopies: Int
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text("No Longer on AO3")
                    .font(.subheadline.weight(.semibold))
                Text("\(count) works · \(formatWords(words)) words · \(lastCopies) kept as your last copy")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func formatWords(_ words: Int) -> String {
        if words >= 1_000_000 {
            return String(format: "%.1fM", Double(words) / 1_000_000.0)
        }
        return "\(words / 1000)k"
    }
}

struct LibraryFeedbackCard: View {
    let kudosLeftPercent: Int
    let bookmarkedPercent: Int
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On Finished Works")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                feedbackRow(label: "Kudos left", percent: kudosLeftPercent)
                feedbackRow(label: "Bookmarked", percent: bookmarkedPercent)
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func feedbackRow(label: String, percent: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 90, alignment: .leading)

            GeometryReader { proxy in
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(theme.effectiveTint)
                            .frame(width: proxy.size.width * CGFloat(percent) / 100.0)
                    }
            }
            .frame(height: 6)

            // One line: "100%" was wider than the old fixed column and broke before the "%".
            Text("\(percent)%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 32, alignment: .trailing)
        }
    }
}

struct LibraryPreservedStatsCard: View {
    let stats: ReadingStatistics
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Library Activity")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                item(title: "Works opened", value: "\(stats.startedWorks)")
                item(title: "Words read", value: stats.wordsRead.formatted(.number.notation(.compactName)))
                item(title: "Still in progress", value: "\(stats.inProgressWorks)")
                item(title: "Finished", value: "\(stats.finishedWorks) (\(Int(stats.completionRate * 100))%)")
                item(title: "Opened in 7 days", value: "\(stats.openedLast7Days)")
                item(title: "Opened in 30 days", value: "\(stats.openedLast30Days)")
            }

            Divider()
                .overlay(theme.appTheme.cardBorder)

            Text("Most-Read Fandoms by Shelf Count")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(spacing: 4) {
                ForEach(Array(stats.topFandoms.prefix(4))) { f in
                    HStack {
                        Circle()
                            .fill(fandomColor(for: f.name))
                            .frame(width: 7, height: 7)
                        Text(discreetMode ? "Fandom" : f.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text("\(f.count) \(f.count == 1 ? "work" : "works")")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func item(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fandomColor(for fandom: String) -> Color {
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        return theme.appTheme.subjectPalette(hue: hue).accent
    }
}
