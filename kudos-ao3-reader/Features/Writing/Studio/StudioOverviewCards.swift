import SwiftUI

/// Card and row building blocks for `StudioOverviewView` (`Studio-Overview.dc.html`,
/// `Studio-Offline.dc.html`), themed across Light, Dark, OLED and Sepia with AX5 reflow.

/// Pure copy helpers for Overview's Today and Continue cards (`Studio-Overview`, `Studio-Offline`).
nonisolated enum StudioTodayCopy {
    static func subtitle(dailyGoal: Int?, streak: Int) -> String {
        var parts: [String] = []
        if let dailyGoal {
            parts.append("of your \(dailyGoal.formatted())-word goal")
        } else {
            parts.append("Daily goal off")
        }
        if streak > 0 {
            parts.append("\(streak)-day streak")
        }
        return parts.joined(separator: " · ")
    }

    static func accessibilityLabel(wordsToday: Int, dailyGoal: Int?, streak: Int) -> String {
        let wordsPart = StudioWorkItem.wordCountLabel(wordsToday)
        let goalPart: String
        if let dailyGoal {
            let percent = StudioWritingGoal.percent(wordsToday: wordsToday, goal: dailyGoal)
            goalPart = "of your \(dailyGoal.formatted())-word goal, \(percent) percent"
        } else {
            goalPart = "daily goal off"
        }
        if streak > 0 {
            return "Today: \(wordsPart), \(goalPart), \(streak)-day streak"
        }
        return "Today: \(wordsPart), \(goalPart)"
    }
}

nonisolated enum StudioContinueCopy {
    static func expiryLine(daysLeft: Int) -> String {
        switch daysLeft {
        case ...0: "AO3 deletes this draft today"
        case 1: "AO3 keeps this draft 1 more day"
        default: "AO3 keeps this draft \(daysLeft) more days"
        }
    }
}

