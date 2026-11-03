import OSLog
import SwiftData
import SwiftUI

/// Fills the Search tab's idle state and Browse root with a two-column masonry of
/// solid colour cards (Board 13). On iOS, tapping a category pushes a dedicated fandom
/// list; on macOS it expands inline to the featured fandoms.
///
/// Each category card is enriched with real fandom/work counts (from the same
/// per-category fandom index the detail page uses, cached in `FandomCatalog`),
/// the user's saved-work count in that category, and top fandom chips.
struct MediaBrowserView: View {
    @Environment(AppRouter.self) private var router
    /// Every raw tag to include, and the name to title the page with. A chip
    /// is a family, so it can name several tags; everything else names one.
    var onSelectFandom: (_ names: [String], _ title: String) -> Void

    @Environment(ThemeManager.self) private var themeManager
    #if os(iOS)
    /// Set by BrowseView on the stack; pairs a category card with the fandom list
    /// it pushes. Absent elsewhere (Search's idle state), where the helper no-ops.
    @Environment(\.workCardTransitionNamespace) private var zoomNamespace
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @Environment(PrivacyGate.self) private var gate
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var allLibrary: [SavedWork]
    /// What Browse may know of the Library: not a work Hide mode hides. Built from
    /// every work, it marked such a work's fandom as yours, counted its download and
    /// offered the fandom in Jump Back In (audit A38). Free in any other mode.
    private var library: [SavedWork] {
        guard hideMature, matureMode == .hide else { return allLibrary }
        return allLibrary.filter { !gate.isHidden($0, enabled: true, mode: .hide) }
    }
    /// Fandom pages opened from Browse, for Jump Back In's order.
    @Query private var fandomVisits: [FandomReadWatermark]

