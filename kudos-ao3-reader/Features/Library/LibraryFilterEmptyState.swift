import SwiftUI

/// Actionable empty state when Library filters hide every work on the page.
/// States the hidden count, names the filters that collide, offers single-filter
/// drops with real remaining counts, and keeps Clear as the last resort.
struct LibraryFilterCollisionCard: View {
    let sectionTitle: String
    let hiddenCount: Int
    @Binding var filters: LibraryFilters
    let works: [SavedWork]
    let palette: SubjectPalette
    var onEdit: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    private var drops: [LibraryFilters.FilterDrop] {
        filters.droppingEachActiveFilter(from: works)
    }

    private var revealingDrops: [LibraryFilters.FilterDrop] {
        drops.filter { $0.remainingCount > 0 }
    }

    private var activeLabels: [String] {
        filters.summaryLabels(includesSort: false).map(\.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 7) {
                Text(collisionTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(collisionDetail)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !revealingDrops.isEmpty {
                Rectangle()
                    .fill(themeManager.appTheme.glassStroke(0.12))
                    .frame(height: 0.5)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Drop one filter")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.85)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                    VStack(spacing: 7) {
                        ForEach(revealingDrops, id: \.filterLabel) { drop in
                            Button {
                                filters = drop.remainingFilters
                            } label: {
                                HStack(spacing: 9) {
                                    Text("Without \(drop.filterLabel)")
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(workCountText(drop.remainingCount))
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.accent)
                                        .fixedSize()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(themeManager.appTheme.glassFill(0.07))
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "Without \(drop.filterLabel), \(workCountText(drop.remainingCount))"
                            )
                        }
                    }
                }
            }

            HStack(spacing: 9) {
                Button {
                    filters = LibraryFilters()
                } label: {
                    Text("Clear all filters")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(clearLabelColor)
                        .background(
                            Capsule().fill(themeManager.appTheme.errorColor)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear all filters")

                Button(action: onEdit) {
                    Text("Edit")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .foregroundStyle(.primary)
                        .overlay(
                            Capsule().strokeBorder(
                                themeManager.appTheme.glassStroke(0.24),
                                lineWidth: 0.5
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .subjectPanel(cornerRadius: 18)
    }

    private var collisionTitle: String {
        switch activeLabels.count {
        case 0: "Nothing matches."
        case 1: "Nothing matches this filter."
        case 2: "Nothing matches both filters."
        case 3: "Nothing matches all three filters."
        case 4: "Nothing matches all four filters."
        case 5: "Nothing matches all five filters."
        default: "Nothing matches all \(activeLabels.count) filters."
        }
    }

    private var collisionDetail: String {
        let hidden = hiddenCount == 1
            ? "The 1 work in \(sectionTitle) is hidden."
            : "All \(hiddenCount) works in \(sectionTitle) are hidden."
        guard activeLabels.count >= 2 else { return hidden }
        return hidden + " " + joinedList(activeLabels) + " have no works in common here."
    }

    private var clearLabelColor: Color {
        themeManager.appTheme.errorColor.relativeLuminance > 0.45 ? Color.black : Color.white
    }

    private func workCountText(_ count: Int) -> String {
        count == 1 ? "1 work" : "\(count) works"
    }

    private func joinedList(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default:
            names.dropLast().joined(separator: ", ") + ", and " + (names.last ?? "")
        }
    }
}
