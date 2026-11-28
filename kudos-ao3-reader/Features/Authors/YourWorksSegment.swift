import SwiftUI

/// Segments for the own-profile works screen (board 41).
enum YourWorksSegment: String, CaseIterable, Hashable, Identifiable, Sendable {
    case works = "Works"
    case series = "Series"
    case drafts = "Drafts"

    var id: String { rawValue }

    /// Formats a segment title with an optional count (e.g. "Works · 6", "Drafts").
    static func formatTitle(label: String, count: String?) -> String {
        guard let count, !count.trimmingCharacters(in: .whitespaces).isEmpty else {
            return label
        }
        return "\(label) · \(count)"
    }

    /// Formats this segment's title with an optional count.
    func title(count: String?) -> String {
        Self.formatTitle(label: rawValue, count: count)
    }
}

/// Segmented control on Your Works (board 41): Works · N / Series · N / Drafts · N.
struct YourWorksSegmentControl: View {
    let currentTab: AO3AuthorProfileTab
    let worksCount: String?
    let seriesCount: String?
    let draftsCount: String?
    let onSelectTab: (AO3AuthorProfileTab) -> Void
    let onSelectDrafts: () -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 6) {
                    segmentButtons
                }
            } else {
                HStack(spacing: 2) {
                    segmentButtons
                }
            }
        }
        .padding(2)
        .background(themeManager.appTheme.glassFill(), in: SubjectMetrics.controlShape(dynamicTypeSize))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your Works Sections")
    }

    @ViewBuilder
    private var segmentButtons: some View {
        segmentButton(
            segment: .works,
            title: YourWorksSegment.works.title(count: worksCount),
            isSelected: currentTab == .works
        ) {
            onSelectTab(.works)
        }
        segmentButton(
            segment: .series,
            title: YourWorksSegment.series.title(count: seriesCount),
            isSelected: currentTab == .series
        ) {
            onSelectTab(.series)
        }
        segmentButton(
            segment: .drafts,
            title: YourWorksSegment.drafts.title(count: draftsCount),
            isSelected: false
        ) {
            onSelectDrafts()
        }
    }

    private func segmentButton(
        segment: YourWorksSegment,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondaryInk))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 32)
                .background {
                    if isSelected {
                        SubjectMetrics.controlShape(dynamicTypeSize)
                            .fill(themeManager.appTheme.cardSurface)
                    }
                }
                .contentShape(SubjectMetrics.controlShape(dynamicTypeSize))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
