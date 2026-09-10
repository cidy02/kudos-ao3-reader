import SwiftUI

/// Multi-tag family block: title once, members listed with the qualifier as
/// the primary text. Single-tag families keep `FandomListRow` and never reach
/// this view — no tint, no "All N tags" marker.
struct FandomFamilyBlock: View {
    let family: FandomFamily
    var palette: SubjectPalette
    var onSelectFamily: () -> Void
    var onSelectMember: (FandomFamily.Member) -> Void

    @Environment(\.workCardTransitionNamespace) private var zoomNamespace
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelectFamily) {
                header
            }
            .buttonStyle(.plain)
            .workCardZoomSource(BrowseZoomKey.fandom(family.zoomKey), in: zoomNamespace)

            memberList
                .padding(.leading, 21)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(palette.accent.opacity(0.32))
                        .frame(width: 1.5)
                        .padding(.leading, 21)
                }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.accent.opacity(themeManager.appTheme.isDarkFamily ? 0.045 : 0.06))
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(family.parsedTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(headerAliases.enumerated()), id: \.offset) { _, alias in
                    aliasText(alias)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 5) {
                    Text(countLabel)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Image(systemName: "doc.text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(countAccessibilityLabel)

                Text("All \(family.memberCount) tags")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var memberList: some View {
        VStack(spacing: 0) {
            ForEach(Array(family.members.enumerated()), id: \.element.id) { index, member in
                if index > 0 {
                    Rectangle()
                        .fill(themeManager.appTheme.glassStroke(0.10))
                        .frame(height: 0.5)
                }
                Button {
                    onSelectMember(member)
                } label: {
                    memberRow(member)
                }
                .buttonStyle(.plain)
                .workCardZoomSource(BrowseZoomKey.fandom(member.originalName), in: zoomNamespace)
            }
        }
        .padding(.top, 8)
    }

    private func memberRow(_ member: FandomFamily.Member) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(member.qualifierDisplay)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(member.workCount.formatted())
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityLabel(
            "\(member.qualifierDisplay), \(member.workCount.formatted()) works"
        )
    }

    private var headerAliases: [String] {
        family.members.first?.aliases ?? []
    }

    private var countLabel: String {
        family.showsApproximateCount
            ? "~\(family.displayedWorkCount.formatted())"
            : family.displayedWorkCount.formatted()
    }

    private var countAccessibilityLabel: String {
        family.showsApproximateCount
            ? "About \(family.displayedWorkCount.formatted()) works"
            : "\(family.displayedWorkCount.formatted()) works"
    }

    private func aliasText(_ alias: String) -> Text {
        let name = Text(alias)
        return FandomScript.hasItalicForm(alias) ? name.italic() : name
    }
}

/// A–Z section header: letter, family count, hairline. Uses the category
/// palette rather than a hardcoded wash colour so Light / Sepia / OLED keep
/// contrast.
struct FandomLetterHeader: View {
    let letter: String
    let count: Int
    var palette: SubjectPalette

    var body: some View {
        HStack(spacing: 8) {
            Text(letter)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.accent)
            Text("\(count)")
                .font(.caption.weight(.medium).monospaced())
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 0.5)
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 8, trailing: 16))
    }
}

/// Sort chips (A–Z / Most works) plus the dashed Filter affordance.
struct FandomListSortRail: View {
    @Binding var sort: FandomFamilySort
    var filterCount: Int
    var palette: SubjectPalette
    var onOpenFilters: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(FandomFamilySort.allCases, id: \.self) { option in
                        Button {
                            sort = option
                        } label: {
                            SubjectChip(
                                text: option.title,
                                style: .pill(isSelected: sort == option),
                                palette: palette
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(sort == option ? .isSelected : [])
                    }
                }
            }

            Button(action: onOpenFilters) {
                SubjectChip(
                    text: filterCount > 0 ? "Filter \(filterCount)" : "Filter",
                    style: .dashed
                )
            }
            .buttonStyle(.plain)
        }
    }
}
