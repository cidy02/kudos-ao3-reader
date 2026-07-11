import OSLog
import SwiftData
import SwiftUI

// Existing canonical detail screen is large; lint cleanup avoids behavior refactors.
// swiftlint:disable file_length

// Lint: this canonical detail screen intentionally stays cohesive.
/// The single, canonical work-detail screen — used for **every** work the app can open,
/// whether it's a locally saved work or a remote AO3 summary (Home, Library, Browse,
/// Search, Bookmarks, AO3 lists, …). There is no separate "compact" remote detail.
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

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth
    @Environment(DownloadQueue.self) private var downloadQueue
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var allWorks: [SavedWork]

    /// The resolved local record: the saved work itself, an existing library match for
    /// a remote summary, or the record created when a remote work is imported on tap.
    @State private var localWork: SavedWork?
    @State private var refreshedRemote: AO3WorkSummary?
    @State private var resolvedExisting = false

    @State private var newTagName = ""
    @State private var showingAddToCollection = false
    @State private var working = false // a download / import is in flight
    @State private var loadError: String?
    @State private var readerWork: SavedWork? // non-nil → push the reader
    @State private var queuingSeries = false
    @State private var showingAddToQueue = false
    @State private var showingSeriesQueuePrompt = false
    @State private var preservingSeries = false
    @State private var seriesPreservationTask: Task<Void, Never>?
    @State private var seriesPreservationProgress: ReadingQueueService.SeriesPreservationResult?
    @State private var seriesPrompt: ReadingQueueService.SeriesPreservationPrompt?
    @State private var queueNotice: String?
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
    private var remote: AO3WorkSummary? {
        refreshedRemote ?? sourceRemote
    }

    private func dismissIfAuthorBylineConflict() {
        guard router.shouldSuppressCardNavigation else { return }
        Task { @MainActor in
            await Task.yield()
            guard router.shouldSuppressCardNavigation else { return }
            dismiss()
        }
    }

    var body: some View {
        Form {
            // Group so .appThemedRows() reaches every section's rows (it doesn't
            // propagate from the Form container, only from a Group/Section/ForEach).
            Group {
                overviewSection
                actionsSection
                if !displaySummary.isEmpty {
                    Section("Summary") { Text(displaySummary) }
                }
                detailsSection
                tagDiscoverySections
                statsSection
                seriesSection
                myTagsSection
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .refreshable { await refreshDetails() }
        // Same-touch author byline on a List card can also activate the row's work
        // NavigationLink. Dismiss async — in-transaction dismiss() is often ignored.
        .onAppear { dismissIfAuthorBylineConflict() }
        .onChange(of: router.cardNavigationSuppressed) { _, suppressed in
            if suppressed { dismissIfAuthorBylineConflict() }
        }
        .task {
            // Resolve an existing library record once (so a browsed work already in the
            // library shows its real saved state), then run the same Work Tags refresh
            // the local detail always did — only when we actually have a local record,
            // so merely viewing a remote work adds no AO3 request. Runs once per open.
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

    // MARK: - Overview

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !displayAuthor.isEmpty {
                    // A real Label (not a hand-rolled HStack) so the icon lines up
                    // with the Fandoms Label right below it — a raw HStack can't
                    // reproduce Label's exact icon size/gap/baseline alignment.
                    Label {
                        AO3AuthorBylineView(
                            names: displayAuthorList,
                            identities: displayAuthorIdentities,
                            includesBy: false,
                            font: .subheadline
                        )
                    } icon: {
                        Image(systemName: "person")
                            .foregroundStyle(.secondary)
                    }
                }

                if !displayFandoms.isEmpty {
                    Label(displayFandoms.joined(separator: ", "), systemImage: "books.vertical")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                FlowLayout(spacing: 10, rowSpacing: 6) {
                    if !displayRating.isEmpty {
                        WorkStatLabel(text: displayRating, symbol: "checkmark.shield")
                    }
                    if !displayChapters.isEmpty {
                        WorkStatLabel(text: displayChapters, symbol: "book")
                    }
                    if let status = displayStatus {
                        WorkStatLabel(
                            text: status,
                            symbol: status == "Complete" ? "checkmark.seal" : "circle.dashed"
                        )
                    }
                    if let words = displayWords {
                        WorkStatLabel(text: words.formatted(), symbol: "textformat.size")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions section

    private var actionsSection: some View {
        Section {
            Button(action: read) {
                HStack {
                    Label(readLabel, systemImage: readIcon)
                    Spacer()
                    if working { ProgressView() }
                }
            }
            .disabled(working)

            if let ao3URL {
                Button {
                    router.open(ao3URL)
                } label: {
                    Label("Open on AO3", systemImage: "safari")
                }
            }

            Button {
                withLocalWork { WorkLifecycle.setSaved($0, !$0.isSaved, in: context) }
            } label: {
                Label(
                    (localWork?.isSaved ?? false) ? "Saved" : "Save to Keep",
                    systemImage: (localWork?.isSaved ?? false) ? "bookmark.fill" : "bookmark"
                )
            }

            Button {
                saveForLater()
            } label: {
                HStack {
                    Label(
                        (localWork?.isInSavedForLaterQueue ?? false) ? "Saved for Later" : "Save for Later",
                        systemImage: (localWork?.isInSavedForLaterQueue ?? false)
                            ? "bookmark.fill"
                            : "bookmark"
                    )
                    Spacer()
                    if preservingStatusIsBusy { ProgressView() }
                }
            }
            .disabled(working || preservingStatusIsBusy || (localWork?.isInSavedForLaterQueue ?? false))

            Button {
                withLocalWork { _ in showingAddToQueue = true }
            } label: {
                Label(queueLabel, systemImage: "list.bullet.rectangle")
            }
            .disabled(working)

            if let work = localWork,
               work.isQueuedForLater,
               work.epubPreservationStatus == .failed || work.epubPreservationStatus == .missingFile {
                Button {
                    retryPreservation(work)
                } label: {
                    Label("Retry Queue Preservation", systemImage: "arrow.clockwise")
                }
            }

            if preservingSeries {
                Button(role: .cancel) {
                    cancelSeriesPreservation()
                } label: {
                    Label("Cancel Series Preservation", systemImage: "xmark.circle")
                }
            }

            Button {
                withLocalWork { work in
                    if work.isFinished {
                        WorkLifecycle.markStillReading(work, in: context)
                    } else {
                        WorkLifecycle.markFinished(work, in: context)
                    }
                }
            } label: {
                let finished = localWork?.isFinished ?? false
                Label(
                    finished ? "Mark as Still Reading" : "Mark as Finished",
                    systemImage: finished ? "arrow.uturn.backward.circle" : "checkmark.circle"
                )
            }

            Button {
                withLocalWork { _ in showingAddToCollection = true }
            } label: {
                Label(collectionLabel, systemImage: "square.stack")
            }
        } footer: {
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
                    Text(loadError).foregroundStyle(.red)
                } else if let queueNotice {
                    Text(queueNotice)
                } else {
                    Text(statusFooter)
                }
            }
        }
    }

    private var readLabel: String {
        if working { return "Downloading…" }
        return (localWork?.hasEPUB ?? false) ? "Read" : "Download & Read"
    }

    private var readIcon: String {
        (localWork?.hasEPUB ?? false) ? "book" : "arrow.down.circle"
    }

    private var collectionLabel: String {
        let count = localWork?.collections.count ?? 0
        return count == 0 ? "Add to Collection" : "In \(count) Collection\(count == 1 ? "" : "s")"
    }

    private var queueLabel: String {
        let count = localWork?.queueMemberships.count ?? 0
        return count == 0 ? "Add to Queue" : "In \(count) Queue\(count == 1 ? "" : "s")"
    }

    private var preservingStatusIsBusy: Bool {
        working || preservingSeries || localWork?.epubPreservationStatus == .preserving
    }

    private var statusFooter: String {
        guard let work = localWork else {
            return "Reading downloads this work to your device. When you finish, "
                + "the file is freed unless you save or favorite it."
        }
        if work.isInSavedForLaterQueue {
            switch work.epubPreservationStatus {
            case .preserved:
                if hasReadableEPUB(for: work) {
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

    private func hasReadableEPUB(for work: SavedWork) -> Bool {
        work.hasEPUB && FileManager.default.fileExists(atPath: work.fileURL.path)
    }

    // MARK: - Toolbar (favorite + more)

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                withLocalWork { work in
                    work.isFavorite.toggle()
                    work.markModified()
                    saveBestEffort("Saving favorite state failed")
                }
            } label: {
                let fav = localWork?.isFavorite ?? false
                Label(fav ? "Unfavorite" : "Favorite", systemImage: fav ? "star.fill" : "star")
            }
            .tint((localWork?.isFavorite ?? false) ? .yellow : nil)
        }
        ToolbarItem {
            Menu {
                if let id = ao3WorkID {
                    AO3WorkActionsMenu(workID: id, actions: workActions, workContext: .init(
                        title: displayTitle,
                        authors: displayAuthorList,
                        authorIdentities: displayAuthorIdentities,
                        fandoms: displayFandoms, rating: displayRating, chapters: displayChapters
                    ))
                }
            } label: {
                Label("More actions", systemImage: "ellipsis.circle")
            }
            .disabled(ao3WorkID == nil)
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        Section("Details") {
            if !displayAuthor.isEmpty {
                LabeledContent("Author") {
                    AO3AuthorBylineView(
                        names: displayAuthorList,
                        identities: displayAuthorIdentities,
                        includesBy: false,
                        font: .body
                    )
                }
            }
            if !displayRating.isEmpty { LabeledContent("Rating", value: displayRating) }
            if !displayCategories.isEmpty {
                LabeledContent("Category", value: displayCategories.joined(separator: ", "))
            }
            if let status = displayStatus {
                LabeledContent("Status", value: status)
            }
            if !displayLanguage.isEmpty { LabeledContent("Language", value: displayLanguage) }
            if let words = displayWords { LabeledContent("Words", value: words.formatted()) }
            if !displayChapters.isEmpty { LabeledContent("Chapters", value: displayChapters) }
            if !displayPublishedDate.isEmpty {
                LabeledContent("Published", value: displayPublishedDate)
            }
            if !displayUpdatedDate.isEmpty {
                LabeledContent("Updated", value: displayUpdatedDate)
            } else if let updated = remote?.dateUpdated, !updated.isEmpty {
                LabeledContent("Updated", value: updated)
            }
            if let work = localWork {
                LabeledContent("Added", value: work.dateAdded.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private var displayTitle: String {
        localWork?.title ?? remote?.title ?? "Untitled"
    }

    private var displayAuthor: String {
        if let author = localWork?.author, !author.isEmpty { return author }
        return remote?.authorText ?? ""
    }

    /// Individual author names (for the comments screen's "Author" badge).
    private var displayAuthorList: [String] {
        if let authors = remote?.authors, !authors.isEmpty { return authors }
        if let identities = localWork?.verifiedAuthorIdentities, !identities.isEmpty {
            return identities.map(\.displayName)
        }
        return displayAuthor.isEmpty ? [] : [displayAuthor]
    }

    private var displayAuthorIdentities: [AO3AuthorIdentity] {
        if let identities = remote?.authorIdentities, !identities.isEmpty { return identities }
        return localWork?.verifiedAuthorIdentities ?? []
    }

    private var displaySummary: String {
        if let summary = localWork?.summary, !summary.isEmpty { return summary.strippingHTML() }
        return remote?.summary ?? ""
    }

    private var displayRating: String {
        firstNonEmpty(localWork?.rating, remote?.rating)
    }

    private var displayLanguage: String {
        firstNonEmpty(localWork?.language, remote?.language)
    }

    private var displayPublishedDate: String {
        localWork?.datePublished ?? ""
    }

    private var displayUpdatedDate: String {
        firstNonEmpty(localWork?.dateUpdated, remote?.dateUpdated)
    }

    /// Warnings / categories / status / stats: prefer the local record's stored values
    /// (canonical once refreshed), falling back to the remote summary while unsaved.
    private var displayWarnings: [String] {
        if let warnings = localWork?.workWarnings, !warnings.isEmpty { return warnings }
        return remote?.warnings ?? []
    }

    private var displayCategories: [String] {
        if let categories = localWork?.workCategories, !categories.isEmpty { return categories }
        return remote?.categories ?? []
    }

    /// Categorized tag chips: prefer the local record's per-type lists (once the AO3
    /// refresh has run), else the remote summary's (the blurb is grouped too).
    private var displayFandoms: [String] {
        if let fandoms = localWork?.workFandoms, !fandoms.isEmpty { return fandoms }
        return remote?.fandoms ?? []
    }

    private var displayRelationships: [String] {
        if let relationships = localWork?.workRelationships, !relationships.isEmpty { return relationships }
        return remote?.relationships ?? []
    }

    private var displayCharacters: [String] {
        if let characters = localWork?.workCharacters, !characters.isEmpty { return characters }
        return remote?.characters ?? []
    }

    private var displayFreeforms: [String] {
        if let freeforms = localWork?.workFreeforms, !freeforms.isEmpty { return freeforms }
        return remote?.tags ?? []
    }

    private var displayStatus: String? {
        // A local work's completion flag is only meaningful for AO3-sourced imports
        // (a plain EPUB import has no status), so don't assert WIP for those.
        if let work = localWork,
           work.ao3WorkID != nil || WorkTags.ao3WorkID(from: work.sourceURL) != nil {
            return work.isComplete ? "Complete" : "Work in Progress"
        }
        if let complete = remote?.isComplete { return complete ? "Complete" : "Work in Progress" }
        return nil
    }

    private var displayKudos: Int? {
        if let kudos = localWork?.kudos, kudos > 0 { return kudos }
        return remote?.kudos
    }

    private var displayComments: Int? {
        if let comments = localWork?.comments, comments > 0 { return comments }
        return remote?.comments
    }

    private var displayHits: Int? {
        if let hits = localWork?.hits, hits > 0 { return hits }
        return remote?.hits
    }

    private var displayWords: Int? {
        if let count = localWork?.wordCount, count > 0 { return count }
        return remote?.words
    }

    private var displayChapters: String {
        firstNonEmpty(localWork?.chapters, remote?.chapters)
    }

    private func firstNonEmpty(_ first: String?, _ second: String?) -> String {
        if let first, !first.isEmpty { return first }
        return second ?? ""
    }

    /// The AO3 URL for "Open on AO3" / web fallback (local source URL or remote work URL).
    private var ao3URL: URL? {
        if let work = localWork, let url = URL(string: work.sourceURL), !work.sourceURL.isEmpty {
            return url
        }
        return remote?.workURL
    }

    /// The AO3 numeric work id (for the More-actions web menu), from either source.
    private var ao3WorkID: Int? {
        if let id = remote?.id { return id }
        if let id = localWork?.ao3WorkID { return id }
        return WorkTags.ao3WorkID(from: localWork?.sourceURL ?? "")
    }

    // MARK: - Stats (remote summaries carry these; local records don't)

    @ViewBuilder
    private var statsSection: some View {
        if displayKudos != nil || displayComments != nil || displayHits != nil || ao3WorkID != nil {
            Section("Stats") {
                if let kudos = displayKudos { LabeledContent("Kudos", value: kudos.formatted()) }
                if let id = ao3WorkID {
                    // Comments open the native comments screen; the count doubles
                    // as the row's value when known.
                    NavigationLink {
                        CommentsView(workID: id, context: .init(
                            title: displayTitle,
                            authors: displayAuthorList,
                            authorIdentities: displayAuthorIdentities,
                            fandoms: displayFandoms, rating: displayRating, chapters: displayChapters
                        ))
                    } label: {
                        LabeledContent("Comments",
                                       value: displayComments.map { $0.formatted() } ?? "Open")
                    }
                } else if let comments = displayComments {
                    LabeledContent("Comments", value: comments.formatted())
                }
                if let hits = displayHits { LabeledContent("Hits", value: hits.formatted()) }
            }
        }
    }

    // MARK: - Tags & discovery (Fandoms / Relationships / Characters / Additional)

    @ViewBuilder
    private var tagDiscoverySections: some View {
        let tapFooter = "Tags from AO3. Tap one to search AO3 for works with that tag."
        let anyCategorized = !displayWarnings.isEmpty || !displayFandoms.isEmpty
            || !displayRelationships.isEmpty || !displayCharacters.isEmpty
            || !displayFreeforms.isEmpty
        if anyCategorized {
            tagChipSection("Archive Warnings", displayWarnings, field: .warning)
            tagChipSection("Fandoms", displayFandoms, field: .fandom)
            tagChipSection("Relationships", displayRelationships, field: .relationship)
            tagChipSection("Characters", displayCharacters, field: .character)
            tagChipSection("Additional Tags", displayFreeforms, field: .freeform, footer: tapFooter)
        } else if let flat = localWork?.workTags, !flat.isEmpty {
            // Un-refreshed local imports carry only a flat, uncategorized tag list.
            tagChipSection("Tags", flat, field: .freeform, footer: tapFooter)
        }
    }

    @ViewBuilder
    private func tagChipSection(_ title: String, _ tags: [String],
                                field: AO3TagSearch.Field, footer: String? = nil) -> some View {
        if !tags.isEmpty {
            Section {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        // Tap a tag → search AO3 for works carrying it.
                        Button { router.searchAO3(field, tag) } label: {
                            TagChip(text: tag)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(title)
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }

    // MARK: - Series

    /// Other downloaded works in the same series, ordered by series position.
    private var seriesWorks: [SavedWork] {
        guard let work = localWork, !work.seriesTitle.isEmpty else { return [] }
        return allWorks
            .filter { $0.seriesTitle == work.seriesTitle && $0.id != work.id }
            .sorted { $0.seriesPosition < $1.seriesPosition }
    }

    private var displaySeriesTitle: String {
        if let title = localWork?.seriesTitle, !title.isEmpty { return title }
        return remote?.seriesTitle ?? ""
    }

    private var displaySeriesPosition: Int {
        localWork?.seriesPosition ?? remote?.seriesPosition ?? 0
    }

    private var displaySeriesURL: String {
        if let url = localWork?.seriesURL, !url.isEmpty { return url }
        return remote?.seriesURL ?? ""
    }

    @ViewBuilder
    private var seriesSection: some View {
        if !displaySeriesTitle.isEmpty {
            Section {
                LabeledContent("Series", value: displaySeriesTitle)
                if displaySeriesPosition > 0 {
                    LabeledContent("Part", value: "\(displaySeriesPosition)")
                }

                ForEach(seriesWorks) { other in
                    NavigationLink {
                        WorkDetailView(work: other)
                    } label: {
                        HStack {
                            if other.seriesPosition > 0 {
                                Text("\(other.seriesPosition).")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Text(other.title).lineLimit(1)
                        }
                    }
                }

                if !displaySeriesURL.isEmpty {
                    // Downloading a whole series needs a local anchor record; offered
                    // once the work itself is in the library.
                    if localWork != nil {
                        Button {
                            Task { await downloadSeries() }
                        } label: {
                            HStack {
                                Label(
                                    queuingSeries ? "Fetching series…" : "Download Whole Series",
                                    systemImage: "arrow.down.circle"
                                )
                                Spacer()
                                if queuingSeries { ProgressView() }
                            }
                        }
                        .disabled(queuingSeries)
                    }

                    Button {
                        if let url = URL(string: displaySeriesURL) { router.open(url) }
                    } label: {
                        Label("View Full Series on AO3", systemImage: "safari")
                    }
                }
            } header: {
                Text("Series")
            } footer: {
                if localWork != nil, seriesWorks.isEmpty {
                    Text("Other works in this series will appear here once you download them.")
                }
            }
        }
    }

    // MARK: - My Tags

    /// Quick-add suggestions for My Tags: the user's other tags plus this work's own
    /// AO3 tags, minus any already applied (case-insensitive, de-duplicated).
    private var suggestions: [String] {
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

    private var myTagsSection: some View {
        Section("My Tags") {
            let myTags = localWork?.tags ?? []
            if myTags.isEmpty {
                Text("No tags yet — add some to organize your Library.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(myTags.sorted { $0.name < $1.name }) { tag in
                    HStack {
                        Button { router.filterLibrary(.userTag, tag.name) } label: {
                            Text(tag.name).foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                TextField("Add a tag", text: $newTagName)
                    .onSubmit(addTypedTag)
                Button("Add", action: addTypedTag)
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { name in
                            Button { apply(named: name) } label: { TagChip(text: name) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
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

    /// Ensures a local `SavedWork` exists, importing the remote work on demand (the
    /// same download+import the reader already used — no new AO3 request types), then
    /// runs `action` with it. Local works run `action` immediately.
    private func withLocalWork(_ action: @escaping (SavedWork) -> Void) {
        resolveExistingIfNeeded()
        if let work = localWork { action(work); return }
        // A remote work needs importing; ignore re-taps while one is already in flight.
        guard let summary = remote, !working else { return }
        Task {
            working = true
            loadError = nil
            do {
                let temp = try await AO3Client.shared.downloadEPUB(workID: summary.id)
                let posted = Int(summary.chapters.split(separator: "/").first?
                    .trimmingCharacters(in: .whitespaces) ?? "") ?? 0
                let saved = try await importEPUB(temp, source: summary.workURL,
                                                 isComplete: summary.isComplete ?? false,
                                                 seriesURL: summary.seriesURL ?? "",
                                                 knownChapterCount: posted, into: context)
                applyRemoteMetadata(summary, to: saved)
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

    /// Copies the AO3 summary's stats / warnings / categories onto a freshly-imported
    /// work so the detail (and a later Library open) shows full parity immediately — the
    /// EPUB carries none of these. The background AO3 refresh keeps them current. Only
    /// fills blanks, so it never clobbers values the import already set.
    private func applyRemoteMetadata(_ summary: AO3WorkSummary, to work: SavedWork) {
        ReadingQueueService.applyRemoteMetadata(summary, to: work)
        saveBestEffort("Saving remote metadata failed")
    }

    // MARK: - Reading Queues

    private func saveForLater() {
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

    private func retryPreservation(_ work: SavedWork) {
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
        var parts: [String] = []
        if result.preserved > 0 {
            parts.append("\(result.preserved) preserved")
        }
        if result.alreadyPreserved > 0 {
            parts.append("\(result.alreadyPreserved) already preserved")
        }
        if result.unavailable > 0 {
            parts.append("\(result.unavailable) unavailable")
        }
        if result.failed > 0 {
            parts.append("\(result.failed) failed")
        }
        if result.skipped > 0 {
            parts.append("\(result.skipped) skipped")
        }
        if parts.isEmpty {
            return "Series works are already preserved for later."
        }
        return "Series preservation complete: " + parts.joined(separator: ", ") + "."
    }

    // MARK: - Reading

    /// Opens the reader for this work. Imports a remote work first, and re-downloads a
    /// freed history entry, before pushing the reader — it never opens another detail.
    private func read() {
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
    /// queue (already-saved works are skipped). Surfaces failures in the action footer.
    private func downloadSeries() async {
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

    private func addTypedTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        apply(named: trimmed)
        newTagName = ""
    }

    private func apply(named name: String) {
        withLocalWork { work in
            let tag = tag(named: name)
            if !work.tags.contains(where: { $0.name == tag.name }) {
                work.tags.append(tag)
                saveBestEffort("Saving tag assignment failed")
            }
        }
    }

    private func removeTag(_ tag: Tag) {
        guard let work = localWork else { return }
        work.tags.removeAll { $0.name == tag.name }
        saveBestEffort("Saving tag removal failed")
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

    private func saveBestEffort(_ reason: StaticString) {
        do {
            try context.save()
        } catch {
            Log.library.error(
                "\(String(describing: reason), privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
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
            .formStyle(.grouped)
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
