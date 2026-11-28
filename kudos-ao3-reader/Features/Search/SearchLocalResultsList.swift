import SwiftData
import SwiftUI

/// Search's on-device matches, shown live as the user types: works, fandoms,
/// tags and collections from the library, plus an explicit "Search AO3" action
/// (no AO3 request fires until the user taps it or submits). Split out of
/// `SearchView` for its file length; the selection state stays there because
/// the toolbar acts on it.
struct SearchLocalResultsList: View {
    let query: String
    let matches: SearchView.LocalMatches
    /// The matched works, already stripped of invalidated models.
    let works: [SavedWork]
    var chips: [SearchLocalChip] = []
    @Binding var isSelecting: Bool
    @Binding var selection: Set<UUID>
    let onSearchAO3: () -> Void
    let onSearchFandom: (String) -> Void

    @Environment(AppRouter.self) private var router
    @State private var pendingDelete: SavedWork?
    @State private var pendingRemoval: PendingLibraryRemoval?

    var body: some View {
        // A deletion re-keys the compute task via the record counts, but a render
        // can land in the gap before the debounce fires — drop invalidated models
        // rather than touching them (SwiftData asserts on invalidated access).
        let matchedCollections = matches.collections.filter { $0.modelContext != nil }
        List {
            Section {
                Button(action: onSearchAO3) {
                    Label("Search AO3 for “\(query)”", systemImage: "magnifyingglass")
                }
            } header: {
                sectionHeader("Archive of Our Own")
            }

            if !works.isEmpty {
                Section {
                    // `SensitiveWorkRow`, as Library's lists: the privacy gate, the
                    // shared long-press menu, and selection (T-339).
                    ForEach(works) { work in
                        let isSelected = selection.contains(work.id)
                        SensitiveWorkRow(
                            work: work,
                            onSelect: { isSelecting = true; selection = [work.id] },
                            isSelecting: isSelecting,
                            isSelected: isSelected,
                            onToggleSelection: { toggle(work) },
                            leadingSelection: isSelecting
                        )
                        .cardRow(isSelected: isSelecting && isSelected, chrome: .plain)
                        // Any kind but History takes the swipes' default branch.
                        .libraryWorkSwipeActions(
                            work,
                            kind: .readingNow,
                            isFavoritesList: false,
                            pendingDelete: $pendingDelete,
                            pendingRemoval: $pendingRemoval
                        )
                    }
                } header: {
                    sectionHeader("In your library", count: works.count)
                }
            }
            if !chips.isEmpty {
                Section {
                    SearchLocalChipsView(
                        chips: chips,
                        collections: matchedCollections,
                        onTagTap: { router.filterLibrary(.userTag, $0) },
                        onFandomTap: { router.filterLibrary(.fandom, $0) }
                    )
                    .pageBodyRow(top: 6, gutter: SubjectMetrics.gutter)
                } header: {
                    sectionHeader(SearchCombinedResultsLogic.chipsSectionTitle)
                }
            }
            if !matches.ao3Fandoms.isEmpty {
                Section {
                    ForEach(Array(matches.ao3Fandoms.enumerated()), id: \.element.id) { index, fandom in
                        SearchAO3FandomRow(
                            fandom: fandom,
                            showsTopSeparator: index > 0,
                            onSearchFandom: onSearchFandom
                        )
                        .cardRow(chrome: .plain)
                    }
                } header: {
                    sectionHeader(SearchCombinedResultsLogic.ao3FandomsSectionTitle)
                }
            }
        }
        .cardList()
        .appScreenSurface(.content)
        .libraryWorkRemovalConfirmations(pendingDelete: $pendingDelete, pendingRemoval: $pendingRemoval)
    }

    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        SectionRuleHeader(title: title, count: count)
            .textCase(nil)
            .listRowInsets(EdgeInsets())
    }

    private func toggle(_ work: SavedWork) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }
}

/// An AO3 fandom match row with name, work count, and chevron (Board 11).
/// Shared between `SearchLocalResultsList` (live typing) and `SearchView` (combined results).
struct SearchAO3FandomRow: View {
    let fandom: AO3Fandom
    var showsTopSeparator = false
    let onSearchFandom: (String) -> Void

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static func countText(for count: Int?) -> String? {
        count?.compactCount
    }

    static func accessibilityLabel(for fandom: AO3Fandom) -> String {
        guard let count = fandom.workCount else { return fandom.name }
        return "\(fandom.name), \(count.formatted()) \(count == 1 ? "work" : "works")"
    }

    var body: some View {
        Button {
            onSearchFandom(fandom.name)
        } label: {
            HStack(spacing: 8) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fandom.name)
                            .font(.body)
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let count = Self.countText(for: fandom.workCount) {
                            Text(count)
                                .font(.subheadline)
                                .foregroundStyle(.secondaryInk)
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 8)
                } else {
                    Text(fandom.name)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: 8)
                    if let count = Self.countText(for: fandom.workCount) {
                        Text(count)
                            .font(.subheadline)
                            .foregroundStyle(.secondaryInk)
                            .monospacedDigit()
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 10 : 0)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if showsTopSeparator {
                    Rectangle()
                        .fill(themeManager.appTheme.glassStroke(0.14))
                        .frame(height: 0.5)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.accessibilityLabel(for: fandom))
    }
}
