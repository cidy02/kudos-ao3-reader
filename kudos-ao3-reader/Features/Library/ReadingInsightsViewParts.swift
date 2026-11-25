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
        String(format: "%.1fk", Double(words) / 1000.0)
    }
}

struct ReadingAndListeningCard: View {
    let readingSeconds: Double
    let silentReadingSeconds: Double
    let listeningSeconds: Double
    let hideReadingTime: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading and Listening")
                .font(.subheadline.weight(.semibold))
            timeRow("Time reading", seconds: readingSeconds)
            timeRow("Reading", seconds: silentReadingSeconds)
            timeRow("Read Aloud", seconds: listeningSeconds)
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
        )
    }

    private func timeRow(_ title: String, seconds: Double) -> some View {
        HStack {
            Text(title).font(.footnote).foregroundStyle(.secondaryInk)
            Spacer()
            Text(hideReadingTime ? "—" : ReadingInsights.durationLabel(seconds))
                .font(.footnote.weight(.semibold)).monospacedDigit()
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
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How Finished Works Arrived").font(.subheadline.weight(.semibold))
            if let since {
                Text("Recorded since \(since.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondaryInk)
            }
            ForEach(rows) { row in
                HStack {
                    Text(row.label).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(row.finished) finished · \(row.saved) saved · \(row.saved == 0 ? 0 : Int((Double(row.finished) / Double(row.saved) * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondaryInk)
                }
                .font(.footnote)
            }
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
    }
}

struct LibraryFoundEarlyCard: View {
    let count: Int
    let grownCount: Int
    let grownShare: Double?
    let example: String?
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Found Early").font(.subheadline.weight(.semibold))
            Text("\(count) finished works had fewer than 500 kudos when saved")
            Text("\(grownCount) have at least tripled since")
            if let grownShare {
                Text("\(Int((grownShare * 100).rounded()))% of the recorded group")
                    .foregroundStyle(.secondaryInk)
            }
            if let example, !discreetMode {
                Text(example).foregroundStyle(.secondaryInk)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
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
            if figure.judgedSittings > 0 {
                metric("Skimmed", value: "\(figure.skimmedWords) words left out of totals")
            } else {
                metric("Skimmed", value: "No chapter pace history yet")
            }
            metric("Peeked at the Ending", value: "\(figure.peekedWorks) works")
        }
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
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

struct LibraryFavouritesAndSeriesCard: View {
    let favoritesWithoutKudos: Int
    let seriesStarted: Int
    let seriesReadToLast: Int
    let nextWaiting: Int
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favourites Without Kudos").font(.subheadline.weight(.semibold))
            Text("\(favoritesWithoutKudos) finished favorites or rereads")
            Divider()
            Text("Series").font(.subheadline.weight(.semibold))
            Text("\(seriesStarted) started · \(seriesReadToLast) read to the last part")
            Text("\(nextWaiting) with a next part waiting").foregroundStyle(.secondaryInk)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
    }
}

struct LibraryAuthorsCard: View {
    let authors: [ReadingLibraryInsights.AuthorRow]
    let discreetMode: Bool
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authors").font(.subheadline.weight(.semibold))
            ForEach(authors.prefix(5)) { author in
                VStack(alignment: .leading, spacing: 2) {
                    Text(discreetMode ? "Author" : author.name).font(.footnote.weight(.medium))
                    Text("\(author.works) read · \(author.words) words · \(author.finished) finished")
                        .font(.caption).foregroundStyle(.secondaryInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.appTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
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
                switch chip.kind {
                case .metadata: return chip.text
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
            let workStatus = taste.usualStatus.isEmpty ? "complete" : taste.usualStatus
            let rating = taste.usualRating.isEmpty ? "Teen" : taste.usualRating
            let cat = taste.usualCategory.isEmpty ? "F/M" : taste.usualCategory
            let topTag = taste.usualTopTag.map { status.tag($0) } ?? "Tag A"
            let topFandom = taste.usualTopFandom.map { status.fandom($0) } ?? "Fandom A"
            let topRel = taste.usualTopRelationship.map { status.ship($0) } ?? ""
            let extraTags = taste.usualExtraTagNames.map { status.tag($0) }.joined(separator: " and ")
            if !topRel.isEmpty && !extraTags.isEmpty {
                return "A \(workStatus), \(rating)-rated \(cat) \(topTag) in \(topFandom), "
                    + "50–150k words long, with \(topRel), \(extraTags)."
            }
            return "A \(workStatus), \(rating)-rated \(cat) \(topTag) in \(topFandom)."
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
                            let name = discreetMode && !f.isRemainder ? discreetMasker.fandom(f.name) : f.name
                            Text(name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(f.worksCount) \(f.worksCount == 1 ? "work" : "works")")
                                .font(.caption)
                                .foregroundStyle(.secondaryInk)

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
                                Circle()
                                    .fill(fandomColor(for: rel.fandom))
                                    .frame(width: 6, height: 6)
                                let fandomLabel = discreetMode ? discreetMasker.fandom(rel.fandom) : rel.fandom
                                Text("\(rel.isRomantic ? "Romantic" : "Platonic") · \(fandomLabel) · \(rel.worksCount) \(rel.worksCount == 1 ? "work" : "works")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondaryInk)
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
                                let displayName = discreetMode ? discreetMasker.fandom(ship.fandom) : ship.fandom
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
        String(format: "%.1fk", Double(words) / 1000.0)
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
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
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
                            let name = discreetMode ? discreetMasker.tag(tag.name) : tag.name
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
                                        .fill(theme.accentInk)
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
                    .foregroundStyle(.secondaryInk)
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
                            .foregroundStyle(day.words > 10_000 ? AnyShapeStyle(ThemeManager.label(on: theme.accentInk)) : AnyShapeStyle(.secondaryInk))
                            .padding(4)
                    }
                }
            }

            // Legend & Streak
            HStack {
                Text("Longest streak \(longestStreak) days")
                    .font(.caption)
                    .foregroundStyle(.secondaryInk)

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
        if words < thresholds[0] { return theme.accentInk.opacity(0.55) }
        if words < thresholds[1] { return theme.accentInk.opacity(0.70) }
        if words < thresholds[2] { return theme.accentInk.opacity(0.85) }
        return theme.accentInk
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
                                Text("\(discreetMode ? discreetMasker.fandom(work.fandom) : work.fandom) · \(work.totalWordsAcrossReads.formatted()) words across reads")
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
    let discreetMode: Bool
    var discreetMasker: InsightsDiscreetMasker = .empty
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fandom Timeline")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if lanes.isEmpty {
                Text("Monthly activity by fandom will appear here as you log reading sessions.")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(lanes.enumerated()), id: \.element.id) { _, lane in
                        HStack(spacing: 6) {
                            Text(discreetMode ? discreetMasker.fandom(lane.name) : lane.name)
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
                Text("About \(m) month\(m == 1 ? "" : "s") at your recent pace")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
            } else if let range = monthsToClearRange {
                Text("About \(range.lowerBound) to \(range.upperBound) months at this pace")
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
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
        return "\(words / 1000)k"
    }

    private func formatK(_ words: Int) -> String {
        String(format: "%.1fk", Double(words) / 1000.0)
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
                    Circle()
                        .fill(fandomColor(for: candidate.fandom))
                        .frame(width: 8, height: 8)
                    let fandomLabel = discreetMode
                        ? discreetMasker.fandom(candidate.fandom) : candidate.fandom
                    Text("\(fandomLabel) · untouched for \(untouchedDurationLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                }

                let workLabel = discreetMode
                    ? discreetMasker.work(id: candidate.id, title: candidate.title) : candidate.title
                Text("Still reading \(workLabel)?")
                    .font(.subheadline.weight(.semibold))

                Text(candidate.chapterProgress)
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
