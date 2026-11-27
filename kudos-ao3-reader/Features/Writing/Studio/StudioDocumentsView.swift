import SwiftUI

/// Writing Studio → Documents section (Lane S2).
///
/// Sits inside S1's `NavigationStack` under the four-part Writing bar
/// (`Overview · Documents · Comments · Stats`). Owns the inline `Pages | Files`
/// switch and merges local manuscripts (`WritingDocumentStore`) with the
/// signed-in account's AO3 works and drafts. Local documents, import, work
/// folders, and Recently Deleted work signed out.
struct StudioDocumentsView: View {
    private let store: WritingDocumentStore

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var mode: StudioDocumentsMode = .pages
    @State private var selectedChip: StudioDocumentsFilterChip = .all
    @State private var searchQuery = ""
    @State private var filesSort: StudioFilesSort = .edited

    @State private var localSnapshots: [StudioLocalWorkSnapshot] = []
    @State private var deletedCount = 0
    @State private var storageSummary = StudioStorageSummary(documentCount: 0, byteCount: 0)

    @State private var profileModel: AO3AuthorProfileModel?
    @State private var postedWorks: [AO3WorkSummary] = []
    @State private var ao3Drafts: AO3DraftsPage?
    @State private var isLoadingAO3 = false
    @State private var ao3Error: String?
    @State private var localReload = 0
    @State private var ao3LoadGeneration = 0

    @State private var importedRoute: ImportedDocumentRoute?

    private struct ImportedDocumentRoute: Identifiable, Hashable {
        let workID: UUID
        let chapterID: UUID
        let workTitle: String
        var id: UUID { chapterID }
    }

    init() {
        self.store = WritingDocumentStore(root: WritingDocumentStore.defaultRoot)
    }

    init(store: WritingDocumentStore) {
        self.store = store
    }

    private var snapshot: StudioDocumentsSnapshot {
        let draftWorks = auth.isLoggedIn ? (ao3Drafts?.page.works ?? []) : []
        let now = Date()
        var draftDaysLeft: [Int: Int] = [:]
        if auth.isLoggedIn, let deletionDates = ao3Drafts?.deletionDates {
            for (workID, components) in deletionDates {
                if let days = DraftExpiry.daysLeft(until: components, now: now, calendar: .current) {
                    draftDaysLeft[workID] = days
                }
            }
        }
        return StudioDocumentsCatalog.build(
            localWorks: localSnapshots,
            ao3PostedWorks: auth.isLoggedIn ? postedWorks : [],
            ao3DraftWorks: draftWorks,
            ao3DraftDaysLeft: draftDaysLeft,
            deviceName: ThisDevice.name
        )
    }

