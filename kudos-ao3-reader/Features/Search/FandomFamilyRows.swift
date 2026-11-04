import SwiftUI

/// Multi-tag family block: title once, members listed with the qualifier as
/// the primary text. Single-tag families keep `FandomListRow` and never reach
/// this view — no tint, no "All N tags" marker.
struct FandomFamilyBlock: View {
    static let leadingInset: CGFloat = 16
    /// Clears the iOS `List` section index column (`★ G S`) on the right edge (Board 14).
    static let trailingInset: CGFloat = 32

    let family: FandomFamily
    let sort: FandomFamilySort
    let library: FandomLibraryIndex
    var palette: SubjectPalette
    var onSelectFamily: () -> Void
    var onSelectMember: (FandomFamily.Member) -> Void

    @Environment(\.workCardTransitionNamespace) private var zoomNamespace
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var starSize = 14.5
    @ScaledMetric(relativeTo: .caption2) private var downloadFontSize = 11.5
    @ScaledMetric(relativeTo: .caption) private var allTagsSize: CGFloat = 11

    /// At the accessibility sizes the figures beside a name took the row and the
    /// name was left a column a letter or two wide ("D / o / ct / or"). There the
    /// name has its own line and the figures go under it; the chevron goes.
    private var stacks: Bool { dynamicTypeSize.isAccessibilitySize }

    private var isFavourite: Bool {
        family.members.contains { library.isFavourited($0.originalName) }
    }

    private var downloadedWorkCount: Int {
        family.members.reduce(0) { $0 + library.entry(for: $1.originalName).downloadedWorkCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelectFamily) {
                header
            }
            .buttonStyle(.plain)
            .workCardZoomSource(BrowseZoomKey.fandom(family.zoomKey), in: zoomNamespace)
            .padding(.leading, Self.leadingInset)
            .padding(.trailing, Self.trailingInset)
            .padding(.vertical, 8)

            memberList
                .padding(.leading, 54)
                .padding(.trailing, Self.trailingInset)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(palette.accent.opacity(0.32))
                        .frame(width: 1.5)
                        .padding(.leading, 30)
                }

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
                .padding(.leading, 54)
                .padding(.trailing, Self.trailingInset)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(CoverArt.workGradient(fandoms: [family.parsedTitle], title: ""))
                .frame(width: 28, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(family.parsedTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isFavourite {
                        Image(systemName: "star.fill")
                            .font(.system(size: starSize))
                            .foregroundStyle(Color.subjectFavoriteGold)
                            .accessibilityLabel("Favorite")
                    }
                }

                ForEach(Array(headerAliases.enumerated()), id: \.offset) { _, alias in
                    aliasText(alias)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let subtitle = FandomSubtitle.text(
                    fandomsCount: family.memberCount,
                    worksCount: family.displayedWorkCount,
                    downloadedCount: downloadedWorkCount
                ) {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text("All \(family.memberCount)")
                    .font(.system(size: allTagsSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(themeManager.accentInk)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
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
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 9))
        return layout {
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
            }

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                if libraryEntry.downloadedWorkCount > 0 {
                    downloadBadge(count: libraryEntry.downloadedWorkCount)
                }

                Text(member.workCount.formatted())
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: stacks ? 0 : 44, alignment: stacks ? .leading : .trailing)
            }

            if !stacks {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
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

/// A–Z section header: letter, family count, hairline. Uses ordinary header ink
/// (`Color.primary`, matching `SectionRuleHeader` and Board 14) rather than an
/// identity hue, and insets the trailing edge to clear the section index column.
struct FandomLetterHeader: View {
    static let titleColor = Color.primary
    static let rowInsets = EdgeInsets(
        top: 14,
        leading: FandomFamilyBlock.leadingInset,
        bottom: 8,
        trailing: FandomFamilyBlock.trailingInset
    )

    let letter: String
    let count: Int
    var palette: SubjectPalette

    var body: some View {
        HStack(spacing: 8) {
            Text(letter)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Self.titleColor)
            Text("\(count)")
                .font(.caption.weight(.medium).monospaced())
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 0.5)
        }
        .textCase(nil)
        .listRowInsets(Self.rowInsets)
    }
}
