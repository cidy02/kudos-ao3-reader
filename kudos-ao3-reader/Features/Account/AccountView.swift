import SwiftData
import SwiftUI

/// The self-contained Account sheet presented by Home's profile button. T-460
/// moves the existing profile, Inbox, AO3 preferences, website entry, Settings
/// and session actions here; its larger visual restyle belongs to T-470.
struct AccountView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inboxModel
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var localWorks: [SavedWork]

    @State private var path = NavigationPath()
    @State private var showingLogin = false
    @State private var selectedTab: AccountTab = .overview
    @ScaledMetric(relativeTo: .body) private var scopeRowTitleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var scopeRowSubtitleSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .body) private var skeletonUsernameSize: CGFloat = 19
    @ScaledMetric(relativeTo: .footnote) private var previewNoticeSize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .footnote) private var scopeRowCountSize: CGFloat = 13
    @State private var readingTab: AccountReadingTab = .later
    @State private var editingWorkID: Int?
    @State private var writingTab: AccountWritingTab = .works
    @State private var activityTab: AccountActivityTab = .history
    /// The signed-in user's own profile content (Works / Series / Bookmarks).
    @State private var profileModel: AO3AuthorProfileModel?
    @State private var showingInboxFilters = false
    @State private var filters = AO3SearchFilters()
    @State private var showingFilters = false
    /// Still read by the unused profile-content helper. The hub no longer draws
    /// an inline work list, so nothing toggles it.
    @State private var expandAll = false
    /// The reader's chosen Shortcuts, as an ordered list of raw values.
    @AppStorage(AccountShortcutStore.key) private var shortcutsRaw = ""
    @State private var editingShortcuts = false
    @AppStorage("hideMatureContent") private var hideMature = true
    @State private var postingPseudName: String?
    @State private var confirmingLogOut = false

    enum Route: Hashable {
        case myCollections
        case preferences
        case moreOnAO3
        case settings
        case backupAndSync
        /// Native AO3 own-user dashboard (sidebar destinations).
        case dashboard
        /// Artboard 1x, which `WritingDraftsView` already is.
        case drafts
        /// Artboards 1u and 1w: the signed-in user's own works and series, on
        /// the profile surface opened at that scope.
        case myWorks
        case mySeries
        /// Artboard 1l.
        case inbox
    }

    enum AccountTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case reading = "Reading"
        case writing = "Writing"
        case activity = "Activity"

        var id: String { rawValue }
    }

    enum AccountReadingTab: String, CaseIterable, Identifiable {
        case later = "Marked for Later"
        case subscriptions = "Subscriptions"
        case bookmarks = "Bookmarks"
        case collections = "Collections"

        var id: String { rawValue }

        /// Matches Overview shortcut / list chrome icons for this subsection.
        var systemImage: String {
            switch self {
            case .later: "clock.badge"
            case .subscriptions: "bell"
            case .bookmarks: "bookmark"
            case .collections: "square.stack"
            }
        }
    }

    enum AccountWritingTab: String, CaseIterable, Identifiable {
        case works = "Works"
        case series = "Series"
        case drafts = "Drafts"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .works: "doc.text"
            case .series: "square.stack.3d.up"
            case .drafts: "doc.badge.clock"
            }
        }
    }

    enum AccountActivityTab: String, CaseIterable, Identifiable {
        case history = "History"
        case inbox = "Inbox"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .history: "clock"
            case .inbox: "tray"
            }
        }
    }

    /// The hub's rows per scope, in the order the signed-in groups draw them and
    /// the signed-out preview lists them. One list each, so the preview cannot
    /// leave out a row the hub has (1n; it once lacked Subscriptions, Drafts and
    /// History). Reading keeps 1bt's order: the three saved shelves, then the
    /// followed one.
    static let readingRowOrder: [AccountReadingTab] = [.later, .bookmarks, .collections, .subscriptions]
    static let writingRowOrder: [AccountWritingTab] = [.works, .series, .drafts]
    static let activityRowOrder: [AccountActivityTab] = [.history, .inbox]

    /// The floating gear fades while you scroll down (owner, 2026-10-01).
    @State private var chromeScrolledAway = false

    var body: some View {
        NavigationStack(path: $path) {
            Group { standardListRoot }
                .navigationTitle("Account")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationDestination(for: Route.self, destination: destination)
                #if DEBUG
                .task {
                    try? await Task.sleep(for: .seconds(1.5))
                    DebugLaunchRoute.applyAccount(to: &path)
                    editingWorkID = DebugLaunchRoute.accountEditWorkID
                    if DebugLaunchRoute.takeSheet("inboxfilter") { showingInboxFilters = true }
                }
                #endif
                .navigationDestination(item: $editingWorkID) { WritingWorkDestination(workID: $0) }
                .navigationDestination(for: SettingsRoute.self) { SettingsDestination(route: $0) }
                .navigationDestination(for: AO3AccountWorksList.Kind.self) {
                    AO3AccountWorksList(kind: $0)
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
                .navigationDestination(for: SavedWork.self) { WorkDetailView(work: $0) }
                // The work cards on this tab carry an ⓘ that pushes
                // `LocalWorkDestination.detail`; without this handler it would be
                // an inert control here while working everywhere else.
                .navigationDestination(for: LocalWorkDestination.self) {
                    LocalWorkDestinationView(destination: $0)
                }
                .navigationDestination(for: AO3WorkSummary.self) { WorkDetailView(remote: $0) }
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
                        onResolveWorkContext: { inboxModel.cacheWorkContext($0, for: destination, auth: auth) }
                    )
                }
                .ao3AuthorNavigation(path: $path, tab: .account)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: dismissAccount) {
                            Label("Done", systemImage: "checkmark")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .sheet(isPresented: $showingLogin) { AO3LoginView() }
                .sheet(isPresented: $editingShortcuts) {
                    AccountShortcutsEditor(raw: $shortcutsRaw)
                }
                .sheet(isPresented: $showingFilters) {
                    AO3FilterPanel(
                        filters: $filters,
                        mode: .refine,
                        canReset: filters != AO3SearchFilters(),
                        onApply: { showingFilters = false },
                        onReset: {
                            filters = AO3SearchFilters()
                            showingFilters = false
                        },
                        // The same array the works section narrows, so the
                        // panel's "N of M match" line and the list behind it
                        // cannot disagree — the precedent is AO3AccountWorksList.
                        refineSource: profileModel?.works ?? []
                    )
                }
                .sheet(isPresented: $showingInboxFilters) {
                    AccountInboxFilterSheet(model: inboxModel)
                }
                .alert("Couldn't update Inbox", isPresented: showingInboxActionError) {
                    Button("OK") { inboxModel.clearActionError() }
                } message: {
                    Text(inboxModel.actionError ?? "AO3 couldn't update your Inbox.")
                }
                .task(id: activationKey) { activateVisibleContent() }
                .onChange(of: router.pendingAccountRoute, initial: true) { _, route in
                    guard let route else { return }
                    openAccountRoute(route)
                    router.pendingAccountRoute = nil
                }
                .onChange(of: auth.username, initial: true) { _, username in
                    syncProfileModel(username: username)
                }
                .onChange(of: auth.sessionGeneration, initial: true) { _, _ in
                    // Reset private Inbox state immediately on logout/session replacement.
                    inboxModel.syncAuthenticationContext(auth: auth)
                }
                .onChange(of: activityTab) { _, tab in
                    if tab != .inbox { inboxModel.endSelection() }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private var standardListRoot: some View {
        standardListBody
    }

    private var standardListBody: some View {
        List {
            profileCardSection

            if auth.isLoggedIn {
                accountProfileCountStrip
                accountLatestSection
                accountInboxSection
                accountAO3Section
            }
            accountKudosSection
            if auth.isLoggedIn { accountLogOutSection }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                theme.appTheme.cardBackdrop
                if auth.isLoggedIn {
                    accountPalette.wash.frame(height: 380)
                }
            }
            .ignoresSafeArea()
        }
        .refreshable { await refreshAccountSheet() }
    }

    /// Account identity follows the same stable username hue as Author Profile.
    /// This palette paints only the header wash; controls inherit app red.
    private var accountPalette: SubjectPalette {
        theme.appTheme.subjectPalette(hue: CoverArt.hue(for: auth.username ?? "AO3 account"))
    }

    // MARK: Activation

    private var activationKey: String {
        [
            auth.username ?? "",
            String(auth.sessionGeneration),
            String(router.isPresentingAccount),
            selectedTab.rawValue,
            readingTab.rawValue,
            writingTab.rawValue,
            activityTab.rawValue
        ].joined(separator: "|")
    }

    private func activateVisibleContent() {
        guard router.isPresentingAccount, auth.isLoggedIn else { return }
        profileModel?.activate(auth: auth)
        inboxModel.activate(auth: auth)
    }

    private func syncProfileModel(username: String?) {
        if let username, let route = AO3AuthorRoute(username: username) {
            if profileModel?.route.username.localizedCaseInsensitiveCompare(username) != .orderedSame {
                profileModel = AO3AuthorProfileModel(route: route, overviewMode: true)
            }
        } else {
            profileModel = nil
            selectedTab = .overview
        }
        postingPseudName = auth.preferredPostingPseudName
        activateVisibleContent()
    }

    private func syncProfileTab(_ tab: AO3AuthorProfileTab) {
        guard let model = profileModel else { return }
        model.selectTab(tab, auth: auth)
        model.activate(auth: auth)
    }

    // MARK: Destinations & toolbar

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .myCollections: AO3CollectionsList()
        case .preferences: AO3PreferencesView()
        case .moreOnAO3: AccountMoreOnAO3View()
        case .settings: SettingsHubView()
        case .backupAndSync: AccountBackupSyncView()
        case .dashboard: AO3DashboardView()
        case .drafts: WritingDraftsView()
        case .myWorks: ownProfile(title: "Works", tab: .works)
        case .mySeries: ownProfile(title: "Series", tab: .series)
        case .inbox:
            AccountInboxScreen(
                model: inboxModel,
                onOpen: openInboxItem,
                onReply: openInboxReply,
                onOpenChapter: openInboxChapter,
                workContext: { knownWorkContext(for: $0) },
                metadataTaskID: inboxMetadataTaskID,
                onEnrichVisible: enrichVisibleInboxWorkContexts
            )
            // Pushed from the hub, the Activity tab is never selected, so
            // `activateVisibleContent` never started the load and the skeleton
            // stayed up (T-318). `activate` is a no-op once loaded.
            .onAppear { inboxModel.activate(auth: auth) }
        }
    }

    /// 1u and 1w are the account's own works and series. `AuthorProfileView` is
    /// already that screen — header, wash, ledger rows — so they open it at the
    /// right scope rather than growing a third copy of the same list.
    @ViewBuilder
    private func ownProfile(title: String, tab: AO3AuthorProfileTab) -> some View {
        if let route = profileModel?.route
            ?? auth.username.flatMap({ AO3AuthorRoute(username: $0) }) {
            AuthorProfileView(route: route, navigationTitle: title, initialTab: tab)
        } else {
            ContentUnavailableView(
                "Not signed in",
                systemImage: "person.crop.circle.badge.questionmark"
            )
        }
    }

    private var isInboxVisible: Bool {
        auth.isLoggedIn && selectedTab == .activity && activityTab == .inbox
    }

    private var showingInboxActionError: Binding<Bool> {
        Binding(
            get: { inboxModel.actionError != nil },
            set: { isPresented in
                if !isPresented { inboxModel.clearActionError() }
            }
        )
    }

    /// The hub's rows open their own screens. Those screens own List/Grid and
    /// Show Summaries. This page has no inline work list to switch.
    private var showsWorkListControls: Bool {
        guard auth.isLoggedIn else { return false }
        switch selectedTab {
        case .overview:
            return false
        case .writing:
            // Its rows open their own screens now, which carry these controls.
            return false
        case .reading:
            // Reading draws only its groups now, so there is no inline list for
            // display-mode, expand-all or the mature reveal to act on. Those
            // controls belong to the screen each row opens, which carries its own.
            return false
        case .activity:
            // History and Inbox open their own screens too, so nothing on this
            // page is a work list any more.
            return false
        }
    }

    /// Every works screen offers Show/Hide mature whenever Hide Mature is on.
    private var showsMatureRevealControl: Bool {
        showsWorkListControls
            && hideMature
    }

    // MARK: Account sheet content

    @ViewBuilder
    private var profileCardSection: some View {
        if auth.isLoggedIn {
            if let model = profileModel {
                if model.header != nil {
                    AuthorProfileOverviewHeader(
                        model: model,
                        isOwnProfile: true,
                        muteAction: nil,
                        blockAction: nil,
                        onSubscription: {},
                        onModeration: { _ in },
                        onSelectScope: { model.selectScope($0, auth: auth) }
                    )
                    accountProfileActions(model)
                } else {
                    accountProfileLoadState(model)
                }
            } else {
                Section {
                    ProgressView("Loading your AO3 profile…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accentFill()
                }
                .cardRow()
            }
        } else {
            Section {
                AccountProfileCard(
                    profileModel: profileModel,
                    postingPseudName: $postingPseudName,
                    onViewProfile: openOwnProfile,
                    onLogin: { showingLogin = true }
                )
                .padding(16)
                .subjectPanel()
                .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
            }
        }

        if let notice = auth.noticeMessage {
            Section {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            }
        }
    }

    @ViewBuilder
    private func accountProfileLoadState(_ model: AO3AuthorProfileModel) -> some View {
        Section {
            switch model.headerPhase {
            case .idle, .loading, .loaded:
                ProgressView("Loading your AO3 profile…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accentFill()
            case .unavailable:
                AO3ProfileMessageRow(
                    title: "Profile unavailable",
                    systemImage: "person.slash",
                    message: "AO3 could not load your profile. It may be temporarily unavailable.",
                    actionTitle: "Try Again",
                    action: { model.retry(auth: auth) }
                )
            case let .failed(message):
                AO3ProfileMessageRow(
                    title: "Couldn't load your profile",
                    systemImage: "exclamationmark.triangle",
                    message: message,
                    actionTitle: "Try Again",
                    action: { model.retry(auth: auth) }
                )
            }
        }
        .cardRow()
    }

    private func accountProfileActions(_ model: AO3AuthorProfileModel) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return Section {
            layout {
                // Board 35 gives this one more room (1.4 : 1 : 1); sized to its
                // label it no longer wraps "View / Profile" onto two lines.
                Button(action: openOwnProfile) {
                    Label("View Profile", systemImage: "person")
                        // Pressed for room, the adaptive label style drops the
                        // title and leaves a bare icon; this button needs both.
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                }
                .buttonStyle(.borderedProminent)
                .accentFill()
                .prominentLabel()

                ShareLink(item: model.route.dashboardURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.accentInk)
                .accentFill()

                Button {
                    if let url = profileEditURL { router.open(url) }
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.accentInk)
                .accentFill()
                .disabled(profileEditURL == nil)
            }
            // Board 35: 15 pt semibold labels, so the three fit one row.
            .font(.subheadline.weight(.semibold))
            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
        }
    }

    @ViewBuilder
    private var accountProfileCountStrip: some View {
        if let model = profileModel, let header = model.header {
            AuthorProfileCountStrip(items: [
                .init(
                    title: "Works",
                    count: header.listCount(for: .works, route: model.route),
                    action: { path.append(Route.myWorks) }
                ),
                .init(
                    title: "Series",
                    count: header.listCount(for: .series, route: model.route),
                    action: { path.append(Route.mySeries) }
                ),
                .init(
                    title: "Bookmarks",
                    count: header.listCount(for: .bookmarks, route: model.route),
                    action: { path.append(AO3AccountWorksList.Kind.bookmarks) }
                ),
                .init(
                    title: "Subscriptions",
                    countText: cachedCount(.subscriptions),
                    action: { openLibraryAO3(.subscriptions) }
                )
            ])
        }
    }

    private var accountLatestSection: some View {
        Section {
            SectionRuleHeader(title: "Your Latest")
                .pageBodyRow(top: 18, gutter: 0)
            if let work = profileModel?.latestWork {
                AuthorProfileLatestCard(work: work)
                    .cardNavigation(to: work, accessibilityLabel: work.title)
                    .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
            } else {
                Text(profileModel?.header?.recentWorks == nil
                    ? "Couldn't read your latest work. Open Works to try again."
                    : "No recent works visible on AO3.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .subjectPanel()
                    .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
            }
        }
    }

    private var accountInboxSection: some View {
        Section {
            VStack(spacing: 0) {
                panelNavRow(
                    title: "Inbox",
                    systemImage: "tray",
                    count: inboxModel.unreadCount.map(String.init),
                    value: Route.inbox
                )
                SubjectRowSeparator()
                accountInboxPreview
            }
            .subjectPanel()
            .pageBodyRow(top: 18, gutter: SubjectMetrics.accountGutter)
        }
    }

    @ViewBuilder
    private var accountInboxPreview: some View {
        switch inboxModel.phase {
        case .idle, .loading:
            ProgressView("Loading recent messages…")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .accentFill()
        case .loaded, .paginationFailed:
            let items = Array(inboxModel.items.prefix(2))
            if items.isEmpty {
                Text("No messages in your AO3 inbox.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SubjectRowSeparator() }
                    AccountInboxPreviewRow(item: item) { openInboxItem(item) }
                }
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Again") { inboxModel.retry(auth: auth) }
                    .foregroundStyle(.accentInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private var accountAO3Section: some View {
        Section {
            VStack(spacing: 0) {
                panelNavRow(
                    title: "Inbox",
                    systemImage: "tray",
                    count: inboxModel.unreadCount.map(String.init),
                    value: Route.inbox
                )
                SubjectRowSeparator()
                panelNavRow(
                    title: "AO3 Preferences",
                    systemImage: "slider.horizontal.3",
                    value: Route.preferences
                )
                SubjectRowSeparator()
                panelNavRow(
                    title: "My Dashboard",
                    systemImage: "square.grid.2x2",
                    value: Route.dashboard
                )
                SubjectRowSeparator()
                panelNavRow(
                    title: "More on AO3",
                    systemImage: "ellipsis.circle",
                    value: Route.moreOnAO3
                )
                SubjectRowSeparator()
                panelActionRow(title: "Open AO3", systemImage: "safari", action: openAO3FromAccount)
            }
            .subjectPanel()
            .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
        } header: {
            SectionRuleHeader(title: "AO3")
                .pageBodyRow(top: 18, gutter: 0)
        }
    }

    private var accountKudosSection: some View {
        Section {
            VStack(spacing: 0) {
                panelNavRow(title: "Settings", systemImage: "gearshape", value: Route.settings)
                SubjectRowSeparator()
                panelNavRow(
                    title: "Backup & Sync",
                    systemImage: "arrow.triangle.2.circlepath.icloud",
                    value: Route.backupAndSync
                )
                SubjectRowSeparator()
                panelNavRow(title: "About", systemImage: "info.circle", value: SettingsRoute.about)
            }
            .subjectPanel()
            .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
        } header: {
            SectionRuleHeader(title: "Kudos")
                .pageBodyRow(top: 18, gutter: 0)
        }
    }

    private var accountLogOutSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingLogOut = true
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accountControlCardRow()
            .logOutConfirmation(isPresented: $confirmingLogOut) {
                Task { await auth.logout() }
            }
        }
    }

    private func refreshAccountSheet() async {
        guard auth.isLoggedIn else { return }
        if let profileModel { await profileModel.refresh(auth: auth) }
        await inboxModel.refresh(auth: auth)
    }

    private func dismissAccount() {
        router.isPresentingAccount = false
        dismiss()
    }

    private func openAO3FromAccount() {
        router.openWebsiteAfterDismissingAccount()
    }

    private func openLibraryAO3(_ route: LibraryAO3Route) {
        router.pendingLibraryAO3Route = route
        router.selection = .library
        dismissAccount()
    }

    private var profileEditURL: URL? {
        AccountExternalNavCard.userURL(suffix: "profile/edit", username: auth.username)
    }

    private func openAccountRoute(_ route: AccountSheetRoute) {
        switch route {
        case .dashboard: path.append(Route.dashboard)
        case .profile: openOwnProfile()
        case .inbox: path.append(Route.inbox)
        case .preferences: path.append(Route.preferences)
        case .moreOnAO3: path.append(Route.moreOnAO3)
        case .openAO3: openAO3FromAccount()
        case .settings: path.append(Route.settings)
        case .backup: path.append(Route.backupAndSync)
        case .about: path.append(SettingsRoute.about)
        }
    }

    private func openOwnProfile() {
        guard let route = profileModel?.route
            ?? auth.username.flatMap({ AO3AuthorRoute(username: $0) }) else { return }
        path.append(route)
    }

    // MARK: Primary segments

    /// The whole hub, in one list.
    ///
    /// This used to be four scopes behind a segmented control. Once every scope
    /// row opened its own screen the scopes were pure menus, and a control that
    /// swapped between four menus was a level of navigation that existed only to
    /// reach navigation. Flattened, per the owner: shortcuts, the three scopes in
    /// order, then the account's own two pages.
    ///
    /// 1m and 1bt draw the pills, so this is a deliberate departure from them —
    /// recorded here rather than left for someone to "fix" back.
    ///
    /// One group per scope, named for the scope — per the owner.
    ///
    /// Flattening took the segmented control away, and with it the only thing
    /// saying which scope a group belonged to: "Saved", "Following", "Posted"
    /// and the rest read as peers of one another, and of "Account". Putting the
    /// scope name back as a *second* tier of heading only made ten headings on
    /// one page compete instead of nest, so the scope name is now the group's
    /// own heading and 1bt's inner split is dropped.
    @ViewBuilder
    private var tabSections: some View {
        shortcutsSection
        readingScopeGroups
        writingScopeGroups
        activityScopeGroups
        accountGroupSection
    }

    // MARK: Overview — identity hub

    /// Three icon cards per row. On a **compact** width (iPhone) that drops to two
    /// at accessibility Dynamic Type sizes, so the tile labels reflow instead of
    /// being crushed by `minimumScaleFactor` (mirrors
    /// `WorkDetailOverviewSections.quickActionColumns`' 3→2 idiom). A **regular**
    /// width (iPad, macOS) keeps all three even at those sizes — it has the room,
    /// and dropping a column there just leaves two over-wide tiles and wasted space
    /// (owner-reported).
    private var shortcutGridColumns: [GridItem] {
        let isCramped = dynamicTypeSize.isAccessibilitySize && horizontalSizeClass == .compact
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: isCramped ? 2 : 3)
    }

    /// The Shortcuts grid: whatever the reader has chosen, in their order.
    ///
    /// Every tile opens its destination directly. They used to select a scope —
    /// "Subscriptions lands on Reading" — which is meaningless now that the page
    /// has no scopes to land on.
    @ViewBuilder
    private var shortcutsSection: some View {
        let shortcuts = AccountShortcutStore.decode(shortcutsRaw)
        if !shortcuts.isEmpty {
            Section {
                LazyVGrid(columns: shortcutGridColumns, spacing: 10) {
                    ForEach(shortcuts) { shortcut in
                        shortcutGridButton(
                            title: shortcut.title,
                            systemImage: shortcut.systemImage,
                            count: shortcut.countKind.flatMap { cachedCount($0) }
                        ) {
                            openShortcut(shortcut)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(
                    top: 6,
                    leading: CardListMetrics.sideMargin,
                    bottom: 6,
                    trailing: CardListMetrics.sideMargin
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                SectionRuleHeader(title: "Shortcuts", onSeeAll: { editingShortcuts = true })
                    .pageBodyRow(top: 18, gutter: 0)
            }
        }
    }

    private func openShortcut(_ shortcut: AccountShortcut) {
        switch shortcut {
        case .dashboard: path.append(Route.dashboard)
        case .markedForLater: path.append(AO3AccountWorksList.Kind.markedForLater)
        case .bookmarks: path.append(AO3AccountWorksList.Kind.bookmarks)
        case .collections: path.append(Route.myCollections)
        case .subscriptions: path.append(AO3AccountWorksList.Kind.subscriptions)
        case .works: path.append(Route.myWorks)
        case .series: path.append(Route.mySeries)
        case .drafts: path.append(Route.drafts)
        case .history: path.append(AO3AccountWorksList.Kind.history)
        case .inbox: path.append(Route.inbox)
        case .preferences: path.append(Route.preferences)
        case .moreOnAO3: path.append(Route.moreOnAO3)
        }
    }

    /// The page's last group, per the owner's ordering: the two AO3 pages that
    /// belong to the account rather than to reading, writing or activity.
    private var accountGroupSection: some View {
        Section {
            VStack(spacing: 0) {
                panelNavRow(
                    title: "Preferences",
                    systemImage: "slider.horizontal.3",
                    value: Route.preferences
                )
                SubjectRowSeparator()
                panelNavRow(
                    title: "More on AO3",
                    systemImage: "ellipsis.circle",
                    value: Route.moreOnAO3
                )
            }
            .subjectPanel()
            .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
        } header: {
            SectionRuleHeader(title: "Account")
                .pageBodyRow(top: 18, gutter: 0)
        }
    }

    // MARK: Reading — Marked for Later | Bookmarks | Collections | Subscriptions

    // MARK: Activity — History | Inbox

    // MARK: Shared profile content

    @ViewBuilder
    private func profileContentSections(
        profileTab: AO3AuthorProfileTab,
        sectionTitle: String,
        layout: AccountWorksLayout = .list
    ) -> some View {
        if let model = profileModel {
            switch model.headerPhase {
            case .idle, .loading:
                if layout == .list {
                    Section(sectionTitle) { AO3AuthorLoadingRows() }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .accentFill()
                }
            case .unavailable:
                profileMessage(
                    title: "Profile unavailable",
                    systemImage: "person.slash",
                    message: "AO3 could not load your profile. It may be temporarily unavailable.",
                    layout: layout
                )
            case let .failed(message):
                profileMessage(
                    title: "Couldn't load your profile",
                    systemImage: "exclamationmark.triangle",
                    message: message,
                    layout: layout,
                    actionTitle: "Try Again",
                    action: { model.retry(auth: auth) }
                )
            case .loaded:
                if model.isShowingStaleCache {
                    if layout == .list {
                        Section {
                            Label("Showing cached AO3 data", systemImage: "wifi.slash")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .cardRow()
                        }
                    } else {
                        Label("Showing cached AO3 data", systemImage: "wifi.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, CardListMetrics.sideMargin)
                    }
                }
                if profileTab == .works {
                    AO3AuthorWorksScopeSection(model: model, layout: layout, showsScopes: true)
                    AO3AuthorFandomFilterSection(model: model, layout: layout)
                    AO3AuthorWorksSection(
                        model: model,
                        expandAll: expandAll,
                        layout: layout,
                        filters: filters
                    )
                } else {
                    AO3AuthorBookmarksSection(
                        model: model,
                        expandAll: expandAll,
                        layout: layout
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func profileMessage(
        title: String,
        systemImage: String,
        message: String,
        layout: AccountWorksLayout,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        let row = AO3ProfileMessageRow(
            title: title,
            systemImage: systemImage,
            message: message,
            actionTitle: actionTitle,
            action: action
        )
        if layout == .list {
            Section { row.cardRow() }
        } else {
            row.padding(.horizontal, CardListMetrics.sideMargin)
        }
    }

    // MARK: Nav helpers

    private func shortcutGridButton(
        title: String,
        systemImage: String,
        count: String? = nil,
        opensExternally: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AccountShortcutGridTile(
                title: title,
                systemImage: systemImage,
                count: count,
                opensExternally: opensExternally
            )
        }
        .buttonStyle(.plain)
        .disabled(opensExternally && auth.username == nil)
    }

    /// A row *inside* a `subjectPanel`, as 1m's Account group draws them — the
    /// panel owns the background, so the row only owns its own padding.
    private func panelNavRow(
        title: String, systemImage: String, count: String? = nil, value: some Hashable
    ) -> some View {
        Button {
            path.append(value)
        } label: {
            AccountNavCardLabel(title: title, systemImage: systemImage, count: count)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }

    private func panelActionRow(
        title: String, systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AccountNavCardLabel(title: title, systemImage: systemImage)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }

    private func navCard(
        title: String, systemImage: String, count: String?, value: some Hashable
    ) -> some View {
        Button {
            path.append(value)
        } label: {
            AccountNavCardLabel(title: title, systemImage: systemImage, count: count)
        }
        .buttonStyle(.plain)
        .accountControlCardRow()
    }

}

/// A small bridge to the two existing settings pages named by the Account row.
/// It introduces no settings or storage of its own.
private struct AccountBackupSyncView: View {
    var body: some View {
        List {
            NavigationLink(value: SettingsRoute.backup) {
                Label("Backup", systemImage: "externaldrive")
            }
            NavigationLink(value: SettingsRoute.syncFolder) {
                Label("Sync Folder", systemImage: "folder.badge.gearshape")
            }
        }
        .navigationTitle("Backup & Sync")
    }
}

private extension AccountView {
    /// `.toolbar { }` has both a `ViewBuilder` and a `ToolbarContentBuilder`
    /// overload, and picks the former for a bare property. Naming this one
    /// `some ToolbarContent` leaves only one overload that can accept it.
    @ToolbarContentBuilder
    var accountToolbarContent: some ToolbarContent { accountToolbar }

    var accountToolbar: AccountToolbarContent {
        AccountToolbarContent(
            isInboxVisible: isInboxVisible,
            model: inboxModel,
            showingInboxFilters: $showingInboxFilters,
            isWorksVisible: selectedTab == .writing && writingTab == .works,
            showingWorksFilter: $showingFilters,
            showsMatureRevealControl: showsMatureRevealControl
        )
    }

    /// 1m's chrome: glass circles over the wash, in an overlay rather than a
    /// `safeAreaInset`, so they take no height from the page. They land on the
    /// identity row's trailing edge, where the artboard draws its own circle.
    ///
    /// 44pt, not the artboard's 34. A drawn number is not a source, and this one
    /// is below the minimum tap target — it also made the button visibly smaller
    /// than the toolbar item it replaced, which is how the shortfall showed up.
    var floatingChromeRow: some View {
        HStack(spacing: 9) {
            ForEach(Array(accountToolbar.actionItems.enumerated()), id: \.offset) { _, item in
                item
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    /// Artboard 1n's "What is waiting".
    ///
    /// A preview of the signed-in tab rather than a description of it: the real
    /// scope headings and the real destination rows, with every value withheld,
    /// faded out at the bottom. Built from `scopeDestinationRow` — the same row
    /// the hub itself draws — and from the same row orders (`readingRowOrder`
    /// and its siblings), titles and symbols, so it cannot drift from the thing
    /// it previews; inert because there is nothing behind it to open yet.
    /// The preview's own opening row: what `signedOutCard` looks like once an
    /// account fills it in, faded the same way every row under it is. Avatar
    /// and name only — no bio, no join date — because this is a glimpse of the
    /// *shape*, and the one identity statement already made by `signedOutCard`
    /// above this section should not be repeated with real-looking values that
    /// aren't real.
    private var identitySkeletonRow: some View {
        HStack(spacing: 13) {
            AO3AuthorAvatar(url: nil, name: "AO3 account", size: 44, isCircular: true)
            Text("Your username")
                .font(.system(size: skeletonUsernameSize, weight: .bold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    var signedOutPreviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                Text("When you sign in, this tab shows your AO3 account and activity.")
                    .font(.system(size: previewNoticeSize))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 14)

                identitySkeletonRow
                    .padding(.bottom, 16)

                previewGroup("Reading", Self.readingRowOrder.map { ($0.rawValue, $0.systemImage) })
                previewGroup("Writing", Self.writingRowOrder.map { ($0.rawValue, $0.systemImage) })
                previewGroup("Activity", Self.activityRowOrder.map { ($0.rawValue, $0.systemImage) })
            }
            .allowsHitTesting(false)
            // The spec fades the preview out rather than ending it on a hard
            // edge — it is a glimpse of the tab, not a list to read to the end.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.62),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "What is waiting. Signing in fills this tab with your reading, writing and activity."
            )
            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
        } header: {
            SectionRuleHeader(title: "What is waiting")
                .pageBodyRow(top: 22, gutter: 0)
        }
    }

    /// One previewed scope: its heading, then its rows with no counts and no
    /// selection, because signed out there is no figure to state and nothing is
    /// chosen.
    func previewGroup(_ title: String, _ rows: [(title: String, systemImage: String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SubjectFieldLabel(text: title, style: .formGroup)
                .padding(.bottom, 7)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { SubjectRowSeparator() }
                    scopeDestinationRow(
                        AccountScopeDestination(
                            id: row.title,
                            title: row.title,
                            systemImage: row.systemImage,
                            open: {}
                        )
                    )
                }
            }
            .subjectPanel()
            .padding(.bottom, 16)
        }
    }

    private func cachedCount(_ kind: AO3AccountListKind) -> String? {
        AO3AccountListCountsCache.shared.count(
            for: kind,
            authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        )?.displayText
    }

    private var inboxMetadataTaskID: String {
        let scope = AO3AuthorProfileFetcher.authenticationScope(for: auth)
        let ids = inboxModel.items.compactMap(\.workID).map(String.init).joined(separator: ",")
        // Includes `sessionGeneration` so a same-username logout/login restarts
        // enrichment instead of silently no-op'ing against the new session
        // (its `scope` string alone would be unchanged; see T91-RF3).
        return "\(scope)#\(auth.sessionGeneration)|\(inboxModel.metadataRevision)|\(ids)"
    }

    private func enrichVisibleInboxWorkContexts() async {
        guard case .loaded = inboxModel.phase else { return }
        let items = inboxModel.items
        var seeds: [Int: AO3CommentsWorkContext] = [:]
        for item in items {
            guard let workID = item.workID else { continue }
            seeds[workID] = knownWorkContext(for: item)
        }
        await inboxModel.enrichVisibleWorkContexts(
            workIDs: items.compactMap(\.workID),
            seededContexts: seeds,
            auth: auth
        )
    }

    private func openInboxItem(_ item: AO3InboxItem) {
        openInboxItem(item, focus: .parentOrSelf)
    }

    private func openInboxChapter(_ item: AO3InboxItem) {
        openInboxItem(item, focus: .chapter)
    }

    private func openInboxReply(_ item: AO3InboxItem) {
        openInboxItem(item, focus: .parentOrSelf, opensReplyComposer: true)
    }

    private func openInboxItem(
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

    /// Local/profile metadata paints immediately; the Inbox model then fills any
    /// missing canonical fields sequentially for distinct works on this page.
    private func knownWorkContext(for item: AO3InboxItem) -> AO3CommentsWorkContext {
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

// MARK: - Scope groups (artboard 1bt)

private extension AccountView {
    @ViewBuilder
    var readingScopeGroups: some View {
        // 1bt splits these into "Saved" and "Following"; flattened to one group
        // named for the scope, with the board's own order kept — the three saved
        // shelves first, then the followed one.
        //
        // Subscriptions still states only its list size:
        // `SubscriptionWatermarks.newChapterCount(for:watermarks:)` needs loaded
        // subscription works, and AO3AccountListCountsCache holds sizes only, so
        // "N with new chapters" cannot be had without loading them.
        scopeGroup("Reading", Self.readingRowOrder.map { tab -> AccountScopeDestination in
            switch tab {
            case .later: return readingDestination(.later, count: .markedForLater)
            case .bookmarks: return readingDestination(.bookmarks, count: .bookmarks)
            case .collections: return readingDestination(.collections, count: .collections)
            case .subscriptions: return readingDestination(.subscriptions, count: .subscriptions)
            }
        })
    }

    @ViewBuilder
    var writingScopeGroups: some View {
        // Was "Posted" / "Unposted". Flattened; Drafts keeps the subtitle that
        // carried the distinction, so nothing the split said is lost —
        // otwarchive's work_drafts.feature keeps 29-day drafts and purges 31-day
        // ones, and WritingDraftsView records the same 30-day rule.
        scopeGroup("Writing", Self.writingRowOrder.map { tab -> AccountScopeDestination in
            switch tab {
            case .works: return writingDestination(.works, count: .myWorks)
            case .series: return writingDestination(.series, count: .series)
            case .drafts: return writingDestination(.drafts, count: nil, subtitle: "Deleted by AO3 after 30 days")
            }
        })
    }

    @ViewBuilder
    var activityScopeGroups: some View {
        // Was "Read on AO3" / "Arrives". Both rows keep the subtitles that said
        // which was which, so the flattening costs no meaning.
        scopeGroup("Activity", Self.activityRowOrder.map { tab -> AccountScopeDestination in
            switch tab {
            case .history:
                return activityDestination(
                    .history, count: .history, subtitle: "Your AO3 history, not your reading activity in Kudos"
                )
            case .inbox:
                return activityDestination(
                    .inbox,
                    count: nil,
                    subtitle: inboxModel.unreadCount.map { "\($0) unread" }
                )
            }
        })
    }

    /// One destination inside a scope.
    ///
    /// One row in a scope group, which **opens its own screen**.
    ///
    /// This used to select an inline section instead, on the reasoning that
    /// pushing "would put an extra screen between the reader and their own
    /// bookmarks". That was wrong on the spec's own evidence: 1o and 1q open with
    /// a 34pt glass circle at the left of their chrome row — a back button, which
    /// a tab root does not have — and each carries its own kicker, rule and
    /// title. They are pushed screens. 1bt confirms it from the other side: after
    /// its last group it draws the tab bar, with no inline list anywhere on it.
    struct AccountScopeDestination: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        var subtitle: String?
        var count: String?
        let open: () -> Void
    }

    private func scopeGroup(_ title: String, _ destinations: [AccountScopeDestination]) -> some View {
        // 1m: counts sit on the rows, not on the group label.
        AccountScopeGroup(
            title: title,
            count: nil,
            layout: .list
        ) {
            VStack(spacing: 0) {
                ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                    if index > 0 { SubjectRowSeparator() }
                    scopeDestinationRow(destination)
                }
            }
        }
    }

    // Each group owns its AppStorage so List/ScrollView remounts and scope
    // switches share the same preference without growing AccountView's body.
    struct AccountScopeGroup<Content: View>: View {
        let title: String
        let count: Int?
        let layout: AccountWorksLayout
        let content: Content
        @AppStorage private var isCollapsed: Bool

        init(title: String, count: Int?, layout: AccountWorksLayout, @ViewBuilder content: () -> Content) {
            self.title = title
            self.count = count
            self.layout = layout
            self.content = content()
            _isCollapsed = AppStorage(wrappedValue: false, "account.scopeGroup.\(title).isCollapsed")
        }

        var body: some View {
            if layout == .list {
                Section {
                    if !isCollapsed {
                        content.subjectPanel()
                            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                    }
                } header: {
                    header.pageBodyRow(top: 18, gutter: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    if !isCollapsed {
                        content.subjectPanel()
                            .padding(.horizontal, SubjectMetrics.accountGutter)
                    }
                }
                .padding(.top, 18)
            }
        }

        private var header: some View {
            SectionRuleHeader(
                title: title,
                count: count,
                isCollapsed: isCollapsed,
                onToggleCollapse: { isCollapsed.toggle() }
            )
        }
    }

    private func scopeDestinationRow(_ destination: AccountScopeDestination) -> some View {
        Button(action: destination.open) {
            HStack(spacing: 12) {
                AccountIconSquare(systemImage: destination.systemImage)

                VStack(alignment: .leading, spacing: 2) {
                    // 1m/1bt: 15px medium, the same as the Preferences cards.
                    Text(destination.title)
                        .font(.system(size: scopeRowTitleSize, weight: .medium))
                        .foregroundStyle(.primary)
                    if let subtitle = destination.subtitle {
                        Text(subtitle)
                            .font(.system(size: scopeRowSubtitleSize))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let count = destination.count {
                    // The cache renders a lower bound as "100+" when AO3 paginated
                    // the list rather than printing a total, which is why the
                    // artboard shows exactly that against Collections.
                    Text(count)
                        .font(.system(size: scopeRowCountSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func readingDestination(
        _ tab: AccountReadingTab, count: AO3AccountListKind?, subtitle: String? = nil
    ) -> AccountScopeDestination {
        AccountScopeDestination(
            id: tab.rawValue,
            title: tab.rawValue,
            systemImage: tab.systemImage,
            subtitle: subtitle,
            count: count.flatMap { cachedCount($0) },
            open: { openReading(tab) }
        )
    }

    /// 1o, 1q, 1r and 1p. `AO3AccountWorksList` already *was* each of these
    /// screens — header block, wash, ledger rows — but the only way to reach it
    /// was a "Refine" action buried under the inline list it duplicated.
    private func openReading(_ tab: AccountReadingTab) {
        switch tab {
        case .later: path.append(AO3AccountWorksList.Kind.markedForLater)
        case .bookmarks: path.append(AO3AccountWorksList.Kind.bookmarks)
        case .subscriptions: path.append(AO3AccountWorksList.Kind.subscriptions)
        case .collections: path.append(Route.myCollections)
        }
    }

    private func writingDestination(
        _ tab: AccountWritingTab, count: AO3AccountListKind?, subtitle: String? = nil
    ) -> AccountScopeDestination {
        AccountScopeDestination(
            id: tab.rawValue,
            title: tab.rawValue,
            systemImage: tab.systemImage,
            subtitle: subtitle,
            count: count.flatMap { cachedCount($0) },
            open: { openWriting(tab) }
        )
    }

    /// Drafts is 1x, and `WritingDraftsView` already is that screen. Works and
    /// Series still select their inline section: 1u and 1w have no pushed screen
    /// yet, and a row that opens nothing is worse than one that is inconsistent.
    private func openWriting(_ tab: AccountWritingTab) {
        switch tab {
        case .works: path.append(Route.myWorks)
        case .series: path.append(Route.mySeries)
        case .drafts: path.append(Route.drafts)
        }
    }

    private func activityDestination(
        _ tab: AccountActivityTab, count: AO3AccountListKind?, subtitle: String? = nil
    ) -> AccountScopeDestination {
        AccountScopeDestination(
            id: tab.rawValue,
            title: tab.rawValue,
            systemImage: tab.systemImage,
            subtitle: subtitle,
            count: count.flatMap { cachedCount($0) },
            open: { openActivity(tab) }
        )
    }

    /// History is 1t, which `AO3AccountWorksList` already draws. Inbox still
    /// selects until 1l has a screen of its own.
    private func openActivity(_ tab: AccountActivityTab) {
        switch tab {
        case .history: path.append(AO3AccountWorksList.Kind.history)
        case .inbox: path.append(Route.inbox)
        }
    }
}
