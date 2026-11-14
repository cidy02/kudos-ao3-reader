import SwiftUI

/// Reader Response detail sheet (FID40, Quality-Response board).
///
/// Shows the quality figures the app ALREADY computes for that work (kudos/hits ratio,
/// comparison against loaded works of similar shape, the cautious estimate, etc.)
/// laid out per the Quality-Response board.
///
/// Hard rule: every number, band or label comes strictly from real data the app already
/// has. No fake calibration percentiles, no backdating, no invented cadence.
struct QualityResponseSheet: View {
    let work: AO3WorkSummary
    var rankedEntry: RankedWork? = nil
    var signal: WorkSignal? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showingExplainer = false

    private var theme: ReaderTheme { themeManager.appTheme }

    private var figures: LoadedWorksRanker.Figures {
        LoadedWorksRanker.Figures(work, now: Date())
    }

    private var ownKudosPerHit: Double? {
        guard let kudos = figures.kudos, let hits = figures.hits, hits > 0 else { return nil }
        return Double(kudos) / Double(hits)
    }

    private var ownSavesPerKudos: Double? {
        guard let bookmarks = figures.bookmarks, let kudos = figures.kudos, kudos > 0 else { return nil }
        return Double(bookmarks) / Double(kudos)
    }

    private var ownCommentsPerKudos: Double? {
        guard let comments = figures.comments, let kudos = figures.kudos, kudos > 0 else { return nil }
        return Double(comments) / Double(kudos)
    }

    private var confidenceWord: String {
        QualitySignalTones.confidenceWord(forKudos: figures.kudos ?? 0)
    }

