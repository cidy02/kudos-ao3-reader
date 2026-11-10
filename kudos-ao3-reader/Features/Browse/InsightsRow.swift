import SwiftUI

/// "Insights" on a fandom or tag works page: the sidebar's most-used relationships,
/// characters and tags as one scrolling row of chips. Tapping a chip adds it as an
/// include filter. Draws nothing when the page carried no sidebar.
struct InsightsRow: View {
    let facets: AO3SearchFacets
    let palette: SubjectPalette
    let onSelect: (AO3FacetEntry, AO3SearchFacets.Kind) -> Void

    @State private var chosen: AO3SearchFacets.Kind = .relationships

    private var kinds: [AO3SearchFacets.Kind] {
        AO3SearchFacets.Kind.allCases.filter { !facets.entries($0).isEmpty }
    }

    var body: some View {
        if !facets.isEmpty {
            let kind = kinds.contains(chosen) ? chosen : (kinds.first ?? .relationships)
            VStack(alignment: .leading, spacing: 6) {
                // Title and switch on one line while they fit; stacked at large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        insightsTitle
                        Spacer(minLength: 0)
                        kindPicker.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        insightsTitle
                        kindPicker
                    }
                }
                .padding(.horizontal, SubjectMetrics.gutter)
                SubjectFilterRail {
                    ForEach(facets.entries(kind)) { entry in
                        Button { onSelect(entry, kind) } label: { chip(entry, kind: kind) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.name), \(entry.count.formatted()) works")
                            .accessibilityHint("Adds it as a filter")
                    }
                }
            }
        }
    }

    private var insightsTitle: some View {
        Text("Insights").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
    }

    private var kindPicker: some View {
        Picker("Insights", selection: $chosen) {
            ForEach(kinds, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func chip(_ entry: AO3FacetEntry, kind: AO3SearchFacets.Kind) -> some View {
        let tinted = kind == .relationships
        return HStack(spacing: 6) {
            Text(entry.name).fontWeight(.semibold)
            Text(InsightsCountFormat.short(entry.count))
                .fontWeight(.medium).monospacedDigit().opacity(0.7)
        }
        .font(.subheadline)
        .lineLimit(1)
        .foregroundStyle(tinted ? palette.accent : Color.primary)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(tinted ? palette.chipFill : Color.primary.opacity(0.08), in: Capsule())
    }
}
