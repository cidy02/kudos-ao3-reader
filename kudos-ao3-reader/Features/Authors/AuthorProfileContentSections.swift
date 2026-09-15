import SwiftData
import SwiftUI

// The Works / Bookmarks tab content of an author profile, extracted from
// `AuthorProfileView` so the Account tab can embed the same rows (scoped to the
// signed-in user's own profile) without the profile's hero card and
// Works/Series/Bookmarks/About segmented Picker shell. `AuthorProfileView` still
// renders these for arbitrary authors; Account supplies its own chrome around the
// same single implementation. All state and fetch logic stays on
// `AO3AuthorProfileModel` — these views are projections of it.

/// Skeleton placeholder rows shown while a profile content tab loads.
struct AO3AuthorLoadingRows: View {
    var body: some View {
        ForEach(0..<4, id: \.self) { _ in
            AO3WorkRowSkeleton().cardRow()
        }
    }
}

/// The empty-or-failed message row for a profile content tab. A failed load gets
/// the retry affordance; a genuinely empty AO3 list gets the tab's empty copy.
struct AO3AuthorContentMessage: View {
    var model: AO3AuthorProfileModel
    let emptyTitle: String
    let emptyMessage: String
    let emptySymbol: String

    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        if case let .failed(message) = model.contentPhase {
            AO3ProfileMessageRow(
                title: "Couldn't load \(model.selectedTab.rawValue.lowercased())",
                systemImage: "exclamationmark.triangle",
                message: message,
                actionTitle: "Try Again",
                action: { model.retry(auth: auth) }
            )
            .cardRow()
        } else {
            AO3ProfileMessageRow(
                title: emptyTitle,
                systemImage: emptySymbol,
                message: emptyMessage
            )
            .cardRow()
        }
    }
}

/// A non-blocking error banner above already-loaded rows (e.g. a refresh that
/// failed after the first page rendered).
struct AO3AuthorInlineErrorRow: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardRow()
    }
}

/// The Load More / retry-pagination rows for a paginated tab. Purely
/// presentational — any paginated source (an `AO3AuthorProfileModel` tab, or a
/// view's own local `@State`) supplies its current values and a load-more action.
struct AO3AuthorPaginationRows: View {
    var loadMoreError: String?
    var hasMore: Bool
    var isLoadingMore: Bool
    var currentPage: Int
    var totalPages: Int
    var loadMore: () -> Void

