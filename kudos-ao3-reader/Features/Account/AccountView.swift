import SwiftData
import SwiftUI

/// The Account tab: signed-in user's native AO3 profile hub with
/// Overview / Reading / Writing / Activity.
///
/// - **Overview** — AO3 dashboard shortcuts, Preferences, More on AO3
/// - **Reading** — Later / Subscriptions / Bookmarks / Collections
/// - **Writing** — Works / Series / Drafts (drafts open AO3 for now)
/// - **Activity** — History / Inbox
///
/// App settings stay behind the toolbar gear.
struct AccountView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Query private var localWorks: [SavedWork]

    @State private var path = NavigationPath()
    @State private var showingLogin = false
    @State private var selectedTab: AccountTab = .overview
    @State private var readingTab: AccountReadingTab = .later
    @State private var writingTab: AccountWritingTab = .works
    @State private var activityTab: AccountActivityTab = .history
    /// The signed-in user's own profile content (Works / Series / Bookmarks).
    @State private var profileModel: AO3AuthorProfileModel?
    /// Activity › Inbox feed state.
    @State private var inboxModel = AO3InboxModel()
    @State private var showingInboxFilters = false
    @State private var expandAll = false
    /// Detailed list rows vs compact two-up cover cards — shared across Account
    /// work lists (Reading / Writing / Activity) and persisted like Home/Library.
    @AppStorage("account.displayMode") private var displayMode: WorkListDisplayMode = .compact
    @AppStorage("hideMatureContent") private var hideMature = true
    @State private var postingPseudName: String?
    /// Bumped by pull-to-refresh on list-style Reading/Activity segments.
    @State private var listReloadToken = 0
    /// Supplied by the child list that is currently on screen. This must never
    /// use the library-wide query: an unrelated adult work must not enable an
    /// inert Mature-reveal button on another Account list.
    @State private var currentListHasAdultContent = false
    @State private var adultContentScope: String?

    enum Route: Hashable {
        case myCollections
        case preferences
        case moreOnAO3
        case settings
        /// Native AO3 own-user dashboard (sidebar destinations).
        case dashboard
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

    /// Compact work lists use Library/Home's root `ScrollView` + `NavigationLink`
    /// pattern. Stacking many links inside one List row breaks tap targets.
    private var usesLibraryStyleCompactLayout: Bool {
        auth.isLoggedIn && displayMode == .compact && showsWorkListControls
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if usesLibraryStyleCompactLayout {
                    libraryStyleCompactRoot
                } else {
                    standardListRoot
                }
            }
            .navigationTitle("Account")
            #if os(iOS)
                .toolbarTitleDisplayMode(.inlineLarge)
            #endif
                .navigationDestination(for: Route.self, destination: destination)
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .privacy: PrivacyDataView()
                    }
                }
                .navigationDestination(for: AO3AccountWorksList.Kind.self) { AO3AccountWorksList(kind: $0) }
                .navigationDestination(for: SavedWork.self) { WorkDetailView(work: $0) }
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
                        onResolveWorkContext: { inboxModel.cacheWorkContext($0, for: destination, auth: auth) }
                    )
                }
                .ao3AuthorNavigation(path: $path, tab: .account)
                .toolbar {
                    AccountToolbarContent(
                        isInboxVisible: isInboxVisible,
                        model: inboxModel,
                        showingInboxFilters: $showingInboxFilters,
                        showsMatureRevealControl: showsMatureRevealControl,
                        showsWorkListControls: showsWorkListControls,
                        displayMode: $displayMode,
                        expandAll: $expandAll
                    )
                }
                .sheet(isPresented: $showingLogin) { AO3LoginView() }
                .sheet(isPresented: $showingInboxFilters) {
                    AccountInboxFilterSheet(model: inboxModel)
                }
                .alert("Couldn't update Inbox", isPresented: showingInboxActionError) {
                    Button("OK") { inboxModel.clearActionError() }
                } message: {
                    Text(inboxModel.actionError ?? "AO3 couldn't update your Inbox.")
                }
                .task(id: activationKey) { activateVisibleContent() }
                .onChange(of: auth.username, initial: true) { _, username in
                    syncProfileModel(username: username)
                }
                .onChange(of: auth.sessionGeneration, initial: true) { _, _ in
                    // Reset a hidden Inbox immediately on logout/session replacement,
                    // but do not fetch it until Activity › Inbox is visibly opened.
                    inboxModel.syncAuthenticationContext(auth: auth)
                }
                .onChange(of: activityTab) { _, tab in
                    if tab != .inbox { inboxModel.endSelection() }
                }
        }
    }

    private var standardListRoot: some View {
        List {
            profileCardSection

            if auth.isLoggedIn {
                tabPickerSection
                tabSections
            }
        }
        .cardList()
        .refreshable { await refreshCurrentTab() }
    }

    /// Matches LibrarySectionListView compact: `ScrollView` + two-up `NavigationLink` cards.
    private var libraryStyleCompactRoot: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AccountControlMetrics.compactSpacing) {
                AccountScrollChromeCard {
                    AccountProfileCard(
                        profileModel: profileModel,
                        postingPseudName: $postingPseudName,
                        onViewProfile: openOwnProfile,
                        onLogin: { showingLogin = true }
                    )
                }

                if let notice = auth.noticeMessage {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, CardListMetrics.sideMargin)
                }

                // Same card chrome as detailed List `tabPickerSection` + `.cardRow()`.
                AccountScrollChromeCard {
                    Picker("Account Content", selection: $selectedTab) {
                        ForEach(AccountTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                compactOverviewLink
                compactScopeChrome
                compactWorksContent
            }
            .padding(.vertical, 12)
        }
        .background(theme.appTheme.cardBackdrop.ignoresSafeArea())
        .refreshable { await refreshCurrentTab() }
    }

    private var compactOverviewLink: some View {
        AccountScrollChromeCard {
            Button {
                selectedTab = .overview
            } label: {
                HStack(spacing: 10) {
                    Label("Overview", systemImage: "square.grid.2x2")
                    Spacer()
                    Text("Shortcuts & Preferences")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows Account shortcuts and preferences")
        }
    }

    @ViewBuilder
    private var compactScopeChrome: some View {
        // Same card chrome as detailed List `.cardRow()` so Show / Works lines up.
        switch selectedTab {
        case .reading:
            AccountScrollChromeCard {
                AccountScopeMenu(
                    prompt: "Show",
                    systemImage: \.systemImage,
                    selection: $readingTab
                )
            }
        case .writing:
            AccountScrollChromeCard {
                AccountScopeMenu(
                    prompt: "Show",
                    systemImage: \.systemImage,
                    selection: $writingTab
                )
            }
        case .activity:
            AccountScrollChromeCard {
                AccountScopeMenu(
                    prompt: "Show",
                    systemImage: \.systemImage,
                    selection: $activityTab
                )
            }
        case .overview:
            EmptyView()
        }
    }

    @ViewBuilder
    private var compactWorksContent: some View {
        switch selectedTab {
        case .reading:
            switch readingTab {
            case .later:
                AccountWorksInlineSection(
                    kind: .markedForLater,
                    expandAll: expandAll,
                    displayMode: .compact,
                    layout: .scroll,
                    reloadToken: listReloadToken,
                    onAdultContentVisibilityChange: adultContentVisibilityHandler(
                        for: matureContentScope
                    ),
                    onRefine: { path.append(AO3AccountWorksList.Kind.markedForLater) }
                )
            case .subscriptions:
                AccountWorksInlineSection(
                    kind: .subscriptions,
                    expandAll: expandAll,
                    displayMode: .compact,
                    layout: .scroll,
                    reloadToken: listReloadToken,
                    onAdultContentVisibilityChange: adultContentVisibilityHandler(
                        for: matureContentScope
                    ),
                    onRefine: { path.append(AO3AccountWorksList.Kind.subscriptions) }
                )
            case .bookmarks:
                profileContentSections(
                    profileTab: .bookmarks,
                    sectionTitle: "Bookmarks",
                    layout: .scroll
                )
            case .collections:
                EmptyView()
            }
        case .writing:
            if writingTab == .works {
                profileContentSections(
                    profileTab: .works,
                    sectionTitle: "Works",
                    layout: .scroll,
                    onAdultContentVisibilityChange: adultContentVisibilityHandler(
                        for: matureContentScope
                    )
                )
            }
        case .activity:
            if activityTab == .history {
                AccountWorksInlineSection(
                    kind: .history,
                    expandAll: expandAll,
                    displayMode: .compact,
                    layout: .scroll,
                    reloadToken: listReloadToken,
                    onAdultContentVisibilityChange: adultContentVisibilityHandler(
                        for: matureContentScope
                    ),
                    onRefine: { path.append(AO3AccountWorksList.Kind.history) }
                )
            }
        case .overview:
            EmptyView()
        }
    }

    // MARK: Activation

    private var activationKey: String {
        [
            auth.username ?? "",
            String(auth.sessionGeneration),
            String(router.selection == .account),
            selectedTab.rawValue,
            readingTab.rawValue,
            writingTab.rawValue,
            activityTab.rawValue
        ].joined(separator: "|")
    }

    private func activateVisibleContent() {
        guard router.selection == .account, auth.isLoggedIn else { return }
        switch selectedTab {
        case .overview:
            // Profile header only — do not prefetch Inbox here (that would hit
            // AO3 on every Account open for a badge the user may never use).
            profileModel?.activate(auth: auth)
        case .reading:
            switch readingTab {
            case .bookmarks:
                syncProfileTab(.bookmarks)
            case .later, .subscriptions, .collections:
                profileModel?.activate(auth: auth)
            }
        case .writing:
            switch writingTab {
            case .works:
                syncProfileTab(.works)
            case .series:
                syncProfileTab(.series)
            case .drafts:
                profileModel?.activate(auth: auth)
            }
        case .activity:
            profileModel?.activate(auth: auth)
            if activityTab == .inbox {
                inboxModel.activate(auth: auth)
            }
        }
    }

    private func syncProfileModel(username: String?) {
        if let username, let route = AO3AuthorRoute(username: username) {
            if profileModel?.route.username.localizedCaseInsensitiveCompare(username) != .orderedSame {
                profileModel = AO3AuthorProfileModel(route: route)
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

    private func refreshCurrentTab() async {
        guard auth.isLoggedIn else { return }
        switch selectedTab {
        case .overview:
            if let model = profileModel { await model.refresh(auth: auth) }
        case .reading:
            switch readingTab {
            case .bookmarks:
                if let model = profileModel { await model.refresh(auth: auth) }
            case .later, .subscriptions:
                listReloadToken += 1
            case .collections:
                // Collections is a push-only card (full list is `AO3CollectionsList`);
                // nothing inline observes `listReloadToken`.
                break
            }
        case .writing:
            switch writingTab {
            case .works, .series:
                if let model = profileModel { await model.refresh(auth: auth) }
            case .drafts:
                break
            }
        case .activity:
            switch activityTab {
            case .history:
                listReloadToken += 1
            case .inbox:
                await inboxModel.refresh(auth: auth)
            }
        }
    }

    // MARK: Destinations & toolbar

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .myCollections: AO3CollectionsList()
        case .preferences: AO3PreferencesView()
        case .moreOnAO3: AccountMoreOnAO3View()
        case .settings: ReaderOptionsForm(includeAppSettings: true).navigationTitle("Settings")
        case .dashboard: AO3DashboardView()
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

    /// Work-list chrome (Detailed/Compact + Expand) for Account segments that
    /// show work cards. Series / Drafts / Inbox / Overview skip it.
    private var showsWorkListControls: Bool {
        guard auth.isLoggedIn else { return false }
        switch selectedTab {
        case .overview:
            return false
        case .writing:
            return writingTab == .works
        case .reading:
            return readingTab == .later
                || readingTab == .subscriptions
                || readingTab == .bookmarks
        case .activity:
            return activityTab == .history
        }
    }

    /// Eye toggle when Hide Mature is on and the library has adult works that
    /// can appear in the currently rendered Account list.
    private var showsMatureRevealControl: Bool {
        showsWorkListControls
            && adultContentScope == matureContentScope
            && PrivacyGate.shouldShowMatureReveal(
                hideMature: hideMature,
                hasVisibleMatureWorks: currentListHasAdultContent
            )
    }

    private var matureContentScope: String {
        [
            auth.username ?? "",
            selectedTab.rawValue,
            readingTab.rawValue,
            writingTab.rawValue,
            activityTab.rawValue
        ].joined(separator: "|")
    }

    private func adultContentVisibilityHandler(for scope: String) -> (Bool) -> Void {
        { hasAdultContent in
            guard scope == matureContentScope else { return }
            adultContentScope = scope
            currentListHasAdultContent = hasAdultContent
        }
    }

    // MARK: Profile card

    private var profileCardSection: some View {
        Section {
            AccountProfileCard(
                profileModel: profileModel,
                postingPseudName: $postingPseudName,
                onViewProfile: openOwnProfile,
                onLogin: { showingLogin = true }
            )
            .accountControlCardRow()
        } footer: {
            if let notice = auth.noticeMessage {
                Text(notice)
            }
        }
    }

    private func openOwnProfile() {
        guard let username = auth.username,
              let route = AO3AuthorRoute(username: username) else { return }
        path.append(route)
    }

    // MARK: Primary segments

    private var tabPickerSection: some View {
        Section {
            Picker("Account Content", selection: $selectedTab) {
                ForEach(AccountTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accountControlCardRow()
        }
    }

    @ViewBuilder
    private var tabSections: some View {
        switch selectedTab {
        case .overview:
            overviewSections
        case .reading:
            readingSections
        case .writing:
            writingSections
        case .activity:
            activitySections
        }
    }

    // MARK: Overview — identity hub

    private static let shortcutGridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    @ViewBuilder
    private var overviewSections: some View {
        Section {
            // 3×2 of individual icon cards (not one shared panel).
            LazyVGrid(columns: Self.shortcutGridColumns, spacing: 10) {
                shortcutGridButton(
                    title: "My Dashboard",
                    systemImage: "square.grid.2x2"
                ) {
                    path.append(Route.dashboard)
                }
                shortcutGridButton(
                    title: "My Subscriptions",
                    systemImage: "bell",
                    count: cachedCount(.subscriptions)
                ) {
                    readingTab = .subscriptions
                    selectedTab = .reading
                }
                shortcutGridButton(
                    title: "My Works",
                    systemImage: "doc.text",
                    count: cachedCount(.myWorks)
                ) {
                    writingTab = .works
                    selectedTab = .writing
                }
                shortcutGridButton(
                    title: "My Bookmarks",
                    systemImage: "bookmark",
                    count: cachedCount(.bookmarks)
                ) {
                    readingTab = .bookmarks
                    selectedTab = .reading
                }
                shortcutGridButton(
                    title: "My Collections",
                    systemImage: "square.stack",
                    count: cachedCount(.collections)
                ) {
                    path.append(Route.myCollections)
                }
                shortcutGridButton(
                    title: "My History",
                    systemImage: "clock",
                    count: cachedCount(.history)
                ) {
                    activityTab = .history
                    selectedTab = .activity
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
            Text("Shortcuts")
        }

        Section {
            navCard(
                title: "Preferences",
                systemImage: "slider.horizontal.3",
                count: nil,
                value: Route.preferences
            )
            navCard(
                title: "More on AO3",
                systemImage: "ellipsis.circle",
                count: nil,
                value: Route.moreOnAO3
            )
        } header: {
            Text("Account")
        }
    }

    // MARK: Reading — Later | Subscriptions | Bookmarks | Collections

    @ViewBuilder
    private var readingSections: some View {
        Section {
            AccountScopeMenu(
                prompt: "Show",
                systemImage: \.systemImage,
                selection: $readingTab
            )
            .accountControlCardRow()
        }

        switch readingTab {
        case .later:
            AccountWorksInlineSection(
                kind: .markedForLater,
                expandAll: expandAll,
                displayMode: displayMode,
                reloadToken: listReloadToken,
                onAdultContentVisibilityChange: adultContentVisibilityHandler(
                    for: matureContentScope
                ),
                onRefine: { path.append(AO3AccountWorksList.Kind.markedForLater) }
            )
        case .subscriptions:
            AccountWorksInlineSection(
                kind: .subscriptions,
                expandAll: expandAll,
                displayMode: displayMode,
                reloadToken: listReloadToken,
                onAdultContentVisibilityChange: adultContentVisibilityHandler(
                    for: matureContentScope
                ),
                onRefine: { path.append(AO3AccountWorksList.Kind.subscriptions) }
            )
        case .bookmarks:
            profileContentSections(profileTab: .bookmarks, sectionTitle: "Bookmarks")
        case .collections:
            // Full collections browser (own List) is a pushed screen so we don't
            // nest lists inside Account's card List.
            Section {
                navCard(
                    title: "Browse Collections",
                    systemImage: "square.stack",
                    count: cachedCount(.collections),
                    value: Route.myCollections
                )
            } footer: {
                Text("Collections you create or maintain on AO3.")
            }
        }
    }

    // MARK: Writing — Works | Series | Drafts

    @ViewBuilder
    private var writingSections: some View {
        Section {
            AccountScopeMenu(
                prompt: "Show",
                systemImage: \.systemImage,
                selection: $writingTab
            )
            .accountControlCardRow()
        }

        switch writingTab {
        case .works:
            profileContentSections(
                profileTab: .works,
                sectionTitle: "Works",
                onAdultContentVisibilityChange: adultContentVisibilityHandler(
                    for: matureContentScope
                )
            )
        case .series:
            profileSeriesSections
        case .drafts:
            Section {
                externalNavCard(
                    title: "Open Drafts on AO3",
                    systemImage: "doc.badge.clock",
                    pathSuffix: "works/drafts"
                )
            } footer: {
                Text("Drafts still open on the Archive until a native editor ships.")
            }
        }
    }

    // MARK: Activity — History | Inbox

    @ViewBuilder
    private var activitySections: some View {
        Section {
            AccountScopeMenu(
                prompt: "Show",
                systemImage: \.systemImage,
                selection: $activityTab
            )
            .accountControlCardRow()
        }

        switch activityTab {
        case .history:
            AccountWorksInlineSection(
                kind: .history,
                expandAll: expandAll,
                displayMode: displayMode,
                reloadToken: listReloadToken,
                onAdultContentVisibilityChange: adultContentVisibilityHandler(
                    for: matureContentScope
                ),
                onRefine: { path.append(AO3AccountWorksList.Kind.history) }
            )
        case .inbox:
            Section {
                AccountInboxRows(
                    model: inboxModel,
                    limit: nil,
                    onOpen: openInboxItem,
                    onReply: openInboxReply,
                    onOpenChapter: openInboxChapter,
                    workContext: { knownWorkContext(for: $0) }
                )
            } header: {
                Text("Inbox")
            } footer: {
                if let total = inboxModel.totalComments {
                    let unread = inboxModel.unreadCount ?? 0
                    Text("\(total) comments in your AO3 inbox, \(unread) unread. "
                        + "Use Select to manage read state or remove notifications; "
                        + "Reply opens the native comments flow.")
                }
            }
            .task(id: inboxMetadataTaskID) { await enrichVisibleInboxWorkContexts() }
        }
    }

    // MARK: Shared profile content

    @ViewBuilder
    private func profileContentSections(
        profileTab: AO3AuthorProfileTab,
        sectionTitle: String,
        layout: AccountWorksLayout = .list,
        onAdultContentVisibilityChange: @escaping (Bool) -> Void = { _ in }
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
                    AO3AuthorFandomFilterSection(model: model, layout: layout)
                    AO3AuthorWorksSection(
                        model: model,
                        expandAll: expandAll,
                        displayMode: displayMode,
                        layout: layout,
                        onAdultContentVisibilityChange: onAdultContentVisibilityChange
                    )
                } else {
                    AO3AuthorBookmarksSection(
                        model: model,
                        expandAll: expandAll,
                        displayMode: displayMode,
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

    @ViewBuilder
    private var profileSeriesSections: some View {
        if let model = profileModel {
            switch model.headerPhase {
            case .idle, .loading:
                Section("Series") { AO3AuthorLoadingRows() }
            case .unavailable:
                Section {
                    AO3ProfileMessageRow(
                        title: "Profile unavailable",
                        systemImage: "person.slash",
                        message: "AO3 could not load your profile. It may be temporarily unavailable."
                    )
                    .cardRow()
                }
            case let .failed(message):
                Section {
                    AO3ProfileMessageRow(
                        title: "Couldn't load your profile",
                        systemImage: "exclamationmark.triangle",
                        message: message,
                        actionTitle: "Try Again",
                        action: { model.retry(auth: auth) }
                    )
                    .cardRow()
                }
            case .loaded:
                if model.isShowingStaleCache {
                    Section {
                        Label("Showing cached AO3 data", systemImage: "wifi.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .cardRow()
                    }
                }
                AO3AuthorSeriesSection(model: model)
            }
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

    private func externalNavCard(
        title: String, systemImage: String, pathSuffix: String
    ) -> some View {
        Button {
            openUserPath(pathSuffix)
        } label: {
            AccountNavCardLabel(
                title: title,
                systemImage: systemImage,
                opensExternally: true
            )
        }
        .buttonStyle(.plain)
        .disabled(auth.username == nil)
        .accountControlCardRow()
    }

    private func openUserPath(_ suffix: String) {
        guard let username = auth.username else { return }
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? username
        let path = suffix.isEmpty
            ? "/users/\(encoded)"
            : "/users/\(encoded)/\(suffix)"
        guard let url = URL(string: "https://archiveofourown.org\(path)") else { return }
        router.open(url)
    }

    private func cachedCount(_ kind: AO3AccountListKind) -> String? {
        AO3AccountListCountsCache.shared.count(
            for: kind,
            authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        )?.displayText
    }
}

private extension AccountView {
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
