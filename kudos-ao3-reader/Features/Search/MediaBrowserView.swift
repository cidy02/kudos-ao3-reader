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
    /// Set by BrowseView on the stack; pairs a category card with the fandom list
    /// it pushes. Absent elsewhere (Search's idle state), where the helper no-ops.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace
    #endif
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var library: [SavedWork]

    @State private var categories: [AO3MediaCategory] = []
    @State private var phase: Phase = .loading
    @State private var visibleCategoryIDs: Set<String> = []
    /// Per-category derived stats, recomputed off the render/main path (see
    /// `recomputeStats`); the cards read this rather than deriving inline.
    @State private var statsByCategory: [String: CategoryStats] = [:]
    /// Set once `cardsReady` has waited as long as it is willing to for counts
    /// (a warm cache beats it; a cold one does not) — see `load`.
    @State private var countsSettled = false
    /// Shared, per-launch cache of each category's fandom list.
    private let catalog = FandomCatalog.shared
    #if os(macOS)
    /// Tracked explicitly (keyed by category name) so a row's expansion can't be
    /// recycled onto a different category as the List scrolls.
    @State private var expanded: Set<String> = []
    #endif

    private enum Phase: Equatable { case loading, loaded, failed(String) }

    /// Whether the cards can be drawn complete — every category's counts are in,
    /// or `load`'s grace period has expired and we show what we have (names plus
    /// a count placeholder) rather than keep the reader on a skeleton.
    /// `fandomCount` is the right thing to check: it and `savedCount` /
    /// `recentFandoms` all come out of the same `recomputeStats` pass, so a
    /// category with its count has its downloaded count and chips too.
    private var cardsReady: Bool {
        guard !categories.isEmpty else { return false }
        return countsSettled
            || categories.allSatisfy { statsByCategory[$0.id]?.fandomCount != nil }
    }

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
                // The names arrive a whole round of requests before the counts
                // do, so revealing here would show every card with its title
                // and an empty stat line that pops a beat later. Keep the
                // skeleton up until the cards can be drawn complete.
                if cardsReady { categoryList } else { CategoryCardSkeletonList() }
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
    /// Artboard 1g: one full-width panel per category rather than a masonry grid
    /// of cards.
    ///
    /// The masonry layout went with the grid. It existed to keep two columns of
    /// variable-height cards level — a real problem, solved properly — but a
    /// single column of full-width panels has no columns to balance, so keeping
    /// it would have meant paying for a custom `Layout` pass to do nothing.
    ///
    /// The panels are wide because the chip cluster needs the width: 1g drops the
    /// horizontal carousel specifically so no fandom hides off the right edge,
    /// and a two-column card cannot hold a dozen wrapped chips.
    private var categoryGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                jumpBackInSection

                ForEach(categories) { category in
                    NavigationLink(value: category) {
                        categoryPanel(category)
                    }
                    .buttonStyle(.plain)
                    // On the NavigationLink itself, not on the panel inside its
                    // label: the system pairs the transition with the link that
                    // performs the push, and marking a nested subview instead
                    // leaves the pair unmatched — which degrades silently to an
                    // ordinary push (verified on device before this moved).
                    .workCardZoomSource(BrowseZoomKey.category(category.id), in: zoomNamespace)
                    .onAppear { visibleCategoryIDs.insert(category.id) }
                    .onDisappear { visibleCategoryIDs.remove(category.id) }
                }

                instructions
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, CardListMetrics.sideMargin)
            }
            .padding(.vertical, 12)
        }
        // `/media` is `max-age=600, public`, so without the invalidation the
        // gesture re-renders the same bytes for ten minutes.
        .refreshable {
            await AO3Client.shared.invalidateCachedResponses()
            await refresh()
        }
    }

    private func categoryPalette(_ category: AO3MediaCategory) -> SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: CoverArt.hue(for: category.name))
    }

    private func categoryPanel(_ category: AO3MediaCategory) -> some View {
        let stats = statsByCategory[category.id]
        let palette = categoryPalette(category)
        // Lowercased once per panel rather than once per chip: the cluster is up
        // to twelve chips and it is re-read on every render.
        let familiarNames = Set((stats?.recentFandoms ?? []).map { $0.lowercased() })

        return SubjectPanel(palette: palette, leadingSymbol: category.symbol) {
            VStack(alignment: .leading, spacing: 3) {
                Text(wrapSafeName(category.name))
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                statsLine(stats)
            }
        } content: {
            if let stats, !stats.clusterFandoms.isEmpty {
                fandomCluster(stats, palette: palette, familiarNames: familiarNames)
            }
        }
        .padding(.horizontal, CardListMetrics.sideMargin)
    }

    /// The chips, wrapping rather than scrolling, with the real remainder pinned
    /// at the end. Spec 1g is explicit that nothing here scrolls sideways — a
    /// carousel hides fandoms off the right edge, which is the reason this
    /// replaced one.
    private func fandomCluster(
        _ stats: CategoryStats,
        palette: SubjectPalette,
        familiarNames: Set<String>
    ) -> some View {
        let remainder = max(0, (stats.fandomCount ?? 0) - stats.clusterFandoms.count)
        return FlowLayout(spacing: 7, rowSpacing: 7) {
            ForEach(stats.clusterFandoms) { fandom in
                // Borderless so a chip tap opens that fandom instead of following
                // the panel's own navigation link.
                Button { onSelectFandom(fandom.name) } label: {
                    FandomClusterChip(
                        name: fandom.name,
                        workCount: fandom.workCount,
                        isFamiliar: familiarNames.contains(fandom.name.lowercased()),
                        palette: palette
                    )
                }
                .buttonStyle(.borderless)
            }

            if remainder > 0 {
                // Not a button: the panel it sits in already pushes the full
                // list, and a second target for the same destination inside that
                // link would race it for the touch.
                SubjectChip(text: "+\(remainder.formatted()) more", style: .dashed)
                    .accessibilityLabel("\(remainder.formatted()) more fandoms")
            }
        }
    }

    /// Spec 1g's "Jump Back In": the fandoms you were most recently reading, as
    /// compact cards carrying their category, name and size.
    ///
    /// Built from `recentFandoms`, which the stats pass already derives per
    /// category — so this needs no new request and no new state, only a flatten
    /// across categories.
    @ViewBuilder
    private var jumpBackInSection: some View {
        let recent = jumpBackInEntries
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                SectionRuleHeader(title: "Jump Back In", count: recent.count)

                HStack(alignment: .top, spacing: 11) {
                    ForEach(recent, id: \.fandom) { entry in
                        Button { onSelectFandom(entry.fandom) } label: {
                            jumpBackInCard(entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CardListMetrics.sideMargin)
            }
        }
    }

    private struct JumpBackInEntry {
        let fandom: String
        let category: AO3MediaCategory
        let workCount: Int?
    }

    /// At most three, one per fandom, in category order. Three because 1g draws
    /// three and they share the width equally — a fourth would squeeze every card
    /// below the width its fandom name needs.
    private var jumpBackInEntries: [JumpBackInEntry] {
        var entries: [JumpBackInEntry] = []
        var seen = Set<String>()
        for category in categories {
            guard let stats = statsByCategory[category.id] else { continue }
            for name in stats.recentFandoms where seen.insert(name.lowercased()).inserted {
                let count = stats.clusterFandoms.first { $0.name == name }?.workCount
                entries.append(JumpBackInEntry(fandom: name, category: category, workCount: count))
                if entries.count == 3 { return entries }
            }
        }
        return entries
    }

    private func jumpBackInCard(_ entry: JumpBackInEntry) -> some View {
        let palette = categoryPalette(entry.category)
        return VStack(alignment: .leading, spacing: 8) {
            SubjectKicker(
                text: entry.category.name,
                palette: palette,
                size: 8.5,
                ruleWidth: 18,
                ruleSpacing: 6
            )

            Text(entry.fandom)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let workCount = entry.workCount {
                Text("\(workCount.formatted()) works")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(themeManager.appTheme.carouselCardSurface)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.cardWash))
                .shadow(color: themeManager.appTheme.carouselCardShadow.color,
                        radius: themeManager.appTheme.carouselCardShadow.radius,
                        x: 0, y: themeManager.appTheme.carouselCardShadow.y)
        )
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
    /// line, and (when present) recently-read chips.
    ///
    /// **macOS only now.** iOS draws `categoryPanel` instead (artboard 1g), where
    /// the same facts sit on a tinted full-width panel with a fandom chip
    /// cluster. The two platforms genuinely diverge here: macOS keeps a
    /// `DisclosureGroup` list, which wants a compact row label, not a panel. Reads precomputed
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

    @ViewBuilder
    private func statsLine(_ stats: CategoryStats?) -> some View {
        if let count = stats?.fandomCount {
            FlowLayout(spacing: 16, rowSpacing: 4) {
                statItem("books.vertical", "\(count.formatted()) fandoms")
                if let works = stats?.workCount {
                    let figure = compact(works)
                    let label = (stats?.isApproximateWorkCount == true)
                        ? "~\(figure) works"
                        : "\(figure) works"
                    statItem("doc.text", label)
                }
                if let saved = stats?.savedCount, saved > 0 {
                    statItem(WorkActionLabels.downloadedSymbol, "\(saved) downloaded")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else {
            loadingStats
        }
    }

    /// Placeholder for a card still waiting on its counts — the cold-cache path
    /// `cardsReady` deliberately lets through (see `load`).
    ///
    /// Shaped like what is actually coming, rather than the single bar this used
    /// to be: three stat lines, because three separate numbers are loading
    /// (fandoms, works, downloaded) and at a masonry column's width they wrap
    /// one per line; then the "Recently read" label and a chip under it. Same
    /// block metrics as `CategoryCardSkeleton` so the full skeleton and this one
    /// speak the same placeholder language.
    ///
    /// The recently-read rows are reserved for every card, but only categories
    /// the reader has actually read from will fill them — the rest collapse by
    /// two rows when their counts land. Reserving is still the better trade:
    /// under-reserving made every card grow instead.
    private var loadingStats: some View {
        VStack(alignment: .leading, spacing: 4) {
            SkeletonBlock(height: 13, width: 96, cornerRadius: 4)
            SkeletonBlock(height: 13, width: 78, cornerRadius: 4)
            SkeletonBlock(height: 13, width: 88, cornerRadius: 4)
            SkeletonBlock(height: 11, width: 92, cornerRadius: 3)
                .padding(.top, 6)
            SkeletonBlock(height: 28, width: 116, cornerRadius: 14)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonShimmer()
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
        /// True when `workCount` is a sum of per-tag counts and therefore
        /// double-counts a work tagged with two fandoms in the category.
        var isApproximateWorkCount: Bool = false
        var savedCount: Int
        var recentFandoms: [String]
        /// The chips artboard 1g clusters under each category, biggest first.
        ///
        /// The spec calls these the category's *featured* fandoms, and its build
        /// note says AO3's featured subset is not in the current parse — true,
        /// and it turns out not to matter: the app already caches the whole
        /// per-category list with a work count on each, so the cluster shows the
        /// largest fandoms instead. No new request, and arguably a better list
        /// than AO3's own featured set, which is hand-curated and often stale.
        var clusterFandoms: [AO3Fandom] = []
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

    /// How many "recently read" fandom chips a category card shows at most.
    private static let recentFandomsLimit = 5

    /// How many fandoms a category's chip cluster shows before the rest collapse
    /// into the "+N more" chip. Twelve fills roughly three wrapped rows at phone
    /// width, which is what 1g draws; the remainder is stated exactly rather than
    /// rounded, since "+9,400 more" is the fact that makes a category feel big.
    private static let clusterFandomLimit = 12

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
                if recent.count >= recentFandomsLimit { break }
            }

            // Sorted here, in the off-actor pass, not in the view: a category can
            // hold nine thousand fandoms, and sorting that on every render is the
            // kind of work this whole `computeStats` split exists to avoid.
            let cluster = input.hasFullList
                ? Array(
                    input.fandoms
                        .sorted { ($0.workCount ?? 0) > ($1.workCount ?? 0) }
                        .prefix(clusterFandomLimit)
                )
                : []

            let summed = input.hasFullList ? CategoryWorkTotal.summedTagCounts(input.fandoms) : nil
            result[input.id] = CategoryStats(
                fandomCount: input.hasFullList ? input.fandoms.count : nil,
                workCount: summed?.workCount,
                isApproximateWorkCount: summed?.isApproximate ?? false,
                savedCount: savedCount,
                recentFandoms: Array(recent.prefix(recentFandomsLimit)),
                clusterFandoms: cluster
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
        countsSettled = false
        do {
            categories = try await AO3Client.shared.mediaCategories()
            phase = .loaded
            // The names land a whole round of requests before the counts do, so
            // `cardsReady` holds the skeleton until the counts arrive and the
            // cards can be drawn complete rather than filling in under the
            // reader. That wait has to be bounded, hence the grace below:
            // FandomCatalog serves a warm disk cache almost immediately (and
            // `recomputeStats` debounces 150ms on top), so a warm launch beats
            // the deadline and never shows a half-filled card — while a cold
            // cache, which needs a request per category, falls through to
            // names-plus-count-placeholders instead of holding a skeleton for
            // seconds. It also stops one category's failed index request, whose
            // count stays nil for good, from stranding Browse on the skeleton.
            //
            // Deliberately not cancelled when `loadMissing` returns early: on a
            // warm-but-slow launch (a large library makes the stats pass itself
            // slow) that deadline is the only thing left to reveal the cards.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                countsSettled = true
            }
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