    private var ao3ActivationKey: String {
        "\(auth.sessionGeneration)|\(auth.username ?? "")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                modeControlBar

                switch mode {
                case .pages:
                    StudioDocumentsPagesView(
                        snapshot: snapshot,
                        store: store,
                        selectedChip: $selectedChip,
                        searchQuery: $searchQuery,
                        isLoadingAO3: isLoadingAO3,
                        ao3Error: ao3Error,
                        onRetryAO3: { Task { await loadAO3(force: true) } },
                        onChanged: { localReload += 1 },
                        onAO3Write: { Task { await loadAO3(force: true) } }
                    )
                case .files:
                    StudioFilesView(
                        works: snapshot.allWorks,
                        deletedCount: deletedCount,
                        storageSummary: storageSummary,
                        store: store,
                        sort: filesSort,
                        isLoadingAO3: isLoadingAO3,
                        onChanged: { localReload += 1 },
                        onAO3Write: { Task { await loadAO3(force: true) } },
                        onOpenImported: { imported in
                            importedRoute = ImportedDocumentRoute(
                                workID: imported.work.id,
                                chapterID: imported.chapter.id,
                                workTitle: imported.work.title
                            )
                        }
                    )
                }
            }
            .padding(.horizontal, SubjectMetrics.gutter)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(theme.appTheme.contentBackdrop.ignoresSafeArea())
        .navigationDestination(item: $importedRoute) { route in
            LocalChapterEditorScreen(
                workID: route.workID,
                chapterID: route.chapterID,
                initialWorkTitle: route.workTitle,
                store: store
            )
        }
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            if !loggedIn { clearAO3Presentation() }
        }
        .task(id: localReload) {
            await reloadLocalStore()
        }
        .task(id: ao3ActivationKey) {
            await loadAO3(force: false)
        }
        .refreshable {
            await reloadLocalStore()
            await loadAO3(force: true)
        }
        .onDisappear {
            profileModel?.cancel()
        }
    }

    // MARK: - Pages | Files bar

    @ViewBuilder
    private var modeControlBar: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                modeSwitch
                if mode == .files {
                    HStack(spacing: 12) {
                        sortMenu
                        Spacer(minLength: 8)
                        selectLink
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                modeSwitch
                    .frame(maxWidth: 164)
                Spacer(minLength: 8)
                if mode == .files {
                    sortMenu
                    selectLink
                }
            }
        }
    }

    private var modeSwitch: some View {
        SubjectSegmentedControl(
            options: StudioDocumentsMode.allCases,
            title: \.title,
            selection: $mode
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Documents view")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(StudioFilesSort.allCases) { option in
                Button {
                    filesSort = option
                } label: {
                    if filesSort == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(filesSort.title)
                    .font(.subheadline)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.accentInk)
            .padding(.horizontal, 8)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel("Sort folders, currently \(filesSort.title)")
    }

    private var selectLink: some View {
        NavigationLink {
            StudioSelectView(
                works: snapshot.allWorks,
                store: store,
                onChanged: { localReload += 1 },
                onAO3Write: { Task { await loadAO3(force: true) } }
            )
        } label: {
            Text("Select")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accentInk)
                .padding(.horizontal, 8)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .disabled(snapshot.allWorks.isEmpty)
        .opacity(snapshot.allWorks.isEmpty ? 0.45 : 1)
        .accessibilityLabel("Select works")
    }

    // MARK: - Data loading

    private func clearAO3Presentation() {
        ao3LoadGeneration += 1
        profileModel?.cancel()
        profileModel = nil
        postedWorks = []
        ao3Drafts = nil
        ao3Error = nil
        isLoadingAO3 = false
        StudioAO3LoadCache.shared.clear()
    }

    /// Loads AO3 works and drafts once, then only on pull to refresh, after a
    /// write, a sign-in or sign-out, or once `StudioAO3Freshness` says the last
    /// load is stale. A fresh cache hit does not create a profile model.
    private func loadAO3(force: Bool) async {
        ao3LoadGeneration += 1
        let loadID = ao3LoadGeneration
        guard auth.isLoggedIn, let username = auth.username, !username.isEmpty else {
            clearAO3Presentation()
            return
        }
        let session = auth.sessionGeneration
        let cache = StudioAO3LoadCache.shared
        let cached = cache.documents(session: session, username: username)
        if let cached {
            postedWorks = cached.posted
            ao3Drafts = cached.drafts
            ao3Error = cached.error
            if !force && !StudioAO3Freshness.isStale(cached.loadedAt) {
                isLoadingAO3 = false
                return
            }
        } else {
            postedWorks = []
            ao3Drafts = nil
            ao3Error = nil
        }
        guard loadID == ao3LoadGeneration else { return }
        isLoadingAO3 = postedWorks.isEmpty && ao3Drafts == nil

        let posted = await reloadPostedWorks(session: session, username: username, force: force)
        guard loadID == ao3LoadGeneration, !Task.isCancelled, session == auth.sessionGeneration, auth.isLoggedIn else {
            if loadID == ao3LoadGeneration { isLoadingAO3 = false }
            return
        }
        if let posted {
            postedWorks = posted
        }

        let draftsOutcome = await reloadDrafts(session: session)
        guard loadID == ao3LoadGeneration, !Task.isCancelled, session == auth.sessionGeneration, auth.isLoggedIn else {
            if loadID == ao3LoadGeneration { isLoadingAO3 = false }
            return
        }
        let draftsLoaded: Bool
        let draftsPage: AO3DraftsPage?
        let error: String?
        switch draftsOutcome {
        case .cancelled:
            isLoadingAO3 = false
            return
        case let .loaded(page):
            ao3Drafts = page
            ao3Error = nil
            draftsLoaded = true
            draftsPage = page
            error = nil
        case let .failed(message):
            ao3Error = message
            draftsLoaded = false
            draftsPage = nil
            error = message
        }
        cache.storeDocuments(
            session: session,
            username: username,
            posted: posted,
            drafts: draftsPage,
            draftsLoaded: draftsLoaded,
            error: error,
            loadedAt: Date()
        )
        isLoadingAO3 = false
    }

    private func reloadPostedWorks(
        session: Int,
        username: String,
        force: Bool
    ) async -> [AO3WorkSummary]? {
        guard let route = AO3AuthorRoute(username: username) else { return nil }
        if profileModel?.route.username.localizedCaseInsensitiveCompare(username) != .orderedSame {
            profileModel?.cancel()
            profileModel = AO3AuthorProfileModel(route: route)
        }
        guard let model = profileModel else { return nil }
        if force || (model.headerPhase == .loaded && model.contentPhase == .loaded) {
            await model.refresh(auth: auth)
        } else {
            model.activate(auth: auth)
            await waitUntilProfileSettles(model)
        }
        guard !Task.isCancelled, session == auth.sessionGeneration else { return nil }
        guard model.contentPhase == .loaded else { return nil }
        return model.works
    }

    private func waitUntilProfileSettles(_ model: AO3AuthorProfileModel) async {
        let deadline = Date().addingTimeInterval(45)
        while !Task.isCancelled, Date() < deadline {
            if profileSettled(model) { return }
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
        }
    }

    private func profileSettled(_ model: AO3AuthorProfileModel) -> Bool {
        switch model.headerPhase {
        case .idle, .loading:
            return false
        case .failed, .unavailable:
            return true
        case .loaded:
            switch model.contentPhase {
            case .idle, .loading: return false
            case .loaded, .failed, .unavailable: return true
            }
        }
    }

    private enum DraftsFetch {
        case loaded(AO3DraftsPage)
        case failed(String)
        case cancelled
    }

    private func reloadDrafts(session: Int) async -> DraftsFetch {
        do {
            let loaded = try await auth.loadDrafts(page: 1)
            guard !Task.isCancelled, session == auth.sessionGeneration else { return .cancelled }
            return .loaded(loaded)
        } catch {
            guard !Task.isCancelled, session == auth.sessionGeneration else { return .cancelled }
            return .failed(UserFacingError.message(for: error))
        }
    }

    private func reloadLocalStore() async {
        do {
            _ = try? await store.emptyRecentlyDeleted()
            let works = try await store.listWorks()
            var loaded: [StudioLocalWorkSnapshot] = []
            for work in works {
                let chapters = (try? await store.listChapters(workID: work.id)) ?? []
                let notes = (try? await store.listStoryNotes(workID: work.id)) ?? []
                var excerpts: [UUID: String] = [:]
                if let latest = chapters.max(by: { $0.updatedAt < $1.updatedAt }),
                   let doc = try? await store.loadChapter(workID: work.id, chapterID: latest.id) {
                    excerpts[latest.id] = StudioDocumentsCatalog.excerpt(fromBodyHTML: doc.bodyHTML)
                }
                loaded.append(StudioLocalWorkSnapshot(
                    work: work,
                    chapters: chapters,
                    storyNotes: notes,
                    chapterExcerpts: excerpts
                ))
            }
            let deleted = (try? await store.listRecentlyDeleted()) ?? []
            guard !Task.isCancelled else { return }
            localSnapshots = loaded
            deletedCount = deleted.count

            let root = store.root
            let docCount = loaded.reduce(0) { total, entry in
                total + max(1, entry.chapters.count) + entry.storyNotes.count
            }
            let measured = await Task.detached(priority: .utility) {
                StudioStorageSummary.measure(root: root, documentCount: docCount)
            }.value
            guard !Task.isCancelled else { return }
            storageSummary = measured
        } catch {
            // Keep prior local state on transient disk read failure.
        }
    }
}
