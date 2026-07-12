import SwiftData
import SwiftUI

/// The Account tab: signed-in user's native AO3 profile hub with
/// Overview / Reading / Writing / Activity.
///
/// - **Overview** — identity hub: shortcuts, Preferences, More on AO3
/// - **Reading** — Later / Subscriptions / Bookmarks / Collections
/// - **Writing** — Works / Series / Drafts (drafts open AO3 for now)
/// - **Activity** — History / Inbox
///
/// App settings stay behind the toolbar gear.
struct AccountView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router

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
    @State private var expandAll = false
    @State private var postingPseudName: String?
    /// Bumped by pull-to-refresh on list-style Reading/Activity segments.
    @State private var listReloadToken = 0

    enum Route: Hashable {
        case myCollections
        case preferences
        case moreOnAO3
        case settings
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
    }

    enum AccountWritingTab: String, CaseIterable, Identifiable {
        case works = "Works"
        case series = "Series"
        case drafts = "Drafts"

        var id: String { rawValue }
    }

    enum AccountActivityTab: String, CaseIterable, Identifiable {
        case history = "History"
        case inbox = "Inbox"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                profileCardSection

                if auth.isLoggedIn {
                    tabPickerSection
                    tabSections
                }
            }
            .cardList()
            .refreshable { await refreshCurrentTab() }
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
                        context: AO3CommentsWorkContext(title: destination.title, authors: [])
                    )
                }
                .ao3AuthorNavigation(path: $path, tab: .account)
                .toolbar { toolbarContent }
                .sheet(isPresented: $showingLogin) { AO3LoginView() }
                .task(id: activationKey) { activateVisibleContent() }
                .onChange(of: auth.username, initial: true) { _, username in
                    syncProfileModel(username: username)
                }
        }
    }

    // MARK: Activation

    private var activationKey: String {
        [
            auth.username ?? "",
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
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 2) {
                if showsExpandControl {
                    WorkListMoreMenu {
                        ExpandAllMenuItem(expandAll: $expandAll)
                    }
                }
                NavigationLink(value: Route.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .labelStyle(.iconOnly)
        }
    }

    private var showsExpandControl: Bool {
        guard auth.isLoggedIn else { return false }
        switch selectedTab {
        case .overview:
            return false
        case .writing:
            // Drafts has no expandable card chrome; Works does.
            return writingTab == .works
        case .reading:
            return readingTab == .later
                || readingTab == .subscriptions
                || readingTab == .bookmarks
        case .activity:
            return activityTab == .history
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
            .cardRow()
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
            .cardRow()
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

    @ViewBuilder
    private var overviewSections: some View {
        Section {
            shortcutCard(
                title: "Marked for Later",
                systemImage: "clock.badge",
                count: cachedCount(.markedForLater)
            ) {
                readingTab = .later
                selectedTab = .reading
            }
            shortcutCard(
                title: "Inbox",
                systemImage: "tray",
                count: nil
            ) {
                activityTab = .inbox
                selectedTab = .activity
            }
            shortcutCard(
                title: "Works",
                systemImage: "doc.text",
                count: cachedCount(.myWorks)
            ) {
                writingTab = .works
                selectedTab = .writing
            }
        } header: {
            Text("Shortcuts")
        } footer: {
            Text("Jump into the lists you open most. Full Reading, Writing, and Activity "
                + "tabs are above.")
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
        } footer: {
            Text("Native preferences in the app. Drafts, challenges, gifts, skins, and "
                + "the full dashboard open from More on AO3.")
        }
    }

    // MARK: Reading — Later | Subscriptions | Bookmarks | Collections

    @ViewBuilder
    private var readingSections: some View {
        Section {
            AccountScopeMenu(prompt: "Show", selection: $readingTab)
                .cardRow()
        }

        switch readingTab {
        case .later:
            AccountWorksInlineSection(
                kind: .markedForLater,
                expandAll: expandAll,
                reloadToken: listReloadToken,
                onRefine: { path.append(AO3AccountWorksList.Kind.markedForLater) }
            )
        case .subscriptions:
            AccountWorksInlineSection(
                kind: .subscriptions,
                expandAll: expandAll,
                reloadToken: listReloadToken,
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
            AccountScopeMenu(prompt: "Show", selection: $writingTab)
                .cardRow()
        }

        switch writingTab {
        case .works:
            profileContentSections(profileTab: .works, sectionTitle: "Works")
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
            AccountScopeMenu(prompt: "Show", selection: $activityTab)
                .cardRow()
        }

        switch activityTab {
        case .history:
            AccountWorksInlineSection(
                kind: .history,
                expandAll: expandAll,
                reloadToken: listReloadToken,
                onRefine: { path.append(AO3AccountWorksList.Kind.history) }
            )
        case .inbox:
            Section {
                AccountInboxRows(model: inboxModel, limit: nil, onOpen: openInboxItem)
            } header: {
                Text("Inbox")
            } footer: {
                if let total = inboxModel.totalComments {
                    let unread = inboxModel.unreadCount ?? 0
                    Text("\(total) comments in your AO3 inbox, \(unread) unread. "
                        + "Manage read state on the AO3 website.")
                }
            }
        }
    }

    // MARK: Shared profile content

    @ViewBuilder
    private func profileContentSections(
        profileTab: AO3AuthorProfileTab,
        sectionTitle: String
    ) -> some View {
        if let model = profileModel {
            switch model.headerPhase {
            case .idle, .loading:
                Section(sectionTitle) { AO3AuthorLoadingRows() }
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
                if profileTab == .works {
                    AO3AuthorFandomFilterSection(model: model)
                    AO3AuthorWorksSection(model: model, expandAll: expandAll)
                } else {
                    AO3AuthorBookmarksSection(model: model, expandAll: expandAll)
                }
            }
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

    private func shortcutCard(
        title: String,
        systemImage: String,
        count: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AccountNavCardLabel(title: title, systemImage: systemImage, count: count)
        }
        .buttonStyle(.plain)
        .cardRow()
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
        .cardRow()
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
        .cardRow()
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
            authenticationScope: AO3AuthorProfileFetcher.authenticationScope(for: auth)
        )?.displayText
    }

    private func openInboxItem(_ item: AO3InboxItem) {
        if let workID = item.workID {
            path.append(AccountInboxThreadDestination(
                workID: workID,
                title: item.subjectTitle
            ))
        } else if let url = item.subjectURL {
            router.open(url)
        }
    }
}
