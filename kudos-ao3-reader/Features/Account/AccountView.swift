import SwiftData
import SwiftUI

/// The Account tab: signed-in user's native AO3 profile hub with
/// Overview / Reading / Writing / Activity.
///
/// - **Overview** — AO3 dashboard shortcuts, Preferences, More on AO3
/// - **Reading** — Later / Subscriptions / Bookmarks / Collections
/// - **Writing** — Works / Series / Drafts (native draft forms)
/// - **Activity** — History / Inbox
///
/// App settings stay behind the toolbar gear.
struct AccountView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var localWorks: [SavedWork]

    @State private var path = NavigationPath()
    @State private var showingLogin = false
    @State private var selectedTab: AccountTab = .overview
    @State private var readingTab: AccountReadingTab = .later
    @State private var editingWorkID: Int?
    @State private var writingTab: AccountWritingTab = .works
    @State private var activityTab: AccountActivityTab = .history
    /// The signed-in user's own profile content (Works / Series / Bookmarks).
    @State private var profileModel: AO3AuthorProfileModel?
    /// Activity › Inbox feed state.
    @State private var inboxModel = AO3InboxModel()
    @State private var showingInboxFilters = false
    @State private var filters = AO3SearchFilters()
    @State private var showingFilters = false
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
        /// Artboard 1x, which `WritingDraftsView` already is.
        case drafts
        /// Artboards 1u and 1w: the signed-in user's own works and series, on
        /// the profile surface opened at that scope.
        case myWorks
        case mySeries
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
            // 1m has no navigation bar at all. Its content column starts at the
            // safe area and its chrome is a glass circle floating over the wash,
            // with the page scrolling underneath — which is the whole 44pt of
            // dead space an empty inline bar was reserving above the header.
            //
            // The bar comes back for the inbox's selection mode, and only that:
            // Select All is a `.confirmationAction`, which has nowhere to live
            // without a bar, and it is a distinct, self-contained state.
            .toolbar(inboxModel.isSelecting ? .visible : .hidden, for: .navigationBar)
                .overlay(alignment: .topTrailing) {
                    if !inboxModel.isSelecting { floatingChromeRow }
                }
                .navigationDestination(for: Route.self, destination: destination)
                .navigationDestination(item: $editingWorkID) { WritingWorkDestination(workID: $0) }
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .privacy: PrivacyDataView()
                    }
                }
                .navigationDestination(for: AO3AccountWorksList.Kind.self) {
                    AO3AccountWorksList(kind: $0)
                }
                .navigationDestination(for: AO3CollectionDestination.self) {
                    AO3CollectionDetailView(slug: $0.slug, title: $0.title)
                }
                .navigationDestination(for: AO3CollectionFormDestination.self) {
                    AO3CollectionFormView(slug: $0.slug)
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
                .toolbar { accountToolbarContent }
                .sheet(isPresented: $showingLogin) { AO3LoginView() }
                .sheet(isPresented: $showingFilters) {
                    AO3FilterPanel(
                        filters: $filters,
                        mode: .refine,
                        canReset: filters != AO3SearchFilters(),
                        onApply: { showingFilters = false },
                        onReset: {
                            filters = AO3SearchFilters()
                            showingFilters = false
                        }
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

    /// Artboard 1n: *"No session, so no accent and no wash: the tab sits on plain
    /// #0b0b0d."* The wash is derived from the account's own accent, so with no
    /// account there is nothing to derive it from — signed out is the one state
    /// where this tab is deliberately colourless.
    @ViewBuilder
    private var standardListRoot: some View {
        if auth.isLoggedIn {
            standardListBody.subjectWash(accountPalette)
        } else {
            standardListBody
        }
    }

    private var standardListBody: some View {
        List {
            profileCardSection

            if auth.isLoggedIn {
                tabPickerSection
                tabSections
            } else {
                signedOutPreviewSection
            }
        }
        .cardList()
        .refreshable { await refreshCurrentTab() }
    }

    /// Spec 1m states the rule this whole treatment follows: *"the header wash is
    /// the user's app accent colour — the crimson shown here is one instance of
    /// it, not a fixed value"*. So the artboard's crimson is the default AO3 red
    /// seen through that rule, not a literal to copy.
    private var accountPalette: SubjectPalette {
        theme.scopePalette
    }

    /// Matches LibrarySectionListView compact: `ScrollView` + two-up `NavigationLink` cards.
    private var libraryStyleCompactRoot: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AccountControlMetrics.compactSpacing) {
                // No `SubjectHeaderBlock` here either: `usesLibraryStyleCompactLayout`
                // is only ever true while signed in, so this one was always the
                // duplicate name. The identity row inside the card below is the
                // same one the list layout shows — this branch is a different
                // *arrangement* of the Account tab, not a different screen.
                AccountProfileCard(
                    profileModel: profileModel,
                    postingPseudName: $postingPseudName,
                    onViewProfile: openOwnProfile,
                    onLogin: { showingLogin = true }
                )
                .padding(.horizontal, SubjectMetrics.accountGutter)

                if let notice = auth.noticeMessage {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, CardListMetrics.sideMargin)
                }

                SubjectSegmentedControl(
                    options: AccountTab.allCases,
                    title: \.rawValue,
                    selection: $selectedTab
                )
                .accessibilityLabel("Account Content")
                .padding(.horizontal, SubjectMetrics.accountGutter)

                compactScopeChrome
                compactWorksContent
            }
            .padding(.vertical, 12)
        }
        // This is a tab root, so keep the tab bar while painting its wash.
        .subjectWash(accountPalette)
        .refreshable { await refreshCurrentTab() }
    }

    @ViewBuilder
    private var compactScopeChrome: some View {
        // Compact swaps the list host, not 1bt's scope membership or controls.
        switch selectedTab {
        case .reading:
            readingScopeGroups
        case .writing:
            writingScopeGroups
        case .activity:
            activityScopeGroups
        case .overview:
            EmptyView()
        }
    }

    @ViewBuilder
    private var compactWorksContent: some View {
        switch selectedTab {
        case .reading:
            EmptyView()
        case .writing:
            EmptyView()
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
        case .drafts: WritingDraftsView()
        case .myWorks: ownProfile(title: "Works", tab: .works)
        case .mySeries: ownProfile(title: "Series", tab: .series)
        }
    }

    /// 1u and 1w are the account's own works and series. `AuthorProfileView` is
    /// already that screen — header, wash, ledger rows — so they open it at the
    /// right scope rather than growing a third copy of the same list.
    @ViewBuilder
    private func ownProfile(title: String, tab: AO3AuthorProfileTab) -> some View {
        if let username = auth.username, let route = AO3AuthorRoute(username: username) {
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

    /// Work-list chrome (Detailed/Compact + Expand) for Account segments that
    /// show work cards. Series / Drafts / Inbox / Overview skip it.
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
            .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
        } footer: {
            if let notice = auth.noticeMessage {
                Text(notice)
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            }
        }
    }

    private func openOwnProfile() {
        guard let username = auth.username,
              let route = AO3AuthorRoute(username: username) else { return }
        path.append(route)
    }

    // MARK: Primary segments

    /// Artboard 1m's scope pills. `SubjectSegmentedControl` rather than a
    /// `Picker(.segmented)`: §1a records that the spec's control is a 9pt-over-7pt
    /// inline shape *and* that the native segmented picker clips rather than
    /// reflows at accessibility text sizes, which is the whole reason this
    /// component exists. Four scope names is exactly the width where that bites.
    private var tabPickerSection: some View {
        Section {
            SubjectSegmentedControl(
                options: AccountTab.allCases,
                title: \.rawValue,
                selection: $selectedTab
            )
            .accessibilityLabel("Account Content")
            .pageBodyRow(top: 14, gutter: SubjectMetrics.accountGutter)
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

    @ViewBuilder
    private var overviewSections: some View {
        Section {
            // 3×2 of individual icon cards (not one shared panel).
            LazyVGrid(columns: shortcutGridColumns, spacing: 10) {
                shortcutGridButton(
                    title: "Dashboard",
                    systemImage: "square.grid.2x2"
                ) {
                    path.append(Route.dashboard)
                }
                shortcutGridButton(
                    title: "Subscriptions",
                    systemImage: "bell",
                    count: cachedCount(.subscriptions)
                ) {
                    readingTab = .subscriptions
                    selectedTab = .reading
                }
                shortcutGridButton(
                    title: "Works",
                    systemImage: "doc.text",
                    count: cachedCount(.myWorks)
                ) {
                    writingTab = .works
                    selectedTab = .writing
                }
                shortcutGridButton(
                    title: "Bookmarks",
                    systemImage: "bookmark",
                    count: cachedCount(.bookmarks)
                ) {
                    readingTab = .bookmarks
                    selectedTab = .reading
                }
                shortcutGridButton(
                    title: "Collections",
                    systemImage: "square.stack",
                    count: cachedCount(.collections)
                ) {
                    path.append(Route.myCollections)
                }
                shortcutGridButton(
                    title: "History",
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
            // The redesign's own rule header, not a plain `Text`: every other
            // restyled screen in this app heads a group this way, and 1m draws
            // the same uppercase rule over both of the hub's groups.
            SectionRuleHeader(title: "Shortcuts")
                .pageBodyRow(top: 18, gutter: 0)
        }

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
        } footer: {
            // 1m closes Overview with a caption. Its first sentence explains the
            // hub's information architecture to a reader of the spec, which would
            // read oddly as on-screen copy; this is the half that tells the user
            // something they cannot otherwise see — that a shortcut is a jump
            // *into a scope*, not a push onto a new screen.
            Text("Tapping a shortcut selects the scope it lives in, "
                + "so Subscriptions lands on Reading and History on Activity.")
                // A `List` footer does not style a `Text` that carries its own
                // row insets, so this drew at body size in the primary colour,
                // flush to the screen edge. 1m sets it at 11.5 and dims it.
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
        }
    }

    // MARK: Reading — Marked for Later | Bookmarks | Collections | Subscriptions

    /// 1bt draws the groups and nothing else: after its last group comes the tab
    /// bar. The inline list that used to sit here was a second copy of the screen
    /// each row now opens — the same works, fetched again, under a heading that
    /// repeated the row above it.
    private var readingSections: some View {
        readingScopeGroups
    }

    // MARK: Activity — History | Inbox

    @ViewBuilder
    private var activitySections: some View {
        activityScopeGroups

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
                AO3AuthorSeriesSection(model: model, showsNewSeriesOnAO3: true)
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

    /// A row *inside* a `subjectPanel`, as 1m's Account group draws them — the
    /// panel owns the background, so the row only owns its own padding.
    private func panelNavRow(
        title: String, systemImage: String, value: some Hashable
    ) -> some View {
        Button {
            path.append(value)
        } label: {
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
            showsMatureRevealControl: showsMatureRevealControl,
            showsWorkListControls: showsWorkListControls,
            displayMode: $displayMode,
            expandAll: $expandAll
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
    /// the hub itself draws — so it cannot drift from the thing it previews, and
    /// inert because there is nothing behind it to open yet.
    @ViewBuilder
    var signedOutPreviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                Text("Signed in, this tab fills in with your own account:")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 14)

                previewGroup("Reading", ["Marked for Later", "Bookmarks", "Collections"])
                previewGroup("Writing", ["Works", "Series"])
                previewGroup("Activity", ["Inbox"])
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
    func previewGroup(_ title: String, _ rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SubjectFieldLabel(text: title, style: .formGroup)
                .padding(.bottom, 7)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { SubjectRowSeparator() }
                    scopeDestinationRow(
                        AccountScopeDestination(
                            id: row,
                            title: row,
                            systemImage: previewSymbol(for: row),
                            open: {}
                        )
                    )
                }
            }
            .subjectPanel()
            .padding(.bottom, 16)
        }
    }

    func previewSymbol(for row: String) -> String {
        switch row {
        case "Marked for Later": AccountReadingTab.later.systemImage
        case "Bookmarks": AccountReadingTab.bookmarks.systemImage
        case "Collections": AccountReadingTab.collections.systemImage
        case "Works": AccountWritingTab.works.systemImage
        case "Series": AccountWritingTab.series.systemImage
        default: AccountActivityTab.inbox.systemImage
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

// MARK: - Writing scope (artboard 1bt)

private extension AccountView {
    // MARK: Writing — Works | Series | Drafts

    @ViewBuilder
    /// Like Reading: 1bt draws the groups and nothing else. Works, Series and
    /// Drafts each open their own screen now, so the inline list that used to sit
    /// here was a second copy of what the row opens.
    private var writingSections: some View {
        writingScopeGroups
    }

    // MARK: Scope groups (artboard 1bt)

    @ViewBuilder
    var readingScopeGroups: some View {
        // 1bt groups Reading by what a shelf means: saved or followed.
        scopeGroup("Saved", [
            readingDestination(.later, count: .markedForLater),
            readingDestination(.bookmarks, count: .bookmarks),
            readingDestination(.collections, count: .collections)
        ])
        // `SubscriptionWatermarks.newChapterCount(for:watermarks:)` needs loaded
        // subscription works. The hub's AO3AccountListCountsCache only holds list
        // sizes, so it cannot supply "N with new chapters" without loading them.
        scopeGroup("Following", [
            readingDestination(.subscriptions, count: .subscriptions)
        ])
    }

    @ViewBuilder
    var writingScopeGroups: some View {
        scopeGroup("Posted", [
            writingDestination(.works, count: .myWorks),
            writingDestination(.series, count: .series)
        ])
        scopeGroup("Unposted", [
            // otwarchive's work_drafts.feature keeps 29-day drafts and purges
            // 31-day drafts; WritingDraftsView records the same 30-day rule.
            writingDestination(.drafts, count: nil, subtitle: "Deleted by AO3 after 30 days")
        ])
    }

    @ViewBuilder
    var activityScopeGroups: some View {
        // 1bt splits arrivals from exchanges; this scope has only Inbox for
        // both, so there is no empty exchanges heading.
        scopeGroup("Read on AO3", [
            activityDestination(
                .history, count: .history, subtitle: "AO3’s own history, not the local reading log"
            )
        ])
        scopeGroup("Arrives", [
            activityDestination(
                .inbox,
                count: nil,
                subtitle: inboxModel.unreadCount.map { "\($0) unread" }
            )
        ])
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
        AccountScopeGroup(
            title: title,
            count: destinations.count,
            layout: usesLibraryStyleCompactLayout ? .scroll : .list
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
        let count: Int
        let layout: AccountWorksLayout
        let content: Content
        @AppStorage private var isCollapsed: Bool

        init(title: String, count: Int, layout: AccountWorksLayout, @ViewBuilder content: () -> Content) {
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
                Image(systemName: destination.systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(accountPalette.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    if let subtitle = destination.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11.5))
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
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
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
        case .inbox: activityTab = tab
        }
    }
}
