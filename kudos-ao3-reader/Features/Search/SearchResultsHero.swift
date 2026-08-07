import SwiftUI

/// AO3's own result-count line plus the filters producing it:
///
///     Naruto (Anime & Manga)                    1–20
///     142,327 works
///     [Sort: Date Updated] [English] [Complete]
///
/// The total is the one fact a page of blurbs cannot tell you — the app knows it
/// has 20 works and how many pages there are, but "how big is this fandom" exists
/// only in AO3's heading. The chips answer the other half: until now nothing on
/// screen said what was filtering a list once the panel was dismissed, only a
/// filter button that changed colour.
///
/// Tapping anywhere opens the filter panel, which is what makes the chips worth
/// their height — they are the control, not a caption about it.
struct SearchResultsHero: View {
    let summary: AO3ResultSummary
    /// From `AO3SearchFilters.summaryLabels(excluding:)` — non-default settings
    /// only, always ending with the sort.
    var filterLabels: [AO3SearchFilters.SummaryLabel] = []
    var onEditFilters: (() -> Void)?

    /// Beyond this the chips would crowd out the works. The overflow is *counted*
    /// rather than silently dropped, so the card never implies it listed everything.
    private static let visibleChipLimit = 6

    var body: some View {
        if let onEditFilters {
            Button(action: onEditFilters) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(spokenLabel))
                .accessibilityHint(Text("Opens filters"))
                .accessibilityAddTraits(.isButton)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(spokenLabel))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                // Only tag and user lists name a subject or state a range; a plain
                // search has neither, so its card starts at the count rather than
                // padding out a title row with something invented.
                if summary.subject != nil || summary.range != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let subject = summary.subject {
                            Text(subject)
                                .font(.headline)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }
                        Spacer(minLength: 0)
                        if let range = summary.range {
                            // Tinted rather than the neutral capsule the filter
                            // chips use: it is a status, not another filter, and
                            // side by side they would otherwise read as the same
                            // kind of thing.
                            TagChip(text: "\(range.lowerBound)–\(range.upperBound)", tinted: true)
                                // Fixed-width digits so paging doesn't resize the
                                // badge, and priority so a long fandom name shrinks
                                // before the badge is squeezed out.
                                .monospacedDigit()
                                .layoutPriority(1)
                        }
                    }
                }

                // Icon tinted by `WorkStatLabel`'s `.tint`, so it tracks the app
                // theme like every other stat glyph; the text inherits the
                // secondary style set here.
                //
                // `square.stack` because the author profile already labels its own
                // "N works" with it — and because `books.vertical` is the *fandom*
                // glyph, which on the Search card can appear as a chip one line
                // below. Two different things must not share an icon in the same
                // card.
                WorkStatLabel(text: countText, symbol: "square.stack")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if !filterLabels.isEmpty {
                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(visibleChips, id: \.self) { TagChip(text: $0.text, symbol: $0.symbol) }
                    if overflowCount > 0 { TagChip(text: "+\(overflowCount) more") }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var visibleChips: [AO3SearchFilters.SummaryLabel] {
        Array(filterLabels.prefix(Self.visibleChipLimit))
    }

    private var overflowCount: Int {
        max(0, filterLabels.count - Self.visibleChipLimit)
    }

    private var countText: String {
        "\(summary.total.formatted()) \(summary.total == 1 ? "work" : "works")"
    }

    /// Preview-only: wraps plain strings so the previews stay readable.
    fileprivate static func previewLabels(_ texts: [String]) -> [AO3SearchFilters.SummaryLabel] {
        texts.map { AO3SearchFilters.SummaryLabel(text: $0, symbol: nil) }
    }

    private var spokenLabel: String {
        var parts = [countText]
        // The verbatim scope, preposition included — "in Naruto (Anime & Manga)"
        // reads correctly aloud where the bare subject used as a heading does not.
        if let scope = summary.scope { parts.append(scope) }
        if let range = summary.range {
            parts.append("showing \(range.lowerBound) to \(range.upperBound)")
        }
        // Every filter, not just the six on screen — the visual cap is about space.
        parts += filterLabels.map(\.text)
        return parts.joined(separator: ", ")
    }
}

#Preview("Browse — fandom with filters") {
    SearchResultsHero(
        summary: AO3ResultSummary(total: 142_327, scope: "in Naruto (Anime & Manga)", range: 1 ... 20),
        filterLabels: SearchResultsHero.previewLabels(["English", "Complete", "Teen And Up+", "Sort: Date Updated"]),
        onEditFilters: {}
    )
    .padding()
}

#Preview("Browse — nothing set") {
    SearchResultsHero(
        summary: AO3ResultSummary(total: 142_327, scope: "in Naruto (Anime & Manga)", range: 1 ... 20),
        filterLabels: SearchResultsHero.previewLabels(["Sort: Date Updated"]),
        onEditFilters: {}
    )
    .padding()
}

#Preview("Overflow") {
    SearchResultsHero(
        summary: AO3ResultSummary(total: 812, scope: "in Naruto (Anime & Manga)", range: 21 ... 40),
        filterLabels: SearchResultsHero.previewLabels([
            "Sasuke Uchiha", "−Time Travel", "Explicit", "No Not Rated",
            "Major Character Death", "Complete", "Words ≥ 1000", "Past week", "Sort: Kudos"
        ]),
        onEditFilters: {}
    )
    .padding()
}

#Preview("Search — no subject or range") {
    SearchResultsHero(
        summary: AO3ResultSummary(total: 92_495, scope: nil, range: 1 ... 20),
        filterLabels: SearchResultsHero.previewLabels(["Sort: Best Match"]),
        onEditFilters: {}
    )
    .padding()
}
