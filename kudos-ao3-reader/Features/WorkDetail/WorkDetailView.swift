import SwiftUI
import SwiftData

/// The single, canonical work-detail screen — used for **every** work the app can open,
/// whether it's a locally saved work or a remote AO3 summary (Home, Library, Browse,
/// Search, Bookmarks, AO3 lists, …). There is no separate "compact" remote detail.
///
/// `Read` always opens the reader; it never pushes another detail page. A remote work
/// is resolved to a local `SavedWork` lazily — only when the reader or a management
/// action actually needs it — so merely browsing never imports a work. Once resolved
/// (or if the work is already in the library), the screen reflects its real local state.
struct WorkDetailView: View {
    /// Where the work came from. A `.remote` summary is resolved to a local record on
    /// demand; a `.saved` work is already local.
    enum Source: Hashable {
        case saved(SavedWork)
        case remote(AO3WorkSummary)
    }

    let source: Source

    init(work: SavedWork) { self.source = .saved(work) }
    init(remote: AO3WorkSummary) { self.source = .remote(remote) }

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(AO3AuthService.self) private var auth
    @Environment(DownloadQueue.self) private var downloadQueue
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Query private var allWorks: [SavedWork]

    /// The resolved local record: the saved work itself, an existing library match for
    /// a remote summary, or the record created when a remote work is imported on tap.
    @State private var localWork: SavedWork?
    @State private var resolvedExisting = false

    @State private var newTagName = ""
    @State private var showingAddToCollection = false
    @State private var working = false          // a download / import is in flight
    @State private var loadError: String?
    @State private var readerWork: SavedWork?    // non-nil → push the reader
    @State private var queuingSeries = false
    @State private var workActions = AO3WorkActionsModel()

    // MARK: - Source helpers

