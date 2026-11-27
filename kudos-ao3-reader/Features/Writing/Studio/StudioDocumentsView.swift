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
    @State private var ao3Drafts: AO3DraftsPage?
    @State private var isLoadingDrafts = false
    @State private var ao3DraftsError: String?
    @State private var reloadToken = 0

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
        let postedWorks = auth.isLoggedIn ? (profileModel?.works ?? []) : []
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
            ao3PostedWorks: postedWorks,
            ao3DraftWorks: draftWorks,
            ao3DraftDaysLeft: draftDaysLeft,
            deviceName: ThisDevice.name
        )
    }

    private var isLoadingAO3: Bool {
        guard auth.isLoggedIn else { return false }
        return isLoadingDrafts
            || profileModel?.contentPhase == .loading
            || profileModel?.headerPhase == .loading
    }

    private var activationKey: String {
        "\(auth.sessionGeneration)|\(auth.username ?? "")|\(reloadToken)"
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
                        ao3Error: ao3DraftsError,
                        onRetryAO3: { reloadToken += 1 },
                        onChanged: { reloadToken += 1 }
                    )
                case .files:
                    StudioFilesView(
                        works: snapshot.allWorks,
                        deletedCount: deletedCount,
                        storageSummary: storageSummary,
                        store: store,
                        sort: filesSort,
                        isLoadingAO3: isLoadingAO3,
                        onChanged: { reloadToken += 1 },
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
        .onChange(of: auth.username, initial: true) { _, _ in
            syncProfileModel()
        }
        .task(id: activationKey) {
            await loadAll()
        }
        .refreshable {
            await refreshAll()
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
                onChanged: { reloadToken += 1 }
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

    private func syncProfileModel() {
        guard auth.isLoggedIn,
              let username = auth.username,
              let route = AO3AuthorRoute(username: username) else {
            profileModel?.cancel()
            profileModel = nil
            ao3Drafts = nil
            ao3DraftsError = nil
            return
        }
        if profileModel?.route.username.localizedCaseInsensitiveCompare(username) != .orderedSame {
            profileModel = AO3AuthorProfileModel(route: route)
        }
        profileModel?.activate(auth: auth)
    }

    private func loadAll() async {
        await reloadLocalStore()
        syncProfileModel()
        await loadAO3Drafts()
    }

    private func refreshAll() async {
        await reloadLocalStore()
        if auth.isLoggedIn {
            if let profileModel {
                await profileModel.refresh(auth: auth)
            }
            await loadAO3Drafts()
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

    private func loadAO3Drafts() async {
        guard auth.isLoggedIn else {
            ao3Drafts = nil
            ao3DraftsError = nil
            isLoadingDrafts = false
            return
        }
        let generation = auth.sessionGeneration
        isLoadingDrafts = true
        ao3DraftsError = nil
        do {
            let loaded = try await auth.loadDrafts(page: 1)
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            ao3Drafts = loaded
        } catch {
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            ao3DraftsError = UserFacingError.message(for: error)
        }
        isLoadingDrafts = false
    }
}
