import SwiftUI

/// Multi-tag family block: title once, members listed with the qualifier as
/// the primary text. Single-tag families keep `FandomListRow` and never reach
/// this view — no tint, no "All N tags" marker.
struct FandomFamilyBlock: View {
    let family: FandomFamily
    let sort: FandomFamilySort
    let library: FandomLibraryIndex
    var palette: SubjectPalette
    var onSelectFamily: () -> Void
    var onSelectMember: (FandomFamily.Member) -> Void

    @Environment(\.workCardTransitionNamespace) private var zoomNamespace
    @Environment(ThemeManager.self) private var themeManager
    @ScaledMetric(relativeTo: .caption) private var starSize = 14.5
    @ScaledMetric(relativeTo: .caption2) private var downloadFontSize = 11.5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelectFamily) {
                header
            }
            .buttonStyle(.plain)
            .workCardZoomSource(BrowseZoomKey.fandom(family.zoomKey), in: zoomNamespace)

            memberList
                .padding(.leading, 35)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(palette.accent.opacity(0.32))
                        .frame(width: 1.5)
                        .padding(.leading, 21)
                }
        }
        .padding(.vertical, 4)
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
                if sort == .familyTotal {
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
                }

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
                    memberRow(member, libraryEntry: library.entry(for: member.originalName))
                }
                .buttonStyle(.plain)
                .workCardZoomSource(BrowseZoomKey.fandom(member.originalName), in: zoomNamespace)
            }
        }
        .padding(.top, 8)
    }

    private func memberRow(
        _ member: FandomFamily.Member,
        libraryEntry: FandomLibraryIndex.Entry
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            if libraryEntry.isFavourite {
                Image(systemName: "star.fill")
                    .font(.system(size: starSize))
                    .foregroundStyle(Color.subjectFavoriteGold)
                    .accessibilityLabel("Favorite")
            }

            Text(member.qualifierDisplay)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if libraryEntry.downloadedWorkCount > 0 {
                downloadBadge(count: libraryEntry.downloadedWorkCount)
            }

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

    private func downloadBadge(count: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.down.circle")
            Text(count.compactCount)
        }
        .font(.system(size: downloadFontSize, weight: .medium, design: .monospaced))
        .foregroundStyle(downloadTint)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count.formatted()) downloaded works")
    }

    private var downloadTint: Color {
        guard let mint = SubjectHueSwatches.all.first(where: { $0.name == "Mint" }) else {
            return themeManager.appTheme.statusSuccessColor
        }
        return themeManager.appTheme.subjectPalette(hue: mint.hue).accent
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

/// Sort chips (A–Z / Most works) and Group variants. Filter is the toolbar's
/// (owner, 2026-10-01: global actions live in the top-right chrome).
struct FandomListSortRail: View {
    @Binding var sort: FandomFamilySort
    /// 1al's "Group variants" switch: tinted while on.
    @Binding var groupsVariants: Bool
    var palette: SubjectPalette

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
                    Button {
                        groupsVariants.toggle()
                    } label: {
                        SubjectChip(
                            text: "Group variants",
                            style: groupsVariants ? .tinted : .neutral,
                            systemImage: "square.stack",
                            palette: palette
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(groupsVariants ? .isSelected : [])
                }
            }

        }
    }
}
