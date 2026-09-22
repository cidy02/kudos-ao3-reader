import SwiftData
import SwiftUI

/// A login-gated list of AO3 works fetched from one of the user's account pages
/// (Marked for Later, bookmarks, …). Self-contained: signed-out prompt, loading,
/// empty, error + retry, and a paginated list reusing the search result card.
/// A work that's also saved locally renders as its richer local row instead of a
/// second, remote card. Navigates through the host's navigation stack, so the host
/// must register `AO3WorkSummary` and `SavedWork` destinations (all hosts do).
struct AO3AccountWorksList: View {
    /// Which account list to show. Holds the page's copy, URL, and fetch method so
    /// the view body is identical across lists.
    enum Kind: Hashable {
        case markedForLater
        case bookmarks
        case history
        case subscriptions
        /// Works in a named collection (the user's own collections list links here).
        case collection(name: String, title: String)

        var title: String {
            switch self {
            case .markedForLater: "Marked for Later"
            case .bookmarks: "My AO3 Bookmarks"
            case .history: "My AO3 History"
            case .subscriptions: "My Subscriptions"
            case let .collection(_, title): title
            }
        }

        var emptyTitle: String {
            switch self {
            case .markedForLater: "Nothing marked for later"
            case .bookmarks: "No bookmarks yet"
            case .history: "No reading history"
            case .subscriptions: "No subscriptions"
            case .collection: "No works in this collection"
            }
        }

        var emptyMessage: String {
            switch self {
            case .markedForLater: "Tap “Mark for Later” on a work on AO3 to queue it up here."
            case .bookmarks: "Bookmark a work on AO3 to see it here."
            case .history: "Works you read on AO3 show up here."
            case .subscriptions: "Works you subscribe to on AO3 show up here."
            case .collection: "This collection has no works yet."
            }
        }

        /// Empty / signed-out chrome — bookmark is reserved for AO3 bookmarks only.
        var emptySymbol: String {
            switch self {
            case .markedForLater: WorkActionLabels.savedForLaterEmptySymbol
            case .bookmarks: "bookmark"
            case .history: "clock.arrow.circlepath"
            case .subscriptions: "bell"
            case .collection: "square.stack"
            }
        }

        var signedOutTitle: String {
            switch self {
            case .markedForLater: "Marked for Later"
            case .bookmarks: "AO3 Bookmarks"
            case .history: "AO3 History"
            case .subscriptions: "AO3 Subscriptions"
            case let .collection(_, title): title
            }
        }

        var signedOutMessage: String {
            switch self {
            case .markedForLater: "Log in to AO3 to see the works you've marked to read later."
            case .bookmarks: "Log in to AO3 to see the works you've bookmarked."
            case .history: "Log in to AO3 to see your reading history."
            case .subscriptions: "Log in to AO3 to see the works you subscribe to."
            case .collection: "Log in to AO3 to see this collection's works."
            }
        }

        func url(username: String, page: Int) -> URL? {
            switch self {
            case .markedForLater: AO3Client.markedForLaterURL(username: username, page: page)
            case .bookmarks: AO3Client.bookmarksURL(username: username, page: page)
            case .history: AO3Client.historyURL(username: username, page: page)
            case .subscriptions: AO3Client.subscriptionsURL(username: username, page: page)
            case let .collection(name, _): AO3Client.collectionWorksURL(name: name, page: page)
            }
        }

        func fetch(for request: URLRequest, page: Int) async throws -> AO3SearchPage {
            switch self {
            // Standard work-blurb pages; bookmarks and subscriptions need their own
            // outer selector / parser.
            // Both readings pages carry per-row visit data; a collection does not.
            case .markedForLater, .history:
                try await AO3Client.shared.readingsPage(for: request, page: page)
            case .collection:
                try await AO3Client.shared.worksPage(for: request, page: page)
            case .bookmarks:
                // The screen does not use this branch. `load` calls
                // `accountBookmarksPage` so the note, tags, privacy, and date
                // survive; folding that page into `AO3SearchPage` would drop them.
                try await AO3Client.shared.bookmarksPage(for: request, page: page)
            case .subscriptions:
                try await AO3Client.shared.subscriptionsPage(for: request, page: page)
            }
        }

        /// Where a fetched page's size lands in the account-list counts cache
        /// (nil for per-collection pages — only the whole-account lists get a
        /// count on the Account tab's Overview cards).
        var countsKind: AO3AccountListKind? {
            switch self {
            case .markedForLater: .markedForLater
            case .bookmarks: .bookmarks
            case .history: .history
            case .subscriptions: .subscriptions
            case .collection: nil
            }
        }
    }

    let kind: Kind
    /// Where the reader came from, drawn as the header's kicker.
    ///
    /// 1ag: Home's Subscriptions chevron opens *this* screen rather than a second
    /// copy, and "The path anchor follows the same source, reading Home or AO3
    /// Account to match." It was hardcoded to AO3 Account, so arriving from Home
    /// announced a tab you had not been in.
    var originKicker: String = "AO3 Account"

    @Environment(AO3AuthService.self) private var auth
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var theme
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var localWorks: [SavedWork]

