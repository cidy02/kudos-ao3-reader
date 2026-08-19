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

    #if os(iOS)
    @Environment(ThemeManager.self) private var themeManager
    #endif
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
        #if os(iOS)
        categoryGrid
        #else
        categoryListMac
        #endif
    }

    #if os(iOS)
    /// A custom `Layout` (`MasonryLayout`, in this file), not two hand-split
    /// columns — two rounds of "guess which column is shorter" both broke on
    /// real content: index alternation stacked several tall cards in one
    /// column, and a follow-up content-based height *estimate* still guessed
    /// wrong for at least one card, leaving the columns visibly uneven again.
    /// `Layout` asks each subview for its real `sizeThatFits` during actual
    /// layout — no estimation, no double-render measurement hack — and places
    /// it into whichever column is shortest *so far*, which is the correct
    /// algorithm this was always trying to approximate.
    private var categoryGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CardListMetrics.interCardSpacing) {
                Text("Browse by fandom")
                    .font(.headline)
                    .padding(.horizontal, CardListMetrics.sideMargin)

                MasonryLayout(columns: 2, spacing: CardListMetrics.interCardSpacing) {
                    ForEach(categories) { category in
                        NavigationLink(value: category) {
                            categoryCard(category)
                                .padding(CardListMetrics.innerHorizontal)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .background(
                                    RoundedRectangle(cornerRadius: CardListMetrics.cornerRadius, style: .continuous)
                                        .fill(themeManager.appTheme.cardSurface)
                                        .overlay(
                                            RoundedRectangle(
                                                cornerRadius: CardListMetrics.cornerRadius, style: .continuous
                                            )
                                            .strokeBorder(themeManager.appTheme.cardBorder, lineWidth: 0.5)
                                        )
                                        .shadow(color: themeManager.appTheme.cardShadow.color,
                                                radius: themeManager.appTheme.cardShadow.radius,
                                                x: 0, y: themeManager.appTheme.cardShadow.y)
                                )
                        }
                        .buttonStyle(.plain)
                        .onAppear { visibleCategoryIDs.insert(category.id) }
                        .onDisappear { visibleCategoryIDs.remove(category.id) }
                    }
                }
                .padding(.horizontal, CardListMetrics.sideMargin)

                instructions
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, CardListMetrics.sideMargin)
            }
            .padding(.vertical, CardListMetrics.interCardSpacing)
        }
        // `/media` is `max-age=600, public`, so without the invalidation the
        // gesture re-renders the same bytes for ten minutes.
        .refreshable {
            await AO3Client.shared.invalidateCachedResponses()
            await refresh()
        }
    }
    #else
    private var categoryListMac: some View {
        List {
            Section {
                ForEach(categories) { category in
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
        // `/media` is `max-age=600, public`, so without the invalidation the
        // gesture re-renders the same bytes for ten minutes.
        .refreshable {
            await AO3Client.shared.invalidateCachedResponses()
            await refresh()
        }
    }
    #endif

    /// Instructional caption shown under the category list.
    private var instructions: Text {
        #if os(iOS)
        Text("Browse fandoms from AO3. Tap a category to see its fandoms.")
        #else
        Text("Popular fandoms from AO3. Tap one to search its works.")
        #endif
    }

    // MARK: - Card

    /// A non-breaking space before "&", so a wrapped title always breaks *after*
    /// the ampersand ("Category &" stays on the first line, the next word moves
    /// down) instead of sometimes breaking before it. Plain wrapping picked
    /// whichever space ran out of width first — "Anime & Manga" wrapped as
    /// "Anime" / "& Manga" while every other card ("Books &" / "Literature")
    /// wrapped the other way; this makes all of them consistent.
    private func wrapSafeName(_ name: String) -> String {
        name.replacingOccurrences(of: " &", with: "\u{00A0}&")
    }

    /// The enriched category card: an emphasized icon + regular-weight name, a stats
    /// line, and (when present) recently-read chips. Reads precomputed
    /// stats (`statsByCategory`) instead of computing them inline — the derivation
    /// scans the category's full fandom list (tens of thousands for the big media
    /// categories) plus the whole library, which must never run per-card during a
    /// render (see `recomputeStats`).
    private func categoryCard(_ category: AO3MediaCategory) -> some View {
        let stats = statsByCategory[category.id]
        return VStack(alignment: .leading, spacing: 8) {
            Text(wrapSafeName(category.name))
                .font(.headline.weight(.regular)) // regular weight (was bold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Room for the icon overlay below so the title never renders
                // under it, and .fixedSize/.lineLimit(nil) so a long name always
                // wraps onto more lines instead of truncating — one card
                // ("Anime & Manga") was truncating to "Anime & Ma…" while every
                // sibling card with an equally long name wrapped fine.
                .padding(.trailing, 28)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)

            statsLine(stats)

            if let stats, !stats.recentFandoms.isEmpty {
                // Space, not a rule: the card's own edge is already the boundary in
                // view here, and a hairline inside it drew a second one a few points
                // away. "Recently read" is its own labelled block — it does not need
                // a line to say it starts.
                Spacer(minLength: 0).frame(height: 2)
                recentlyRead(stats.recentFandoms)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Icon decoupled from the title row, into the card's own top-right
        // corner — a badge rather than a leading glyph.
        .overlay(alignment: .topTrailing) {
            Image(systemName: category.symbol)
                .font(.headline)
                .foregroundStyle(.tint)
        }
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
                statItem(WorkActionLabels.downloadedSymbol, "\(saved) downloaded")
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

#if os(iOS)
/// Masonry: N equal-width columns, each subview placed into whichever column is
/// shortest *so far* — using each subview's own real `sizeThatFits`, not a guess.
/// Two earlier attempts at this same layout (index alternation, then a
/// content-based height estimate) both produced visibly uneven columns on real
/// data; `Layout` gets the actual size during layout itself, so there's nothing
/// left to estimate.
private struct MasonryLayout: Layout {
    var columns: Int = 2
    var spacing: CGFloat = 12

    /// Guards against a `columns <= 0` caller: unguarded, `columnWidth` divides
    /// by zero (silently producing `.infinity`, not a crash) but the
    /// `count: columns` array allocations below it would crash outright.
    private var safeColumns: Int { max(1, columns) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        // `?? .replacingUnspecifiedDimensions()`, not a bare `.zero` fallback:
        // a nil proposal.width (e.g. a parent asking for this layout's ideal
        // size rather than fitting it to a known width) would otherwise
        // collapse the whole layout to zero size instead of reporting one.
        let width = proposal.width ?? proposal.replacingUnspecifiedDimensions().width
        let columnWidth = columnWidth(for: width)
        let columnHeights = placedColumnHeights(columnWidth: columnWidth, subviews: subviews)
        // Each column's running height carries one trailing `spacing` past its
        // last item (added unconditionally every iteration, including the
        // last), which isn't real content — trimmed here so the reported
        // height matches what's actually drawn, not one gap taller.
        let contentHeight = (columnHeights.max() ?? 0) - spacing
        return CGSize(width: width, height: max(0, contentHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let columnWidth = columnWidth(for: bounds.width)
        var columnHeights = Array(repeating: CGFloat(0), count: safeColumns)
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            let column = shortestColumn(columnHeights)
            let origin = CGPoint(
                x: bounds.minX + CGFloat(column) * (columnWidth + spacing),
                y: bounds.minY + columnHeights[column]
            )
            subview.place(at: origin, proposal: ProposedViewSize(width: columnWidth, height: height))
            columnHeights[column] += height + spacing
        }
    }

    private func columnWidth(for totalWidth: CGFloat) -> CGFloat {
        max(0, (totalWidth - spacing * CGFloat(safeColumns - 1)) / CGFloat(safeColumns))
    }

    private func shortestColumn(_ heights: [CGFloat]) -> Int {
        heights.indices.min { heights[$0] < heights[$1] } ?? 0
    }

    /// Dry-runs the same placement loop `placeSubviews` uses, just to total each
    /// column's final height for `sizeThatFits` — kept as a separate pass (not
    /// shared state) since `sizeThatFits` and `placeSubviews` aren't guaranteed
    /// to run back-to-back for the same proposal.
    private func placedColumnHeights(columnWidth: CGFloat, subviews: Subviews) -> [CGFloat] {
        var columnHeights = Array(repeating: CGFloat(0), count: safeColumns)
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            let column = shortestColumn(columnHeights)
            columnHeights[column] += height + spacing
        }
        return columnHeights
    }
}
#endif
