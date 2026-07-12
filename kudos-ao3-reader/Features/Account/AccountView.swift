import SwiftData
import SwiftUI

/// The Account tab, redesigned as the signed-in user's own native profile hub:
/// a profile identity card over Overview / Works / Bookmarks / Activity segments,
/// matching the visual language of Author Profiles and Comments. Works and
/// Bookmarks embed the same `AO3AuthorProfileModel`-backed rows Author Profiles
/// use, scoped to the signed-in user; Activity surfaces AO3 History, Marked for
/// Later, and the AO3 Inbox. AO3-account functionality only — app settings live
/// behind the toolbar gear (`ReaderOptionsForm`), local History/Favorites moved
/// to the Library tab.
struct AccountView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router

    @State private var path = NavigationPath()
    @State private var showingLogin = false
    @State private var selectedTab: AccountTab = .overview
    @State private var activityTab: AccountActivityTab = .history
    /// The signed-in user's own profile content (Works / Bookmarks), self-scoped.
    /// nil while signed out. Loaded lazily — only once the user opens the tab.
    @State private var profileModel: AO3AuthorProfileModel?
    /// Shared by Overview's Recent Comments preview and Activity › Comments.
    @State private var inboxModel = AO3InboxModel()
    @State private var expandAll = false
    /// UI mirror of the persisted "Posting As" choice (nil = AO3 default).
    @State private var postingPseudName: String?
    /// Bumped by pull-to-refresh on Activity › History/Later to force a reload.
    @State private var activityReloadToken = 0

    /// Pushable Account destinations that aren't already value-routed types.
    enum Route: Hashable {
        case myCollections
        case settings
    }

    /// The page's primary segments.
    enum AccountTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case works = "Works"
        case bookmarks = "Bookmarks"
        case activity = "Activity"

        var id: String { rawValue }
    }

    /// Activity's secondary segments.
    enum AccountActivityTab: String, CaseIterable, Identifiable {
        case history = "History"
        case later = "Later"
        case comments = "Comments"

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

    /// Re-runs activation whenever what's on screen changes: tab into Account,
    /// login/logout, or a segment switch. Content loads only when its surface is
    /// actually visible — the Account tab stays mounted (but idle) inside the
    /// root TabView, and no request should fire for a hidden screen.
    private var activationKey: String {
        [
            auth.username ?? "",
            String(router.selection == .account),
            selectedTab.rawValue,
            activityTab.rawValue
        ].joined(separator: "|")
    }

    private func activateVisibleContent() {
        guard router.selection == .account, auth.isLoggedIn else { return }
        switch selectedTab {
        case .overview:
            // The profile header feeds the Profile Card (avatar, pseud list) —
            // same open-behavior as tapping into an author profile.
            profileModel?.activate(auth: auth)
            inboxModel.activate(auth: auth)
        case .works:
            syncProfileTab(.works)
        case .bookmarks:
            syncProfileTab(.bookmarks)
        case .activity:
            profileModel?.activate(auth: auth)
            if activityTab == .comments {
                inboxModel.activate(auth: auth)
            }
            // History / Later load themselves via AccountWorksInlineSection.
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
        // The activation task can fire before this onChange creates the model
        // (initial-appearance ordering is undefined) — re-activate now that it
        // exists; activation is idempotent and self-gates on tab visibility.
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
            await inboxModel.refresh(auth: auth)
        case .works, .bookmarks:
            if let model = profileModel { await model.refresh(auth: auth) }
        case .activity:
            switch activityTab {
            case .history, .later:
                activityReloadToken += 1
            case .comments:
                await inboxModel.refresh(auth: auth)
            }
        }
    }

    // MARK: Destinations & toolbar

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .myCollections: AO3CollectionsList()
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

    /// Expand-all applies to the tabs that render work cards.
    private var showsExpandControl: Bool {
        guard auth.isLoggedIn else { return false }
        switch selectedTab {
        case .overview: return false
        case .works, .bookmarks: return true
        case .activity: return activityTab != .comments
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

    // MARK: Segments

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
        case .works:
            profileContentSections(tab: .works)
        case .bookmarks:
            profileContentSections(tab: .bookmarks)
        case .activity:
            activitySections
        }
    }

    // MARK: Overview

    @ViewBuilder
    private var overviewSections: some View {
        Section("My AO3") {
            Button {
                selectedTab = .works
            } label: {
                AccountNavCardLabel(
                    title: "My Works",
                    systemImage: "doc.text",
                    count: cachedCount(.myWorks)
                )
            }
            .buttonStyle(.plain)
            .cardRow()

            navCard(
                title: "My Collections", systemImage: "square.stack",
                count: cachedCount(.collections), value: Route.myCollections
            )
            navCard(
                title: "My Subscriptions", systemImage: "bell",
                count: cachedCount(.subscriptions), value: AO3AccountWorksList.Kind.subscriptions
            )
            navCard(
                title: "Marked for Later", systemImage: "clock.badge",
                count: cachedCount(.markedForLater), value: AO3AccountWorksList.Kind.markedForLater
            )
        }

        Section {
            AccountInboxRows(
                model: inboxModel,
                limit: 3,
                onOpen: openInboxItem,
                onSeeAll: {
                    activityTab = .comments
                    selectedTab = .activity
                }
            )
        } header: {
            Text("Recent Comments")
        }

        Section {
            webLink("My Preferences", systemImage: "slider.horizontal.3", path: "/preferences")
                .cardRow()
        } header: {
            Text("On AO3")
        } footer: {
            Text("Opens your AO3 settings on the website.")
        }
    }

    /// A rich navigation card that pushes `value` (kept as a Button + manual
    /// chevron so all four Overview cards read identically, including the
    /// tab-switching My Works card).
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
            // Tag / admin-post comments have no native thread screen — honest
            // web fallback.
            router.open(url)
        }
    }

    // MARK: Works / Bookmarks (shared author-profile rows, scoped to self)

    @ViewBuilder
    private func profileContentSections(tab: AO3AuthorProfileTab) -> some View {
        if let model = profileModel {
            switch model.headerPhase {
            case .idle, .loading:
                Section(tab.rawValue) { AO3AuthorLoadingRows() }
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
                if tab == .works {
                    AO3AuthorFandomFilterSection(model: model)
                    AO3AuthorWorksSection(model: model, expandAll: expandAll)
                } else {
                    AO3AuthorBookmarksSection(model: model, expandAll: expandAll)
                }
            }
        }
    }

    // MARK: Activity

    @ViewBuilder
    private var activitySections: some View {
        Section {
            Picker("Activity", selection: $activityTab) {
                ForEach(AccountActivityTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .cardRow()
        }

        switch activityTab {
        case .history:
            AccountWorksInlineSection(
                kind: .history, expandAll: expandAll, reloadToken: activityReloadToken
            )
        case .later:
            AccountWorksInlineSection(
                kind: .markedForLater, expandAll: expandAll, reloadToken: activityReloadToken
            )
        case .comments:
            Section {
                AccountInboxRows(model: inboxModel, limit: nil, onOpen: openInboxItem)
            } header: {
                Text("Comments")
            } footer: {
                if let total = inboxModel.totalComments {
                    let unread = inboxModel.unreadCount ?? 0
                    Text("\(total) comments in your AO3 inbox, \(unread) unread. "
                        + "Manage read state on the AO3 website.")
                }
            }
        }
    }

    // MARK: Helpers

    /// A row that opens an AO3 path on the website (via the in-app browser).
    /// Disabled (with a hint) for account-specific paths when signed out.
    @ViewBuilder
    private func webLink(_ title: String, systemImage: String, path: String) -> some View {
        let needsAccount = path.contains("/users/")
        Button {
            if let url = URL(string: "https://archiveofourown.org\(path)") { router.open(url) }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.forward.square").foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(needsAccount && auth.username == nil)
    }
}