    private var confidenceSubtitle: String {
        switch confidenceWord {
        case "Steady":
            "Thousands of readers; the figure is unlikely to move much"
        case "Settling":
            "Hundreds of readers; the figure is settling"
        default:
            "Few readers yet; early figure"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    contextCard
                    statStrip
                    kudosPerHitSection
                    howSureSection
                    otherSignalsSection
                    datesSection
                    explainerSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .appThemedScroll()
            .background(theme.cardBackdrop.ignoresSafeArea())
            .navigationTitle("Reader Response")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                        .sheetConfirmStyle()
                        .accessibilityLabel("Done")
                }
            }
            .sheet(isPresented: $showingExplainer) {
                HowReaderResponseWorksSheet()
            }
        }
    }

    // MARK: - Context Card

    private var contextCard: some View {
        HStack(alignment: .center, spacing: 12) {
            CompactWorkCover(title: work.title, fandoms: work.fandoms)

            VStack(alignment: .leading, spacing: 2) {
                if let kickerText = contextKicker {
                    Text(kickerText.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(kickerColor)
                        .lineLimit(1)
                }

                Text(work.title)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(contextMeta)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.cardBorder, lineWidth: 0.5)
        )
        .combinedAccessibilityRow("\(work.title) by \(work.authorText), \(contextMeta)")
    }

    private var contextKicker: String? {
        if let entry = rankedEntry {
            if entry.isSetAside {
                return "Unusual stats · Not ranked"
            }
            if let pos = entry.rankPosition, let total = entry.totalLoaded {
                let rankName = entry.rankTitle ?? "Reader Response"
                return "\(rankName) · \(pos.ordinalString) of \(total) loaded"
            }
            if let total = entry.totalLoaded {
                return "Not ranked · \(total) loaded"
            }
        }
        return "Reader Response"
    }

    private var kickerColor: Color {
        if rankedEntry?.isSetAside == true {
            return .secondary
        }
        return themeManager.accentInk
    }

    private var contextMeta: String {
        var parts: [String] = [work.authorText]
        if let words = work.words {
            parts.append("\(words.formatted()) words")
        }
        if !work.chapters.isEmpty {
            parts.append(work.chapters)
        }
        let status = (work.isComplete == true) ? "complete" : "in progress"
        parts.append(status)
        return parts.joined(separator: " · ")
    }

    // MARK: - Stats Strip

    private var statStrip: some View {
        let multiplierStr: String = {
            if let score = rankedEntry?.score {
                return "\(QualitySignalTones.decimal(score))×"
            }
            if let own = ownKudosPerHit, let prior = rankedEntry?.prior, prior > 0 {
                return "\(QualitySignalTones.decimal(own / prior))×"
            }
            return "—"
        }()

        let kudosStr = figures.kudos?.formatted() ?? "0"
        let hitsStr = figures.hits?.compactCount ?? "0"
        let savedStr = ownSavesPerKudos.map { "\(Int(round($0 * 100)))%" } ?? "—"

        return SubjectStatStrip(
            cells: [
                SubjectStatStrip.Cell(
                    value: multiplierStr,
                    label: "vs similar",
                    isHighlighted: true,
                    tint: themeManager.accentInk,
                    accessibilityText: "Kudos per hit versus similar: \(multiplierStr)"
                ),
                SubjectStatStrip.Cell(
                    value: kudosStr,
                    label: "Kudos",
                    accessibilityText: "\(kudosStr) kudos"
                ),
                SubjectStatStrip.Cell(
                    value: hitsStr,
                    label: "Hits",
                    accessibilityText: "\(hitsStr) hits"
                ),
                SubjectStatStrip.Cell(
                    value: savedStr,
                    label: "Saved",
                    accessibilityText: "\(savedStr) saved"
                )
            ],
            palette: themeManager.scopePalette
        )
    }

    // MARK: - Kudos per Hit Section

    private var kudosPerHitSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Kudos per Hit")

            VStack(spacing: 0) {
                // Row 1: This work
                let ownRate = ownKudosPerHit ?? 0
                let ownDetail = ownKudosPerHit.map { "\(QualitySignalTones.decimal($0 * 100))%" } ?? "—"
                let ownSub: String = {
                    guard let kudos = figures.kudos, let hits = figures.hits else { return "No hits recorded" }
                    return "\(kudos.formatted()) kudos ÷ \(hits.formatted()) hits"
                }()

                QualityResponseRow(
                    label: "This work",
                    subtitle: ownSub,
                    detail: ownDetail,
                    barFraction: 1.0,
                    barColor: themeManager.accentInk
                )

                // Row 2: Similar works (if prior exists)
                if let prior = rankedEntry?.prior, prior > 0 {
                    Divider().padding(.leading, 16)

                    let priorDetail = "\(QualitySignalTones.decimal(prior * 100))%"
                    let barFrac = ownRate > 0 ? min(1.0, prior / ownRate) : 1.0

                    QualityResponseRow(
                        label: "Similar works",
                        subtitle: similarWorksSubtitle,
                        detail: priorDetail,
                        barFraction: barFrac,
                        barColor: Color.secondary.opacity(0.35)
                    )
                }
            }
            .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.cardBorder, lineWidth: 0.5)
            )

            sectionFooter("AO3 counts one hit per reader per day, so long and serialized works collect more hits for each reader. Similar works are the loaded works of this one’s length and age; with too few of those, of its length, then all loaded works.")
        }
    }

    private var similarWorksSubtitle: String {
        var parts: [String] = []
        if let words = figures.words {
            if words < 10_000 {
                parts.append("Under 10,000 words")
            } else if words < 50_000 {
                parts.append("10,000 to 50,000 words")
            } else {
                parts.append("50,000+ words")
            }
        }
        if let age = figures.ageGroup {
            switch age {
            case 0: parts.append("updated within a year")
            case 1: parts.append("updated 1 to 3 years ago")
            default: parts.append("updated 3+ years ago")
            }
        }
        let status = (work.isComplete == true) ? "complete" : "in progress"
        parts.append(status)
        parts.append("loaded works median")
        return parts.joined(separator: " · ")
    }

    // MARK: - How Sure Section

    private var howSureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("How Sure")

            VStack(spacing: 0) {
                let badgeFg: Color = {
                    switch confidenceWord {
                    case "Steady": theme.statusSuccessColor
                    case "Early": theme.favoriteColor
                    default: Color.secondary
                    }
                }()

                let badgeBg: Color = {
                    switch confidenceWord {
                    case "Steady": theme.statusSuccessColor.opacity(0.15)
                    case "Early": theme.favoriteColor.opacity(0.15)
                    default: Color(.quaternarySystemFill)
                    }
                }()

                QualityResponseRow(
                    label: "Confidence",
                    subtitle: confidenceSubtitle,
                    badge: confidenceWord,
                    badgeBg: badgeBg,
                    badgeFg: badgeFg
                )

                if let score = rankedEntry?.score {
                    Divider().padding(.leading, 16)

                    QualityResponseRow(
                        label: "Cautious estimate",
                        subtitle: "What the ranking uses",
                        detail: "\(QualitySignalTones.decimal(score))×"
                    )
                }
            }
            .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.cardBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Other Signals Section

    @ViewBuilder
    private var otherSignalsSection: some View {
        let hasSaves = ownSavesPerKudos != nil
        let hasComments = ownCommentsPerKudos != nil

        if hasSaves || hasComments {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Other Signals")

                VStack(spacing: 0) {
                    if let saves = ownSavesPerKudos {
                        QualityResponseRow(
                            label: "Saves per kudos",
                            subtitle: "public bookmarks only",
                            detail: "\(QualitySignalTones.decimal(saves * 100))%"
                        )
                    }

                    if let comments = ownCommentsPerKudos {
                        if hasSaves { Divider().padding(.leading, 16) }

                        QualityResponseRow(
                            label: "Comments per kudos",
                            subtitle: "replies included",
                            detail: "\(QualitySignalTones.decimal(comments * 100))%"
                        )
                    }
                }
                .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Dates Section

    @ViewBuilder
    private var datesSection: some View {
        if !work.dateUpdated.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Dates")

                VStack(spacing: 0) {
                    QualityResponseRow(
                        label: "Last chapter",
                        detail: work.dateUpdated
                    )
                }
                .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Explainer Section

    private var explainerSection: some View {
        VStack(spacing: 0) {
            QualityResponseRow(
                label: "How Reader Response Works",
                showsChevron: true
            ) {
                showingExplainer = true
            }
        }
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Section Chrome

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
    }

    private func sectionFooter(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A single row inside a Reader Response section (Quality-Response board).
struct QualityResponseRow: View {
    let label: String
    var subtitle: String? = nil
    var detail: String? = nil
    var badge: String? = nil
    var badgeBg: Color? = nil
    var badgeFg: Color? = nil
    var barFraction: Double? = nil
    var barColor: Color? = nil
    var showsChevron: Bool = false
    var action: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let barFraction, let barColor {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                            Capsule()
                                .fill(barColor)
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(barFraction))))
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            }

            if let badge, !badge.isEmpty {
                Text(badge)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeBg ?? Color(.quaternarySystemFill))
                    .foregroundStyle(badgeFg ?? Color.secondary)
                    .clipShape(Capsule())
                    .layoutPriority(1)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var accessibilityText: String {
        var text = label
        if let subtitle, !subtitle.isEmpty {
            text += ", \(subtitle)"
        }
        if let detail, !detail.isEmpty {
            text += ": \(detail)"
        }
        if let badge, !badge.isEmpty {
            text += ", \(badge)"
        }
        return text
    }
}

/// Explainer sheet detailing the Reader Response method (Quality-Method board).
struct HowReaderResponseWorksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    private var theme: ReaderTheme { themeManager.appTheme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    explainerSection(
                        title: "Why Kudos Ranks Loaded Works",
                        symbol: "chart.line.uptrend.xyaxis",
                        paragraphs: [
                            "AO3 sorts by raw counts (kudos, hits, bookmarks), so old, long, and serialized works dominate while new, short, or niche works sink.",
                            "Kudos compares each work with loaded works of similar length and age to surface works readers responded to strongly."
                        ]
                    )

                    explainerSection(
                        title: "Hits Count Reader-Days",
                        symbol: "calendar.badge.clock",
                        paragraphs: [
                            "On AO3, a hit is counted once per reader per calendar day. Long works and multi-chapter serials collect many hits per reader as they return for each update.",
                            "Dividing kudos by hits without adjustment punishes longer works; comparing works within shape bands levels the field."
                        ]
                    )

                    explainerSection(
                        title: "Rank Cautiously",
                        symbol: "scale.3d",
                        paragraphs: [
                            "With Rank Cautiously on, works with few readers need more evidence to rank high: their rates are pulled toward the loaded median until more readers arrive.",
                            "Confidence bands (Steady, Settling, Early) reflect the volume of reader feedback."
                        ]
                    )

                    explainerSection(
                        title: "Only What You Loaded",
                        symbol: "lock.shield",
                        paragraphs: [
                            "Ranking reorders only the works you have already loaded, on this device. It loads nothing extra unless you ask for Rank Top 100.",
                            "No ratings, summaries, or authors are graded. Kudos only looks at how readers responded."
                        ]
                    )

                    explainerSection(
                        title: "Unusual Stats",
                        symbol: "exclamationmark.triangle",
                        paragraphs: [
                            "Works with unexpected statistics (such as more kudos than hits, or thousands of kudos with almost no bookmarks) are set aside into “Not ranked” rather than assigned an artificial score."
                        ]
                    )
                }
                .padding(16)
            }
            .appThemedScroll()
            .background(theme.cardBackdrop.ignoresSafeArea())
            .navigationTitle("How Reader Response Works")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                        .sheetConfirmStyle()
                        .accessibilityLabel("Done")
                }
            }
        }
    }

    private func explainerSection(title: String, symbol: String, paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(themeManager.accentInk)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.cardBorder, lineWidth: 0.5)
        )
    }
}

extension Int {
    /// 1-based ordinal suffix ("1st", "2nd", "3rd", "4th").
    fileprivate var ordinalString: String {
        let ones = self % 10
        let tens = (self / 10) % 10
        if tens == 1 { return "\(self)th" }
        switch ones {
        case 1: return "\(self)st"
        case 2: return "\(self)nd"
        case 3: return "\(self)rd"
        default: return "\(self)th"
        }
    }
}