    /// The remote summary, when this detail was opened from an AO3 listing.
    private var remote: AO3WorkSummary? {
        if case .remote(let summary) = source { return summary }
        return nil
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
        .task {
            // Resolve an existing library record once (so a browsed work already in the
            // library shows its real saved state), then run the same Work Tags refresh
            // the local detail always did — only when we actually have a local record,
            // so merely viewing a remote work adds no AO3 request. Runs once per open.
            resolveExistingIfNeeded()
            guard let work = localWork else { return }
            await WorkTags.backfillFromEPUB(for: work, in: context)
            await WorkTags.refreshFromAO3(for: work, in: context)
        }
        // BookReaderView routes to the Readium navigator on iOS, the legacy reader on
        // macOS — so the unified detail opens the right reader on this branch.
        .navigationDestination(item: $readerWork) { BookReaderView(work: $0) }
        .sheet(isPresented: $showingAddToCollection) {
            if let work = localWork { AddToCollectionView(work: work) }
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

    @ViewBuilder
    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !displayAuthor.isEmpty {
                    Label(displayAuthor, systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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

    @ViewBuilder
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

            if !(localWork?.isFinished ?? false) {
                Button {
                    withLocalWork { WorkLifecycle.markFinished($0, in: context) }
                } label: {
                    Label("Mark as Finished", systemImage: "checkmark.circle")
                }
            }

            Button {
                withLocalWork { _ in showingAddToCollection = true }
            } label: {
                Label(collectionLabel, systemImage: "square.stack")
            }
        } footer: {
            if let loadError {
                Text(loadError).foregroundStyle(.red)
            } else {
                Text(statusFooter)
            }
        }
    }

    private var readLabel: String {
        if working { return "Downloading…" }
        return (localWork?.hasEPUB ?? false) ? "Read" : "Download & Read"
    }
    private var readIcon: String { (localWork?.hasEPUB ?? false) ? "book" : "arrow.down.circle" }

    private var collectionLabel: String {
        let count = localWork?.collections.count ?? 0
        return count == 0 ? "Add to Collection" : "In \(count) Collection\(count == 1 ? "" : "s")"
    }

    private var statusFooter: String {
        guard let work = localWork else {
            return "Reading downloads this work to your device. When you finish, "
                + "the file is freed unless you save or favorite it."
        }
        if work.isSaved { return "Saved — kept on this device." }
        if WorkTags.ao3WorkID(from: work.sourceURL) == nil {
            return "Imported EPUB — kept on this device for offline reading."
        }
        if !work.hasEPUB {
            return "Finished. The file was freed to save space; it re-downloads when you read it again."
        }
        if work.isFinished { return "Finished." }
        if work.isFavorite { return "Favorited, so its file is kept when finished." }
        return "Reading. When you finish, the file is freed unless you save or favorite it."
    }

    // MARK: - Toolbar (favorite + more)

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                withLocalWork { work in
                    work.isFavorite.toggle()
                    try? context.save()
                }
            } label: {
                let fav = localWork?.isFavorite ?? false
                Label(fav ? "Unfavorite" : "Favorite", systemImage: fav ? "star.fill" : "star")
            }
            .tint((localWork?.isFavorite ?? false) ? .yellow : nil)
        }
        ToolbarItem {
            Menu {
                if let id = ao3WorkID { AO3WorkActionsMenu(workID: id, actions: workActions) }
            } label: {
                Label("More actions", systemImage: "ellipsis.circle")
            }
            .disabled(ao3WorkID == nil)
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        Section("Details") {
            if !displayAuthor.isEmpty { LabeledContent("Author", value: displayAuthor) }
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

    private var displayTitle: String { localWork?.title ?? remote?.title ?? "Untitled" }
    private var displayAuthor: String {
        if let a = localWork?.author, !a.isEmpty { return a }
        return remote?.authorText ?? ""
    }
    private var displaySummary: String {
        if let s = localWork?.summary, !s.isEmpty { return s.strippingHTML() }
        return remote?.summary ?? ""
    }
    private var displayRating: String { firstNonEmpty(localWork?.rating, remote?.rating) }
    private var displayLanguage: String { firstNonEmpty(localWork?.language, remote?.language) }
    private var displayPublishedDate: String { localWork?.datePublished ?? "" }
    private var displayUpdatedDate: String { firstNonEmpty(localWork?.dateUpdated, remote?.dateUpdated) }

    // Warnings / categories / status / stats: prefer the local record's stored values
    // (canonical once refreshed), falling back to the remote summary while unsaved.
    private var displayWarnings: [String] {
        if let w = localWork?.workWarnings, !w.isEmpty { return w }
        return remote?.warnings ?? []
    }
    private var displayCategories: [String] {
        if let c = localWork?.workCategories, !c.isEmpty { return c }
        return remote?.categories ?? []
    }
    // Categorized tag chips: prefer the local record's per-type lists (once the AO3
    // refresh has run), else the remote summary's (the blurb is grouped too).
    private var displayFandoms: [String] {
        if let f = localWork?.workFandoms, !f.isEmpty { return f }
        return remote?.fandoms ?? []
    }
    private var displayRelationships: [String] {
        if let r = localWork?.workRelationships, !r.isEmpty { return r }
        return remote?.relationships ?? []
    }
    private var displayCharacters: [String] {
        if let c = localWork?.workCharacters, !c.isEmpty { return c }
        return remote?.characters ?? []
    }
    private var displayFreeforms: [String] {
        if let f = localWork?.workFreeforms, !f.isEmpty { return f }
        return remote?.tags ?? []
    }
    private var displayStatus: String? {
        // A local work's completion flag is only meaningful for AO3-sourced imports
        // (a plain EPUB import has no status), so don't assert WIP for those.
        if let work = localWork, WorkTags.ao3WorkID(from: work.sourceURL) != nil {
            return work.isComplete ? "Complete" : "Work in Progress"
        }
        if let complete = remote?.isComplete { return complete ? "Complete" : "Work in Progress" }
        return nil
    }
    private var displayKudos: Int? {
        if let k = localWork?.kudos, k > 0 { return k }
        return remote?.kudos
    }
    private var displayComments: Int? {
        if let c = localWork?.comments, c > 0 { return c }
        return remote?.comments
    }
    private var displayHits: Int? {
        if let h = localWork?.hits, h > 0 { return h }
        return remote?.hits
    }
    private var displayWords: Int? {
        if let count = localWork?.wordCount, count > 0 { return count }
        return remote?.words
    }
    private var displayChapters: String { firstNonEmpty(localWork?.chapters, remote?.chapters) }

    private func firstNonEmpty(_ a: String?, _ b: String?) -> String {
        if let a, !a.isEmpty { return a }
        return b ?? ""
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
        return WorkTags.ao3WorkID(from: localWork?.sourceURL ?? "")
    }

    // MARK: - Stats (remote summaries carry these; local records don't)

    @ViewBuilder
    private var statsSection: some View {
        if displayKudos != nil || displayComments != nil || displayHits != nil {
            Section("Stats") {
                if let kudos = displayKudos { LabeledContent("Kudos", value: kudos.formatted()) }
                if let comments = displayComments { LabeledContent("Comments", value: comments.formatted()) }
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
        if let t = localWork?.seriesTitle, !t.isEmpty { return t }
        return remote?.seriesTitle ?? ""
    }
    private var displaySeriesPosition: Int { localWork?.seriesPosition ?? remote?.seriesPosition ?? 0 }
    private var displaySeriesURL: String {
        if let u = localWork?.seriesURL, !u.isEmpty { return u }
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
                if localWork != nil && seriesWorks.isEmpty {
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

    @ViewBuilder
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
        case .saved(let work):
            localWork = work
        case .remote(let summary):
            localWork = existingWork(forSource: summary.workURL, in: context)
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
        if work.workWarnings.isEmpty { work.workWarnings = summary.warnings }
        if work.workCategories.isEmpty { work.workCategories = summary.categories }
        if work.kudos == 0, let kudos = summary.kudos { work.kudos = kudos }
        if work.comments == 0, let comments = summary.comments { work.comments = comments }
        if work.hits == 0, let hits = summary.hits { work.hits = hits }
        if work.wordCount == 0, let words = summary.words { work.wordCount = words }
        if work.chapters.isEmpty { work.chapters = summary.chapters }
        try? context.save()
    }

    // MARK: - Reading

    /// Opens the reader for this work. Imports a remote work first, and re-downloads a
    /// freed history entry, before pushing the reader — it never opens another detail.
    private func read() {
        withLocalWork { work in
            if work.hasEPUB { readerWork = work; return }
            // Freed history entry: re-download into the existing record, keeping its id
            // (so progress/tags stay attached), then open.
            guard let id = WorkTags.ao3WorkID(from: work.sourceURL) else {
                loadError = "This work can't be re-downloaded automatically. Open it on AO3."
                return
            }
            Task {
                working = true
                loadError = nil
                do {
                    let temp = try await AO3Client.shared.downloadEPUB(workID: id)
                    try? FileManager.default.removeItem(at: work.fileURL)
                    try FileManager.default.moveItem(at: temp, to: work.fileURL)
                    work.hasEPUB = true
                    work.isFinished = false
                    work.lastSpineIndex = 0
                    try? context.save()
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
                try? context.save()
            }
        }
    }

    private func removeTag(_ tag: Tag) {
        guard let work = localWork else { return }
        work.tags.removeAll { $0.name == tag.name }
        try? context.save()
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
