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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Words read")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)

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
                    .foregroundStyle(delta >= 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondaryInk))
                }
            }

            if let novelStr = ReadingInsights.novelsWorthLabel(words: insights.totalWordsRead) {
                Text(novelStr)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            }

            Divider()
                .overlay(theme.appTheme.cardBorder)
                .padding(.vertical, 4)

            // Three columns until accessibility sizes, where bold title3 values would break mid-figure.
            let statsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            statsLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time reading")
                        .font(.caption2)
                        .foregroundStyle(.secondaryInk)
                    Text(hideReadingTime ? "—" : ReadingInsights.durationLabel(insights.totalSeconds))
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Finished")
                        .font(.caption2)
                        .foregroundStyle(.secondaryInk)
                    Text(insights.finishedWorksCount.formatted())
                        .font(.title3.bold())
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading days")
                        .font(.caption2)
                        .foregroundStyle(.secondaryInk)
                    Text("\(insights.readingDaysCount) of \(totalDaysElapsed)")
                        .font(.title3.bold())
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
                    .foregroundStyle(.secondaryInk)
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
                                        .foregroundStyle(.secondaryInk)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                } else {
                                    Spacer(minLength: 0)
                                }

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(day.words > 0 ? theme.accentInk : Color.primary.opacity(0.08))
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
                            .foregroundStyle(.secondaryInk)
                    }
                    Spacer()
                    if days.count >= 15 {
                        let mid = days[days.count / 2]
                        Text("\(mid.dayNumber)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondaryInk)
                    }
                    Spacer()
                    if let last = days.last {
                        Text("\(last.dayNumber)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondaryInk)
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
    var discreetMasker: InsightsDiscreetMasker = .empty
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
                    .foregroundStyle(.secondaryInk)
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

                        let displayName = discreetMode && !f.isRemainder ? discreetMasker.fandom(f.name) : f.name
                        Text(displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(formatK(f.words)) · \(f.worksCount) \(f.worksCount == 1 ? "work" : "works")")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondaryInk)

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
        ReadingInsights.compactWordsLabel(words)
    }
}

struct ReadingAndListeningCard: View {
    let readingSeconds: Double
    let silentReadingSeconds: Double
    let listeningSeconds: Double
    var listeningPlaybackRate: Double? = nil
    var listeningWorksCount: Int = 0
    let hideReadingTime: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var listeningDetail: String? {
        var parts: [String] = []
        if let rate = listeningPlaybackRate, rate > 0 {
            parts.append(String(format: "%.1f×", rate))
        }
        if listeningWorksCount > 0 {
            let noun = listeningWorksCount == 1 ? "work" : "works"
            parts.append("\(listeningWorksCount) \(noun)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reading and Listening")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(hideReadingTime ? "—" : ReadingInsights.durationLabel(readingSeconds))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondaryInk)
            }

            if readingSeconds > 0 {
                GeometryReader { proxy in
                    let total = max(1.0, silentReadingSeconds + listeningSeconds)
                    let readRatio = min(1.0, max(0.0, silentReadingSeconds / total))
                    let listenRatio = min(1.0, max(0.0, listeningSeconds / total))
                    let gap: CGFloat = (silentReadingSeconds > 0 && listeningSeconds > 0) ? 2 : 0
                    let usableWidth = max(0, proxy.size.width - gap)
                    HStack(spacing: gap) {
                        if silentReadingSeconds > 0 {
                            Rectangle()
                                .fill(theme.accentInk)
                                .frame(width: max(4, usableWidth * CGFloat(readRatio)))
                        }
                        if listeningSeconds > 0 {
                            Rectangle()
                                .fill(theme.accentInk.opacity(0.35))
                                .frame(width: max(4, usableWidth * CGFloat(listenRatio)))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .frame(height: 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reading and Read Aloud time split")
            }

            VStack(spacing: 0) {
                modeRow(
                    title: "Reading",
                    detail: nil,
                    seconds: silentReadingSeconds,
                    swatchColor: theme.accentInk
                )
                Divider()
                    .overlay(theme.appTheme.cardBorder)
                modeRow(
                    title: "Read Aloud",
                    detail: listeningDetail,
                    seconds: listeningSeconds,
                    swatchColor: theme.accentInk.opacity(0.35)
                )
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
    private func modeRow(title: String, detail: String?, seconds: Double, swatchColor: Color) -> some View {
        let valueText = hideReadingTime ? "—" : ReadingInsights.durationLabel(seconds)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(swatchColor)
                        .frame(width: 10, height: 10)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
                Text(valueText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(swatchColor)
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Text(valueText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minHeight: 32)
        }
    }
}

struct InsightsUnavailableCard: View {
    let title: String
    let explanation: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(explanation).font(.footnote).foregroundStyle(.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
            .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5))
    }
}

struct LibraryArrivalCard: View {
    let rows: [ReadingLibraryInsights.ArrivalRow]
    let since: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var visibleRows: [ReadingLibraryInsights.ArrivalRow] {
        rows.filter { $0.finished > 0 }
    }

    private var totalFinished: Int {
        visibleRows.reduce(0) { (partial: Int, row: ReadingLibraryInsights.ArrivalRow) -> Int in
            partial + row.finished
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("How Finished Works Arrived")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let since {
                    Text("since \(since.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }

            VStack(spacing: 8) {
                ForEach(visibleRows) { row in
                    let sharePct = row.finishedSharePercent(totalFinished: totalFinished)
                    let statsText = "\(sharePct)% share · \(row.finishRatePercent)% finish rate"
                    VStack(alignment: .leading, spacing: 2) {
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                        layout {
                            Text(row.label)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(statsText)
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondaryInk)
                        }
                        Text("\(row.finished) finished of \(row.saved) saved")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
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

struct LibraryFoundEarlyCard: View {
    let recordedFinishedCount: Int
    let count: Int
    let foundEarlyShare: Double?
    let grownCount: Int
    let grownShare: Double?
    let since: Date?
    let example: ReadingLibraryInsights.FoundEarlyExample?
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Found Early")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let since {
                    Text("since \(since.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }

            if let foundEarlyShare {
                let pct = Int((foundEarlyShare * 100).rounded())
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(pct)%")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("of finished works had under 500 kudos when saved (\(count) of \(recordedFinishedCount))")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("\(count) finished works had fewer than 500 kudos when saved")
                    .font(.footnote)
            }

            if let grownShare {
                let pct = Int((grownShare * 100).rounded())
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(pct)%")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("have at least tripled their kudos since (\(grownCount))")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let example {
                let title = discreetMode
                    ? discreetMasker.work(id: example.workID, title: example.title)
                    : example.title
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        Text("\(example.kudosAtSave.formatted()) kudos when saved")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondaryInk)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                        Text(example.kudosNow.formatted())
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text("now")
                            .font(.caption)
                            .foregroundStyle(.secondaryInk)
                    }
                }
                .padding(12)
                .background(theme.appTheme.cardBackdrop)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct HabitsChapterTimingCard: View {
    let figure: InsightsProvenance.ChapterTimingFigure
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chapter Habits").font(.subheadline.weight(.semibold))
            metric("Chapters each, average", value: figure.averageChaptersEach.map { String(format: "%.1f", $0) } ?? "No chapter spans yet")
            metric("End on a chapter", value: figure.chapterEndShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "No eligible sittings yet")
            if figure.canShowSkimAndPeek {
                metric("Skimmed", value: "\(ReadingInsights.compactWordsLabel(figure.skimmedWords)) words left out of totals")
                let noun = figure.peekedWorks == 1 ? "work" : "works"
                metric("Peeked at the Ending", value: "\(figure.peekedWorks) \(noun)")
            } else {
                metric("Skimmed · Peeked at the Ending", value: "Available after 20 measured chapters")
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

    private func metric(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondaryInk)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }
}

struct LibraryFavoritesWithoutKudosCard: View {
    let count: Int
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.accentInk)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Favourites Without Kudos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                let noun = count == 1 ? "work" : "works"
                Text("\(count) finished favourite or reread \(noun) still on AO3")
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondaryInk)
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

struct LibrarySeriesCard: View {
    let started: Int
    let readToLast: Int
    let longestFinished: ReadingLibraryInsights.LongestFinishedSeries?
    let nextWaiting: Int
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Series")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            let countsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            countsLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(started)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("started")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(readToLast)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("read to the last part")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let longest = longestFinished {
                let title = discreetMode ? discreetMasker.series(longest.title) : longest.title
                let partNoun = longest.partCount == 1 ? "part" : "parts"
                let wordsPart = longest.wordCount > 0
                    ? ", \(ReadingInsights.compactWordsLabel(longest.wordCount))"
                    : ""
                Text("Longest finished: \(title) · \(longest.partCount) \(partNoun)\(wordsPart)")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if nextWaiting > 0 {
                Divider()
                    .overlay(theme.appTheme.cardBorder)
                HStack(spacing: 10) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.accentInk)
                        .accessibilityHidden(true)
                    Text("Next Part Waiting")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(nextWaiting) series")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

struct LibraryAuthorsCard: View {
    let authors: [ReadingLibraryInsights.AuthorRow]
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authors").font(.subheadline.weight(.semibold))
            ForEach(authors.prefix(5)) { author in
                VStack(alignment: .leading, spacing: 2) {
                    Text(discreetMode ? discreetMasker.author(author.name) : author.name)
                        .font(.footnote.weight(.medium))
                    Text("\(author.works) read · \(ReadingInsights.compactWordsLabel(author.words)) words · \(author.finished) finished")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondaryInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let charactersPerHour: Double
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

            if charactersPerHour > 0 {
                recordTile(
                    title: "Character pace",
                    value: String(format: "%.1fk", charactersPerHour / 1000.0),
                    detail: "characters an hour"
                )
            }
        }
    }

    private func recordTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
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
                    .foregroundStyle(.secondaryInk)
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
                    .foregroundStyle(.secondaryInk)
                    .lineLimit(1)
            }
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Hidden section's top row (owner, 2026-11-19): hidden mature works' reading is
/// summarized on its own, below the main figures. Locked, this row is all there is: it
/// names no work, fandom or count, and offers the shared reveal control.
struct InsightsHiddenHeader: View {
    let isRevealed: Bool
    /// The main figures above include hidden works too (Include Hidden).
    let includesHidden: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var theme

    private var caption: String {
        if !isRevealed { return "Mature works are kept out of Insights." }
        return includesHidden
            ? "Hidden mature works only. The figures above include them."
            : "Hidden mature works only. The figures above leave them out."
    }

    var body: some View {
        // Side by side until accessibility sizes, where the reveal button needs its own line.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        layout {
            HStack(spacing: 10) {
                Image(systemName: isRevealed ? "eye" : "eye.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondaryInk)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hidden")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)

            MatureRevealToggle()
                .font(.subheadline.weight(.medium))
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

struct FinishedInPeriodSection: View {
    let works: [SavedWork]
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
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
                                        let displayName = discreetMode ? discreetMasker.fandom(fandom) : fandom
                                        Text(displayName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondaryInk)
                                    }
                                }

                                Text(discreetMode ? discreetMasker.work(id: work.id, title: work.title) : work.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                let wordStr = work.wordCount > 0 ? "\(work.wordCount.formatted()) words" : ""
                                Text(wordStr)
                                    .font(.caption2)
                                    .foregroundStyle(.secondaryInk)
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
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    private var displayedChips: [String] {
        guard discreetMode else { return taste.usualFicTags }
        if !taste.usualChips.isEmpty {
            return taste.usualChips.map { chip in
                if chip.text == "varied" { return "varied" }
                switch chip.kind {
                case .metadata: return chip.text
                case .fandom: return discreetMasker.fandom(chip.text)
                case .tag: return discreetMasker.tag(chip.text)
                case .ship: return discreetMasker.ship(chip.text)
                }
            }
        }
        return taste.usualFicTags.indices.map { index in
            "Tag \(InsightsDiscreetMasker.letterCode(for: index))"
        }
    }

    var body: some View {
        let status = discreetMode ? discreetMasker : InsightsDiscreetMasker.empty
        let summaryText: String = {
            if taste.usualFicTags.isEmpty { return taste.usualFicSummary }
            if !discreetMode { return taste.usualFicSummary }
            let topTag = taste.usualTopTag.map { status.tag($0) } ?? "varied"
            let secondTag = taste.usualSecondTag.map { status.tag($0) } ?? "varied"
            let topFandom = taste.usualTopFandom.map { status.fandom($0) } ?? "varied"
            let topRel = taste.usualTopRelationship.map { status.ship($0) } ?? "varied"
            return "Usually \(taste.usualStatus) · \(taste.usualRating) · \(taste.usualCategory) · \(taste.usualLengthBand) · \(topFandom) · \(topRel) · \(topTag) · \(secondTag)."
        }()

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Usual Fic")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("from \(taste.totalWorksCount) works")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            }

            Text(summaryText)
                .font(.system(.title3, design: .serif))
                .lineSpacing(4)
                .foregroundStyle(.primary)

            let chips = displayedChips
            if !chips.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(chips.indices, id: \.self) { index in
                        Text(chips[index])
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
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    private var sortedFandoms: [ReadingInsights.FandomWordsShare] {
        // Keep `"Everything else"` last regardless of rank mode.
        fandoms.sorted { (lhs: ReadingInsights.FandomWordsShare, rhs: ReadingInsights.FandomWordsShare) -> Bool in
            if lhs.isRemainder != rhs.isRemainder { return !lhs.isRemainder }
            if rankByWorks {
                if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
                if lhs.words != rhs.words { return lhs.words > rhs.words }
            } else {
                if lhs.words != rhs.words { return lhs.words > rhs.words }
                if lhs.worksCount != rhs.worksCount { return lhs.worksCount > rhs.worksCount }
            }
            return lhs.name < rhs.name
        }
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
                            let name = discreetMode && !f.isRemainder ? discreetMasker.fandom(f.name) : f.name
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            let worksText = "\(f.worksCount) \(f.worksCount == 1 ? "work" : "works")"
                            if rankByWorks {
                                if f.words > 0 {
                                    Text(formatK(f.words))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondaryInk)
                                }
                                Text(worksText)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .fixedSize()
                                    .frame(minWidth: 44, alignment: .trailing)
                            } else {
                                Text(worksText)
                                    .font(.caption)
                                    .foregroundStyle(.secondaryInk)

                                Text(formatK(f.words))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .fixedSize()
                                    .frame(minWidth: 44, alignment: .trailing)
                            }
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
        ReadingInsights.compactWordsLabel(words)
    }
}

struct TasteRelationshipsCard: View {
    let relationships: [RelationshipShare]
    let shipConcentrations: [ShipConcentration]
    let rankByWorks: Bool
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
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
                            let name = discreetMode ? discreetMasker.ship(rel.name) : rel.name
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                if !rel.fandom.isEmpty {
                                    Circle()
                                        .fill(fandomColor(for: rel.fandom))
                                        .frame(width: 6, height: 6)
                                }
                                let fandomSegment = rel.fandom.isEmpty
                                    ? ""
                                    : "\(discreetMode ? discreetMasker.fandom(rel.fandom) : rel.fandom) · "
                                Text("\(rel.isRomantic ? "Romantic" : "Platonic") · \(fandomSegment)\(rel.worksCount) \(rel.worksCount == 1 ? "work" : "works")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondaryInk)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(rankByWorks ? "\(rel.worksCount)" : formatK(rel.words))
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
                                let displayName = discreetMode ? discreetMasker.fandom(ship.fandom) : ship.fandom
                                Text(displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 110, alignment: .leading)

                                GeometryReader { proxy in
                                    let ratio = min(1.0, max(0.0, CGFloat(ship.percentage) / 100.0))
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                        .overlay(alignment: .leading) {
                                            Capsule()
                                                .fill(fandomColor(for: ship.fandom))
                                                .frame(width: proxy.size.width * ratio)
                                        }
                                }
                                .frame(height: 6)

                                Text(ship.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondaryInk)
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
        ReadingInsights.compactWordsLabel(words)
    }
}

struct TasteCharactersCard: View {
    let characters: [ReadingTasteInsights.CharacterShare]
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Characters")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            FlowLayout(spacing: 8) {
                ForEach(Array(characters.prefix(9).enumerated()), id: \.element.id) { _, char in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(fandomColor(for: char.fandom))
                            .frame(width: 7, height: 7)
                        let displayName = discreetMode ? discreetMasker.character(char.name) : char.name
                        Text(displayName)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                        Text("\(char.count)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondaryInk)
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
    let rankByWorks: Bool
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    private var maxWords: Int {
        rankByWorks ? max(1, tags.map(\.count).max() ?? 1) : max(1, tags.map(\.words).max() ?? 1)
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
                            let name = discreetMode ? discreetMasker.tag(tag.name) : tag.name
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            let worksLabel = "\(tag.count) \(tag.count == 1 ? "work" : "works")"
                            Text(rankByWorks ? worksLabel : ReadingInsights.compactWordsLabel(tag.words))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }

                        GeometryReader { proxy in
                            let value = rankByWorks ? tag.count : tag.words
                            let ratio = min(1.0, max(0.04, Double(value) / Double(maxWords)))
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(theme.accentInk)
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
                                let label = discreetMode
                                    ? "\(discreetMasker.tag(pair.tagA)) + \(discreetMasker.tag(pair.tagB))"
                                    : "\(pair.tagA) + \(pair.tagB)"
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(.secondaryInk)
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
    let statuses: [ReadingTasteInsights.CountBreakdown]
    let categories: [ReadingTasteInsights.CountBreakdown]
    let warnings: [ReadingTasteInsights.CountBreakdown]
    let rankByWorks: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 12) {
            breakdownCard(title: "Rating", items: ratings)
            breakdownCard(title: "Status", items: statuses)
            breakdownCard(title: "Category", items: categories)
            breakdownCard(title: "Warnings", items: warnings)
            Text("A work may have several categories or warnings, so those totals may exceed works read.")
                .font(.caption2)
                .foregroundStyle(.secondaryInk)
        }
    }

    private func breakdownCard(title: String, items: [ReadingTasteInsights.CountBreakdown]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            // All four bars use the same works/words denominator. Multiple
            // categories or warnings can therefore add to over 100%.
            let total = max(1, ratings.reduce(0) { partial, row in
                partial + (rankByWorks ? row.count : row.words)
            })
            VStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Text(item.label)
                            .font(.caption)
                            .frame(width: 110, alignment: .leading)
                            .lineLimit(1)

                        GeometryReader { proxy in
                            let value = rankByWorks ? item.count : item.words
                            let ratio = min(1.0, max(0.04, Double(value) / Double(total)))
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(theme.accentInk)
                                        .frame(width: proxy.size.width * ratio)
                                }
                        }
                        .frame(height: 5)

                        Text(rankByWorks ? "\(item.count)" : ReadingInsights.compactWordsLabel(item.words))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 36, alignment: .trailing)
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
                    .foregroundStyle(.secondaryInk)
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
            .foregroundStyle(.secondaryInk)
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
                    .foregroundStyle(.secondaryInk)
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
                    .foregroundStyle(.secondaryInk)
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
    var hideReadingTime: Bool = false
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
                    .foregroundStyle(.secondaryInk)
            }

            // 24-hour bar chart
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(hourly) { item in
                        let height = max(3.0, (item.seconds / maxSeconds) * 86.0)
                        let isLateNight = item.hour >= 1 && item.hour < 5
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.seconds > 0 ? (isLateNight ? theme.accentInk.opacity(0.6) : theme.accentInk) : Color.primary.opacity(0.08))
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
                .foregroundStyle(.secondaryInk)
            }

            let durationText = hideReadingTime ? "—" : ReadingInsights.durationLabel(lateNightDuration)
            Text("Late night, 1:00–5:00: \(durationText) (\(lateNightSharePercent)%)")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
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
    let thresholds: [Int]
    var totalDaysElapsed: Int? = nil
    var isMonthPeriod: Bool = false
    @Environment(ThemeManager.self) private var theme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    /// True only for a real single-month period with a contiguous 1…N day sequence
    /// inside one calendar month; never true for Year-mode active-day lists.
    static func isContiguousMonthGrid(
        days: [ReadingInsights.DailyWordsBucket],
        isMonthPeriod: Bool,
        calendar: Calendar = .current
    ) -> Bool {
        guard isMonthPeriod, !days.isEmpty, days.count <= 31, let first = days.first else {
            return false
        }
        let firstParts = calendar.dateComponents([.year, .month], from: first.date)
        for (offset, bucket) in days.enumerated() {
            guard bucket.dayNumber == offset + 1 else { return false }
            let parts = calendar.dateComponents([.year, .month], from: bucket.date)
            guard parts.year == firstParts.year && parts.month == firstParts.month else {
                return false
            }
        }
        return true
    }

    private var isMonthGrid: Bool {
        Self.isContiguousMonthGrid(days: days, isMonthPeriod: isMonthPeriod)
    }

    private var leadingBlankCount: Int {
        guard isMonthGrid, let firstDate = days.first?.date else { return 0 }
        // Calendar.weekday: 1 = Sun, 2 = Mon, ..., 7 = Sat -> Mon-first offset = (weekday + 5) % 7.
        let weekday = Calendar.current.component(.weekday, from: firstDate)
        return (weekday + 5) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reading Days")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                let readingDays = days.filter { $0.hasReading || $0.words > 0 }.count
                let elapsed = totalDaysElapsed ?? days.count
                Text("\(readingDays) of \(elapsed)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondaryInk)
            }

            if isMonthGrid {
                HStack {
                    ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, day in
                        Text(day)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            // Days grid
            LazyVGrid(columns: columns, spacing: 6) {
                if leadingBlankCount > 0 {
                    ForEach(0..<leadingBlankCount, id: \.self) { _ in
                        Color.clear
                            .frame(height: 32)
                            .accessibilityHidden(true)
                    }
                }
                ForEach(days) { day in
                    let tier = heatTier(for: day)
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(tierColor(tier))
                            .frame(height: 32)

                        Text("\(day.dayNumber)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(
                                tier >= 2
                                    ? AnyShapeStyle(ThemeManager.label(on: theme.accentInk))
                                    : AnyShapeStyle(.secondaryInk)
                            )
                            .padding(4)
                    }
                }
            }

            // Legend & Streak
            HStack {
                Text("Longest streak \(longestStreak) \(longestStreak == 1 ? "day" : "days")")
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)

                Spacer()

                HStack(spacing: 3) {
                    Text("Less")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(0..<5, id: \.self) { tier in
                        swatch(tierColor(tier))
                    }
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

    private func heatTier(for day: ReadingInsights.DailyWordsBucket) -> Int {
        guard day.words > 0 || day.hasReading else { return 0 }
        guard day.words > 0 else { return 1 }
        let q1 = thresholds.indices.contains(0) ? thresholds[0] : 5_000
        let q2 = thresholds.indices.contains(1) ? thresholds[1] : 10_000
        let q3 = thresholds.indices.contains(2) ? thresholds[2] : 20_000
        if day.words < q1 { return 1 }
        if day.words < q2 { return 2 }
        if day.words < q3 { return 3 }
        return 4
    }

    private func tierColor(_ tier: Int) -> Color {
        switch tier {
        case 0: return Color.primary.opacity(0.06)
        case 1: return theme.accentInk.opacity(0.35)
        case 2: return theme.accentInk.opacity(0.60)
        case 3: return theme.accentInk.opacity(0.82)
        default: return theme.accentInk
        }
    }
}

struct HabitsSittingsCard: View {
    let sittings: [ReadingInsights.SittingBucket]
    let typicalSeconds: Double
    var hideReadingTime: Bool = false
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
                    .foregroundStyle(.secondaryInk)
            }

            // Duration distribution bars
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(sittings) { sit in
                    let height = max(4.0, (Double(sit.count) / Double(maxCount)) * 64.0)
                    VStack(spacing: 2) {
                        Text("\(sit.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(sit.count > 0 ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondaryInk))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(sit.count > 0 ? theme.accentInk : Color.primary.opacity(0.08))
                            .frame(height: height)
                        Text(sit.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondaryInk)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 90)

            Divider()
                .overlay(theme.appTheme.cardBorder)

            HStack {
                statColumn(label: "Typical sitting", value: hideReadingTime ? "—" : ReadingInsights.durationLabel(typicalSeconds))
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
                .foregroundStyle(.secondaryInk)
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
    let savedToOpenedCount: Int
    let openedToFinishedCount: Int
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
                    .fill(theme.accentInk.opacity(0.55))
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(theme.accentInk)
                    .frame(height: 2)
                Circle()
                    .fill(theme.accentInk)
                    .frame(width: 12, height: 12)
            }

            HStack {
                Text("Saved")
                    .font(.caption2)
                    .foregroundStyle(.secondaryInk)
                Spacer()
                Text("Opened")
                    .font(.caption2)
                    .foregroundStyle(.secondaryInk)
                Spacer()
                Text("Finished")
                    .font(.caption2)
                    .foregroundStyle(.secondaryInk)
            }

            HStack(spacing: 12) {
                if let days = savedToOpenedDays {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(days) days")
                            .font(.headline)
                        Text("saved to opened, median")
                            .font(.caption2)
                            .foregroundStyle(.secondaryInk)
                        Text("\(savedToOpenedCount) works")
                            .font(.caption2)
                            .foregroundStyle(.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let days = openedToFinishedDays {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(days) days")
                            .font(.headline)
                        Text("opened to finished, median")
                            .font(.caption2)
                            .foregroundStyle(.secondaryInk)
                        Text("\(openedToFinishedCount) works")
                            .font(.caption2)
                            .foregroundStyle(.secondaryInk)
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
    let rereadTimeShare: Double?
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rereads")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            if let rereadTimeShare {
                Text("\(Int((rereadTimeShare * 100).rounded()))% of reading time")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                if rereads.isEmpty {
                    Text("Works you complete multiple times will appear here as rereads.")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                        .padding(16)
                } else {
                    ForEach(Array(rereads.prefix(3).enumerated()), id: \.element.id) { index, work in
                        if index > 0 {
                            Divider()
                                .overlay(theme.appTheme.cardBorder)
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(discreetMode ? discreetMasker.work(id: work.id, title: work.title) : work.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                let fandomPrefix = work.fandom.isEmpty
                                    ? ""
                                    : "\(discreetMode ? discreetMasker.fandom(work.fandom) : work.fandom) · "
                                Text("\(fandomPrefix)\(work.totalWordsAcrossReads.formatted()) words across reads")
                                    .font(.caption2)
                                    .foregroundStyle(.secondaryInk)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text("×\(work.finishCount)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(theme.accentInk)
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
    var year: Int = 0
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    private let monthInitials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    private var yearSubtitle: String? {
        guard year > 0 else { return nil }
        let currentYear = Calendar.current.component(.year, from: Date())
        return year == currentYear ? "\(year) so far" : "\(year)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fandom Timeline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let yearSubtitle {
                    Text(yearSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }

            if lanes.isEmpty {
                Text("Monthly activity by fandom will appear here as you log reading sessions.")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(lanes.enumerated()), id: \.element.id) { _, lane in
                        let isRemainder = lane.name == ReadingInsights.remainderName
                        HStack(spacing: 6) {
                            let label = discreetMode && !isRemainder
                                ? discreetMasker.fandom(lane.name) : lane.name
                            Text(label)
                                .font(.caption)
                                .foregroundStyle(isRemainder ? AnyShapeStyle(.secondaryInk) : AnyShapeStyle(Color.primary))
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

                    HStack(spacing: 6) {
                        Spacer()
                            .frame(width: 90)
                        HStack(spacing: 3) {
                            ForEach(Array(monthInitials.enumerated()), id: \.offset) { _, initial in
                                Text(initial)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .accessibilityHidden(true)
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
        if fandom == ReadingInsights.remainderName {
            if tier == 1 { return Color.secondary.opacity(0.22) }
            if tier == 2 { return Color.secondary.opacity(0.45) }
            return Color.secondary.opacity(0.72)
        }
        let hue = CoverArt.workHue(fandoms: [fandom], title: "")
        let base = theme.appTheme.subjectPalette(hue: hue).accent
        if tier == 1 { return base.opacity(0.3) }
        if tier == 2 { return base.opacity(0.65) }
        return base
    }
}

struct HabitsStoppedCard: View {
    let stoppedCount: Int
    let stoppedInPeriodCount: Int
    let medianProgress: Double?
    let reasons: [ReadingHabitsInsights.StopReasonCount]
    let commonTags: [(name: String, count: Int)]
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stopped Reading")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(stoppedInPeriodCount) this period · \(stoppedCount) in all")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            }

            if let medianProgress {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int((medianProgress * 100).rounded()))%")
                        .font(.title2.weight(.bold))
                    Text("of the way in, typically")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }

            ForEach(reasons) { reason in
                HStack {
                    Text(reason.label)
                    Spacer()
                    Text("\(reason.count)").monospacedDigit()
                }
                .font(.footnote)
            }

            if !commonTags.isEmpty {
                Divider()
                    .overlay(theme.appTheme.cardBorder)

                Text("Common in Stopped Works")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                FlowLayout(spacing: 6) {
                    ForEach(Array(commonTags.enumerated()), id: \.offset) { _, tag in
                        Text("\(discreetMode ? discreetMasker.tag(tag.name) : tag.name) \(tag.count)")
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
    let monthsToClearRange: ClosedRange<Int>?
    let addedWords: Int
    let readWords: Int
    @Environment(ThemeManager.self) private var theme
    @Environment(\.secondaryInk) private var secondaryInk

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unread in your library")
                .font(.footnote)
                .foregroundStyle(.secondaryInk)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatWords(unreadWords))
                    .font(.system(size: 38, weight: .bold))
                    .monospacedDigit()
                Text("words · \(unreadCount) works")
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
            }

            if let m = monthsToClear, m > 0 {
                Text("About \(m) month\(m == 1 ? "" : "s") at this pace")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            } else if let range = monthsToClearRange {
                if range.lowerBound == range.upperBound {
                    Text("About \(range.lowerBound) month\(range.lowerBound == 1 ? "" : "s") at this pace")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                } else {
                    Text("About \(range.lowerBound) to \(range.upperBound) months at this pace")
                        .font(.footnote)
                        .foregroundStyle(.secondaryInk)
                }
            }

            Divider()
                .overlay(theme.appTheme.cardBorder)

            // Added vs Read
            VStack(spacing: 6) {
                let maxW = max(1, max(addedWords, readWords))
                barRow(label: "Added", words: addedWords, color: secondaryInk ?? Color.secondary, maxVal: maxW)
                barRow(label: "Read", words: readWords, color: theme.accentInk, maxVal: maxW)
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
                .foregroundStyle(.secondaryInk)
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
        return ReadingInsights.compactWordsLabel(words)
    }

    private func formatK(_ words: Int) -> String {
        ReadingInsights.compactWordsLabel(words)
    }
}

struct LibraryWhereEverythingStandsCard: View {
    let partition: ReadingStatusPartition
    @Environment(ThemeManager.self) private var theme
    @Environment(\.secondaryInk) private var secondaryInk

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
                statusRow(icon: "pause.circle.fill", color: secondaryInk ?? Color.secondary, label: "On Hold", count: partition.onHoldCount)
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
                        .foregroundStyle(.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondaryInk)

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
    var discreetMasker: InsightsDiscreetMasker = .empty
    let onStillReading: () -> Void
    let onStoppedReading: () -> Void
    @Environment(ThemeManager.self) private var theme

    private var untouchedDurationLabel: String {
        let days = max(1, candidate.daysUntouched)
        if days >= 14 || days % 7 == 0 {
            let weeks = max(1, days / 7)
            return "\(weeks) \(weeks == 1 ? "week" : "weeks")"
        }
        return "\(days) \(days == 1 ? "day" : "days")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if !candidate.fandom.isEmpty {
                        Circle()
                            .fill(fandomColor(for: candidate.fandom))
                            .frame(width: 8, height: 8)
                    }
                    let fandomPrefix = candidate.fandom.isEmpty
                        ? ""
                        : "\(discreetMode ? discreetMasker.fandom(candidate.fandom) : candidate.fandom) · "
                    Text("\(fandomPrefix)untouched for \(untouchedDurationLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                }

                let workLabel = discreetMode
                    ? discreetMasker.work(id: candidate.id, title: candidate.title) : candidate.title
                Text("Still reading \(workLabel)?")
                    .font(.subheadline.weight(.semibold))

                let progressText = discreetMode && !candidate.discreetChapterProgress.isEmpty
                    ? candidate.discreetChapterProgress
                    : candidate.chapterProgress
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)
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
            Button("Stopped Reading?") { onStoppedReading() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.effectiveTint)
                .accessibilityHint("Record a reason or put this work on hold")
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
                    .foregroundStyle(.secondaryInk)
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
                .foregroundStyle(.secondaryInk)
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
                .foregroundStyle(.secondaryInk)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text("No Longer on AO3")
                    .font(.subheadline.weight(.semibold))
                Text("\(count) works · \(formatWords(words)) words · \(lastCopies) kept as your last copy")
                    .font(.caption2)
                    .foregroundStyle(.secondaryInk)
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
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On Finished Works")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            feedbackRow(label: "Kudos left", percent: kudosLeftPercent)
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
                            .fill(theme.accentInk)
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
    var discreetMasker: InsightsDiscreetMasker = .empty
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
                        Text(discreetMode ? discreetMasker.fandom(f.name) : f.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text("\(f.count) \(f.count == 1 ? "work" : "works")")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondaryInk)
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
                .foregroundStyle(.secondaryInk)
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
