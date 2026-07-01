import SwiftUI
import SwiftData

/// Fills the Search tab's idle state with a live browse of AO3's media categories
/// (scraped from `/media`). On iOS, tapping a category pushes a dedicated fandom
/// list; on macOS it expands inline to the featured fandoms.
///
/// Each category card is enriched with real fandom/work counts (from the same
/// per-category fandom index the detail page uses, cached in `FandomCatalog`),
/// the user's saved-work count in that category, and recently-read fandom chips.
struct MediaBrowserView: View {
    var onSelectFandom: (String) -> Void

    @Query private var library: [SavedWork]

    @State private var categories: [AO3MediaCategory] = []
    @State private var phase: Phase = .loading
    /// Shared, per-launch cache of each category's fandom list.
    private let catalog = FandomCatalog.shared
    #if os(macOS)
    /// Tracked explicitly (keyed by category name) so a row's expansion can't be
    /// recycled onto a different category as the List scrolls.
    @State private var expanded: Set<String> = []
    #endif

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                CategoryCardSkeletonList()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load fandoms", systemImage: "wifi.slash")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            case .loaded:
                categoryList
            }
        }
        .task { if categories.isEmpty { await load() } }
    }

    private var categoryList: some View {
        List {
            Section {
                ForEach(categories) { category in
                    #if os(iOS)
                    NavigationLink(value: category) {
                        categoryCard(category)
                    }
                    #else
                    DisclosureGroup(isExpanded: expansionBinding(for: category.id)) {
                        ForEach(category.fandoms) { fandom in
                            Button {
                                onSelectFandom(fandom.name)
                            } label: {
                                Text(fandom.name)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } label: {
                        categoryCard(category)
                    }
                    #endif
                }
                .cardRow()   // cards only on the category rows
            } header: {
                Text("Browse by fandom")
            }

            // Instruction as a clear-background row, not a Section footer: a plain
            // list row with no listRowBackground falls back to white under Sepia's
            // light scheme, so clear it to let the warm backdrop show through.
            instructions
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 12, trailing: 20))
        }
        .cardList()
    }

    /// Instructional caption shown under the category list.
    private var instructions: Text {
        #if os(iOS)
        Text("Browse fandoms from AO3. Tap a category to see its fandoms.")
        #else
        Text("Popular fandoms from AO3. Tap one to search its works.")
        #endif
    }

    // MARK: - Card

    /// The enriched category card: an emphasized icon + regular-weight name, a stats
    /// line, and (when present) a divider + recently-read chips.
    private func categoryCard(_ category: AO3MediaCategory) -> some View {
        let stats = stats(for: category)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.headline)              // icon stays emphasized
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                Text(category.name)
                    .font(.headline.weight(.regular))   // regular weight (was bold)
                    .foregroundStyle(.primary)
            }

            statsLine(stats)

            if !stats.recentFandoms.isEmpty {
                Divider()
                recentlyRead(stats.recentFandoms)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statsLine(_ stats: CategoryStats) -> some View {
        FlowLayout(spacing: 16, rowSpacing: 4) {
            if let count = stats.fandomCount {
                statItem("books.vertical", "\(count.formatted()) fandoms")
                if let works = stats.workCount {
                    statItem("doc.text", "~\(compact(works)) works")
                }
            } else {
                // Counts for this category are still loading (no extra request) — show
                // a quiet stat-line skeleton instead of a "Counting…" spinner.
                SkeletonBlock(height: 11, width: 104, cornerRadius: 4)
                    .skeletonShimmer()
            }
            if stats.savedCount > 0 {
                statItem("bookmark.fill", "\(stats.savedCount) saved")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func statItem(_ symbol: String, _ text: String) -> some View {
        // Icon hugs its label and is bold + tinted — matches the Search/Library
        // result-card stats for visual consistency.
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)
            Text(text)
        }
        .fixedSize()
    }

    /// Recently-read fandom chips — clearly secondary to the stats. Tapping a chip
    /// runs a search filtered to that fandom.
    private func recentlyRead(_ fandoms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Recently read")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(fandoms, id: \.self) { fandom in
                    // Borderless so the chip's tap runs the fandom search instead of
                    // following the card's navigation link.
                    Button { onSelectFandom(fandom) } label: {
                        TagChip(text: fandom)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Stats

    private struct CategoryStats {
        /// nil while the category's fandom list is still loading.
        var fandomCount: Int?
        var workCount: Int?
        var savedCount: Int
        var recentFandoms: [String]
    }

    private func stats(for category: AO3MediaCategory) -> CategoryStats {
        let list = catalog.fandoms(for: category)
        // Match the user's works to this category by fandom name — using the full
        // fetched list when available, else the featured fandoms while it loads.
        let names = list?.map(\.name) ?? category.fandoms.map(\.name)
        let nameSet = Set(names.map { $0.lowercased() })

        func inCategory(_ work: SavedWork) -> Bool {
            work.workFandoms.contains { nameSet.contains($0.lowercased()) }
        }

        var recent: [String] = []
        var seen = Set<String>()
        for work in library.filter({ $0.hasBeenRead }).sorted(by: { $0.dateAdded > $1.dateAdded }) {
            for fandom in work.workFandoms where nameSet.contains(fandom.lowercased()) {
                if seen.insert(fandom.lowercased()).inserted { recent.append(fandom) }
            }
            if recent.count >= 3 { break }
        }

        return CategoryStats(
            fandomCount: list?.count,
            workCount: list.map { $0.reduce(0) { $0 + ($1.workCount ?? 0) } },
            savedCount: library.filter(inCategory).count,
            recentFandoms: Array(recent.prefix(3))
        )
    }

    /// 1_234_567 → "1.2M".
    private func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName))
    }

    #if os(macOS)
    private func expansionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
    #endif

    private func load() async {
        phase = .loading
        do {
            categories = try await AO3Client.shared.mediaCategories()
            phase = .loaded
            // Fill in per-category fandom counts/lists in the background; the cards
            // update as each lands.
            await catalog.loadMissing(for: categories)
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private extension SavedWork {
    /// The user has opened this work at least once (has reader progress / finished).
    var hasBeenRead: Bool {
        isFinished || lastSpineIndex > 0
    }
}
