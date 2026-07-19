import OSLog
import SwiftData
import SwiftUI

/// Fills the Search tab's idle state with a live browse of AO3's media categories
/// (scraped from `/media`). On iOS, tapping a category pushes a dedicated fandom
/// list; on macOS it expands inline to the featured fandoms.
///
/// Each category card is enriched with real fandom/work counts (from the same
/// per-category fandom index the detail page uses, cached in `FandomCatalog`),
/// the user's saved-work count in that category, and recently-read fandom chips.
struct MediaBrowserView: View {
    var onSelectFandom: (String) -> Void

    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var library: [SavedWork]

    @State private var categories: [AO3MediaCategory] = []
    @State private var phase: Phase = .loading
    @State private var visibleCategoryIDs: Set<String> = []
    /// Per-category derived stats, recomputed off the render/main path (see
    /// `recomputeStats`); the cards read this rather than deriving inline.
    @State private var statsByCategory: [String: CategoryStats] = [:]
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
            case let .failed(message):
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
        // Derive per-category stats off the main render path, refired (and debounced)
        // whenever a fandom list lands or the library changes.
        .task(id: statsToken) { await recomputeStats() }
    }

    private var categoryList: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Group {
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
                    .onAppear { visibleCategoryIDs.insert(category.id) }
                    .onDisappear { visibleCategoryIDs.remove(category.id) }
                }
                .cardRow() // cards only on the category rows
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
        .refreshable { await refresh() }
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
    /// line, and (when present) a divider + recently-read chips. Reads precomputed
    /// stats (`statsByCategory`) instead of computing them inline — the derivation
    /// scans the category's full fandom list (tens of thousands for the big media
    /// categories) plus the whole library, which must never run per-card during a
    /// render (see `recomputeStats`).
    private func categoryCard(_ category: AO3MediaCategory) -> some View {
        let stats = statsByCategory[category.id]
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.headline) // icon stays emphasized
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                Text(category.name)
                    .font(.headline.weight(.regular)) // regular weight (was bold)
                    .foregroundStyle(.primary)
            }

            statsLine(stats)

            if let stats, !stats.recentFandoms.isEmpty {
                Divider()
                recentlyRead(stats.recentFandoms)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statsLine(_ stats: CategoryStats?) -> some View {
        FlowLayout(spacing: 16, rowSpacing: 4) {
            if let count = stats?.fandomCount {
                statItem("books.vertical", "\(count.formatted()) fandoms")
                if let works = stats?.workCount {
                    statItem("doc.text", "~\(compact(works)) works")
                }
            } else {
                // Counts for this category are still loading (or being recomputed) —
                // show a quiet stat-line skeleton instead of a "Counting…" spinner.
                SkeletonBlock(height: 11, width: 104, cornerRadius: 4)
                    .skeletonShimmer()
            }
            if let saved = stats?.savedCount, saved > 0 {
                statItem("bookmark.fill", "\(saved) saved")
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
                    .minimumHitTarget(28)
                }
            }
        }
    }

    // MARK: - Stats

    private struct CategoryStats: Sendable {
        /// nil while the category's fandom list is still loading.
        var fandomCount: Int?
        var workCount: Int?
        var savedCount: Int
        var recentFandoms: [String]
    }

    /// A category's inputs, snapshotted as `Sendable` values so the (heavy) stats
    /// derivation can run off the main actor.
    private struct CategoryStatsInput: Sendable {
        let id: String
        let fandoms: [AO3Fandom]
        /// True when `fandoms` is the full fetched list (so counts are meaningful),
        /// false while only the small featured set is available.
        let hasFullList: Bool
    }

    /// One library work reduced to just the fields the stats need, pre-lowercased,
    /// so the off-actor pass does only set lookups (SavedWork isn't `Sendable`).
    private struct LibraryWorkSnapshot: Sendable {
        let fandomsLower: [String]
        let fandomsDisplay: [String]
        let hasBeenRead: Bool
        let dateAdded: Date
    }

    /// Cheap signature of everything `recomputeStats` depends on: which categories
    /// have a full list yet (+its size) and the library's size/newest item. The
    /// body recomputes only THIS (O(categories)), never the stats themselves; the
    /// stats recompute is driven by `.task(id: statsToken)`.
    private var statsToken: String {
        var parts: [String] = []
        for category in categories {
            parts.append("\(category.id):\(catalog.fandoms(for: category)?.count ?? -1)")
        }
        let newest = library.map(\.dateAdded).max()?.timeIntervalSince1970 ?? 0
        parts.append("lib:\(library.count):\(newest)")
        return parts.joined(separator: "|")
    }

    /// Recomputes every category's stats once, off the main actor. Debounced: while
    /// fandom lists stream in during load, `statsToken` changes rapidly and
    /// `.task(id:)` cancels the prior invocation, so the cancellation-aware sleep
    /// collapses the burst into a single pass once the lists settle — instead of
    /// the old behavior (a full O(categories × fandoms) rebuild on every render as
    /// each list landed, on the main thread, which is what spiked CPU/memory).
    private func recomputeStats() async {
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }

        // Snapshot on the main actor (SavedWork can't cross actors).
        let works = library.map { work in
            LibraryWorkSnapshot(
                fandomsLower: work.workFandoms.map { $0.lowercased() },
                fandomsDisplay: work.workFandoms,
                hasBeenRead: work.hasBeenRead,
                dateAdded: work.dateAdded
            )
        }
        let inputs = categories.map { category -> CategoryStatsInput in
            let list = catalog.fandoms(for: category)
            return CategoryStatsInput(
                id: category.id,
                fandoms: list ?? category.fandoms,
                hasFullList: list != nil
            )
        }

        let computed = await Task.detached(priority: .userInitiated) {
            Self.computeStats(inputs: inputs, works: works)
        }.value

        guard !Task.isCancelled else { return }
        statsByCategory = computed
    }

    /// Pure, off-actor derivation: builds each category's lowercased name set ONCE
    /// (the expensive part for big categories) and scans the library against it.
    private nonisolated static func computeStats(
        inputs: [CategoryStatsInput],
        works: [LibraryWorkSnapshot]
    ) -> [String: CategoryStats] {
        let readWorks = works
            .filter(\.hasBeenRead)
            .sorted { $0.dateAdded > $1.dateAdded }

        var result: [String: CategoryStats] = [:]
        result.reserveCapacity(inputs.count)
        for input in inputs {
            let nameSet = Set(input.fandoms.map { $0.name.lowercased() })

            var savedCount = 0
            for work in works where work.fandomsLower.contains(where: nameSet.contains) {
                savedCount += 1
            }

            var recent: [String] = []
            var seen = Set<String>()
            for work in readWorks {
                for index in work.fandomsLower.indices where nameSet.contains(work.fandomsLower[index]) {
                    if seen.insert(work.fandomsLower[index]).inserted {
                        recent.append(work.fandomsDisplay[index])
                    }
                }
                if recent.count >= 3 { break }
            }

            result[input.id] = CategoryStats(
                fandomCount: input.hasFullList ? input.fandoms.count : nil,
                workCount: input.hasFullList
                    ? input.fandoms.reduce(0) { $0 + ($1.workCount ?? 0) }
                    : nil,
                savedCount: savedCount,
                recentFandoms: Array(recent.prefix(3))
            )
        }
        return result
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

    private func refresh() async {
        do {
            let loaded = try await AO3Client.shared.mediaCategories()
            categories = loaded
            phase = .loaded
            // Refresh only category rows currently visible in this list. The catalog
            // keeps existing counts if an individual category request fails.
            let visible = loaded.filter { visibleCategoryIDs.contains($0.id) }
            await catalog.refresh(visible.isEmpty ? Array(loaded.prefix(4)) : visible)
        } catch let error as AO3Error {
            if categories.isEmpty {
                phase = .failed(error.errorDescription ?? "Something went wrong.")
            } else {
                Log.network.notice("Browse refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            if categories.isEmpty {
                phase = .failed(error.localizedDescription)
            } else {
                Log.network.notice("Browse refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private extension SavedWork {
    /// The user has opened this work at least once (or finished it, even if its
    /// progress fields were later reset). Defers to the model's canonical
    /// `hasStartedReading` — a local re-listing of its fields here once missed the
    /// Readium reader's locator, so works read only on iOS never surfaced a
    /// recently-read fandom.
    var hasBeenRead: Bool {
        isFinished || hasStartedReading
    }
}
