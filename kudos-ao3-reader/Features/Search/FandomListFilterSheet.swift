import SwiftUI

/// Artboard 1an: the Browse category filter sheet. Hide-switches show how many
/// tags they would remove; the positive switches (favourited, downloads,
/// more-than-one-tag) show how many rows they would keep. Tag-kind and library
/// switches count tags; "more than one tag" counts families.
struct FandomListFilterSheet: View {
    @Binding var options: FandomListFilterOptions
    let families: [FandomFamily]
    let library: FandomLibraryIndex
    var palette: SubjectPalette
    var onApply: () -> Void
    var onReset: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    private var tallies: FandomFamilyFilterTallies {
        FandomFamilyFilters.tallies(families, library: library)
    }

    private var remainingTagCount: Int {
        FandomFamilyFilters.tagCount(
            in: FandomFamilyFilters.apply(families, options: options, library: library)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    minimumWorksBlock
                    spacer
                    sectionLabel("Tag kinds")
                    toggleRow(
                        title: "Hide RPF tags",
                        detail: tagCountLabel(tallies.rpfTags),
                        isOn: $options.hideRPF
                    )
                    rowDivider
                    toggleRow(
                        title: "Hide All Media Types umbrellas",
                        detail: tagCountLabel(tallies.allMediaTypesTags),
                        isOn: $options.hideAllMediaTypes
                    )
                    rowDivider
                    toggleRow(
                        title: "Hide Related Fandoms groupings",
                        detail: tagCountLabel(tallies.relatedFandomsTags),
                        isOn: $options.hideRelatedFandoms
                    )
                    spacer
                    sectionLabel("Yours")
                    toggleRow(
                        title: "Favourited only",
                        detail: tagCountLabel(tallies.favouritedTags),
                        isOn: $options.favouritedOnly
                    )
                    rowDivider
                    toggleRow(
                        title: "I have downloads from",
                        detail: tagCountLabel(tallies.downloadTags),
                        isOn: $options.downloadsOnly
                    )
                    spacer
                    sectionLabel("Grouping")
                    toggleRow(
                        title: "Only fandoms with more than one tag",
                        detail: familyCountLabel(tallies.multiTagFamilies),
                        isOn: $options.multiTagOnly
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                applyButton
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                    .background(
                        LinearGradient(
                            colors: [
                                themeManager.appTheme.cardBackdrop.opacity(0),
                                themeManager.appTheme.cardBackdrop,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .background(themeManager.appTheme.cardBackdrop)
            .navigationTitle("Filter")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset", action: onReset)
                            .disabled(!options.hasActiveFilters)
                    }
                }
        }
    }

    private var minimumWorksBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Minimum works")
            SubjectSegmentedControl(
                options: FandomListFilterOptions.MinimumWorks.allCases,
                title: { $0.title },
                selection: $options.minimumWorks
            )
            if options.minimumWorks != .any {
                Text(minimumWorksCaption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var minimumWorksCaption: String {
        let count = tallies.tagsBelowMinimumWorks(options.minimumWorks)
        let formatted = count.formatted()
        return "\(formatted) tags in this category hold fewer than \(options.minimumWorks.title.replacingOccurrences(of: "+", with: "")) works."
    }

    private var spacer: some View { Color.clear.frame(height: 24) }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .tint(palette.accent)
        .padding(.vertical, 11)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(themeManager.appTheme.glassStroke(0.11))
            .frame(height: 0.5)
    }

    private var applyButton: some View {
        Button(action: onApply) {
            Text("Show \(remainingTagCount.formatted()) tags")
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(palette.accentOnFill)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.accent)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(remainingTagCount.formatted()) tags")
    }

    private func tagCountLabel(_ count: Int) -> String {
        count == 1 ? "1 tag" : "\(count.formatted()) tags"
    }

    private func familyCountLabel(_ count: Int) -> String {
        count == 1 ? "1 fandom" : "\(count.formatted()) fandoms"
    }
}
