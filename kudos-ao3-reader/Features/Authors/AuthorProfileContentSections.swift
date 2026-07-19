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
        if model.selectedTab == .works,
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
                .minimumHitTarget(28)
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
                    .minimumHitTarget(28)
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
                        if let work = entry.local {
                            // No .cardNavigation here: SensitiveWorkRow already applies it
                            // internally (MatureContent.swift) for its non-blurred,
                            // non-selecting branch. Re-wrapping it here would stack a
                            // second, unhidden, real-titled NavigationLink behind the
                            // blurred branch's reveal gate — a privacy bypass, not just a
                            // duplicate VoiceOver stop.
                            SensitiveWorkRow(work: work, expandAll: expandAll)
                                .cardRow()
                        } else if let remote = entry.remote {
                            AO3WorkRow(work: remote, expandAll: expandAll)
                                .cardNavigation(to: remote, accessibilityLabel: remote.title)
                                .cardRow()
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

    private func selectableWorkRow(_ work: AO3WorkSummary) -> some View {
        Button { onToggleSelection(work) } label: {
            AO3WorkRow(
                work: work,
                expandAll: expandAll,
                isSelecting: true,
                isSelected: selection.contains(work.id)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(work.title)
        .accessibilityValue(selection.contains(work.id) ? "Selected" : "Not selected")
    }
}

/// Series rows of an author profile (title, work count, navigation into series
/// detail). Extracted so Account › Writing can embed the same list for the
/// signed-in user.
struct AO3AuthorSeriesSection: View {
    var model: AO3AuthorProfileModel

    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        Section("Series") {
            if model.contentPhase == .loading, model.series.isEmpty {
                AO3AuthorLoadingRows()
            } else if model.series.isEmpty {
                AO3AuthorContentMessage(
                    model: model,
                    emptyTitle: "No series",
                    emptyMessage: "AO3 has no visible series for this author scope.",
                    emptySymbol: "square.stack"
                )
            } else {
                if case let .failed(message) = model.contentPhase {
                    AO3AuthorInlineErrorRow(message: message)
                }
                ForEach(model.series) { series in
                    AO3SeriesRow(series: series)
                        .cardNavigation(to: series, accessibilityLabel: series.title)
                        .cardRow()
                }
                AO3AuthorPaginationRows(model: model, auth: auth)
            }
        }
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