    @State private var works: [AO3WorkSummary] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var phase: Phase = .idle
    @State private var showLogin = false
    /// Spec 1p's "X New" badge. Loaded once per appearance rather than read from
    /// `UserDefaults` per row — a decode per row of a two-hundred row list is the
    /// kind of thing that only shows up on someone else's device.
    @State private var subscriptionWatermarks: [Int: SubscriptionWatermark] = [:]
    /// 1t's per-row visit data, keyed the way the watermarks above are. Rows for
    /// works AO3 has deleted carry no id and so are absent here — they also have
    /// no blurb to annotate.
    @State private var readingEntries: [Int: AO3ReadingEntry] = [:]
    /// 1q's per-row bookmark, keyed by the work id (`AO3AuthorBookmark.work.id`),
    /// the same way `readingEntries` is. The author's Bookmarks tab already
    /// parses the note, tags, privacy flag, and date; this list used to ask for
    /// an `AO3SearchPage` and throw them away.
    @State private var bookmarkDetails: [Int: AO3AuthorBookmark] = [:]
    @State private var expandAll = false
    /// Matches Account tab's layout preference so Refine screens stay consistent.
    @AppStorage("account.displayMode") private var displayMode: WorkListDisplayMode = .compact
    /// Client-side refine of the loaded page — narrows the works on screen in place,
    /// contextual to this account list rather than a fresh AO3 search.
    @State private var filters = AO3SearchFilters()
    @State private var showingFilters = false
    /// 1t's Everything / In progress / Finished pills. Local reading state only;
    /// ignored by every other list kind.
    @State private var historyProgressFilter = AO3HistoryProgressFilter.everything
    /// 1o's All / Updated / Downloaded pills. Ignored by every other list kind.
    @State private var markedForLaterFilter = AO3MarkedForLaterFilter.all
    /// 1q's All / Recs / Private / With notes pills. They narrow the loaded
    /// page. Ignored by every other list kind.
    @State private var bookmarksFilter = AO3BookmarksFilter.all
    /// Subscriptions' All / Updated pills. They narrow the loaded page.
    /// Ignored by every other list kind.
    @State private var subscriptionsFilter = AO3SubscriptionsFilter.all
    /// Each subscription row's unsubscribe form action, keyed by work id the
    /// way `bookmarkDetails` is. Empty for every other list.
    @State private var unsubscribePaths: [Int: String] = [:]
    /// Work-page summaries for subscription rows, same key. The index blurb's
    /// `chapters` is empty, so Updated and the chapter range read this once
    /// the row's enrichment has arrived.
    @State private var enrichedSubscriptionSummaries: [Int: AO3WorkSummary] = [:]
    /// Generation whose rows are on screen. Nil until the load task has bound
    /// one. A later run with the same generation is a reappearance and must
    /// not wipe a page that is already loaded.
    @State private var loadedSessionGeneration: Int?
    /// Marked for Later's own "since you looked" clock. Not the subscriptions
    /// map: the same work can be on both lists, and one look must not clear both.
    @State private var markedForLaterWatermarks: [Int: SubscriptionWatermark] = [:]
    /// Pages fetched during this visit. Recorded when the screen goes away, so
    /// the Updated group stays up for the visit that revealed it.
    @State private var markedForLaterSeenThisVisit: [Int: AO3WorkSummary] = [:]
    /// Set when a Marked for Later fetch succeeds. The artboard's "synced 2 min
    /// ago". Not persisted: the next open fetches again and starts a new clock.
    @State private var lastSyncedAt: Date?
    /// The row whose AO3 history entry the reader asked to remove. Setting it
    /// opens the confirm; the write runs only from that confirm.
    @State private var pendingHistoryDelete: CanonicalWork?
    @State private var confirmClearHistory = false
    @State private var historyWriteError: String?
    @State private var historyWriteInFlight = false
    /// The row whose AO3 subscription the reader asked to drop. Setting it
    /// opens the confirm; the write runs only from that confirm.
    @State private var pendingUnsubscribe: CanonicalWork?
    @State private var subscriptionWriteError: String?
    @State private var subscriptionWriteInFlight = false
    /// Chapter-count fetches for the subscriptions page on screen. Not part of
    /// `AO3AccountWorksSessionReload.cleared`: a task is not that value. A new
    /// generation cancels it from `clearLoadedAccount`, and a new page replaces it.
    @State private var subscriptionEnrichment: Task<Void, Never>?

    private enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    /// The loaded page narrowed by the active refine filters.
    private var visibleWorks: [AO3WorkSummary] {
        filters.apply(to: works)
    }

    /// History's progress pills, applied after the refine facets. Other lists
    /// leave the merged page alone.
    private var historyDisplayedEntries: [CanonicalWork] {
        guard kind == .history else { return visibleEntries }
        return visibleEntries.filter {
            historyProgressFilter.includes(
                isInProgress: $0.local?.readingState == .inProgress,
                isFinished: $0.local?.isFinished == true
            )
        }
    }

    /// The visible page with locally-saved matches paired in, so each renders as
    /// the richer local row. Matching only against privacy-visible works keeps a
    /// Hide-mode Mature work on its plain remote row instead of surfacing local
    /// state for it; in Blur mode the paired local row blurs itself.
    private var visibleEntries: [CanonicalWork] {
        CanonicalWorkMerge.remoteLed(
            remote: visibleWorks,
            localLibrary: localWorks.filter { !gate.isHidden($0, enabled: hideMature, mode: matureMode) }
        )
    }