    @State private var categories: [AO3MediaCategory] = []
    @State private var phase: Phase = .loading
    @State private var visibleCategoryIDs: Set<String> = []
    /// Per-category derived stats, recomputed off the render/main path (see
    /// `recomputeStats`); the cards read this rather than deriving inline.
    @State private var statsByCategory: [String: CategoryStats] = [:]
    /// Jump Back In picks from the off-actor pass — see `jumpBackInFandoms`.
    @State private var jumpBackInPicks: [JumpBackInPick] = []
    @ScaledMetric(relativeTo: .subheadline) private var categoryNameSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var categoryStatSize: CGFloat = 12
    @ScaledMetric(relativeTo: .subheadline) private var chipTitleSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption2) private var chipCountSize: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline) private var moreLinkSize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var jumpBackInTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .footnote) private var jumpBackInDetailSize: CGFloat = 13
    @ScaledMetric(relativeTo: .footnote) private var openWebsiteSize: CGFloat = 13.5
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

    private enum Phase: Equatable { case loading, loaded, failed(message: String, systemImage: String) }

    /// Whether the cards can be drawn complete — every category's counts are in,
    /// or `load`'s grace period has expired and we show what we have (names plus
    /// a count placeholder) rather than keep the reader on a skeleton.
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
            case let .failed(message, systemImage):
                #if os(iOS)
                // Jump Back In is local: an AO3 failure must not take it away
                // with the categories (LOOP-v3, offline Browse).
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        jumpBackInSection
                        loadFailure(message, systemImage: systemImage).padding(.top, 24)
                    }
                }
                #else
                loadFailure(message, systemImage: systemImage)
                #endif
            case .loaded:
                if cardsReady { categoryList } else { CategoryCardSkeletonList() }
            }
        }
        .appScreenSurface(.content)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.openWebsite()
                } label: {
                    Image(systemName: "globe")
                }
                .accessibilityLabel("AO3 website")
            }
        }
        #endif
        .task { if categories.isEmpty { await load() } }
        // Derive per-category stats off the main render path, refired (and debounced)
        // whenever a fandom list lands or the library changes.
        .task(id: statsToken) { await recomputeStats() }
    }

    private func loadFailure(_ message: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load fandoms", systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await load() } }
        }
    }

    private func categoryPalette(_ category: AO3MediaCategory) -> SubjectPalette {
        themeManager.appTheme.subjectPalette(hue: CoverArt.hue(for: category.name))
    }

    private var categoryList: some View {
        #if os(iOS)
        categoryGrid
        #else
        categoryListMac
        #endif
    }

    #if os(iOS)
    /// Board 13: Jump Back In followed by a two-column masonry of solid colour cards.
    private var categoryGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                jumpBackInSection

                VStack(alignment: .leading, spacing: 10) {
                    Text("Categories")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .accessibilityAddTraits(.isHeader)

                    let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
                    MasonryLayout(columns: columns, spacing: 10, rowSpacing: 10) {
                        ForEach(categories) { category in
                            categoryCardView(category)
                                .onAppear { visibleCategoryIDs.insert(category.id) }
                                .onDisappear { visibleCategoryIDs.remove(category.id) }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                openWebsiteRow
            }
            .padding(.vertical, 12)
        }
        .refreshable {
            await AO3Client.shared.invalidateCachedResponses()
            await refresh()
        }
    }

    /// Board 13 solid colour card: takes its colour from the category name, shows its icon
    /// large behind it at 15% white, category name at the top, fandom and work counts,
    /// download capsule top-right, and top fandoms as 18%-white capsules.
    private func categoryCardView(_ category: AO3MediaCategory) -> some View {
        let stats = statsByCategory[category.id]
        let chips = stats?.clusterFandoms ?? []

        return VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: category) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wrapSafeName(category.name))
                            .font(.system(size: categoryNameSize, weight: .bold))
                            .foregroundStyle(Color.white)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)

                        if let fandomCount = stats?.familyCount ?? stats?.fandomCount {
                            let fandomText = "\(compact(fandomCount)) fandoms"
                            let worksText: String = {
                                if let works = stats?.workCount {
                                    let figure = compact(works)
                                    return (stats?.isApproximateWorkCount == true) ? "· ~\(figure) works" : "· \(figure) works"
                                }
                                return ""
                            }()
                            Text("\(fandomText) \(worksText)")
                                .font(.system(size: categoryStatSize))
                                .foregroundStyle(Color.white.opacity(0.8))
                                .lineLimit(2)
                        } else {
                            SkeletonBlock(height: 12, width: 80, cornerRadius: 3)
                                .opacity(0.4)
                        }
                    }

                    Spacer(minLength: 4)

                    if let saved = stats?.savedCount, saved > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(saved)")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 22)
                        .background(Color.white.opacity(0.22), in: Capsule())
                        .accessibilityLabel("\(saved) downloaded")
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(categoryHeaderAccessibilityLabel(category, stats: stats))

            VStack(spacing: 6) {
                ForEach(chips) { chip in
                    Button {
                        onSelectFandom(chip.names, chip.title)
                    } label: {
                        HStack(spacing: 6) {
                            if chip.isFamiliar {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 6, height: 6)
                                    .accessibilityHidden(true)
                            }
                            Text(chip.title)
                                .font(.system(size: chipTitleSize, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 4)
                            Text((chip.isApproximate ? "~" : "") + compact(chip.workCount))
                                .font(.system(size: chipCountSize))
                                .foregroundStyle(Color.white.opacity(0.8))
                                .lineLimit(1)
                                .layoutPriority(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(minHeight: 30)
                        .background(Color.white.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .layoutFreeHitTarget { onSelectFandom(chip.names, chip.title) }
                    .accessibilityLabel("\(chip.title), \(compact(chip.workCount)) works" + (chip.isFamiliar ? ", you have read from this fandom" : ""))
                }

                NavigationLink(value: category) {
                    HStack(spacing: 4) {
                        if let count = stats?.familyCount ?? stats?.fandomCount {
                            Text("\(compact(count)) fandoms")
                                .font(.system(size: moreLinkSize, weight: .semibold))
                        } else {
                            Text("All fandoms")
                                .font(.system(size: moreLinkSize, weight: .semibold))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.white)
                    .frame(minHeight: 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All \(stats?.familyCount ?? stats?.fandomCount ?? 0) fandoms in \(category.name)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                .fill(CoverArt.workGradient(fandoms: [category.name], title: ""))
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: category.symbol)
                .font(.system(size: 110, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.15))
                .offset(x: 20, y: -10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous))
        .workCardZoomSource(BrowseZoomKey.category(category.id), in: zoomNamespace)
    }

    private func categoryHeaderAccessibilityLabel(_ category: AO3MediaCategory, stats: CategoryStats?) -> String {
        var parts = [category.name]
        if let fandomCount = stats?.familyCount ?? stats?.fandomCount {
            parts.append("\(compact(fandomCount)) fandoms")
        }
        if let works = stats?.workCount {
            let label = (stats?.isApproximateWorkCount == true) ? "about \(compact(works)) works" : "\(compact(works)) works"
            parts.append(label)
        }
        if let saved = stats?.savedCount, saved > 0 {
            parts.append("\(saved) downloaded")
        }
        return parts.joined(separator: ", ")
    }
    #endif

    /// The rest of AO3, a dashed row rather than a card.
    private var openWebsiteRow: some View {
        Button {
            router.openWebsite()
        } label: {
            HStack {
                Text("Open AO3 Website")
                    .font(.system(size: openWebsiteSize, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .foregroundStyle(.tertiary)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .accessibilityLabel("Open AO3 Website")
    }

    /// Board 13: Jump Back In — compact grey chips with a fandom swatch.
    @ViewBuilder
    private var jumpBackInSection: some View {
        let recent = jumpBackInEntries
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Jump Back In")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recent, id: \.fandom) { entry in
                            jumpBackInCard(entry)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .horizontalScrollViewport(preservesShadows: true, cardGutter: 16)
            }
        }
    }

    private struct JumpBackInEntry {
        let fandom: String
        let category: AO3MediaCategory
        let workCount: Int?
        let isFavorite: Bool
        let lastVisitedAt: Date?
    }

    /// At most ten (`jumpBackInLimit`), one per fandom, most recently visited or
    /// read first.
    private var jumpBackInEntries: [JumpBackInEntry] {
        jumpBackInPicks.compactMap { pick in
            guard let category = categories.first(where: { $0.id == pick.categoryID }) else { return nil }
            return JumpBackInEntry(
                fandom: pick.fandom,
                category: category,
                workCount: pick.workCount,
                isFavorite: pick.isFavorite,
                lastVisitedAt: pick.lastVisitedAt
            )
        }
    }

    private var jumpBackInChipBackground: Color {
        #if os(iOS)
        themeManager.appTheme.appElevatedBackground ?? Color(uiColor: .secondarySystemBackground)
        #else
        themeManager.appTheme.appElevatedBackground ?? Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private var jumpBackInMaxWidth: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? nil : 260
    }

    private func jumpBackInCard(_ entry: JumpBackInEntry) -> some View {
        Button {
            onSelectFandom([entry.fandom], entry.fandom)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(CoverArt.workGradient(fandoms: [entry.fandom], title: ""))
                    .frame(width: 28, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(FandomDisplayName.bareTitle(entry.fandom, among: jumpBackInPicks.map(\.fandom)))
                        .font(.system(size: jumpBackInTitleSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        Text(entry.category.name)
                        if entry.isFavorite {
                            Text("·")
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.subjectFavoriteGold)
                            Text("favorite")
                        } else if let visited = entry.lastVisitedAt, Calendar.current.isDateInToday(visited) {
                            Text("· visited today")
                        } else if let count = entry.workCount, count > 0 {
                            Text("· \(compact(count)) works")
                        }
                    }
                    .font(.system(size: jumpBackInDetailSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .frame(maxWidth: jumpBackInMaxWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(jumpBackInChipBackground)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(jumpBackInAccessibilityLabel(entry))
    }

    private func jumpBackInAccessibilityLabel(_ entry: JumpBackInEntry) -> String {
        var parts = [entry.fandom, entry.category.name]
        if entry.isFavorite {
            parts.append("favorite")
        } else if let visited = entry.lastVisitedAt, Calendar.current.isDateInToday(visited) {
            parts.append("visited today")
        } else if let count = entry.workCount, count > 0 {
            parts.append("\(compact(count)) works")
        }
        return parts.joined(separator: ", ")
    }

    #if os(macOS)
    private var categoryListMac: some View {
        List {
            if !jumpBackInEntries.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(jumpBackInEntries, id: \.fandom) { entry in
                                jumpBackInCard(entry)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Jump Back In")
                }
            }

            Section {
                ForEach(categories) { category in
                    DisclosureGroup(isExpanded: expansionBinding(for: category.id)) {
                        ForEach(category.fandoms) { fandom in
                            Button {
                                onSelectFandom([fandom.name], fandom.name)
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
                .cardRow()
            }
        }
        .cardList()
        .refreshable {
            await AO3Client.shared.invalidateCachedResponses()
            await refresh()
        }
    }

    private func categoryCard(_ category: AO3MediaCategory) -> some View {
        let stats = statsByCategory[category.id]
        return VStack(alignment: .leading, spacing: 8) {
            Text(wrapSafeName(category.name))
                .font(.headline.weight(.regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 28)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)

            statsLine(stats, palette: categoryPalette(category))

            if let stats, !stats.recentFandoms.isEmpty {
                Spacer(minLength: 0).frame(height: 2)
                recentlyRead(stats.recentFandoms)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Image(systemName: category.symbol)
                .font(.headline)
                .foregroundStyle(categoryPalette(category).accent)
        }
    }
    #endif

    // MARK: - Card helpers

    private func wrapSafeName(_ name: String) -> String {
        name.replacingOccurrences(of: " &", with: "\u{00A0}&")
    }

    @ViewBuilder
    private func statsLine(_ stats: CategoryStats?, palette: SubjectPalette? = nil) -> some View {
        if let count = stats?.familyCount ?? stats?.fandomCount {
            FlowLayout(spacing: 16, rowSpacing: 4) {
                statItem("books.vertical", "\(compact(count)) fandoms", palette: palette)
                if let works = stats?.workCount {
                    let figure = compact(works)
                    let label = (stats?.isApproximateWorkCount == true)
                        ? "~\(figure) works"
                        : "\(figure) works"
                    statItem("doc.text", label, palette: palette)
                }
                if let saved = stats?.savedCount, saved > 0 {
                    statItem(WorkActionLabels.downloadedSymbol, "\(saved) downloaded", palette: palette)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else {
            loadingStats
        }
    }

    private var loadingStats: some View {
        VStack(alignment: .leading, spacing: 4) {
            SkeletonBlock(height: 13, width: 96, cornerRadius: 4)
            SkeletonBlock(height: 13, width: 78, cornerRadius: 4)
            SkeletonBlock(height: 13, width: 88, cornerRadius: 4)
            SkeletonBlock(height: 11, width: 92, cornerRadius: 3)
                .padding(.top, 6)
            SkeletonBlock(height: 28, width: 116, cornerRadius: SubjectMetrics.capsuleRadius)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .skeletonShimmer()
    }

    private func statItem(_ symbol: String, _ text: String, palette: SubjectPalette? = nil) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(palette.map { AnyShapeStyle($0.accent) } ?? AnyShapeStyle(.tint))
            Text(text)
        }
        .fixedSize()
    }

    private func recentlyRead(_ fandoms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Recently read")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(fandoms, id: \.self) { fandom in
                    Button { onSelectFandom([fandom], fandom) } label: {
                        TagChip(text: fandom)
                    }
                    .buttonStyle(.borderless)
                    .minimumHitTarget(28)
                }
            }
        }
    }

    // MARK: - Stats

    fileprivate struct CategoryStats: Sendable {
        var fandomCount: Int?
        var familyCount: Int?
        var workCount: Int?
        var isApproximateWorkCount: Bool = false
        var savedCount: Int
        var recentFandoms: [String]

        struct ClusterFandom: Identifiable, Hashable, Sendable {
            let id: String
            let names: [String]
            let title: String
            let workCount: Int
            let isApproximate: Bool
            var isFamiliar: Bool = false

            init(
                id: String,
                names: [String],
                title: String,
                workCount: Int,
                isApproximate: Bool,
                isFamiliar: Bool = false
            ) {
                self.id = id
                self.names = names
                self.title = title
                self.workCount = workCount
                self.isApproximate = isApproximate
                self.isFamiliar = isFamiliar
            }
        }

        var clusterFandoms: [ClusterFandom] = []
    }

    /// A category's inputs, snapshotted as `Sendable` values so the (heavy) stats
    /// derivation can run off the main actor.
    private struct CategoryStatsInput: Sendable {
        let id: String
        let fandoms: [AO3Fandom]
        let hasFullList: Bool
    }

    /// One library work reduced to just the fields the stats need, pre-lowercased,
    /// so the off-actor pass does only set lookups (SavedWork isn't `Sendable`).
    /// Internal, not private, so `jumpBackInFandoms` can be tested.
    nonisolated struct LibraryWorkSnapshot: Sendable {
        let fandomsLower: [String]
        let fandomsDisplay: [String]
        let hasBeenRead: Bool
        let dateAdded: Date
        let lastReadDate: Date?
        var isOnDevice = true
        var isFavorite: Bool = false

        init(
            fandomsLower: [String],
            fandomsDisplay: [String],
            hasBeenRead: Bool,
            dateAdded: Date,
            lastReadDate: Date?,
            isOnDevice: Bool = true,
            isFavorite: Bool = false
        ) {
            self.fandomsLower = fandomsLower
            self.fandomsDisplay = fandomsDisplay
            self.hasBeenRead = hasBeenRead
            self.dateAdded = dateAdded
            self.lastReadDate = lastReadDate
            self.isOnDevice = isOnDevice
            self.isFavorite = isFavorite
        }

        var recency: Date {
            lastReadDate ?? dateAdded
        }
    }

    /// One Jump Back In card's worth: the fandom as the library spells it, the
    /// category it was found in, and the fandom's AO3 work count when known.
    nonisolated struct JumpBackInPick: Equatable, Sendable {
        let fandom: String
        let categoryID: String
        let workCount: Int?
        var isFavorite: Bool = false
        var lastVisitedAt: Date? = nil

        init(
            fandom: String,
            categoryID: String,
            workCount: Int?,
            isFavorite: Bool = false,
            lastVisitedAt: Date? = nil
        ) {
            self.fandom = fandom
            self.categoryID = categoryID
            self.workCount = workCount
            self.isFavorite = isFavorite
            self.lastVisitedAt = lastVisitedAt
        }
    }

    /// Cheap signature of everything `recomputeStats` depends on: which categories
    /// have a full list yet (+its size), the catalog's revision, and the library's
    /// size and latest change. The body recomputes only THIS (O(categories +
    /// works)), never the stats themselves; the stats recompute is driven by
    /// `.task(id: statsToken)`.
    private var statsToken: String {
        var parts: [String] = []
        for category in categories {
            parts.append("\(category.id):\(catalog.fandoms(for: category)?.count ?? -1)")
        }
        parts.append("rev:\(catalog.revision)")
        let changed = library.map(\.lastModifiedAt).max()?.timeIntervalSince1970 ?? 0
        let lastRead = library.compactMap(\.lastReadDate).max()?.timeIntervalSince1970 ?? 0
        parts.append("lib:\(library.count):\(changed):\(lastRead)")
        let lastVisit = fandomVisits.map(\.lastVisitedAt).max()?.timeIntervalSince1970 ?? 0
        parts.append("visits:\(fandomVisits.count):\(lastVisit)")
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

        let works = library.map { work in
            LibraryWorkSnapshot(
                fandomsLower: work.workFandoms.map { $0.lowercased() },
                fandomsDisplay: work.workFandoms,
                hasBeenRead: work.hasBeenRead,
                dateAdded: work.dateAdded,
                lastReadDate: work.lastReadDate,
                isOnDevice: work.isDownloaded,
                isFavorite: work.isFavorite
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

        let visits = fandomVisits.map { FandomVisit(fandom: $0.fandomName, at: $0.lastVisitedAt) }

        let computed = await Task.detached(priority: .userInitiated) {
            (
                stats: Self.computeStats(inputs: inputs, works: works),
                jumpBackIn: Self.rankJumpBackIn(inputs: inputs, works: works, visits: visits)
            )
        }.value

        guard !Task.isCancelled else { return }
        statsByCategory = computed.stats
        jumpBackInPicks = computed.jumpBackIn
    }

    /// How many "recently read" fandom chips a category card shows at most.
    private static let recentFandomsLimit = 5

    /// How many Jump Back In cards the carousel holds (owner, 2026-10-01: ten).
    private nonisolated static let jumpBackInLimit = 10

    /// Maps only the fandoms you have read to their category (the first that
    /// lists them, in `/media` order) and to their work count — looked up in the
    /// category's whole cached list, not just the twelve cluster chips, so a
    /// fandom outside the top twelve still shows its size (1g.7).
    private nonisolated static func rankJumpBackIn(
        inputs: [CategoryStatsInput],
        works: [LibraryWorkSnapshot],
        visits: [FandomVisit]
    ) -> [JumpBackInPick] {
        let readLower = Set(works.lazy.filter(\.hasBeenRead).flatMap(\.fandomsLower))
            .union(visits.map { $0.fandom.lowercased() })
        guard !readLower.isEmpty else { return [] }
        var categoryByFandom: [String: String] = [:]
        var workCountByFandom: [String: Int] = [:]
        for input in inputs {
            for fandom in input.fandoms {
                let lower = fandom.name.lowercased()
                guard readLower.contains(lower), categoryByFandom[lower] == nil else { continue }
                categoryByFandom[lower] = input.id
                if let count = fandom.workCount { workCountByFandom[lower] = count }
            }
        }
        return jumpBackInFandoms(
            works: works,
            visits: visits,
            categoryFor: { categoryByFandom[$0] },
            workCountFor: { workCountByFandom[$0] },
            limit: jumpBackInLimit
        )
    }

    /// Board 13: each category card shows up to 3 top fandom chips.
    private static let clusterFandomLimit = 3

    /// Pure, off-actor derivation: builds each category's lowercased name set ONCE
    /// (the expensive part for big categories) and scans the library against it.
    private nonisolated static func computeStats(
        inputs: [CategoryStatsInput],
        works: [LibraryWorkSnapshot]
    ) -> [String: CategoryStats] {
        let readWorks = works
            .filter(\.hasBeenRead)
            .sorted { $0.recency > $1.recency }

        var result: [String: CategoryStats] = [:]
        result.reserveCapacity(inputs.count)
        for input in inputs {
            let nameSet = Set(input.fandoms.map { $0.name.lowercased() })

            var savedCount = 0
            for work in works where work.isOnDevice && work.fandomsLower.contains(where: nameSet.contains) {
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

            let families = input.hasFullList ? FandomFamily.grouped(fandoms: input.fandoms) : []
            let familiarSet = Set(recent.map { $0.lowercased() })
            var pickedFamilies: [FandomFamily] = []
            var pickedIDs = Set<String>()

            // 1. Familiar families in this category first
            for family in families where family.includedFilterNames.contains(where: { familiarSet.contains($0.lowercased()) }) {
                if pickedIDs.insert(family.id).inserted {
                    pickedFamilies.append(family)
                    if pickedFamilies.count >= clusterFandomLimit { break }
                }
            }

            // 2. Fill remaining slots with largest fandoms by work count
            if pickedFamilies.count < clusterFandomLimit {
                let sortedByCount = families.sorted { $0.summedWorkCount > $1.summedWorkCount }
                for family in sortedByCount {
                    if pickedIDs.insert(family.id).inserted {
                        pickedFamilies.append(family)
                        if pickedFamilies.count >= clusterFandomLimit { break }
                    }
                }
            }

            let cluster: [CategoryStats.ClusterFandom] = pickedFamilies.map { family in
                let isFamiliar = family.includedFilterNames.contains { familiarSet.contains($0.lowercased()) }
                return CategoryStats.ClusterFandom(
                    id: family.id,
                    names: family.includedFilterNames,
                    title: family.parsedTitle,
                    workCount: family.summedWorkCount,
                    isApproximate: family.showsApproximateCount,
                    isFamiliar: isFamiliar
                )
            }

            let summed = input.hasFullList ? CategoryWorkTotal.summedTagCounts(input.fandoms) : nil
            result[input.id] = CategoryStats(
                fandomCount: input.hasFullList ? input.fandoms.count : nil,
                familyCount: input.hasFullList ? families.count : nil,
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
        } catch {
            phase = .failed(
                message: UserFacingError.message(for: error),
                systemImage: UserFacingError.systemImage(for: error)
            )
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
        } catch {
            if categories.isEmpty {
                phase = .failed(
                    message: UserFacingError.message(for: error),
                    systemImage: UserFacingError.systemImage(for: error)
                )
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

/// `FlowLayout` stopped at `maxRows`. The last subview is a trailing chip that
/// always gets a place, after as many of the others as fit; the rest get no
/// room. `onFit` hears how many fitted, so the caller can hide them and count
/// them in the trailing chip.
struct CappedFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat
    var maxRows: Int
    var onFit: (Int) -> Void = { _ in }

    struct Arrangement: Equatable {
        var origins: [CGPoint?]
        var trailing: CGPoint?
        var fitCount: Int
        var size: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout Void) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout Void) {
        let result = arrange(width: bounds.width, subviews: subviews)
        let origins = result.origins + [result.trailing]
        for (index, subview) in subviews.enumerated() {
            if let origin = origins[index] {
                subview.place(
                    at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                    proposal: ProposedViewSize(size(subview, maxWidth: bounds.width))
                )
            } else {
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: .zero)
            }
        }
        onFit(result.fitCount)
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> Arrangement {
        guard let trailing = subviews.last else {
            return Arrangement(origins: [], trailing: nil, fitCount: 0, size: .zero)
        }
        return arrange(
            sizes: subviews.dropLast().map { size($0, maxWidth: width) },
            trailing: size(trailing, maxWidth: width),
            width: width
        )
    }

    private func size(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        return ideal.width <= maxWidth ? ideal : subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func arrange(sizes: [CGSize], trailing: CGSize, width: CGFloat) -> Arrangement {
        for fitCount in stride(from: sizes.count, through: 0, by: -1) {
            let placed = place(Array(sizes.prefix(fitCount)) + [trailing], width: width)
            guard let placed else { continue }
            let origins = Array(placed.origins.dropLast()).map(Optional.some)
                + Array(repeating: nil, count: sizes.count - fitCount)
            return Arrangement(origins: origins, trailing: placed.origins.last, fitCount: fitCount, size: placed.size)
        }
        return Arrangement(
            origins: Array(repeating: nil, count: sizes.count), trailing: nil, fitCount: 0, size: .zero
        )
    }

    private func place(_ sizes: [CGSize], width: CGFloat) -> (origins: [CGPoint], size: CGSize)? {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, rows = 1, widest: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > width {
                rows += 1
                guard rows <= maxRows else { return nil }
                y += rowHeight + rowSpacing
                x = 0
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, CGSize(width: widest, height: y + rowHeight))
    }
}
