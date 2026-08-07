import SwiftUI

/// AO3's own result-count line, shown above a works list.
///
/// The total is the one fact a page of blurbs cannot tell you — the app knows it
/// has 20 works and how many pages there are, but "how big is this fandom" only
/// exists in AO3's heading. AO3 prints it as `92,495 Found` on `/works/search` and
/// `1 - 20 of 142,322 Works in <tag>` on a tag or user list; the range is dropped
/// here because the pagination row already says which page you are on, and the
/// scope is kept verbatim so this reads the way the site does.
struct SearchResultsHero: View {
    let summary: AO3ResultSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(summary.total, format: .number)
                .font(.largeTitle.weight(.semibold))
                // Monospaced digits so paging between counts of different widths
                // doesn't shuffle the layout; numericText so it rolls rather than
                // hard-cuts when a new search lands.
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        // One VoiceOver stop reading "142,322 works in Naruto", not a bare number
        // followed by an orphaned phrase.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(summary.total.formatted()) \(caption)"))
        .accessibilityAddTraits(.isHeader)
    }

    /// "works in Naruto (Anime & Manga)", "works by astolat", or plain "works
    /// found" when AO3 named no subject.
    private var caption: String {
        let noun = summary.total == 1 ? "work" : "works"
        guard let scope = summary.scope else { return "\(noun) found" }
        return "\(noun) \(scope)"
    }
}

#Preview("Tag") {
    SearchResultsHero(summary: AO3ResultSummary(total: 142_322, scope: "in Naruto (Anime & Manga)"))
        .padding()
}

#Preview("Search") {
    SearchResultsHero(summary: AO3ResultSummary(total: 92_495, scope: nil))
        .padding()
}

#Preview("Single") {
    SearchResultsHero(summary: AO3ResultSummary(total: 1, scope: "by astolat"))
        .padding()
}
