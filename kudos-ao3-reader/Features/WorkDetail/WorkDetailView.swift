import OSLog
import SwiftData
import SwiftUI

// The canonical detail screen stays cohesive; section builders live in
// WorkDetailOverviewSections.swift / WorkDetailSections.swift.
// swiftlint:disable file_length

/// The single, canonical work-detail screen — used for **every** work the app can open,
/// whether it's a locally saved work or a remote AO3 summary (Home, Library, Browse,
/// Search, Bookmarks, AO3 lists, …). There is no separate "compact" remote detail.
///
/// Redesigned as a work-centric hub matching Account / Author Profiles: a hero
/// identity card, then a four-way segmented control — **Overview** (summary,
/// quick actions, metadata cards, series), **Tags** (AO3 classification chips),
/// **Discussion** (native comments entry points), **Library** (personal state:
/// saved/later/queues/collections/download/progress/My Tags).
///
/// `Read` always opens the reader; it never pushes another detail page. A remote work
/// is resolved to a local `SavedWork` lazily — only when the reader or a management
/// action actually needs it — so merely browsing never imports a work. Once resolved
/// (or if the work is already in the library), the screen reflects its real local state.
struct WorkDetailView: View { // swiftlint:disable:this type_body_length
    /// Where the work came from. A `.remote` summary is resolved to a local record on
    /// demand; a `.saved` work is already local.
    enum Source: Hashable {
        case saved(SavedWork)
        case remote(AO3WorkSummary)
    }

    let source: Source

    init(work: SavedWork) {
        source = .saved(work)
    }

    init(remote: AO3WorkSummary) {
        source = .remote(remote)
    }

