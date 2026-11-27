import Combine
import SwiftData
import SwiftUI

/// When Writing Studio may read AO3 again. Showing the tab, a section, or a card is not a reason.
enum StudioAO3Load {
    /// Same window `WritingView.isStale` uses once that lands (wave 52). This branch predates it.
    static let freshnessWindow: TimeInterval = 15 * 60

    struct Stamp: Equatable {
        var loadedAt: Date?
        var sessionGeneration: Int?
        var username: String?
        var reloadToken: Int = 0
    }

    static func shouldLoad(
        stamp: Stamp,
        now: Date,
        sessionGeneration: Int,
        username: String?,
        reloadToken: Int,
        force: Bool
    ) -> Bool {
        if force { return true }
        if stamp.sessionGeneration != sessionGeneration || stamp.username != username { return true }
        guard let loadedAt = stamp.loadedAt, stamp.reloadToken == reloadToken else { return true }
        return now.timeIntervalSince(loadedAt) >= freshnessWindow
    }
}

/// The Writing Studio tab root (T-574): "Writing" title, pseud / offline subtitle, pinned
/// four-part section bar (Overview · Documents · Comments · Stats), and the active section.
///
/// Offline sections (Overview and Documents) work without an AO3 account. Signed out,
/// Comments and Stats present an account-required panel with Log In rather than an error.
struct WritingStudioView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inboxModel
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(\.duoLayout) private var duoLayout
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var localWorks: [SavedWork]

    @AppStorage(StudioSectionStore.storageKey) private var selectedSectionRaw = StudioSection.overview.rawValue

    @State private var path = NavigationPath()
    @State private var profileModel: AO3AuthorProfileModel?
    @State private var postingPseudName: String?

    @State private var daySnapshot: StudioDayLogSnapshot = .empty
    @State private var localDocuments: [StudioLocalDocumentSummary] = []
    @State private var localReload = 0

    @State private var drafts: AO3DraftsPage?
    @State private var draftsError: String?
    @State private var isLoadingDrafts = false
    @State private var draftsReload = 0
    @State private var draftsStamp = StudioAO3Load.Stamp()

    @State private var stats: AO3UserStats?
    @State private var statsHistory: [StudioStatsSnapshot] = []
    @State private var statsError: String?
    @State private var isLoadingStats = false
    @State private var statsReload = 0
    @State private var statsStamp = StudioAO3Load.Stamp()
    @State private var activeStatsRequestID: UUID?
    /// Session already handed to `AO3AuthorProfileModel.activate`. A second launch cancels the first.
    @State private var profileActivationToken: String?

    @State private var editingWorkID: Int?
    @State private var showingLogin = false
    @State private var showingImport = false
    @State private var showingGoalSheet = false
    @State private var startWritingError: String?
    @State private var isCreatingDocument = false
    @State private var now = Date()

    /// Private navigation routes owned solely by the S1 shell.
    private enum ShellDestination: Hashable {
        case requests
        case gifts
        case stats
        case inbox
        case settings
        case newAO3Work
        case localDocument(StudioLocalDocumentTarget)
    }

    private var selectedSection: StudioSection {
        StudioSection(rawValue: selectedSectionRaw) ?? .overview
    }

    private var selectedSectionBinding: Binding<StudioSection> {
        Binding(
            get: { selectedSection },
            set: { selectedSectionRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                studioHeader
                sectionBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Writing")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inlineLarge)
            #endif
            .duoVerticalCompressionPrefersTabBar(duoLayout.hasVerticalBar)
            .subjectScreenSurface(.content, palette: theme.scopePalette)
            .hidesNavigationBarChrome()
            .navigationDestination(for: WritingRoute.self, destination: writingDestination)
            .navigationDestination(for: ShellDestination.self, destination: shellDestination)
            .navigationDestination(for: SettingsRoute.self) { SettingsDestination(route: $0) }
            .navigationDestination(item: $editingWorkID) {
                WritingWorkDestination(workID: $0) { draftsReload += 1 }
            }
            .navigationDestination(for: AO3WorkSummary.self) { WorkDetailView(remote: $0) }
            .navigationDestination(for: SavedWork.self) { WorkDetailView(work: $0) }
            .navigationDestination(for: LocalWorkDestination.self) { LocalWorkDestinationView(destination: $0) }
            .navigationDestination(for: AccountInboxThreadDestination.self) { destination in
                CommentsView(
                    workID: destination.workID,
                    context: destination.workContext,
                    initialChapterPosition: destination.focus == .chapter
                        ? destination.chapterPosition : nil,
                    initialCommentID: destination.commentID,
                    initialFocusesChapter: destination.focus == .chapter,
                    initialReplyCommentID: destination.opensReplyComposer ? destination.commentID : nil,
                    requiredSessionGeneration: destination.sessionGeneration,
                    onResolveWorkContext: {
                        inboxModel.cacheWorkContext($0, for: destination, auth: auth)
                    }
                )
            }
            .navigationDestination(for: AO3CollectionDestination.self) {
                AO3CollectionDetailView(slug: $0.slug, title: $0.title)
            }
            .navigationDestination(for: AO3CollectionFormDestination.self) {
                AO3CollectionFormView(
                    slug: $0.slug,
                    onDeleted: { if !path.isEmpty { path.removeLast() } }
                )
            }
            .navigationDestination(for: AO3CollectionItemsDestination.self) {
                AO3CollectionItemsView(slug: $0.slug, title: $0.title)
            }
            .ao3AuthorNavigation(path: $path, tab: .writing)
            .toolbar { studioToolbar }
            .sheet(isPresented: $showingLogin) { AO3LoginView() }
            .sheet(isPresented: $showingGoalSheet) { StudioWritingGoalSheet() }
            .sheet(isPresented: $showingImport) {
                ImportWorkView(
                    onOpenDraft: { workID in
                        draftsReload += 1
                        editingWorkID = workID
                    },
                    onOpenWork: { workID in
                        router.openAO3Link(AO3Client.workURL(workID: workID))
                    }
                )
            }
            .alert(
                "Couldn't Start Document",
                isPresented: Binding(
                    get: { startWritingError != nil },
                    set: { if !$0 { startWritingError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { startWritingError = nil }
            } message: {
                Text(startWritingError ?? "")
            }
            #if DEBUG
            .task {
                try? await Task.sleep(for: .seconds(1.5))
                DebugLaunchRoute.applyWriting(to: &path)
                editingWorkID = DebugLaunchRoute.accountEditWorkID
                if DebugLaunchRoute.takePush("writingrequests") {
                    path.append(ShellDestination.requests)
                }
                if DebugLaunchRoute.takeSheet("importwork") {
                    showingImport = true
                }
                if DebugLaunchRoute.takePush("newdocument") {
                    startNewLocalDocument()
                }
            }
            #endif
            .task(id: localActivationKey) { await reloadLocalState() }
            .task(id: ao3ActivationKey) { await activateAO3State() }
            .task(id: statsActivationKey) { await loadStats() }
            .onChange(of: auth.username, initial: true) { _, _ in syncProfileModel() }
            .onChange(of: router.pendingWritingRoute, initial: true) { _, route in
                guard let route else { return }
                path = NavigationPath()
                path.append(route)
                router.pendingWritingRoute = nil
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    let currentDate = Date()
                    now = currentDate
                    localReload += 1
                    reloadStaleAO3IfNeeded(now: currentDate)
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: StudioWritingDayLog.didChangeNotification)
                    .receive(on: RunLoop.main)
            ) { _ in
                localReload += 1
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                    .receive(on: RunLoop.main)
            ) { _ in
                now = Date()
                localReload += 1
            }
            .richEditorPrewarm(backgroundColor: theme.appTheme.backgroundColor)
            .onDisappear { profileModel?.cancel() }
        }
    }

    // MARK: - Header & section bar (pinned under title while section scrolls)

    private var studioHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            if auth.isLoggedIn {
                StudioPseudMenu(
                    profileModel: profileModel,
                    postingPseudName: $postingPseudName
                )
            } else {
                Text("Not signed in · your writing stays on this \(ThisDevice.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Not signed in. Your writing stays on this \(ThisDevice.name)")
            }

            StudioSectionBar(
                selection: selectedSectionBinding,
                isSignedIn: auth.isLoggedIn,
                unreadCommentCount: auth.isLoggedIn ? (inboxModel.unreadCount ?? 0) : 0
            )
        }
        .padding(.horizontal, SubjectMetrics.accountGutter)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch selectedSection {
        case .overview:
            StudioOverviewView(
                daySnapshot: daySnapshot,
                localDocuments: localDocuments,
                drafts: drafts,
                isLoadingDrafts: isLoadingDrafts,
                draftsError: draftsError,
                stats: stats,
                statsHistory: statsHistory,
                isLoadingStats: isLoadingStats,
                statsError: statsError,
                recentPostedWorks: Array((profileModel?.works ?? []).prefix(5)),
                cachedCount: cachedCount,
                now: now,
                onTapGoal: { showingGoalSheet = true },
                onStartNewDocument: startNewLocalDocument,
                onOpenLocalDocument: { path.append(ShellDestination.localDocument($0)) },
                onOpenAO3Draft: { editingWorkID = $0 },
                onOpenAO3Work: { path.append($0) },
                onSelectSection: { selectedSectionRaw = $0.rawValue },
                onOpenRequests: { path.append(ShellDestination.requests) },
                onOpenSeries: { path.append(WritingRoute.series) },
                onOpenCollections: { path.append(WritingRoute.collectionsAndChallenges) },
                onOpenGifts: { path.append(ShellDestination.gifts) },
                onRetryDrafts: { draftsReload += 1 },
                onRetryStats: { statsReload += 1 },
                onSignIn: { showingLogin = true },
                onRefresh: refreshAll
            )

        case .documents:
            StudioDocumentsView()

        case .comments:
            if auth.isLoggedIn {
                StudioCommentsView()
            } else {
                StudioSignedOutSectionPanel(
                    section: .comments,
                    onSignIn: { showingLogin = true },
                    onBackToOverview: { selectedSectionRaw = StudioSection.overview.rawValue }
                )
            }

        case .stats:
            if auth.isLoggedIn {
                StudioStatsView()
            } else {
                StudioSignedOutSectionPanel(
                    section: .stats,
                    onSignIn: { showingLogin = true },
                    onBackToOverview: { selectedSectionRaw = StudioSection.overview.rawValue }
                )
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var studioToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: startNewLocalDocument) {
                Label("New Document", systemImage: "square.and.pencil")
            }
            .disabled(isCreatingDocument)
            .accessibilityLabel("New Document")

            Menu {
                Button {
                    showingGoalSheet = true
                } label: {
                    Label("Writing Goal…", systemImage: "target")
                }

                if auth.isLoggedIn {
                    signedInMenuItems
                } else {
                    Button {
                        showingLogin = true
                    } label: {
                        Label("Sign In to AO3", systemImage: "person.badge.key")
                    }
                }

                Divider()

                Button {
                    path.append(ShellDestination.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .accessibilityLabel("More writing actions")
        }
    }

    @ViewBuilder
    private var signedInMenuItems: some View {
        Button {
            path.append(ShellDestination.newAO3Work)
        } label: {
            Label("New Work on AO3", systemImage: "doc.badge.plus")
        }

        Button {
            showingImport = true
        } label: {
            Label("Import from a URL", systemImage: "square.and.arrow.down")
        }

        Divider()

        Button {
            path.append(ShellDestination.requests)
        } label: {
            Label("Requests", systemImage: "tray.and.arrow.down")
        }

        Button {
            path.append(WritingRoute.works)
        } label: {
            Label("Your Works", systemImage: "books.vertical")
        }

        Button {
            path.append(WritingRoute.drafts)
        } label: {
            Label("AO3 Drafts", systemImage: "doc.badge.clock")
        }

        Button {
            path.append(WritingRoute.series)
        } label: {
            Label("Series", systemImage: "square.stack.3d.up")
        }

        Button {
            path.append(WritingRoute.collectionsAndChallenges)
        } label: {
            Label("Collections & Challenges", systemImage: "person.3.sequence")
        }

        Button {
            path.append(ShellDestination.gifts)
        } label: {
            Label("Gifts", systemImage: "gift")
        }

        Button {
            path.append(ShellDestination.stats)
        } label: {
            Label("Stats by Work", systemImage: "chart.bar")
        }

        Button {
            path.append(ShellDestination.inbox)
        } label: {
            Label("AO3 Inbox", systemImage: "tray")
        }
    }
}

private extension WritingStudioView {
    // MARK: - Destinations

    @ViewBuilder
    func writingDestination(_ route: WritingRoute) -> some View {
        switch route {
        case .works: ownProfile(title: "Your Works", tab: .works)
        case .drafts: WritingDraftsView()
        case .series: ownProfile(title: "Series", tab: .series)
        case .collectionsAndChallenges: AO3CollectionsList()
        }
    }

    @ViewBuilder
    private func shellDestination(_ destination: ShellDestination) -> some View {
        switch destination {
        case .requests:
            WritingRequestsView()
        case .gifts:
            ownProfile(title: "Gifts", tab: .gifts)
        case .stats:
            WritingStatsView()
        case .inbox:
            AccountInboxScreen(
                model: inboxModel,
                onOpen: { openInboxItem($0, focus: .parentOrSelf) },
                onReply: { openInboxItem($0, focus: .parentOrSelf, opensReplyComposer: true) },
                onOpenChapter: { openInboxItem($0, focus: .chapter) },
                workContext: knownWorkContext,
                metadataTaskID: inboxMetadataTaskID,
                onEnrichVisible: enrichVisibleInboxWorkContexts
            )
            .onAppear { inboxModel.activate(auth: auth) }
        case .settings:
            SettingsHubView()
        case .newAO3Work:
            WritingWorkDestination(workID: nil) { draftsReload += 1 }
        case let .localDocument(target):
            LocalChapterEditorScreen(
                workID: target.workID,
                chapterID: target.chapterID,
                initialWorkTitle: target.title
            )
            .onDisappear { localReload += 1 }
        }
    }

    @ViewBuilder
    func ownProfile(title: String, tab: AO3AuthorProfileTab) -> some View {
        if let username = auth.username, let route = AO3AuthorRoute(username: username) {
            AuthorProfileView(route: route, navigationTitle: title, initialTab: tab)
        } else {
            ContentUnavailableView {
                Label("Not signed in", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Sign in to AO3 to view \(title.lowercased()).")
            } actions: {
                Button("Sign In to AO3") { showingLogin = true }
                    .buttonStyle(.kudosPrimary)
            }
        }
    }

    // MARK: - Data loading

    var localActivationKey: String {
        [
            "\(router.selection == .writing)",
            selectedSectionRaw,
            "\(localReload)",
            "\(path.count)",
            "\(auth.sessionGeneration)",
            auth.username ?? ""
        ].joined(separator: "|")
    }

    var ao3ActivationKey: String {
        "\(router.selection == .writing)|\(auth.sessionGeneration)|\(auth.username ?? "")|\(draftsReload)"
    }

    var statsActivationKey: String {
        "\(router.selection == .writing)|\(auth.sessionGeneration)|\(auth.username ?? "")|\(statsReload)"
    }

    func reloadLocalState() async {
        guard router.selection == .writing else { return }
        let currentDate = Date()
        now = currentDate
        if let snapshot = try? await StudioWritingDayLog.shared.snapshot(asOf: currentDate) {
            daySnapshot = snapshot
        }
        if let docs = try? await StudioLocalLibraryLoader.loadRecent() {
            localDocuments = docs
        }
        if auth.isLoggedIn, let account = auth.username, !account.isEmpty {
            let store = StudioStatsHistoryStore(account: account)
            let loaded = await Task.detached(priority: .utility) { store.load() }.value
            if auth.isLoggedIn, auth.username == account {
                statsHistory = loaded
            }
        } else {
            statsHistory = []
        }
    }

    func activateAO3State() async {
        guard router.selection == .writing else { return }
        syncProfileModel()
        guard auth.isLoggedIn else {
            await loadDrafts()
            return
        }
        let now = Date()
        let shouldFetch = StudioAO3Load.shouldLoad(
            stamp: draftsStamp,
            now: now,
            sessionGeneration: auth.sessionGeneration,
            username: auth.username,
            reloadToken: draftsReload,
            force: false
        )
        if shouldFetch {
            let loadedAt = draftsStamp.loadedAt
            let sameAccount = loadedAt != nil
                && draftsStamp.sessionGeneration == auth.sessionGeneration
                && draftsStamp.username == auth.username
            if sameAccount, let loadedAt, now.timeIntervalSince(loadedAt) >= StudioAO3Load.freshnessWindow {
                // Window elapsed. `refresh` keeps the rows already on screen; `activate` would no-op.
                await inboxModel.refresh(auth: auth)
                guard !Task.isCancelled else { return }
            } else {
                // First load, sign-in, or a draft reload. `activate` fetches only while the inbox is idle.
                inboxModel.activate(auth: auth)
            }
        }
        await loadDrafts()
    }

    func refreshAll() async {
        await reloadLocalState()
        guard auth.isLoggedIn else { return }
        if let profileModel { await profileModel.refresh(auth: auth) }
        await inboxModel.refresh(auth: auth)
        await loadDrafts(force: true)
        await loadStats(force: true)
    }

    /// Foregrounding past the freshness window reloads drafts and stats. A fresh stamp does nothing,
    /// so becoming active is not itself a fetch.
    func reloadStaleAO3IfNeeded(now: Date) {
        guard auth.isLoggedIn else { return }
        if draftsStamp.loadedAt != nil, StudioAO3Load.shouldLoad(
            stamp: draftsStamp,
            now: now,
            sessionGeneration: auth.sessionGeneration,
            username: auth.username,
            reloadToken: draftsReload,
            force: false
        ) {
            draftsReload += 1
        }
        if statsStamp.loadedAt != nil, StudioAO3Load.shouldLoad(
            stamp: statsStamp,
            now: now,
            sessionGeneration: auth.sessionGeneration,
            username: auth.username,
            reloadToken: statsReload,
            force: false
        ) {
            statsReload += 1
        }
    }

    func syncProfileModel() {
        guard let username = auth.username, let route = AO3AuthorRoute(username: username) else {
            profileModel = nil
            profileActivationToken = nil
            drafts = nil
            draftsError = nil
            isLoadingDrafts = false
            draftsStamp = StudioAO3Load.Stamp()
            stats = nil
            statsHistory = []
            statsError = nil
            isLoadingStats = false
            activeStatsRequestID = nil
            statsStamp = StudioAO3Load.Stamp()
            postingPseudName = nil
            return
        }
        if profileModel?.route.username.localizedCaseInsensitiveCompare(username) != .orderedSame {
            profileModel = AO3AuthorProfileModel(route: route)
            profileActivationToken = nil
        }
        postingPseudName = auth.preferredPostingPseudName
        let token = "\(auth.sessionGeneration)|\(username)"
        guard profileActivationToken != token else { return }
        profileActivationToken = token
        profileModel?.activate(auth: auth)
    }

    func loadDrafts(force: Bool = false) async {
        guard auth.isLoggedIn else {
            drafts = nil
            draftsError = nil
            isLoadingDrafts = false
            draftsStamp = StudioAO3Load.Stamp()
            return
        }
        let generation = auth.sessionGeneration
        let username = auth.username
        let token = draftsReload
        guard StudioAO3Load.shouldLoad(
            stamp: draftsStamp,
            now: Date(),
            sessionGeneration: generation,
            username: username,
            reloadToken: token,
            force: force
        ) else {
            isLoadingDrafts = false
            return
        }
        if draftsStamp.sessionGeneration != generation || draftsStamp.username != username {
            drafts = nil
            draftsError = nil
        }
        isLoadingDrafts = true
        draftsError = nil
        defer { isLoadingDrafts = false }
        do {
            let loaded = try await auth.loadDrafts(page: 1)
            guard !Task.isCancelled, generation == auth.sessionGeneration, auth.username == username else { return }
            drafts = loaded
            draftsStamp = finishedAO3Stamp(generation: generation, username: username, reloadToken: token)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled, generation == auth.sessionGeneration, auth.username == username else { return }
            draftsError = UserFacingError.message(for: error)
            draftsStamp = finishedAO3Stamp(generation: generation, username: username, reloadToken: token)
        }
    }

    func loadStats(force: Bool = false) async {
        guard auth.isLoggedIn else {
            stats = nil
            statsHistory = []
            statsError = nil
            isLoadingStats = false
            activeStatsRequestID = nil
            statsStamp = StudioAO3Load.Stamp()
            return
        }
        // Leaving Writing restarts this task. Keep the numbers already on screen.
        guard router.selection == .writing else { return }
        let generation = auth.sessionGeneration
        let username = auth.username
        let token = statsReload
        guard StudioAO3Load.shouldLoad(
            stamp: statsStamp,
            now: Date(),
            sessionGeneration: generation,
            username: username,
            reloadToken: token,
            force: force
        ) else {
            isLoadingStats = false
            return
        }
        if statsStamp.sessionGeneration != generation || statsStamp.username != username {
            stats = nil
            statsError = nil
        }
        let requestID = UUID()
        activeStatsRequestID = requestID
        isLoadingStats = true
        statsError = nil
        defer {
            if activeStatsRequestID == requestID { isLoadingStats = false }
        }
        do {
            let loaded = try await auth.loadUserStats()
            guard activeStatsRequestID == requestID, !Task.isCancelled,
                  generation == auth.sessionGeneration, auth.username == username else { return }
            stats = loaded
            statsStamp = finishedAO3Stamp(generation: generation, username: username, reloadToken: token)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard activeStatsRequestID == requestID, !Task.isCancelled,
                  generation == auth.sessionGeneration, auth.username == username else { return }
            statsError = UserFacingError.message(for: error)
            statsStamp = finishedAO3Stamp(generation: generation, username: username, reloadToken: token)
        }
    }

    func finishedAO3Stamp(generation: Int, username: String?, reloadToken: Int) -> StudioAO3Load.Stamp {
        StudioAO3Load.Stamp(
            loadedAt: Date(),
            sessionGeneration: generation,
            username: username,
            reloadToken: reloadToken
        )
    }

    func startNewLocalDocument() {
        guard !isCreatingDocument else { return }
        isCreatingDocument = true
        Task {
            defer { isCreatingDocument = false }
            do {
                let target = try await StudioStartWritingAction.createFirstDocument(router: router)
                localReload += 1
                path.append(ShellDestination.localDocument(target))
            } catch {
                startWritingError = UserFacingError.message(for: error)
            }
        }
    }

    func cachedCount(_ kind: AO3AccountListKind) -> String? {
        AO3AccountListCountsCache.shared.count(
            for: kind,
            authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        )?.displayText
    }

    // MARK: - Inbox routing helpers

    var inboxMetadataTaskID: String {
        let ids = inboxModel.items.compactMap(\.workID).map(String.init).joined(separator: ",")
        return "\(auth.sessionGeneration)|\(inboxModel.metadataRevision)|\(ids)"
    }

    func enrichVisibleInboxWorkContexts() async {
        guard case .loaded = inboxModel.phase else { return }
        var seeds: [Int: AO3CommentsWorkContext] = [:]
        for item in inboxModel.items {
            guard let workID = item.workID else { continue }
            seeds[workID] = knownWorkContext(for: item)
        }
        await inboxModel.enrichVisibleWorkContexts(
            workIDs: inboxModel.items.compactMap(\.workID),
            seededContexts: seeds,
            auth: auth
        )
    }

    func openInboxItem(
        _ item: AO3InboxItem,
        focus: AccountInboxThreadFocus,
        opensReplyComposer: Bool = false
    ) {
        if let workID = item.workID {
            path.append(AccountInboxThreadDestination(
                workID: workID,
                workContext: knownWorkContext(for: item),
                commentID: item.id,
                chapterPosition: item.chapterPosition,
                focus: focus,
                opensReplyComposer: opensReplyComposer,
                sessionGeneration: auth.sessionGeneration
            ))
        } else {
            router.open(AO3Client.commentThreadURL(commentID: item.id))
        }
    }

    func knownWorkContext(for item: AO3InboxItem) -> AO3CommentsWorkContext {
        guard let workID = item.workID else {
            return AO3CommentsWorkContext(title: item.workTitle, authors: [])
        }
        if let context = inboxModel.workContext(for: workID) { return context }
        if let work = localWorks.first(where: { $0.ao3WorkID == workID }) {
            return AO3CommentsWorkContext(savedWork: work)
        }
        if let work = profileModel?.works.first(where: { $0.id == workID }) {
            return AO3CommentsWorkContext(remote: work)
        }
        return AO3CommentsWorkContext(title: item.workTitle, authors: [])
    }
}