    var body: some View {
        if let loadMoreError {
            VStack(alignment: .leading, spacing: 8) {
                Label(loadMoreError, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Loading More", action: loadMore)
                    .frame(minHeight: 44)
            }
            .cardRow()
        } else if hasMore || isLoadingMore {
            Button(action: loadMore) {
                HStack {
                    if isLoadingMore { ProgressView().controlSize(.small) }
                    Text(isLoadingMore ? "Loading…" : "Load More")
                    Spacer()
                    Text("Page \(max(1, currentPage)) of \(totalPages)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .disabled(isLoadingMore)
            .cardRow()
        }
    }
}

extension AO3AuthorPaginationRows {
    /// Convenience for the common case: drive directly off an `AO3AuthorProfileModel`.
    init(model: AO3AuthorProfileModel, auth: AO3AuthService) {
        self.init(
            loadMoreError: model.loadMoreError,
            hasMore: model.hasMore,
            isLoadingMore: model.isLoadingMore,
            currentPage: model.currentPage,
            totalPages: model.totalPages,
            loadMore: { model.loadMore(auth: auth) }
        )
    }
}

/// The horizontal fandom-filter chip strip for the Works tab. Renders nothing
/// unless the Works tab is selected and the profile lists fandoms.
struct AO3AuthorFandomFilterSection: View {
    var model: AO3AuthorProfileModel
    /// Runs before a chip changes the filter (hosts use it to exit select mode).
    var onWillChange: () -> Void = {}
    /// `.list` → List `Section` + `.cardRow()` (detailed Account / author profile).
    /// `.scroll` → same card chrome as compact Account scope menu (aligned insets).
    var layout: AccountWorksLayout = .list

    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        // The facet is parsed from the plain works index and AO3 offers it only
        // there — `collected` renders its own `_collection_filters` and gifts
        // has no facet at all. Left up, it would offer a stranger's fandoms as
        // filters over a list they do not describe.
        if model.selectedTab == .works,
           model.worksScope == .works,
           let fandoms = model.header?.fandoms,
           !fandoms.isEmpty {
            if layout == .scroll {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fandom")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, CardListMetrics.sideMargin + CardListMetrics.innerHorizontal)
                    AccountScrollChromeCard {
                        chipStrip(fandoms: fandoms)
                    }
                }
            } else {
                Section("Fandom") {
                    chipStrip(fandoms: fandoms)
                        .cardRow()
                }
            }
        }
    }

    private func chipStrip(fandoms: [AO3AuthorFandom]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    onWillChange()
                    model.selectFandom(nil, auth: auth)
                } label: {
                    TagChip(text: "All", tinted: model.selectedFandom == nil)
                }
                .buttonStyle(.plain)
                // 44pt (not the 28pt dense-flow floor used elsewhere in Wave 2): this
                // is a single horizontal scroll row, not a wrapping FlowLayout, so a
                // full 44pt box can't overlap an adjacent row the way it could in a
                // dense tag cloud — and 44pt is what this bar already had before Wave 2
                // (a hand-rolled .frame(minHeight: 44)), so this restores rather than
                // grows it.
                .minimumHitTarget()
                .accessibilityAddTraits(model.selectedFandom == nil ? .isSelected : [])

                ForEach(fandoms) { fandom in
                    Button {
                        onWillChange()
                        model.selectFandom(fandom, auth: auth)
                    } label: {
                        let count = fandom.workCount.map { " (\($0.formatted()))" } ?? ""
                        TagChip(
                            text: fandom.name + count,
                            tinted: model.selectedFandom == fandom
                        )
                    }
                    .buttonStyle(.plain)
                    // See the "All" chip above: 44pt restores this bar's pre-Wave-2 size
                    // (a single scroll row, no FlowLayout overlap risk).
                    .minimumHitTarget()
                    .accessibilityAddTraits(model.selectedFandom == fandom ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// The Works rows of an author profile: loading skeletons, empty/failed copy,
/// work cards merged against the local library, optional select mode, and
/// pagination. Extracted verbatim from `AuthorProfileView.worksRows`.
/// Artboard **1u**'s swipe actions on your own works: "Swipe exposes AO3's real
/// actions — Edit, Tags, Delete". The mock also swipes a Chapter action, and all
/// four already have destinations or endpoints in the app.
///
/// A value rather than four closures, so the row only has to say *what* was
/// asked for and the profile decides how to open it — pushing from inside a
/// swipe button does not work, so the host turns this into a navigation.
nonisolated enum AO3OwnWorkAction: Identifiable, Hashable, Sendable {
    case edit(workID: Int)
    case tags(workID: Int)
    case chapter(workID: Int, title: String)
    case delete(workID: Int, title: String)

    var id: String {
        switch self {
        case let .edit(id): "edit-\(id)"
        case let .tags(id): "tags-\(id)"
        case let .chapter(id, _): "chapter-\(id)"
        case let .delete(id, _): "delete-\(id)"
        }
    }
}

struct AO3AuthorWorksSection: View {
    var model: AO3AuthorProfileModel
    var expandAll: Bool
    /// Account (and other hosts) can switch to a two-up cover grid; author
    /// profile keeps the default detailed list.
    var displayMode: WorkListDisplayMode = .detailed
    /// `.scroll` hosts compact grids the Library way (outside a List).
    var layout: AccountWorksLayout = .list
    var isSelecting: Bool = false
    var selection: Set<Int> = []
    var onToggleSelection: (AO3WorkSummary) -> Void = { _ in }
    /// Lets an embedding surface scope its Mature-reveal control to these rows.
    var onAdultContentVisibilityChange: (Bool) -> Void = { _ in }
    /// Own-profile hosts opt into the same in-card strip as Dashboard (1y).
    var showsPerformance: Bool = false
    /// 1u's swipe actions. `nil` on someone else's works, where AO3 would refuse
    /// every one of them — the swipe simply does not exist rather than failing.
    var onOwnWorkAction: ((AO3OwnWorkAction) -> Void)?

    @Environment(AO3AuthService.self) private var auth
    @Environment(PrivacyGate.self) private var gate
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var localWorks: [SavedWork]
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    var body: some View {
        Group {
            if layout == .scroll, displayMode == .compact, !isSelecting {
                scrollCompactBody
            } else {
                listBody
            }
        }
        .onChange(of: hasVisibleAdultContent, initial: true) { _, hasVisibleAdultContent in
            onAdultContentVisibilityChange(hasVisibleAdultContent)
        }
    }

    private var scrollCompactBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Works")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, CardListMetrics.sideMargin + CardListMetrics.innerHorizontal)
            if model.contentPhase == .loading, model.works.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if model.works.isEmpty {
                AccountScrollChromeCard {
                    AO3AuthorContentMessage(
                        model: model,
                        emptyTitle: "No works",
                        emptyMessage: "AO3 has no visible works for this author scope.",
                        emptySymbol: "books.vertical"
                    )
                }
            } else {
                if case let .failed(message) = model.contentPhase {
                    AccountScrollChromeCard {
                        AO3AuthorInlineErrorRow(message: message)
                    }
                }
                AccountWorksCompactGrid(entries: workEntries)
                AO3AuthorPaginationRows(model: model, auth: auth)
                    .padding(.horizontal, CardListMetrics.sideMargin + CardListMetrics.innerHorizontal)
            }
        }
    }

    private var listBody: some View {
        Section("Works") {
            if model.contentPhase == .loading, model.works.isEmpty {
                AO3AuthorLoadingRows()
            } else if model.works.isEmpty {
                AO3AuthorContentMessage(
                    model: model,
                    emptyTitle: "No works",
                    emptyMessage: "AO3 has no visible works for this author scope.",
                    emptySymbol: "books.vertical"
                )
            } else {
                if case let .failed(message) = model.contentPhase {
                    AO3AuthorInlineErrorRow(message: message)
                }
                if isSelecting {
                    ForEach(model.works) { work in
                        selectableWorkRow(work)
                            .cardRow(isSelected: selection.contains(work.id))
                    }
                } else {
                    ForEach(workEntries) { entry in
                        AO3AuthorWorkCard(
                            entry: entry,
                            expandAll: expandAll,
                            usesLedger: layout != .scroll,
                            showsPerformance: showsPerformance
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            ownWorkSwipeActions(entry)
                        }
                    }
                }
                AO3AuthorPaginationRows(model: model, auth: auth)
            }
        }
    }

    private var workEntries: [CanonicalWork] {
        canonicalEntries(
            localLibrary: localWorks.filter {
                !gate.isHidden($0, enabled: hideMature, mode: matureMode)
            }
        )
    }

    private var hasVisibleAdultContent: Bool {
        canonicalEntries(localLibrary: localWorks)
            .contains { $0.local?.isAdult == true }
    }

    private func canonicalEntries(localLibrary: [SavedWork]) -> [CanonicalWork] {
        CanonicalWorkMerge.remoteLed(remote: model.works, localLibrary: localLibrary)
    }

    /// 1u's four. Empty when these are not your works, which leaves the row with
    /// no trailing swipe at all.
    @ViewBuilder
    private func ownWorkSwipeActions(_ entry: CanonicalWork) -> some View {
        if let onOwnWorkAction, let remote = entry.remote {
            Button {
                onOwnWorkAction(.delete(workID: remote.id, title: remote.title))
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Button {
                onOwnWorkAction(.chapter(workID: remote.id, title: remote.title))
            } label: {
                Label("Chapter", systemImage: "text.append")
            }
            .tint(.indigo)

            Button {
                onOwnWorkAction(.tags(workID: remote.id))
            } label: {
                Label("Tags", systemImage: "tag")
            }
            .tint(.teal)

            Button {
                onOwnWorkAction(.edit(workID: remote.id))
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
            .tint(.blue)
        }
    }

    private func selectableWorkRow(_ work: AO3WorkSummary) -> some View {
        let isSelected = selection.contains(work.id)
        return Button { onToggleSelection(work) } label: {
            AO3WorkRow(
                work: work,
                expandAll: expandAll,
                isSelecting: true,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(work.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        // Matches `SelectableAO3WorkRow` (`RemoteWorkSelection.swift`) exactly —
        // this row is a deliberately separate component (its own doc comment:
        // "AuthorProfileView keeps its own rows"), not a stale duplicate, so
        // the fix is these two modifiers here rather than a controller-based
        // consolidation (HIG audit UI-2/UI-3).
        .accessibilityHint("Double-tap to \(isSelected ? "deselect" : "select") this work.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Series rows of an author profile (title, work count, navigation into series
/// detail). Extracted so Account › Writing can embed the same list for the
/// signed-in user.
struct AO3AuthorSeriesSection: View {
    var model: AO3AuthorProfileModel
    /// The signed-in user's own series list can offer "New series on AO3" (Safari).
    /// Other authors get the existing empty copy. Creating a series is an AO3 write
    /// this screen does not implement.
    var showsNewSeriesOnAO3: Bool = false
    var displayMode: WorkListDisplayMode = .detailed
    var layout: AccountWorksLayout = .list

    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        Section("Series") {
            if model.contentPhase == .loading, model.series.isEmpty {
                AO3AuthorLoadingRows()
            } else if model.series.isEmpty {
                if case .failed = model.contentPhase {
                    AO3AuthorContentMessage(
                        model: model,
                        emptyTitle: "No series",
                        emptyMessage: "AO3 has no visible series for this author scope.",
                        emptySymbol: "square.stack"
                    )
                } else if showsNewSeriesOnAO3 {
                    // 1az's own copy, verbatim. The generic empty message said
                    // nothing about what a series is FOR, which is the half that
                    // earns the trip to Safari underneath it.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You have not made a series.")
                            .font(.system(size: 14, weight: .semibold))
                        Text("A series groups your works so they read in order. "
                            + "Series are created on AO3; anything you make there "
                            + "appears here on the next refresh.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardRow()
                    AccountExternalNavCard(
                        title: "New series on AO3",
                        systemImage: "square.stack.badge.plus",
                        pathSuffix: "series/new"
                    )
                } else {
                    AO3AuthorContentMessage(
                        model: model,
                        emptyTitle: "No series",
                        emptyMessage: "AO3 has no visible series for this author scope.",
                        emptySymbol: "square.stack"
                    )
                }
            } else {
                if case let .failed(message) = model.contentPhase {
                    AO3AuthorInlineErrorRow(message: message)
                }
                ForEach(model.series) { series in
                    // Follows the chosen mode, not the layout. It used to draw
                    // ledger rows on the list layout whatever the reader picked,
                    // which is the same Ledger/Detailed conflation fixed
                    // elsewhere — and this screen had no picker at all until now.
                    AO3SeriesRow(
                        series: series,
                        presentation: displayMode == .ledger ? .ledger : .standard
                    )
                        .cardNavigation(to: series, accessibilityLabel: series.title)
                        .cardRow()
                }
                AO3AuthorPaginationRows(model: model, auth: auth)
            }
        }
    }
}

/// Zero-length series list for the signed-in account. The action leaves for
/// Safari because creating a series is an AO3 write the app does not do.
struct AO3SeriesEmptyCard: View {
    @Environment(\.openURL) private var openURL
    @Environment(ThemeManager.self) private var themeManager

    /// AO3's New Series form. Constant, not a session — posting stays on the site.
    static let newSeriesURL = URL(string: "https://archiveofourown.org/series/new")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("You have not made a series.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(
                    "A series groups your works so they read in order. "
                        + "Series are created on AO3; anything you make there appears here on the next refresh."
                )
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(themeManager.appTheme.glassStroke(0.12))
                .frame(height: 0.5)
                .accessibilityHidden(true)

            Button {
                openURL(Self.newSeriesURL)
            } label: {
                HStack(spacing: 7) {
                    Text("New series on AO3")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .foregroundStyle(buttonLabelColor)
                .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens archiveofourown.org in Safari")

            Text("Opens archiveofourown.org in Safari. Posting is not something the app does.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .subjectPanel(cornerRadius: 18)
    }

    private var buttonLabelColor: Color {
        Color.accentColor.relativeLuminance > 0.45 ? Color.black : Color.white
    }
}

/// The Bookmarks rows of an author profile — the rich bookmark cards
/// (notes/tags/private/recommendation) with pagination. Extracted verbatim from
/// `AuthorProfileView.bookmarkRows`.
struct AO3AuthorBookmarksSection: View {
    var model: AO3AuthorProfileModel
    var expandAll: Bool
    var displayMode: WorkListDisplayMode = .detailed
    var layout: AccountWorksLayout = .list

    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        if layout == .scroll, displayMode == .compact {
            scrollCompactBody
        } else {
            listBody
        }
    }

    private var scrollCompactBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bookmarks")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, CardListMetrics.sideMargin + CardListMetrics.innerHorizontal)
            if model.contentPhase == .loading, model.bookmarks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if model.bookmarks.isEmpty {
                AccountScrollChromeCard {
                    AO3AuthorContentMessage(
                        model: model,
                        emptyTitle: "No visible bookmarks",
                        emptyMessage: "AO3 has no bookmarks visible to this session for this author scope.",
                        emptySymbol: "bookmark"
                    )
                }
            } else {
                if case let .failed(message) = model.contentPhase {
                    AccountScrollChromeCard {
                        AO3AuthorInlineErrorRow(message: message)
                    }
                }
                AccountBookmarksCompactGrid(bookmarks: model.bookmarks)
                AO3AuthorPaginationRows(model: model, auth: auth)
                    .padding(.horizontal, CardListMetrics.sideMargin + CardListMetrics.innerHorizontal)
            }
        }
    }

    private var listBody: some View {
        Section("Bookmarks") {
            if model.contentPhase == .loading, model.bookmarks.isEmpty {
                AO3AuthorLoadingRows()
            } else if model.bookmarks.isEmpty {
                AO3AuthorContentMessage(
                    model: model,
                    emptyTitle: "No visible bookmarks",
                    emptyMessage: "AO3 has no bookmarks visible to this session for this author scope.",
                    emptySymbol: "bookmark"
                )
            } else {
                if case let .failed(message) = model.contentPhase {
                    AO3AuthorInlineErrorRow(message: message)
                }
                ForEach(model.bookmarks) { bookmark in
                    AO3AuthorBookmarkRow(bookmark: bookmark, expandAll: expandAll)
                        .cardNavigation(to: bookmark.work, accessibilityLabel: bookmark.work.title)
                        .cardRow()
                }
                AO3AuthorPaginationRows(model: model, auth: auth)
            }
        }
    }
}