    @Environment(\.modelContext) var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) var router
    @Environment(AO3AuthService.self) private var auth
    @Environment(DownloadQueue.self) private var downloadQueue
    @Query(sort: \Tag.name) var allTags: [Tag]
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var allWorks: [SavedWork]

    /// The resolved local record: the saved work itself, an existing library match for
    /// a remote summary, or the record created when a remote work is imported on tap.
    @State var localWork: SavedWork?
    @State private var refreshedRemote: AO3WorkSummary?
    @State private var resolvedExisting = false

    /// The selected top-level section. Plain view state, like Account's
    /// `selectedTab`: it survives child pushes (the root view stays alive) and
    /// deliberately resets on a fresh open rather than persisting globally.
    @State var selectedTab: WorkDetailTab = .overview
    /// Long summaries start collapsed; this is the Show More toggle.
    @State var summaryExpanded = false

    @State var newTagName = ""
    @State var showingAddToCollection = false
    @State var working = false // a download / import is in flight
    @State var loadError: String?
    @State private var readerWork: SavedWork? // non-nil → push the reader
    @State var queuingSeries = false
    @State var showingAddToQueue = false
    @State private var showingSeriesQueuePrompt = false
    @State var preservingSeries = false
    @State private var seriesPreservationTask: Task<Void, Never>?
    @State private var seriesPreservationProgress: ReadingQueueService.SeriesPreservationResult?
    @State private var seriesPrompt: ReadingQueueService.SeriesPreservationPrompt?
    @State var queueNotice: String?
    @State private var workActions = AO3WorkActionsModel()

    @AppStorage("autoPreserveSmallSeriesOnSaveForLater")
    private var autoPreserveSmallSeriesOnSaveForLater = false
    @AppStorage("autoPreserveSeriesWorkThreshold")
    private var autoPreserveSeriesWorkThreshold = 5

    // MARK: - Source helpers

    /// The original remote summary, when this detail was opened from an AO3 listing.
    private var sourceRemote: AO3WorkSummary? {
        if case let .remote(summary) = source { return summary }
        return nil
    }

    /// The currently displayed remote summary. Pull-to-refresh can replace this
    /// value in memory without importing/saving a browsed work.
    var remote: AO3WorkSummary? {
        refreshedRemote ?? sourceRemote
    }

    /// Set once, on this view's genuine first `.onAppear` — never updated again, so a
    /// later re-appearance (e.g. Back from a pushed Author Profile revealing this view)
    /// is never mistaken for a fresh, possibly-spurious push.
    @State private var appearedAt: Date?

    private func dismissIfAuthorBylineConflict() {
        guard router.shouldSuppressCardNavigation else { return }
        // Only a same-touch race at this view's own genuine push can make it the
        // spurious duplicate `cardNavigationSuppressed` guards against. Without this,
        // tapping this already-settled screen's own author byline flips the same
        // global flag and this handler dismissed the very screen the user is on.
        guard let appearedAt, Date().timeIntervalSince(appearedAt) < 0.5 else { return }
        Task { @MainActor in
            await Task.yield()
            guard router.shouldSuppressCardNavigation else { return }
            dismiss()
        }
    }

    var body: some View {
        List {
            heroSection
            sectionPickerSection
            statusSection
            switch selectedTab {
            case .overview:
                overviewSections
            case .tags:
                tagSections
            case .discussion:
                discussionSections
            case .library:
                librarySections
            }
        }
        .cardList()
        .refreshable { await refreshDetails() }
        // Same-touch author byline on a List card can also activate the row's work
        // NavigationLink. Dismiss async — in-transaction dismiss() is often ignored.
        // Only the first appearance can be that spurious push, so only it sets
        // `appearedAt` / runs the check — a later re-appearance (Back from a child)
        // must never re-trigger it.
        .onAppear {
            if appearedAt == nil {
                appearedAt = Date()
                dismissIfAuthorBylineConflict()
            }
        }
        .onChange(of: router.cardNavigationSuppressed) { _, suppressed in
            if suppressed { dismissIfAuthorBylineConflict() }
        }
        .task {
            // Resolve an existing library record once (so a browsed work already in the
            // library shows its real saved state), then run the same Work Tags refresh
            // the local detail always did — only when we actually have a local record,
            // so merely viewing a remote work adds no AO3 request. Runs once per open;
            // switching sections re-renders from this already-loaded state without
            // re-fetching anything.
            resolveExistingIfNeeded()
            guard let work = localWork else { return }
            ReadingQueueService.normalize(work)
            await WorkTags.backfillFromEPUB(for: work, in: context)
            await WorkTags.refreshFromAO3(for: work, in: context)
        }
        // BookReaderView routes to the Readium navigator on iOS, the legacy reader on
        // macOS — so the unified detail opens the right reader on this branch.
        .navigationDestination(item: $readerWork) { BookReaderView(work: $0) }
        .sheet(isPresented: $showingAddToCollection) {
            if let work = localWork { AddToCollectionView(work: work) }
        }
        .sheet(isPresented: $showingAddToQueue) {
            if let work = localWork { AddToQueueView(work: work) }
        }
        .sheet(isPresented: $showingSeriesQueuePrompt) {
            if let seriesPrompt {
                SeriesPreservationPromptSheet(
                    prompt: seriesPrompt,
                    autoPreserveSmallSeries: $autoPreserveSmallSeriesOnSaveForLater,
                    threshold: autoPreserveSeriesWorkThreshold,
                    onOnlyThisWork: {
                        showingSeriesQueuePrompt = false
                    },
                    onPreserveSeries: {
                        showingSeriesQueuePrompt = false
                        preserveSeriesForLater()
                    }
                )
            } else {
                ProgressView("Checking series size…")
                    .padding()
            }
        }
        .navigationTitle(displayTitle)
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            .ao3WorkActions(workActions, workID: ao3WorkID ?? 0, auth: auth)
            .toolbar { detailToolbar }
    }

    // MARK: - Hero + section control

    private var heroSection: some View {
        Section {
            WorkDetailHeroCard(
                title: displayTitle,
                authors: displayAuthorList,
                identities: displayAuthorIdentities,
                fandoms: displayFandoms,
                rating: displayRating,
                status: displayStatus,
                chapters: displayChapters,
                words: displayWords
            )
            .cardRow()
        }
    }

    private var sectionPickerSection: some View {
        Section {
            Picker("Work Details Section", selection: $selectedTab) {
                ForEach(WorkDetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accountControlCardRow()
        }
    }

    /// Transient feedback (refresh/queue notices, errors, series-preservation
    /// progress) lives directly under the section control so it stays visible no
    /// matter which section triggered it.
    @ViewBuilder
    private var statusSection: some View {
        if loadError != nil || queueNotice != nil || preservingSeries {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if preservingSeries,
                       let progress = seriesPreservationProgress,
                       progress.total > 0 {
                        ProgressView(
                            value: Double(progress.completed),
                            total: Double(progress.total)
                        )
                    }

                    if let loadError {
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if let queueNotice {
                        Text(queueNotice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if preservingSeries {
                        Button(role: .cancel) {
                            cancelSeriesPreservation()
                        } label: {
                            Label("Cancel Series Preservation", systemImage: "xmark.circle")
                                .font(.footnote)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .cardRow()
            }
        }
    }

    // MARK: - Toolbar (favorite + more)

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ActionToolbar {
            let fav = localWork?.isFavorite ?? false
            ToolbarIconButton(
                title: fav ? "Unfavorite" : "Favorite",
                systemImage: fav ? "star.fill" : "star",
                tint: fav ? .yellow : nil
            ) {
                withLocalWork { work in
                    work.isFavorite.toggle()
                    work.markModified()
                    context.saveBestEffort(reason: "Saving favorite state failed")
                }
            }

            Menu {
                if let id = ao3WorkID {
                    AO3WorkActionsMenu(workID: id, actions: workActions,
                                       workContext: commentsWorkContext)
                }
            } label: {
                Label("More actions", systemImage: "ellipsis.circle")
            }
            .disabled(ao3WorkID == nil)
        }
    }

    // MARK: - Display values (local record first, remote summary fallback)

    var displayTitle: String {
        localWork?.title ?? remote?.title ?? "Untitled"
    }

    var displayAuthor: String {
        if let author = localWork?.author, !author.isEmpty { return author }
        return remote?.authorText ?? ""
    }

    /// Individual author names (for the hero byline and the comments screen's
    /// "Author" badge).
    var displayAuthorList: [String] {
        if let authors = remote?.authors, !authors.isEmpty { return authors }
        if let identities = localWork?.verifiedAuthorIdentities, !identities.isEmpty {
            return identities.map(\.displayName)
        }
        return displayAuthor.isEmpty ? [] : [displayAuthor]
    }

    var displayAuthorIdentities: [AO3AuthorIdentity] {
        if let identities = remote?.authorIdentities, !identities.isEmpty { return identities }
        return localWork?.verifiedAuthorIdentities ?? []
    }

    var displaySummary: String {
        if let summary = localWork?.summary, !summary.isEmpty { return summary.strippingHTML() }
        return remote?.summary ?? ""
    }

    var displayRating: String {
        firstNonEmpty(localWork?.rating, remote?.rating)
    }

    var displayLanguage: String {
        firstNonEmpty(localWork?.language, remote?.language)
    }

    var displayPublishedDate: String {
        localWork?.datePublished ?? ""
    }

    var displayUpdatedDate: String {
        firstNonEmpty(localWork?.dateUpdated, remote?.dateUpdated)
    }

    /// Warnings / categories / status / stats: prefer the local record's stored values
    /// (canonical once refreshed), falling back to the remote summary while unsaved.
    var displayWarnings: [String] {
        if let warnings = localWork?.workWarnings, !warnings.isEmpty { return warnings }
        return remote?.warnings ?? []
    }

    var displayCategories: [String] {
        if let categories = localWork?.workCategories, !categories.isEmpty { return categories }
        return remote?.categories ?? []
    }

    /// Categorized tag chips: prefer the local record's per-type lists (once the AO3
    /// refresh has run), else the remote summary's (the blurb is grouped too).
    var displayFandoms: [String] {
        if let fandoms = localWork?.workFandoms, !fandoms.isEmpty { return fandoms }
        return remote?.fandoms ?? []
    }

    var displayRelationships: [String] {
        if let relationships = localWork?.workRelationships, !relationships.isEmpty { return relationships }
        return remote?.relationships ?? []
    }

    var displayCharacters: [String] {
        if let characters = localWork?.workCharacters, !characters.isEmpty { return characters }
        return remote?.characters ?? []
    }

    var displayFreeforms: [String] {
        if let freeforms = localWork?.workFreeforms, !freeforms.isEmpty { return freeforms }
        return remote?.tags ?? []
    }

    var displayStatus: String? {
        // A local work's completion flag is only meaningful for AO3-sourced imports
        // (a plain EPUB import has no status), so don't assert WIP for those.
        if let work = localWork,
           work.ao3WorkID != nil || WorkTags.ao3WorkID(from: work.sourceURL) != nil {
            return work.isComplete ? "Complete" : "Work in Progress"
        }
        if let complete = remote?.isComplete { return complete ? "Complete" : "Work in Progress" }
        return nil
    }

    var displayKudos: Int? {
        if let kudos = localWork?.kudos, kudos > 0 { return kudos }
        return remote?.kudos
    }

    var displayComments: Int? {
        if let comments = localWork?.comments, comments > 0 { return comments }
        return remote?.comments
    }

    var displayHits: Int? {
        if let hits = localWork?.hits, hits > 0 { return hits }
        return remote?.hits
    }

    var displayWords: Int? {
        if let count = localWork?.wordCount, count > 0 { return count }
        return remote?.words
    }

    var displayChapters: String {
        firstNonEmpty(localWork?.chapters, remote?.chapters)
    }

    private func firstNonEmpty(_ first: String?, _ second: String?) -> String {
        if let first, !first.isEmpty { return first }
        return second ?? ""
    }

    /// The AO3 URL for "Open on AO3" / web fallback (local source URL or remote work URL).
    var ao3URL: URL? {
        if let work = localWork, let url = URL(string: work.sourceURL), !work.sourceURL.isEmpty {
            return url
        }
        return remote?.workURL
    }

    /// The AO3 numeric work id (for comments and the More-actions web menu).
    var ao3WorkID: Int? {
        if let id = remote?.id { return id }
        if let id = localWork?.ao3WorkID { return id }
        return WorkTags.ao3WorkID(from: localWork?.sourceURL ?? "")
    }

    /// Work context handed to the native comments screen (Discussion section and
    /// the toolbar's On-AO3 menu share it).
    var commentsWorkContext: AO3CommentsWorkContext {
        AO3CommentsWorkContext(
            title: displayTitle,
            authors: displayAuthorList,
            authorIdentities: displayAuthorIdentities,
            fandoms: displayFandoms, rating: displayRating, chapters: displayChapters
        )
    }

    // MARK: - Series values

    /// Other downloaded works in the same series, ordered by series position.
    var seriesWorks: [SavedWork] {
        guard let work = localWork, !work.seriesTitle.isEmpty else { return [] }
        return allWorks
            .filter { $0.seriesTitle == work.seriesTitle && $0.id != work.id }
            .sorted { $0.seriesPosition < $1.seriesPosition }
    }

    var displaySeriesTitle: String {
        if let title = localWork?.seriesTitle, !title.isEmpty { return title }
        return remote?.seriesTitle ?? ""
    }

    var displaySeriesPosition: Int {
        localWork?.seriesPosition ?? remote?.seriesPosition ?? 0
    }

    var displaySeriesURL: String {
        if let url = localWork?.seriesURL, !url.isEmpty { return url }
        return remote?.seriesURL ?? ""
    }

    // MARK: - Library state helpers

    var preservingStatusIsBusy: Bool {
        working || preservingSeries || localWork?.epubPreservationStatus == .preserving
    }

    var statusFooter: String {
        guard let work = localWork else {
            return "Reading downloads this work to your device. When you finish, "
                + "the file is freed unless you save or favorite it."
        }
        if work.isInSavedForLaterQueue {
            switch work.epubPreservationStatus {
            case .preserved:
                if WorkReaderPreparation.hasReadableEPUB(for: work) {
                    return "Saved for Later — a local EPUB is kept for offline reading."
                }
                return "Saved for Later, but the local EPUB needs to be restored."
            case .preserving:
                return "Saving for Later — preserving a local EPUB."
            case .failed, .missingFile:
                return "Saved for Later, but the local EPUB needs to be restored."
            case .queued:
                return "Saved for Later — preservation is queued."
            case .notPreserved:
                return "Saved for Later."
            }
        }
        if work.isQueuedForLater {
            return "In a Reading Queue — its EPUB is protected while queued."
        }
        if work.isSaved { return "Saved — kept on this device." }
        if work.ao3WorkID == nil, WorkTags.ao3WorkID(from: work.sourceURL) == nil {
            return "Imported EPUB — kept on this device for offline reading."
        }
        switch work.readingState {
        case .finished:
            return work.hasEPUB
                ? "Finished."
                : "Finished. The file was freed to save space; it re-downloads when you read it again."
        case .freedHistory:
            // Freed without being finished — don't call it "Finished."
            return "In your reading history. The file was freed to save space; it re-downloads when you read it again."
        case .inProgress, .unread:
            if work.isFavorite { return "Favorited, so its file is kept when finished." }
            return "Reading. When you finish, the file is freed unless you save or favorite it."
        }
    }

    // MARK: - Resolving a local record (lazy import)

    /// On first appearance, adopt an existing library record so a browsed work that's
    /// already saved shows its real local state. Doesn't import anything.
    private func resolveExistingIfNeeded() {
        guard !resolvedExisting else { return }
        resolvedExisting = true
        switch source {
        case let .saved(work):
            localWork = work
        case let .remote(summary):
            // A match sitting in Recently Deleted is deliberately not adopted: the
            // page keeps showing remote state (with Save), and saving revives the
            // hidden record through importEPUB's Recently Deleted reuse.
            let match = existingWork(forSource: summary.workURL, in: context)
            localWork = match?.isPendingDeletion == true ? nil : match
        }
    }

    private func refreshDetails() async {
        loadError = nil
        queueNotice = nil
        resolveExistingIfNeeded()
        do {
            if let work = localWork {
                try await WorkMetadataRefresh.refresh(work, in: context)
            } else if let summary = remote {
                refreshedRemote = try await WorkMetadataRefresh.remoteSummary(workID: summary.id)
            } else {
                return
            }
            queueNotice = "Details refreshed."
        } catch {
            loadError = "Refresh failed; existing details were left unchanged. "
                + WorkMetadataRefresh.message(for: error)
        }
    }

    /// Ensures a local `SavedWork` exists, importing the remote work on demand through
    /// the same centralized resolve/download/import/apply-metadata sequence every other
    /// remote-work action (`WorkCardActions.performRemoteAction`, bulk actions) already
    /// uses — no new AO3 request types, and no separately-derived chapter count. Local
    /// works, and works with an existing (possibly Recently-Deleted, silently revived)
    /// local match, run `action` immediately without a download.
    func withLocalWork(_ action: @escaping (SavedWork) -> Void) {
        resolveExistingIfNeeded()
        if let work = localWork { action(work); return }
        // A remote work needs importing; ignore re-taps while one is already in flight.
        guard let summary = remote, !working else { return }
        Task {
            working = true
            loadError = nil
            do {
                let saved = try await ReadingQueueService.resolveLocalWork(for: summary, in: context)
                localWork = saved
                working = false
                action(saved)
            } catch let error as AO3Error {
                loadError = error.errorDescription
                working = false
            } catch {
                loadError = "The download couldn't be saved."
                working = false
            }
        }
    }

    // MARK: - Lifecycle toggles (Quick Actions + Library rows)

    func toggleSaved() {
        withLocalWork { WorkLifecycle.setSaved($0, !$0.isSaved, in: context) }
    }

    func toggleFinished() {
        withLocalWork { work in
            if work.isFinished {
                WorkLifecycle.markStillReading(work, in: context)
            } else {
                WorkLifecycle.markFinished(work, in: context)
            }
        }
    }

    // MARK: - Reading Queues

    func saveForLater() {
        resolveExistingIfNeeded()
        queueNotice = nil
        loadError = nil

        if let work = localWork {
            Task {
                working = true
                _ = await ReadingQueueService.addToSavedForLater(work, in: context)
                working = false
                queueNotice = "Saved for Later."
                maybeOfferSeriesPreservation(for: work)
            }
            return
        }

        guard let summary = remote, !working else { return }
        Task {
            working = true
            loadError = nil
            do {
                let work = try await ReadingQueueService.addToSavedForLater(summary, in: context)
                localWork = work
                working = false
                queueNotice = "Saved for Later."
                maybeOfferSeriesPreservation(for: work)
            } catch let error as AO3Error {
                loadError = error.errorDescription
                working = false
            } catch {
                loadError = "The work couldn't be saved for later."
                working = false
            }
        }
    }

    /// The same command the work-card context menus run for "Remove from Saved for
    /// Later" — a queue-only record moves to Recently Deleted (90-day recovery).
    func removeFromSavedForLater() {
        guard let work = localWork else { return }
        queueNotice = nil
        loadError = nil
        ReadingQueueService.removeFromQueueAndDeleteIfQueueOnly(
            work,
            from: ReadingQueueService.ensureSavedForLaterQueue(in: context),
            in: context
        )
        if work.isPendingDeletion, case .remote = source {
            // The record existed only for the queue; the page returns to remote
            // state — the same rule as resolveExistingIfNeeded, which never adopts
            // a Recently-Deleted match.
            localWork = nil
        }
        queueNotice = "Removed from Saved for Later."
    }

    func retryPreservation(_ work: SavedWork) {
        Task {
            queueNotice = nil
            do {
                try await ReadingQueueService.preserve(work, in: context)
            } catch is CancellationError {
                queueNotice = "Preservation was cancelled."
                return
            } catch {
                loadError = "The EPUB couldn't be preserved right now."
                return
            }
            if work.epubPreservationStatus == .preserved {
                queueNotice = "The queued EPUB is available offline."
            } else {
                loadError = "The EPUB couldn't be preserved right now."
            }
        }
    }

    private func maybeOfferSeriesPreservation(for work: SavedWork) {
        guard !work.seriesURL.isEmpty else { return }
        Task {
            await prepareSeriesPreservationPrompt(for: work)
        }
    }

    private func prepareSeriesPreservationPrompt(for work: SavedWork) async {
        guard let url = URL(string: work.seriesURL) else {
            seriesPrompt = ReadingQueueService.seriesPrompt(
                for: nil,
                threshold: autoPreserveSeriesWorkThreshold,
                previewFailed: true
            )
            showingSeriesQueuePrompt = true
            return
        }
        queueNotice = "Checking series size…"
        do {
            let preview = try await AO3Client.shared.seriesPreview(seriesURL: url)
            let prompt = ReadingQueueService.seriesPrompt(
                for: preview,
                threshold: autoPreserveSeriesWorkThreshold
            )
            if autoPreserveSmallSeriesOnSaveForLater, prompt.canAutoPreserve {
                startSeriesPreservation(with: preview.works)
            } else {
                queueNotice = "Saved for Later."
                seriesPrompt = prompt
                showingSeriesQueuePrompt = true
            }
        } catch {
            queueNotice = "Saved for Later."
            seriesPrompt = ReadingQueueService.seriesPrompt(
                for: nil,
                threshold: autoPreserveSeriesWorkThreshold,
                previewFailed: true
            )
            showingSeriesQueuePrompt = true
        }
    }

    private func preserveSeriesForLater() {
        let previewWorks = seriesPrompt?.canUsePreviewForPreservation == true
            ? seriesPrompt?.preview?.works
            : nil
        startSeriesPreservation(with: previewWorks)
    }

    private func startSeriesPreservation(with summaries: [AO3WorkSummary]? = nil) {
        guard let work = localWork, seriesPreservationTask == nil else { return }
        preservingSeries = true
        queueNotice = "Preserving series…"
        seriesPreservationProgress = nil
        seriesPreservationTask = Task { @MainActor in
            let result: ReadingQueueService.SeriesPreservationResult = if let summaries {
                await ReadingQueueService.preserveSeries(
                    summaries,
                    in: context,
                    progress: {
                        seriesPreservationProgress = $0
                        queueNotice = seriesProgressText($0)
                    }
                )
            } else {
                await ReadingQueueService.preserveSeries(
                    anchoredAt: work,
                    in: context,
                    progress: {
                        seriesPreservationProgress = $0
                        queueNotice = seriesProgressText($0)
                    }
                )
            }
            preservingSeries = false
            seriesPreservationTask = nil
            seriesPreservationProgress = nil
            queueNotice = seriesCompletionText(result)
        }
    }

    private func cancelSeriesPreservation() {
        seriesPreservationTask?.cancel()
        queueNotice = "Cancelling series preservation…"
    }

    private func seriesProgressText(_ result: ReadingQueueService.SeriesPreservationResult) -> String {
        guard result.total > 0 else { return "Preserving series…" }
        return "Preserving series \(result.completed) of \(result.total)…"
    }

    private func seriesCompletionText(_ result: ReadingQueueService.SeriesPreservationResult) -> String {
        if result.cancelled > 0 {
            return "Series preservation cancelled. Preserved "
                + "\(result.preserved) work\(result.preserved == 1 ? "" : "s")."
        }
        if result.total == 0 { return "No other series works were found." }
        let parts = result.summaryParts(verb: "preserved")
        if parts.isEmpty {
            return "Series works are already preserved for later."
        }
        return "Series preservation complete: " + parts.joined(separator: ", ") + "."
    }

    // MARK: - Reading

    /// Opens the reader for this work. Imports a remote work first, and re-downloads a
    /// freed history entry, before pushing the reader — it never opens another detail.
    func read() {
        withLocalWork { work in
            if WorkReaderPreparation.hasReadableEPUB(for: work) { readerWork = work; return }
            // Freed history entry: re-download into the existing record, keeping its id
            // (so progress/tags stay attached), then open.
            Task {
                working = true
                loadError = nil
                do {
                    try await WorkReaderPreparation.restoreReadableEPUB(for: work, in: context)
                    working = false
                    readerWork = work
                } catch let error as AO3Error {
                    loadError = error.errorDescription
                    working = false
                } catch {
                    loadError = error.localizedDescription
                    working = false
                }
            }
        }
    }

    /// Fetches every work in this work's series from AO3 and hands them to the download
    /// queue (already-saved works are skipped). Surfaces failures in the status area.
    func downloadSeries() async {
        guard let work = localWork, let url = URL(string: work.seriesURL) else { return }
        queuingSeries = true
        loadError = nil
        do {
            let works = try await AO3Client.shared.seriesWorks(seriesURL: url)
            let items = works.map {
                DownloadQueue.Item(
                    id: $0.id, title: $0.title, sourceURL: $0.workURL,
                    isComplete: $0.isComplete ?? false, seriesURL: work.seriesURL
                )
            }
            downloadQueue.enqueue(items, into: context)
        } catch let error as AO3Error {
            loadError = error.errorDescription
        } catch {
            loadError = "Couldn't load the series from AO3."
        }
        queuingSeries = false
    }

    // MARK: - My Tags editing

    /// Quick-add suggestions for My Tags: the user's other tags plus this work's own
    /// AO3 tags, minus any already applied (case-insensitive, de-duplicated).
    var suggestions: [String] {
        let applied = Set((localWork?.tags ?? []).map { $0.name.lowercased() })
        let workTags = localWork?.workTags ?? remote?.tags ?? []
        var seen = Set<String>()
        var result: [String] = []
        for name in allTags.map(\.name) + workTags {
            let key = name.lowercased()
            guard !applied.contains(key), seen.insert(key).inserted else { continue }
            result.append(name)
        }
        return result
    }

    func addTypedTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apply(named: trimmed)
        newTagName = ""
    }

    func apply(named name: String) {
        withLocalWork { work in
            let tag = tag(named: name)
            if !work.tags.contains(where: { $0.name == tag.name }) {
                work.tags.append(tag)
                // User tags are part of the derived search text (index v2).
                WorkSearchIndex.reindex(work)
                context.saveBestEffort(reason: "Saving tag assignment failed")
            }
        }
    }

    func removeTag(_ tag: Tag) {
        guard let work = localWork else { return }
        work.tags.removeAll { $0.name == tag.name }
        WorkSearchIndex.reindex(work)
        context.saveBestEffort(reason: "Saving tag removal failed")
    }

    /// Returns an existing tag with this name (case-insensitive) or creates one.
    private func tag(named name: String) -> Tag {
        if let existing = allTags.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let created = Tag(name: name)
        context.insert(created)
        return created
    }
}

private struct SeriesPreservationPromptSheet: View {
    @Environment(\.dismiss) private var dismiss

    let prompt: ReadingQueueService.SeriesPreservationPrompt
    @Binding var autoPreserveSmallSeries: Bool
    let threshold: Int
    let onOnlyThisWork: () -> Void
    let onPreserveSeries: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Text(prompt.message)
                        Text("Kudos preserves series works one at a time using the normal AO3 request pacing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Toggle(prompt.autoPreserveLabel, isOn: $autoPreserveSmallSeries)
                        Text("Automatic preservation only runs when the first AO3 series page proves the whole "
                            + "series is within your \(threshold)-work limit.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button {
                            dismiss()
                            onPreserveSeries()
                        } label: {
                            Label("Preserve Entire Series", systemImage: "square.stack.3d.up")
                        }

                        Button(role: .cancel) {
                            dismiss()
                            onOnlyThisWork()
                        } label: {
                            Label("Only This Work", systemImage: "bookmark")
                        }
                    }
                }
                .appThemedRows()
            }
            .formStyle(.grouped)
            .appThemedScroll()
            .navigationTitle("Preserve Series?")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                            onOnlyThisWork()
                        }
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}