    var body: some View {
        Group {
            if auth.isLoggedIn {
                signedInContent
            } else {
                signedOutPrompt
            }
        }
        // The list states its own name in the header block now (spec 1o), so the
        // bar would be saying it twice — `subjectScreenWash` empties it, and
        // hides the floating tab bar this used to ask for separately. macOS has
        // no such treatment in its window chrome and keeps the real title.
        #if os(macOS)
            .navigationTitle(kind.title)
        #endif
            .toolbar {
                // Gated as a whole, not just its inner pieces — an empty HStack still
                // reserves an (empty-looking) toolbar slot, most commonly hit here
                // while signed out (no local matches to reveal, no filter/menu cluster
                // since nothing's loaded yet).
                let hasMature = hideMature && visibleEntries.contains(where: { $0.local?.isAdult == true })
                let hasWorks = auth.isLoggedIn && phase == .loaded && !works.isEmpty
                if hasMature || hasWorks {
                    // Matches the pattern already established in LibraryView.swift's
                    // dashboard toolbar. WorkListMoreMenu's own gate widened to
                    // `hasWorks || hasMature` — Privacy now lives inside it, so it
                    // needs a home even with nothing loaded yet.
                    ActionToolbar(items: [
                        hasWorks
                            ? AnyView(FilterButton(filtersActive: filters.hasActiveFilters,
                                                    showingFilters: $showingFilters,
                                                    onClearFilters: { filters = AO3SearchFilters() }))
                            : nil,
                        AnyView(WorkListMoreMenu {
                            if hasMature {
                                MatureRevealToggle()
                            }
                            if hasWorks {
                                // 1o is one layout — covers for what changed, ledger
                                // rows for the rest — so the account-wide display
                                // switch would change a preference this screen
                                // does not draw. Subscriptions is one list too:
                                // the chapter range and the unsubscribe swipe
                                // are on that row, and the switch would not draw them.
                                if kind != .markedForLater, kind != .subscriptions {
                                    DisplayModeMenuPicker(mode: $displayMode)
                                    if displayMode != .compact {
                                        ExpandAllMenuItem(expandAll: $expandAll)
                                    }
                                }
                                if tracksNewChapters, worksWithNewChapters > 0 {
                                    Button(action: markAllSeen) {
                                        Label("Mark All as Seen", systemImage: "bell.badge.slash")
                                    }
                                }
                                if kind == .history {
                                    Button(role: .destructive) {
                                        confirmClearHistory = true
                                    } label: {
                                        Label("Clear History", systemImage: "trash")
                                    }
                                }
                            }
                        })
                    ].compactMap { $0 })
                }
            }
            .filterPanelPresentation(isPresented: $showingFilters) {
                AO3FilterPanel(
                    filters: $filters,
                    mode: .refine,
                    canReset: filters.hasActiveFilters,
                    onApply: { showingFilters = false },
                    onReset: { filters = AO3SearchFilters() },
                    // The same array `visibleWorks` narrows, so 1au's line and the
                    // list behind it can never disagree.
                    refineSource: works
                )
                .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
            }
            .task(id: AO3AccountWorksLoadID(
                sessionGeneration: auth.sessionGeneration,
                isLoggedIn: auth.isLoggedIn
            )) {
                // Watermarks are a device clock, not this account's rows, so a
                // generation change does not clear them. Load them before that
                // clear so an empty check is not looking at a map the clear wiped.
                if tracksNewChapters, subscriptionWatermarks.isEmpty {
                    subscriptionWatermarks = SubscriptionWatermarks.load()
                }
                if kind == .markedForLater, markedForLaterWatermarks.isEmpty {
                    markedForLaterWatermarks = SubscriptionWatermarks.load(namespace: .markedForLater)
                }
                // A new generation means these rows belong to the previous
                // session. Drop them before the idle gate, or a sign-out and
                // sign-in refires this task, sees `.loaded`, and keeps the
                // previous account's works and unsubscribe paths.
                if AO3AccountWorksSessionReload.shouldClear(
                    boundGeneration: loadedSessionGeneration,
                    sessionGeneration: auth.sessionGeneration
                ) {
                    clearLoadedAccount()
                    loadedSessionGeneration = auth.sessionGeneration
                }
                if auth.isLoggedIn, phase == .idle {
                    await load(page: 1)
                } else if kind == .subscriptions, phase == .loaded,
                          subscriptionEnrichment?.isCancelled != false {
                    // Reappearing after the walk was cancelled. The same
                    // generation keeps the page, so this is not a new load.
                    enrichLoadedSubscriptionPage(works, generation: auth.sessionGeneration)
                }
            }
            .onDisappear { subscriptionEnrichment?.cancel() }
            .sheet(isPresented: $showLogin) { AO3LoginView() }
            .destructiveConfirmation(
                for: $pendingHistoryDelete,
                title: "Delete from History?",
                confirmLabel: "Delete from History",
                message: { entry in
                    let title = entry.title
                    if title.isEmpty {
                        return "This removes the work from your AO3 reading history. "
                            + "The work itself is left where it is."
                    }
                    return "“\(title)” will be removed from your AO3 reading history. "
                        + "The work itself is left where it is."
                },
                perform: { entry in Task { await deleteHistoryEntry(entry) } }
            )
            .destructiveConfirmation(
                isPresented: $confirmClearHistory,
                title: "Clear your entire history?",
                confirmLabel: "Clear History",
                message: "This removes every work from your AO3 reading history. It cannot be undone.",
                perform: { Task { await clearHistory() } }
            )
            .alert(
                "Couldn't update history",
                isPresented: Binding(
                    get: { historyWriteError != nil },
                    set: { if !$0 { historyWriteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { historyWriteError = nil }
            } message: {
                Text(historyWriteError ?? "")
            }
            .destructiveConfirmation(
                for: $pendingUnsubscribe,
                title: "Unsubscribe?",
                confirmLabel: "Unsubscribe",
                message: { entry in
                    let title = entry.title
                    if title.isEmpty {
                        return "This removes the work from your AO3 subscriptions. "
                            + "The work itself is left where it is."
                    }
                    return "“\(title)” will be removed from your AO3 subscriptions. "
                        + "The work itself is left where it is."
                },
                perform: { entry in Task { await unsubscribe(entry) } }
            )
            .alert(
                "Couldn't unsubscribe",
                isPresented: Binding(
                    get: { subscriptionWriteError != nil },
                    set: { if !$0 { subscriptionWriteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { subscriptionWriteError = nil }
            } message: {
                Text(subscriptionWriteError ?? "")
            }
    }

    // MARK: Signed in

    @ViewBuilder
    private var signedInContent: some View {
        switch phase {
        case .loaded where works.isEmpty:
            ContentUnavailableView {
                Label(kind.emptyTitle, systemImage: kind.emptySymbol)
            } description: {
                Text(kind.emptyMessage)
            }

        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't load your list", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load(page: currentPage) } }
            }

        case .loading where works.isEmpty:
            // First page of this AO3 list — show the work-row shape (same skeleton as
            // Search/Browse) instead of a centered spinner.
            AO3WorkRowSkeletonList()

        default:
            worksList
        }
    }

    /// 1t's reading line, under the blurb and inside the same card.
    ///
    /// Adds nothing at all on a list that is not History or Marked for Later —
    /// only `/users/:id/readings` carries this data, so every other caller of
    /// this list renders exactly as before.
    @ViewBuilder
    private func readingAnnotated<Content: View>(
        _ entry: CanonicalWork,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let reading = readingEntry(for: entry) {
            VStack(alignment: .leading, spacing: 6) {
                content()
                readingFootnote(reading)
            }
        } else {
            content()
        }
    }

    private func readingEntry(for entry: CanonicalWork) -> AO3ReadingEntry? {
        // CanonicalWork already resolves local-or-remote to one AO3 id.
        guard let id = entry.ao3WorkID else { return nil }
        return readingEntries[id]
    }

    /// Each fact is dropped rather than zeroed when AO3 did not state it: a row
    /// that names no version status says nothing about versions.
    private func readingFootnote(_ reading: AO3ReadingEntry) -> some View {
        let facts = [
            reading.visitCountDisplay,
            reading.versionDisplay,
            reading.lastVisitedDisplay
        ].compactMap(\.self)
        return VStack(alignment: .leading, spacing: 4) {
            if !facts.isEmpty {
                Text(facts.joined(separator: " · "))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if reading.isMarkedForLater || reading.isFlaggedToSkip {
                HStack(spacing: 6) {
                    if reading.isMarkedForLater {
                        Label("Marked for later", systemImage: "clock.badge")
                    }
                    if reading.isFlaggedToSkip {
                        Label("Flagged to skip", systemImage: "eye.slash")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var worksList: some View {
        // Compact: Library-style root ScrollView + NavigationLink grid.
        // Detailed: card List with one NavigationLink/cardNavigation per row.
        Group {
            if kind == .history {
                AO3HistoryWorksBrowser(
                    entries: historyDisplayedEntries,
                    readings: readingEntries,
                    displayMode: displayMode,
                    expandAll: expandAll,
                    palette: accountPalette,
                    kicker: originKicker,
                    subtitle: headerTallyLine,
                    showPagination: showPagination,
                    currentPage: currentPage,
                    totalPages: totalPages,
                    isLoading: phase == .loading,
                    filter: $historyProgressFilter,
                    onPage: { page in Task { await load(page: page) } },
                    onDelete: { pendingHistoryDelete = $0 }
                )
            } else if kind == .markedForLater {
                AO3MarkedForLaterWorksBrowser(
                    entries: visibleEntries,
                    watermarks: markedForLaterWatermarks,
                    expandAll: expandAll,
                    palette: accountPalette,
                    kicker: originKicker,
                    syncedAt: lastSyncedAt,
                    showPagination: showPagination,
                    currentPage: currentPage,
                    totalPages: totalPages,
                    isLoading: phase == .loading,
                    filter: $markedForLaterFilter,
                    onPage: { page in Task { await load(page: page) } }
                )
                .onDisappear { persistMarkedForLaterLook() }
            } else if kind == .bookmarks {
                AO3BookmarksWorksBrowser(
                    entries: visibleEntries,
                    bookmarks: bookmarkDetails,
                    displayMode: displayMode,
                    expandAll: expandAll,
                    palette: accountPalette,
                    kicker: originKicker,
                    showPagination: showPagination,
                    currentPage: currentPage,
                    totalPages: totalPages,
                    isLoading: phase == .loading,
                    filter: $bookmarksFilter,
                    onPage: { page in Task { await load(page: page) } }
                )
            } else if kind == .subscriptions {
                AO3SubscriptionsWorksBrowser(
                    entries: visibleEntries,
                    watermarks: subscriptionWatermarks,
                    unsubscribePaths: unsubscribePaths,
                    enrichedSummaries: enrichedSubscriptionSummaries,
                    expandAll: expandAll,
                    palette: accountPalette,
                    kicker: originKicker,
                    showPagination: showPagination,
                    currentPage: currentPage,
                    totalPages: totalPages,
                    isLoading: phase == .loading,
                    filter: $subscriptionsFilter,
                    onPage: { page in Task { await load(page: page) } },
                    onUnsubscribe: { pendingUnsubscribe = $0 },
                    onEnriched: noteEnrichedSubscription
                )
            } else if displayMode == .compact {
                ScrollView {
                    VStack(spacing: 12) {
                        subjectHeader.padding(.top, 20)
                        if showPagination { paginationBar }
                        AccountWorksCompactGrid(entries: visibleEntries)
                        if showPagination { paginationBar }
                    }
                    .padding(.vertical, 8)
                }
                // The wash, not the flat backdrop: the compact grid is a different
                // arrangement of this list, not a different screen, and a page
                // that changed colour at a display-mode switch would be a bug in
                // waiting. `subjectScreenWash` paints the backdrop itself.
                .subjectScreenWash(palette: accountPalette)
            } else {
                List {
                    subjectHeaderSection
                    if showPagination {
                        Section { paginationRow }
                    }
                    Section {
                        ForEach(visibleEntries) { entry in
                            if let work = entry.local {
                                // No .cardNavigation here: SensitiveWorkRow already applies
                                // it internally (MatureContent.swift) for its non-blurred,
                                // non-selecting branch — re-wrapping it stacks a second,
                                // unhidden, real-titled NavigationLink behind the blurred
                                // branch's reveal gate.
                                readingAnnotated(entry) {
                                    SensitiveWorkRow(
                                        work: work,
                                        expandAll: expandAll,
                                        presentation: displayMode == .ledger ? .ledger : .standard
                                    )
                                }
                                    // The badge belongs on this branch too: a
                                    // subscribed work already in the library renders
                                    // here, and it is the one most worth telling
                                    // someone about — they can open it right now.
                                    .overlay(alignment: .topTrailing) {
                                        newChapterBadge(newChapterCount(for: entry)).padding(10)
                                    }
                                    // The row's wash is painted here, at the card's true
                                    // outer edge, rather than inside the row — see
                                    // `WorkLedgerRow.drawsBackground`.
                                    .cardRow(tintHue: CoverArt.workHue(
                                        fandoms: work.workFandoms, title: work.title
                                    ))
                            } else if let remote = entry.remote {
                                let newChapters = newChapterCount(for: entry)
                                // Local and remote take the *same* presentation, so a
                                // list holding both does not change shape work by work
                                // depending on which ones happen to be in the library.
                                readingAnnotated(entry) {
                                    EnrichingAO3WorkRow(
                                        work: remote,
                                        expandAll: expandAll,
                                        presentation: displayMode == .ledger ? .searchLedger : .standard
                                    )
                                }
                                .overlay(alignment: .topTrailing) {
                                    newChapterBadge(newChapters).padding(10)
                                }
                                .cardRow(tintHue: CoverArt.workHue(
                                    fandoms: remote.fandoms, title: remote.title
                                ))
                            }
                        }
                    }
                    if showPagination {
                        Section { paginationRow }
                    }
                }
                .cardList()
                .subjectScreenWash(palette: accountPalette)
            }
        }
        .overlay {
            if phase == .loading {
                ProgressView().controlSize(.large)
            } else if visibleWorks.isEmpty, !works.isEmpty {
                // Everything on the page was filtered out by the refine facets.
                ContentUnavailableView {
                    Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No works on this page match the current filters.")
                } actions: {
                    Button("Clear Filters") { filters = AO3SearchFilters() }
                }
            }
        }
        .refreshable { await load(page: currentPage) }
    }

    // MARK: Subscriptions — what is new since you last looked (spec 1p)

    /// Only Subscriptions carries the badge. On Bookmarks or History "new chapters"
    /// would be a fact about a list that is not about following anything.
    private var tracksNewChapters: Bool { kind == .subscriptions }

    /// New chapters on this row since it was last seen, or 0 when there is nothing
    /// to say.
    private func newChapterCount(for entry: CanonicalWork) -> Int {
        guard tracksNewChapters, let remote = entry.remote else { return 0 }
        return SubscriptionWatermarks.newChapterCount(
            for: resolvedSubscriptionWork(remote), watermarks: subscriptionWatermarks
        )
    }

    /// The work-page summary when this row has one. The index blurb's
    /// `chapters` is empty, so a badge computed from it is always zero.
    private func resolvedSubscriptionWork(_ remote: AO3WorkSummary) -> AO3WorkSummary {
        AO3SubscriptionsChapterSource.summary(
            remote: remote, enrichedSummaries: enrichedSubscriptionSummaries
        )
    }

    @ViewBuilder
    private func newChapterBadge(_ count: Int) -> some View {
        if count > 0 {
            Text(count == 1 ? "1 NEW" : "\(count) NEW")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accountPalette.accentOnFill)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(accountPalette.chipFill)
                        .overlay(Capsule().strokeBorder(accountPalette.chipStroke, lineWidth: 0.5))
                )
                .accessibilityLabel(
                    count == 1 ? "1 new chapter" : "\(count) new chapters"
                )
        }
    }

    /// Works on the page that have something new.
    private var worksWithNewChapters: Int {
        guard tracksNewChapters else { return 0 }
        return visibleEntries.filter { newChapterCount(for: $0) > 0 }.count
    }

    /// Same first-sight rule as subscriptions, on Marked for Later's own key.
    /// Adds only: a work already watermarked keeps its "updated" place through
    /// the load that is drawing it. Leaving the screen is what records the look
    /// (`persistMarkedForLaterLook`).
    private func baselineMarkedForLater(_ works: [AO3WorkSummary]) {
        guard kind == .markedForLater, !works.isEmpty else { return }
        guard let updated = SubscriptionWatermarks.baseline(works, into: markedForLaterWatermarks) else {
            return
        }
        markedForLaterWatermarks = updated
        SubscriptionWatermarks.save(updated, namespace: .markedForLater)
    }

    /// Writes this visit's pages as seen, without touching the map the screen is
    /// still drawing from. The next open loads the saved counts, so "updated"
    /// means chapters posted since the reader left — not since the row appeared.
    private func persistMarkedForLaterLook() {
        guard kind == .markedForLater, !markedForLaterSeenThisVisit.isEmpty else { return }
        let stored = SubscriptionWatermarks.load(namespace: .markedForLater)
        let updated = SubscriptionWatermarks.markSeen(
            Array(markedForLaterSeenThisVisit.values),
            in: stored
        )
        SubscriptionWatermarks.save(updated, namespace: .markedForLater)
        markedForLaterSeenThisVisit = [:]
    }

    /// Records a first sight for anything not yet watermarked, so a reader opening
    /// this screen for the first time does not meet three hundred badges — every one
    /// technically true and collectively meaningless.
    private func baselineWatermarks() {
        guard tracksNewChapters else { return }
        let remotes = visibleEntries.compactMap(\.remote).map(resolvedSubscriptionWork)
        guard !remotes.isEmpty else { return }
        if let updated = SubscriptionWatermarks.baseline(remotes, into: subscriptionWatermarks) {
            subscriptionWatermarks = updated
            SubscriptionWatermarks.save(updated)
        }
    }

    /// Clears every badge on the page. An explicit action rather than something the
    /// page load does: a list that marked itself read on sight would clear the badge
    /// before the reader had a chance to use it.
    private func markAllSeen() {
        let remotes = visibleEntries.compactMap(\.remote).map(resolvedSubscriptionWork)
        guard !remotes.isEmpty else { return }
        let updated = SubscriptionWatermarks.markSeen(remotes, in: subscriptionWatermarks)
        subscriptionWatermarks = updated
        SubscriptionWatermarks.save(updated)
    }

    /// Spec 1o: every pushed account list opens with the kicker, its rule, the
    /// list's own 32pt name and one line of tallies — at a **16pt** gutter, ten
    /// tighter than a subject's own page. These are lists *of* things rather
    /// than pages *about* one, and the spec sets them accordingly.
    private var subjectHeader: some View {
        SubjectHeaderBlock(
            kicker: originKicker,
            title: kind.title,
            subtitle: headerTallyLine,
            palette: accountPalette,
            gutter: SubjectMetrics.accountGutter
        )
    }

    private var subjectHeaderSection: some View {
        Section {
            subjectHeader
            .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// The app accent's hue, not a work's: this page is scoped to the account,
    /// which is the rule spec 1m states outright and every account surface
    /// follows.
    private var accountPalette: SubjectPalette {
        theme.scopePalette
    }

    /// Counts what is *visible*, since the refine facets can hide part of a page
    /// and a tally that ignored them would contradict the rows underneath it.
    ///
    /// Marked for Later does not use this line. Its own header is "N works ·
    /// synced … ago" (`AO3MarkedForLaterCopy`), which needs a fetch timestamp
    /// this shared tally does not have. Everyone else still says which page
    /// you are on — the fact a nine-page list can actually use.
    private var headerTallyLine: String {
        let shown = kind == .history ? historyDisplayedEntries.count : visibleEntries.count
        var line = shown == 1 ? "1 work" : "\(shown) works"
        if kind == .history, historyProgressFilter == .everything {
            let inProgress = visibleEntries.filter { $0.local?.readingState == .inProgress }.count
            if inProgress == 1 {
                line += " · 1 in progress"
            } else if inProgress > 1 {
                line += " · \(inProgress) in progress"
            }
        }
        let newCount = worksWithNewChapters
        if newCount > 0 {
            line += " · \(newCount) with new chapters"
        }
        if totalPages > 1 {
            line += " · page \(currentPage) of \(totalPages)"
        }
        return line
    }

    private var paginationBar: some View {
        SearchPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            isLoading: phase == .loading
        ) { page in
            Task { await load(page: page) }
        }
        .padding(.horizontal, CardListMetrics.sideMargin)
    }

    private var showPagination: Bool {
        totalPages > 1 && !works.isEmpty
    }

    private var paginationRow: some View {
        SearchPaginationBar(
            currentPage: currentPage,
            totalPages: totalPages,
            isLoading: phase == .loading
        ) { page in
            Task { await load(page: page) }
        }
        .bareListRow()
    }

    // MARK: Signed out

    private var signedOutPrompt: some View {
        ContentUnavailableView {
            Label(kind.signedOutTitle, systemImage: kind.emptySymbol)
        } description: {
            Text(kind.signedOutMessage)
        } actions: {
            Button("Log In to AO3") { showLogin = true }
        }
    }

    // MARK: Loading

    private func load(page: Int) async {
        let expectedSessionGeneration = auth.sessionGeneration
        guard let username = auth.username,
              let url = kind.url(username: username, page: page)
        else {
            phase = .failed("You need to be logged in to AO3.")
            return
        }
        phase = .loading
        do {
            let request = try auth.authenticatedRequest(for: url)
            // 1q: a bookmark row is the work plus a note, tags, a privacy flag,
            // and a date. `AO3SearchPage` has nowhere to put those, and a second
            // fetch of the same URL would spend another paced request to recover
            // them. One `accountBookmarksPage` feeds both the work list and
            // `bookmarkDetails`. Subscriptions does the same with the unsubscribe
            // form already on the index. Every other kind still goes through `fetch`.
            let result: AO3SearchPage
            let details: [Int: AO3AuthorBookmark]
            let paths: [Int: String]
            if kind == .bookmarks {
                let parsed = try await AO3Client.shared.accountBookmarksPage(for: request, page: page)
                result = AO3SearchPage(
                    works: parsed.bookmarks.map(\.work),
                    currentPage: parsed.currentPage,
                    totalPages: parsed.totalPages
                )
                details = Dictionary(
                    parsed.bookmarks.map { ($0.work.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                paths = [:]
            } else if kind == .subscriptions {
                // The unsubscribe action is the `<dd><form>` beside each work.
                // `AO3SearchPage` has nowhere to put it. One `subscriptionsIndex`
                // feeds both the work list and `unsubscribePaths`.
                let parsed = try await AO3Client.shared.subscriptionsIndex(for: request, page: page)
                result = parsed.page
                details = [:]
                paths = parsed.unsubscribePaths
            } else {
                result = try await kind.fetch(for: request, page: page)
                details = [:]
                paths = [:]
            }
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            works = result.works
            readingEntries = Dictionary(
                result.readingEntries.compactMap { entry in
                    entry.workID.map { ($0, entry) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            bookmarkDetails = details
            unsubscribePaths = paths
            currentPage = result.currentPage
            totalPages = result.totalPages
            if kind == .markedForLater {
                lastSyncedAt = Date()
                for work in result.works {
                    markedForLaterSeenThisVisit[work.id] = work
                }
            }
            phase = .loaded
            // First sight baselines rather than badges. Runs after `works` is
            // replaced so it sees the page that just arrived, and only ever adds
            // entries — a work already watermarked keeps its badge through the load
            // that displayed it.
            baselineWatermarks()
            baselineMarkedForLater(result.works)
            // After the page is stored, so the list is not held empty while
            // chapter counts arrive. No-op for every kind but subscriptions.
            enrichLoadedSubscriptionPage(result.works, generation: expectedSessionGeneration)
            if let countsKind = kind.countsKind {
                AO3AccountListCountsCache.shared.record(
                    page: result,
                    kind: countsKind,
                    authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
                )
            }
        } catch AO3Error.authenticationRequired {
            guard await auth.sessionDidExpire(expectedGeneration: expectedSessionGeneration) else { return }
            works = []
            readingEntries = [:]
            bookmarkDetails = [:]
            unsubscribePaths = [:]
            phase = .idle // back to the signed-out prompt
        } catch is CancellationError {
            // This view's load task restarts (cancelling whatever load was in
            // flight) when the session generation or the signed-in flag
            // changes. That's not a failure the user caused or can fix with
            // "Try Again": the restarted task loads again, or the view is
            // already gone and nothing is watching `phase`. Leaving `phase`
            // alone (instead of surfacing the raw system error) avoids a
            // permanent-looking "Swift.CancellationError" card for what is,
            // from the user's side, nothing happening at all.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Same reasoning as the CancellationError case above.
        } catch let error as AO3Error {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            guard auth.sessionGeneration == expectedSessionGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// AO3 history removal always asks first. `confirmBeforeDelete` gates the
    /// local trash; this write is not that trash, and a swipe must not post.
    private func deleteHistoryEntry(_ entry: CanonicalWork) async {
        guard !historyWriteInFlight else { return }
        let generation = auth.sessionGeneration
        guard let workID = entry.ao3WorkID, let readingID = readingEntries[workID]?.readingID else {
            historyWriteError = "AO3 didn't show a delete link for this row, so nothing was removed."
            return
        }
        historyWriteInFlight = true
        defer {
            if writeResultStillOwnsScreen(generation) {
                historyWriteInFlight = false
            }
        }
        do {
            _ = try await auth.deleteReading(readingID: readingID, page: currentPage)
            // The POST is generation-fenced. This list may already be the next
            // account's by the time that result comes back. The defer uses the
            // same check, so it does not drop a write that account has started.
            guard writeResultStillOwnsScreen(generation) else { return }
            works.removeAll { $0.id == workID }
            readingEntries[workID] = nil
        } catch is CancellationError {
            // Session changed between the form GET and the POST. Nothing landed.
        } catch {
            guard writeResultStillOwnsScreen(generation) else { return }
            historyWriteError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The flag, the error, and the row edit for one write. A later generation
    /// has its own flag: `clearLoadedAccount` set it false, and that
    /// generation's write may have set it true. See
    /// `shouldApplyCapturedGeneration`.
    private func writeResultStillOwnsScreen(_ generation: Int) -> Bool {
        AO3AccountWorksSessionReload.shouldApplyCapturedGeneration(
            generation,
            sessionGeneration: auth.sessionGeneration
        )
    }

    /// AO3 unsubscribe always asks first. The swipe only stages the row.
    /// A flick does not post: the button sets `pendingUnsubscribe`, and the
    /// confirm is what calls this.
    private func unsubscribe(_ entry: CanonicalWork) async {
        guard !subscriptionWriteInFlight else { return }
        let generation = auth.sessionGeneration
        guard let workID = entry.ao3WorkID,
              let path = unsubscribePaths[workID],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            subscriptionWriteError = "AO3 didn't show an unsubscribe link for this row, so nothing was changed."
            return
        }
        subscriptionWriteInFlight = true
        defer {
            if writeResultStillOwnsScreen(generation) {
                subscriptionWriteInFlight = false
            }
        }
        do {
            _ = try await auth.unsubscribe(path: path, page: currentPage)
            // The path was this session's. A switch that lands while the POST
            // is in flight must not drop that work id from the next account,
            // and must not clear the flag or show this failure on that account.
            guard writeResultStillOwnsScreen(generation) else { return }
            works.removeAll { $0.id == workID }
            unsubscribePaths[workID] = nil
        } catch is CancellationError {
            // Session changed between the form GET and the POST. Nothing landed.
        } catch {
            guard writeResultStillOwnsScreen(generation) else { return }
            subscriptionWriteError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Drops every row fetched for the previous session, then leaves `phase`
    /// idle so the load gate below actually fetches. The pending confirms go
    /// too: an Unsubscribe staged for account A must not post after B signs in.
    private func clearLoadedAccount() {
        subscriptionEnrichment?.cancel()
        subscriptionEnrichment = nil
        let cleared = AO3AccountWorksSessionReload.cleared
        works = cleared.works
        currentPage = cleared.currentPage
        totalPages = cleared.totalPages
        phase = .idle
        readingEntries = cleared.readingEntries
        bookmarkDetails = cleared.bookmarkDetails
        unsubscribePaths = cleared.unsubscribePaths
        enrichedSubscriptionSummaries = cleared.enrichedSubscriptionSummaries
        markedForLaterSeenThisVisit = cleared.markedForLaterSeenThisVisit
        lastSyncedAt = cleared.lastSyncedAt
        pendingHistoryDelete = nil
        confirmClearHistory = cleared.confirmClearHistory
        historyWriteError = cleared.historyWriteError
        historyWriteInFlight = cleared.historyWriteInFlight
        pendingUnsubscribe = nil
        subscriptionWriteError = cleared.subscriptionWriteError
        subscriptionWriteInFlight = cleared.subscriptionWriteInFlight
    }

    /// Stores a subscription row's work-page summary and, the first time that
    /// summary names a posted count, baselines the watermark. An existing
    /// watermark is left alone, which is what lets a later visit show Updated.
    private func noteEnrichedSubscription(_ summary: AO3WorkSummary) {
        if enrichedSubscriptionSummaries[summary.id] != summary {
            enrichedSubscriptionSummaries[summary.id] = summary
        }
        guard let updated = SubscriptionWatermarks.baseline(
            [summary], into: subscriptionWatermarks
        ) else { return }
        subscriptionWatermarks = updated
        SubscriptionWatermarks.save(updated)
    }

    private func clearHistory() async {
        guard !historyWriteInFlight else { return }
        let generation = auth.sessionGeneration
        historyWriteInFlight = true
        defer {
            if writeResultStillOwnsScreen(generation) {
                historyWriteInFlight = false
            }
        }
        do {
            _ = try await auth.clearReadingHistory()
            guard writeResultStillOwnsScreen(generation) else { return }
            works = []
            readingEntries = [:]
            currentPage = 1
            totalPages = 1
        } catch is CancellationError {
            // Session changed between the confirm-page GET and the POST.
        } catch {
            guard writeResultStillOwnsScreen(generation) else { return }
            historyWriteError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Starts chapter-count fetches for this subscriptions page and stops the
    /// previous page's walk. Rows that have not been handed to the enricher
    /// yet are not fetched. A result from the old generation is not recorded.
    private func enrichLoadedSubscriptionPage(_ works: [AO3WorkSummary], generation: Int) {
        guard kind == .subscriptions else { return }
        subscriptionEnrichment?.cancel()
        subscriptionEnrichment = Task {
            await AO3SubscriptionsPageEnrichment.enrichPage(
                works,
                generation: generation,
                sessionGeneration: { auth.sessionGeneration },
                note: noteEnrichedSubscription
            )
        }
    }
}

/// An AO3 work row that fills itself in when the listing it came from was sparse.
///
/// AO3's subscriptions page lists only title, id and author, so those cards would
/// otherwise show no tags, no stats and no summary. This task runs when the row
/// appears, which is what paints the card. The subscriptions list also asks for
/// the rest of the loaded page (`AO3SubscriptionsPageEnrichment`) after the page
/// is on screen, so a chapter count does not wait for the row to appear. Both
/// calls share `AO3SparseWorkEnricher`, so a visible row is not a second request.
///
/// A row that is already complete — every other list in the app — does no work at
/// all; `enrich` returns nil immediately and this stays exactly `AO3WorkRow`.
/// Internal rather than file-private: `AO3CollectionDetailView` renders the same
/// remote row, and a second copy of the enrich-on-appear logic is exactly the kind
/// of duplication that drifts.
struct EnrichingAO3WorkRow: View {
    let work: AO3WorkSummary
    let expandAll: Bool
    var presentation: AO3WorkRow.Presentation = .standard
    /// Fired when enrichment produced a summary. Nil for every caller except
    /// the subscriptions list, which needs the work page's chapter count for
    /// grouping. The row's own card still uses `enriched` either way.
    var onEnriched: ((AO3WorkSummary) -> Void)?

    @State private var enriched: AO3WorkSummary?

    private var displayed: AO3WorkSummary { enriched ?? work }

    var body: some View {
        AO3WorkRow(work: displayed, expandAll: expandAll, presentation: presentation)
            .cardNavigation(to: displayed, accessibilityLabel: displayed.title)
            .task(id: work.id) {
                // `.task(id:)` so recycling this row onto a different work cancels
                // the previous fetch instead of writing its result into the new row.
                let result = await AO3SparseWorkEnricher.shared.enrich(work)
                enriched = result
                if let result {
                    onEnriched?(result)
                }
            }
    }
}
