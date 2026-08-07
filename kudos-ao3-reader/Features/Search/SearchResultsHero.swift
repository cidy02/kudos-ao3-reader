import SwiftUI

/// AO3's own result-count line, shown above a works list:
///
///     Naruto (Anime & Manga)                    1–20
///     142,322 works
///
/// The total is the one fact a page of blurbs cannot tell you — the app knows it
/// has 20 works and how many pages there are, but "how big is this fandom" exists
/// only in AO3's heading. AO3 prints the whole thing as `92,495 Found` on
/// `/works/search` and `1 - 20 of 142,322 Works in <tag>` on a tag or user list.
struct SearchResultsHero: View {
    let summary: AO3ResultSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Only tag and user lists name a subject or state a range; a plain
            // search has neither, so its card is the count line alone rather than
            // a title row padded out with something invented.
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
                        Text("\(range.lowerBound)–\(range.upperBound)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            // Fixed-width digits so paging doesn't jiggle the row,
                            // and no truncation: a long fandom name must shrink
                            // before the range disappears.
                            .monospacedDigit()
                            .layoutPriority(1)
                    }
                }
            }

            Text(countText)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        // One VoiceOver stop reading "142,322 works in Naruto (Anime & Manga),
        // showing 1 to 20", not three orphaned fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityAddTraits(.isHeader)
    }

    private var countText: String {
        "\(summary.total.formatted()) \(summary.total == 1 ? "work" : "works")"
    }

    private var spokenLabel: String {
        var parts = [countText]
        // The verbatim scope, preposition included — "in Naruto (Anime & Manga)"
        // reads correctly aloud where the bare subject used as a heading does not.
        if let scope = summary.scope { parts.append(scope) }
        if let range = summary.range {
            parts.append("showing \(range.lowerBound) to \(range.upperBound)")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Tag") {
    SearchResultsHero(summary: AO3ResultSummary(
        total: 142_322, scope: "in Naruto (Anime & Manga)", range: 1 ... 20
    ))
    .padding()
}

#Preview("Long tag name") {
    SearchResultsHero(summary: AO3ResultSummary(
        total: 3401,
        scope: "in Marvel Cinematic Universe - All Media Types & Related Fandoms",
        range: 981 ... 1000
    ))
    .padding()
}

#Preview("User") {
    SearchResultsHero(summary: AO3ResultSummary(total: 535, scope: "by astolat", range: 1 ... 20))
        .padding()
}

#Preview("Search — no subject or range") {
    SearchResultsHero(summary: AO3ResultSummary(total: 92_495, scope: nil, range: nil))
        .padding()
}

#Preview("Single result") {
    SearchResultsHero(summary: AO3ResultSummary(total: 1, scope: "in Some Tiny Tag", range: 1 ... 1))
        .padding()
}