struct StudioTodayCard: View {
    let snapshot: StudioDayLogSnapshot
    let dailyGoal: Int?
    let onTapGoal: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onTapGoal) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        metricsColumn
                        progressRing
                    }
                } else {
                    HStack(alignment: .center, spacing: 14) {
                        metricsColumn
                        progressRing
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .subjectPanel(cornerRadius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            StudioTodayCopy.accessibilityLabel(
                wordsToday: snapshot.wordsToday,
                dailyGoal: dailyGoal,
                streak: snapshot.streak
            )
        )
        .accessibilityHint("Adjusts your daily writing goal")
    }

    private var metricsColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondaryInk)

            Text(StudioWorkItem.wordCountLabel(snapshot.wordsToday))
                .font(.title.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(StudioTodayCopy.subtitle(dailyGoal: dailyGoal, streak: snapshot.streak))
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if !snapshot.recentDays.isEmpty {
                sevenDayBars
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sevenDayBars: some View {
        let maxDayWords = snapshot.recentDays.map(\.words).max() ?? 0
        let ceiling = max(dailyGoal ?? 0, maxDayWords, 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(snapshot.recentDays) { day in
                let ratio = min(1, Double(day.words) / Double(ceiling))
                let barHeight = max(3, CGFloat(ratio) * 32)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(day.isToday ? theme.accentInk : Color.primary.opacity(0.20))
                        .frame(width: 14, height: barHeight)
                    Text(day.weekdayInitial)
                        .font(.caption2.weight(day.isToday ? .bold : .medium))
                        .foregroundStyle(.secondaryInk)
                }
            }
        }
        .frame(height: 48, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var progressRing: some View {
        let progress = StudioWritingGoal.progress(wordsToday: snapshot.wordsToday, goal: dailyGoal)
        let percent = StudioWritingGoal.percent(wordsToday: snapshot.wordsToday, goal: dailyGoal)
        return ZStack {
            Circle()
                .stroke(theme.appTheme.glassStroke(0.24), lineWidth: 7)
            if dailyGoal != nil {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        theme.accentInk,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(percent)%")
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            } else {
                Text("Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
            }
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }
}

struct StudioContinueCard: View {
    let item: StudioContinueItem
    let now: Date
    let onContinue: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var paperBackground: Color {
        StudioTonePalette.paperBackground(for: theme.appTheme)
    }

    private var paperBorder: Color {
        StudioTonePalette.paperBorder(for: theme.appTheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerLine
            excerptBlock
            footerRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(paperBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(paperBorder, lineWidth: 0.5)
                )
        )
        .shadow(
            color: theme.appTheme.cardShadow.color,
            radius: theme.appTheme.cardShadow.radius,
            y: theme.appTheme.cardShadow.y
        )
    }

    private var headerLine: some View {
        let titlePart = Text(workTitle)
            .fontWeight(.semibold)
            .foregroundStyle(Color.primary)
        let detailPart = Text(" · \(contextDetail)")
            .foregroundStyle(.secondaryInk)
        return Text("\(titlePart)\(detailPart)")
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var excerptBlock: some View {
        let text = previewText
        return ZStack(alignment: .bottom) {
            Group {
                if text.isEmpty {
                    Text("Open the editor to start writing your first lines.")
                        .italic()
                        .foregroundStyle(.secondaryInk)
                } else {
                    Text(text)
                        .foregroundStyle(.primary)
                }
            }
            .font(.system(.body, design: .serif))
            .lineSpacing(4)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, text.isEmpty ? 0 : 12)

            if !text.isEmpty {
                LinearGradient(
                    colors: [paperBackground.opacity(0), paperBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 48)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var footerRow: some View {
        let meta = VStack(alignment: .leading, spacing: 2) {
            Text(wordAndEditLine)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let expiryLine = ao3ExpiryLine {
                Text(expiryLine)
                    .font(.footnote)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        let button = Button("Continue", action: onContinue)
            .buttonStyle(.kudosPrimary)
            .accessibilityLabel("Continue writing \(workTitle)")

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                meta
                button
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                meta
                    .frame(maxWidth: .infinity, alignment: .leading)
                button
            }
        }
    }

    private var workTitle: String {
        switch item {
        case let .local(doc):
            doc.displayWorkTitle
        case let .ao3Draft(work, _):
            work.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : work.title
        }
    }

    private var contextDetail: String {
        switch item {
        case let .local(doc):
            let trimmedChapter = doc.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if doc.totalChapters > 1 || !trimmedChapter.isEmpty {
                if trimmedChapter.isEmpty {
                    return "Chapter \(doc.chapterNumber)"
                }
                return "Chapter \(doc.chapterNumber), “\(trimmedChapter)”"
            }
            return "on this \(ThisDevice.name)"
        case .ao3Draft:
            return "AO3 draft"
        }
    }

    private var previewText: String {
        switch item {
        case let .local(doc):
            doc.excerpt
        case let .ao3Draft(work, _):
            work.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var wordAndEditLine: String {
        var parts: [String] = []
        switch item {
        case let .local(doc):
            parts.append(StudioWorkItem.wordCountLabel(doc.wordCount))
            parts.append(StudioDateCopy.editedPhrase(doc.updatedAt, now: now))
        case let .ao3Draft(work, _):
            if let words = work.words {
                parts.append(StudioWorkItem.wordCountLabel(words))
            }
            if !work.dateUpdated.isEmpty {
                parts.append("edited \(StudioDateCopy.shortAO3Date(work.dateUpdated, now: now))")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var ao3ExpiryLine: String? {
        guard case let .ao3Draft(_, deletion) = item,
              let deletion,
              let daysLeft = DraftExpiry.daysLeft(until: deletion, now: now, calendar: .current)
        else { return nil }
        return StudioContinueCopy.expiryLine(daysLeft: daysLeft)
    }
}

struct StudioOverviewCommentRow: View {
    let item: AO3InboxItem
    let now: Date
    let onTap: () -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var timeLabel: String {
        AO3InboxTimeLabel.label(for: item.postedAgo, now: now)?.display ?? item.postedAgo
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        commentContent
                        if item.canReply && !item.isReplied {
                            replyBadge
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 10) {
                        commentContent
                        if item.canReply && !item.isReplied {
                            replyBadge
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens Comments")
    }

    private var commentContent: some View {
        HStack(alignment: .top, spacing: 10) {
            AO3AuthorAvatar(
                url: item.avatarURL,
                name: item.commenterName,
                size: 32,
                isCircular: true
            )
            VStack(alignment: .leading, spacing: 2) {
                let byline = Text(item.commenterName)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.primary)
                let target = item.workTitle.isEmpty ? "" : " on \(item.workTitle)"
                let when = timeLabel.isEmpty ? "" : " · \(timeLabel)"
                let suffix = Text("\(target)\(when)")
                    .foregroundStyle(.secondaryInk)
                Text("\(byline)\(suffix)")
                    .font(.footnote)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)

                if !item.excerpt.isEmpty {
                    Text(item.excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var replyBadge: some View {
        Text("Reply")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.accentInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(StudioTonePalette.softAccentFill(for: theme), in: Capsule())
    }

    private var accessibilityLabel: String {
        var parts = ["Comment from \(item.commenterName)"]
        if !item.workTitle.isEmpty { parts.append("on \(item.workTitle)") }
        if !timeLabel.isEmpty { parts.append(timeLabel) }
        if !item.excerpt.isEmpty { parts.append(item.excerpt) }
        return parts.joined(separator: ", ")
    }
}

struct StudioStatsGlanceGrid: View {
    let stats: AO3UserStats
    let baseline: StudioStatsSnapshot?
    let kudosSparkline: [Double]
    let hitsSparkline: [Double]

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            if let kudos = stats.kudos {
                let change = StudioStatsHistory.change(kudos, since: baseline?.total(.kudos))
                metricCard(
                    title: "Kudos",
                    value: StudioOverviewCopy.statsGlanceValue(total: kudos, change: change),
                    accented: true,
                    sparkline: kudosSparkline
                )
            }
            if let hits = stats.hits {
                let change = StudioStatsHistory.change(hits, since: baseline?.total(.hits))
                metricCard(
                    title: "Hits",
                    value: StudioOverviewCopy.statsGlanceValue(total: hits, change: change),
                    accented: false,
                    sparkline: hitsSparkline
                )
            }
        }
    }

    private func metricCard(
        title: String,
        value: String,
        accented: Bool,
        sparkline: [Double]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondaryInk)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(accented ? AnyShapeStyle(.accentInk) : AnyShapeStyle(Color.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if !sparkline.isEmpty {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(sparkline.enumerated()), id: \.offset) { index, fraction in
                        let isLast = index == sparkline.count - 1
                        let barColor: Color = if isLast {
                            accented ? theme.accentInk : Color.primary.opacity(0.75)
                        } else {
                            Color.primary.opacity(0.20)
                        }
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(barColor)
                            .frame(height: max(3, CGFloat(fraction) * 28))
                    }
                }
                .frame(height: 28, alignment: .bottom)
                .accessibilityHidden(true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .subjectPanel(cornerRadius: SubjectMetrics.cornerRadius)
    }
}

struct StudioRecentPaperCard: View {
    let entry: StudioRecentEntry
    let now: Date
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 112
    @ScaledMetric(relativeTo: .body) private var pageHeight: CGFloat = 146

    private var paperBackground: Color {
        StudioTonePalette.paperBackground(for: theme.appTheme)
    }

    private var paperBorder: Color {
        StudioTonePalette.paperBorder(for: theme.appTheme)
    }

    private var lineColor: Color {
        switch theme.appTheme {
        case .light: Color(red: 0.851, green: 0.831, blue: 0.784)
        case .sepia: Color(red: 0.74, green: 0.67, blue: 0.56).opacity(0.6)
        case .dark, .oled: theme.appTheme.glassStroke(0.24)
        }
    }

    var body: some View {
        let clampedWidth = min(cardWidth, 168)
        let clampedHeight = min(pageHeight, 196)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title)
                        .font(.system(size: 10, weight: .bold, design: .serif))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    ForEach(Array(entry.lineWidths.enumerated()), id: \.offset) { _, fraction in
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(lineColor)
                                .frame(width: max(8, proxy.size.width * fraction), height: 3)
                        }
                        .frame(height: 3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 9)
                .frame(width: clampedWidth, height: clampedHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(paperBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(paperBorder, lineWidth: 0.5)
                        )
                )
                .shadow(
                    color: theme.appTheme.cardShadow.color,
                    radius: theme.appTheme.cardShadow.radius,
                    y: theme.appTheme.cardShadow.y
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(metaLine)
                        .font(.caption)
                        .foregroundStyle(.secondaryInk)
                        .lineLimit(1)
                }
            }
            .frame(width: clampedWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.title), \(metaLine)")
    }

    private var metaLine: String {
        if let editedAt = entry.editedAt {
            let short = StudioDateCopy.shortDate(editedAt, now: now)
            return "\(entry.subtitle) · \(short)"
        }
        if let fallback = entry.editedFallback {
            return "\(entry.subtitle) · \(fallback)"
        }
        return entry.subtitle
    }
}

struct StudioNewDocumentPaperTile: View {
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 112
    @ScaledMetric(relativeTo: .body) private var pageHeight: CGFloat = 146

    var body: some View {
        let clampedWidth = min(cardWidth, 168)
        let clampedHeight = min(pageHeight, 196)
        return Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title2.weight(.medium))
                Text("New Document")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.accentInk)
            .padding(10)
            .frame(width: clampedWidth, height: clampedHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        theme.appTheme.glassStroke(0.32),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New Document")
        .accessibilityHint("Creates a new local document on this \(ThisDevice.name)")
    }
}
