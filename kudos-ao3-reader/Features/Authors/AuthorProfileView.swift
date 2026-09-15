import SwiftData
import SwiftUI

struct AuthorProfileView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme

    @State private var model: AO3AuthorProfileModel
    @State private var expandAll = false
    /// Per-screen, like Home's and Library's section lists. This screen drew its
    /// rows from the *layout* before, so Ledger and Detailed were unreachable.
    @AppStorage("authorProfile.displayMode") private var displayMode: WorkListDisplayMode = .detailed
    @State private var bulkSelection = RemoteWorkSelectionController()
    /// 1bn: pushed rather than presented, so the bulk form gets a real back stack.
    @State private var isBulkEditing = false
    /// 1u's swipe actions. Edit / Tags / Chapter push; Delete confirms first.
    @State private var pendingOwnWorkAction: AO3OwnWorkAction?
    @State private var pendingDeleteWork: (id: Int, title: String)?
    @State private var deleteErrorMessage: String?
    @State private var confirmingUnsubscribe = false
    /// Signed-out Mute/Block/Subscribe — same prompt for all profile write actions.
    @State private var showingLoginRequired = false
    @State private var showingLogin = false
    /// Resume after the login sheet succeeds (cleared on cancel / failed login).
    @State private var pendingAuthAction: PendingAuthAction?
    @State private var dashboardDestination: AO3AuthorProfileTab?
    /// Nav bar title. Account's **My Dashboard** reuses this surface for the
    /// signed-in user's home (`/users/:login`) under the title "Dashboard".
    private let navigationTitle: String
    private let showsDashboard: Bool
    private let isContentDestination: Bool

    /// `initialTab` lets Account's Writing scope open this surface directly on
    /// Works (1u) or Series (1w) rather than on whichever tab the model defaults
    /// to. Without it a row named "Series" opened a screen showing works.
    init(
        route: AO3AuthorRoute,
        navigationTitle: String = "Author",
        initialTab: AO3AuthorProfileTab? = nil,
        showsDashboard: Bool = false
    ) {
        let model = AO3AuthorProfileModel(route: route, dashboardOnly: showsDashboard)
        if let initialTab { model.selectedTab = initialTab }
        _model = State(initialValue: model)
        self.navigationTitle = navigationTitle
        self.showsDashboard = showsDashboard
        isContentDestination = initialTab != nil
    }

    var body: some View {
        Group {
            switch model.headerPhase {
            case .idle, .loading:
                AO3AuthorProfileSkeleton()
            case .unavailable:
                unavailableView
            case let .failed(message):
                failedProfileView(message)
            case .loaded:
                profileList
            }
        }
        .navigationTitle(navigationTitle)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            .toolbar { toolbarContent }
            .navigationDestination(item: $dashboardDestination) { tab in
                AuthorProfileView(route: model.route, navigationTitle: tab.rawValue, initialTab: tab)
            }
            .navigationDestination(isPresented: $isBulkEditing) { bulkEditDestination }
            .navigationDestination(item: ownWorkPushBinding) { ownWorkDestination($0) }
            .confirmationDialog(
                "Delete “\(pendingDeleteWork?.title ?? "this work")”?",
                isPresented: deleteConfirmationBinding,
                titleVisibility: .visible
            ) {
                Button("Delete on AO3", role: .destructive) { confirmDeleteWork() }
                Button("Cancel", role: .cancel) { pendingDeleteWork = nil }
            } message: {
                Text("This removes the work from AO3 for everyone, with its chapters, "
                    + "kudos, comments and bookmarks. It cannot be undone.")
            }
            .alert("Couldn’t delete", isPresented: deleteErrorBinding) {
                Button("OK") { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "AO3 refused the delete.")
            }
            .remoteWorkSelectionChrome(bulkSelection)
            .sheet(isPresented: $showingLogin, onDismiss: {
                Task { await resumePendingAuthActionIfNeeded() }
            }) {
                AO3LoginView()
            }
            .alert("AO3 Profile", isPresented: actionMessagePresented) {
                Button("OK", role: .cancel) { model.clearActionMessage() }
            } message: {
                Text(model.actionMessage ?? "")
            }
            .alert("Log in to AO3", isPresented: $showingLoginRequired) {
                Button("Cancel", role: .cancel) { pendingAuthAction = nil }
                Button("Log In") {
                    // Present the login sheet after the alert finishes dismissing.
                    // Simultaneous alert-dismiss + sheet-present can drop the sheet
                    // on some iOS versions before the user ever submits credentials.
                    //
                    // This sleep is deliberately NOT convertible to a completion
                    // signal, unlike the Comments sheet cases in this same wave
                    // (T-139/UI-8). `.sheet`/`.fullScreenCover` take an `onDismiss:`
                    // closure that fires when the dismiss transition genuinely
                    // finishes; `.alert` has no such parameter, and there is no
                    // other SwiftUI event for "this alert is gone". `onChange` on
                    // the alert's own `isPresented` binding is NOT a substitute —
                    // SwiftUI clears that binding to *begin* the dismissal, so the
                    // handler runs about a frame after the tap with the alert still
                    // animating away, i.e. it removes the wait rather than deriving
                    // it. That was tried here and reverted. Until a real signal
                    // exists, the tested duration stays.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        showingLogin = true
                    }
                }
            } message: {
                Text("This action requires an AO3 account, log in first.")
            }
            .confirmationDialog(
                "Unsubscribe from \(model.route.username)?",
                isPresented: $confirmingUnsubscribe,
                titleVisibility: .visible
            ) {
                Button("Unsubscribe", role: .destructive) {
                    Task { await model.toggleSubscription(auth: auth) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("AO3 subscriptions apply to the underlying user account, not only this pseud.")
            }
            // Centered alert (same style as "Log in to AO3"), not an action sheet.
            .alert(
                model.pendingModerationForm?.title ?? "Confirm",
                isPresented: moderationConfirmPresented
            ) {
                Button(
                    model.pendingModerationForm?.submitLabel ?? "Confirm",
                    role: (model.pendingModerationForm?.kind.isUndo ?? false) ? nil : .destructive
                ) {
                    // Snapshot is held on the model — alert dismiss clears `pending`
                    // before this Task runs.
                    Task { await model.confirmPendingModeration(auth: auth) }
                }
                Button(model.pendingModerationForm?.cancelLabel ?? "Cancel", role: .cancel) {
                    model.cancelPendingModeration()
                }
            } message: {
                if let form = model.pendingModerationForm {
                    Text(form.message)
                }
            }
            .onChange(of: authenticationScope, initial: true) { _, _ in
                bulkSelection.exitSelectMode()
                model.activate(auth: auth)
            }
            .onDisappear {
                model.cancel()
            }
    }
}

/// Profile write action to continue after a successful login from the signed-out prompt.
private enum PendingAuthAction: Equatable {
    case subscribe
    case moderation(AO3AuthorWebAction.Kind)
}

private extension AuthorProfileView {
    private var authenticationScope: String {
        showsDashboard
            ? AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
            : AO3AuthorProfileFetcher.authenticationScope(for: auth)
    }

    private var profileList: some View {
        List {
            if usesAccountHeader {
                accountHeader
            } else {
                Section {
                    if let header = model.header {
                        AO3AuthorHero(
                            header: header,
                            route: model.route,
                            profileTitle: model.about?.profileTitle ?? "",
                            isOwnProfile: isOwnProfile,
                            isPerformingSubscription: model.isPerformingSubscription,
                            isPerformingModeration: model.isPerformingModeration,
                            muteAction: muteAction,
                            blockAction: blockAction,
                            onSubscription: subscriptionTapped,
                            onModerationAction: moderationTapped
                        )
                        .cardRow()
                    }
                }
            }

            if !usesAccountHeader, let header = model.header, header.pseuds.count > 1 {
                Section {
                    pseudSelector(header.pseuds)
                        .cardRow()
                }
            }

            if !showsDashboard, !isContentDestination {
                Section {
                    SubjectSegmentedControl(
                        options: AO3AuthorProfileTab.allCases,
                        title: { $0.rawValue },
                        selection: tabSelection
                    )
                    .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }
            }

            if model.isShowingStaleCache {
                Section {
                    Label("Showing cached AO3 data", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .cardRow()
                }
            }

            if showsDashboard, let header = model.header {
                AO3DashboardSections(
                    header: header,
                    route: model.route,
                    expandAll: expandAll,
                    onSeeAll: { dashboardDestination = $0 }
                )
            } else {
                AO3AuthorWorksScopeSection(
                    model: model,
                    // Same gate as showsPerformance below, for the same reason:
                    // 1u is the own-works screen, and deriving this from the
                    // model rather than a host flag means no future caller can
                    // switch a stranger's profile onto their Gifts by mistake.
                    showsScopes: isOwnProfile,
                    onWillChange: bulkSelection.exitSelectMode
                )
                AO3AuthorFandomFilterSection(model: model, onWillChange: bulkSelection.exitSelectMode)
                contentRows
            }
        }
        .cardList()
        .subjectScreenWash(palette: theme.scopePalette)
        .refreshable { await model.refresh(auth: auth) }
    }

    private var usesAccountHeader: Bool { showsDashboard || (isOwnProfile && isContentDestination) }

    private var accountHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            SubjectHeaderBlock(
                kicker: "AO3 Account",
                title: showsDashboard ? model.route.displayName : model.selectedTab.rawValue,
                subtitle: accountSubtitle,
                palette: theme.scopePalette,
                gutter: SubjectMetrics.accountGutter
            )
            if let header = model.header, !header.pseuds.isEmpty {
                pseudSelector(header.pseuds)
                    .padding(.horizontal, SubjectMetrics.accountGutter)
            }
            if isOwnProfile, showsDashboard || model.selectedTab == .works {
                NavigationLink { WritingWorkDestination(workID: nil) } label: {
                    SubjectChip(text: "New work", style: .tinted, systemImage: "plus", palette: theme.scopePalette)
                        .minimumHitTarget()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, SubjectMetrics.accountGutter)
            }
        }
        .pageBodyRow(top: 16, gutter: 0)
    }

    private var accountSubtitle: String? {
        if showsDashboard {
            // Joined lives on About, not this page. Don't fetch a profile just
            // for the artboard's date, or invent pseud/invitation totals.
            return model.route.pseud.map { _ in "Pseud of \(model.route.username)" }
        }
        // AO3AccountListCountsCache holds the count for the plain works index.
        // Under "In collections" or "Gifts" the list on screen is a different
        // one, so the count would caption the wrong thing — drop it rather than
        // print a figure that does not describe what is below it.
        guard isOwnProfile, model.route.pseud == nil,
              model.worksScope == .works,
              let kind = AO3DashboardSections.listKind(for: model.selectedTab),
              let stored = AO3AccountListCountsCache.shared.count(
                  for: kind,
                  authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
              ),
              let count = stored.displayText else { return model.route.displayName }
        // 1u's hero is "12 works · 248,400 words · 3,812 kudos". Words and kudos
        // come from /users/:id/stats and exist only for the signed-in account,
        // so on anyone else's page — and before the fetch lands — this stays the
        // count and the name it has always been rather than showing blanks.
        var parts = ["\(count) \(scopeNoun(stored.exact))"]
        if model.selectedTab == .works, let stats = model.stats {
            if let words = stats.wordCount {
                parts.append("\(words.formatted()) words")
            }
            if let kudos = stats.kudos {
                parts.append("\(kudos.formatted()) kudos")
            }
        }
        if parts.count > 1 { return parts.joined(separator: " · ") }
        return "\(parts[0]) · \(model.route.displayName)"
    }

    /// The tab's own name is always the plural — "Works", "Bookmarks" — so an
    /// account with one work read "1 works". Spelled out per case rather than
    /// trimming an "s", because "series" is both forms and would lose one.
    ///
    /// Only an exact 1 singularises: a lower bound is rendered "100+", which is
    /// never one of anything.
    private func scopeNoun(_ exact: Int?) -> String {
        switch model.selectedTab {
        case .works: exact == 1 ? "work" : "works"
        case .series: "series"
        case .bookmarks: exact == 1 ? "bookmark" : "bookmarks"
        case .about: "about"
        }
    }

    private var tabSelection: Binding<AO3AuthorProfileTab> {
        Binding(
            get: { model.selectedTab },
            set: { tab in
                bulkSelection.exitSelectMode()
                model.selectTab(tab, auth: auth)
            }
        )
    }

    private func pseudSelector(_ pseuds: [AO3AuthorPseud]) -> some View {
        HStack(spacing: 12) {
            Label("Scope", systemImage: "person.2")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Menu {
                if let allPseuds = AO3AuthorRoute(username: model.route.username) {
                    Button {
                        bulkSelection.exitSelectMode()
                        model.selectScope(allPseuds, auth: auth)
                    } label: {
                        Label(
                            "All Pseuds",
                            systemImage: model.route.pseud == nil ? "checkmark" : "person.2"
                        )
                    }
                }
                ForEach(pseuds) { pseud in
                    Button {
                        bulkSelection.exitSelectMode()
                        model.selectScope(pseud.route, auth: auth)
                    } label: {
                        Label(
                            pseud.name,
                            systemImage: model.route == pseud.route ? "checkmark" : "person"
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(model.route.pseud ?? "All Pseuds")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.tint)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("Author scope")
            .accessibilityValue(model.route.pseud ?? "All Pseuds")
        }
    }

    @ViewBuilder
    private var contentRows: some View {
        switch model.selectedTab {
        case .works:
            AO3AuthorWorksSection(
                model: model,
                expandAll: expandAll,
                displayMode: displayMode,
                isSelecting: bulkSelection.isSelecting,
                selection: bulkSelection.selection,
                onToggleSelection: bulkSelection.toggle,
                // Artboard 1y is the Dashboard, which is this view pointed at
                // yourself. Gating on `isOwnProfile` rather than on a flag the
                // Dashboard passes means no future caller can turn a stranger's
                // per-work kudos and hits on by mistake.
                showsPerformance: isOwnProfile,
                // 1u's swipe actions, on the same gate: AO3 refuses every one of
                // them on someone else's work, so the swipe does not exist there.
                onOwnWorkAction: ownWorkActionHandler
            )
        case .series:
            AO3AuthorSeriesSection(
                model: model,
                showsNewSeriesOnAO3: isOwnProfile,
                displayMode: displayMode
            )
        case .bookmarks:
            AO3AuthorBookmarksSection(model: model, expandAll: expandAll, displayMode: displayMode)
        case .about:
            aboutRows
        }
    }

    @ViewBuilder
    private var aboutRows: some View {
        if model.contentPhase == .loading, model.about == nil {
            Section("About") { AO3AuthorLoadingRows() }
        } else if let about = model.about {
            Section("Bio") {
                if about.bio.isEmpty {
                    Text("This user has not added a bio.")
                        .foregroundStyle(.secondary)
                        .cardRow()
                } else {
                    AO3RichTextView(document: about.bio)
                        .cardRow()
                }
            }

            if !about.pseuds.isEmpty {
                Section("Pseuds") {
                    ForEach(about.pseuds) { pseud in
                        Button {
                            bulkSelection.exitSelectMode()
                            model.selectScope(pseud.route, auth: auth)
                        } label: {
                            HStack {
                                Label(pseud.name, systemImage: "person")
                                Spacer()
                                if model.route == pseud.route {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .cardRow()
                    }
                }
            }

            Section("Account") {
                if let pseud = model.route.pseud {
                    LabeledContent("Selected Pseud", value: pseud).cardRow()
                }
                if !about.joinedDate.isEmpty {
                    LabeledContent("Joined", value: about.joinedDate).cardRow()
                }
                if let userID = about.userID {
                    LabeledContent("User ID", value: userID.formatted()).cardRow()
                }
            }
        } else {
            Section("About") {
                AO3AuthorContentMessage(
                    model: model,
                    emptyTitle: "Profile details unavailable",
                    emptyMessage: "Kudos could not read this AO3 profile page.",
                    emptySymbol: "person.text.rectangle"
                )
            }
        }
    }
}

private extension AuthorProfileView {

    private var isOwnProfile: Bool {
        auth.username?.localizedCaseInsensitiveCompare(model.route.username) == .orderedSame
    }

    /// 1bn is AO3's `/users/<name>/works/edit_multiple` — your own works only, and
    /// only the Works tab. Bookmarks and Series select the same way but have no
    /// bulk editor behind them.
    private var showsBulkEdit: Bool {
        isOwnProfile && auth.isLoggedIn && model.selectedTab == .works
    }

    /// Edit / Tags / Chapter push; Delete is filtered out here and routed to the
    /// confirmation instead, so a destructive swipe can never navigate straight
    /// into doing the thing.
    private var ownWorkPushBinding: Binding<AO3OwnWorkAction?> {
        Binding(
            get: {
                if case .delete = pendingOwnWorkAction { return nil }
                return pendingOwnWorkAction
            },
            set: { pendingOwnWorkAction = $0 }
        )
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteWork != nil },
            set: { if !$0 { pendingDeleteWork = nil } }
        )
    }

    private var deleteErrorBinding: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )
    }

    @ViewBuilder
    private func ownWorkDestination(_ action: AO3OwnWorkAction) -> some View {
        switch action {
        case let .edit(workID):
            WritingWorkDestination(workID: workID)
        case let .tags(workID):
            WritingTagsDestination(workID: workID)
        case let .chapter(workID, title):
            WritingChapterDestination(workID: workID, workTitle: title) {
                Task { await model.refresh(auth: auth) }
            }
        case .delete:
            // Never reached: `ownWorkPushBinding` filters delete out.
            EmptyView()
        }
    }

    /// Spelled out with its type rather than inlined as
    /// `showsBulkEdit ? handleOwnWorkAction : nil`: a ternary producing an
    /// optional closure inside that call is what made the type checker give up
    /// with "failed to produce diagnostic for expression".
    private var ownWorkActionHandler: ((AO3OwnWorkAction) -> Void)? {
        guard showsBulkEdit else { return nil }
        return handleOwnWorkAction
    }

    /// Delete forks to the confirmation; everything else becomes a push.
    private func handleOwnWorkAction(_ action: AO3OwnWorkAction) {
        if case let .delete(workID, title) = action {
            pendingDeleteWork = (id: workID, title: title)
        } else {
            pendingOwnWorkAction = action
        }
    }

    private func confirmDeleteWork() {
        guard let pending = pendingDeleteWork else { return }
        pendingDeleteWork = nil
        Task {
            do {
                _ = try await auth.deleteWork(workID: pending.id)
                await model.refresh(auth: auth)
            } catch {
                deleteErrorMessage = error.localizedDescription
            }
        }
    }

    /// Resolved when the push happens, so it acts on the live selection rather
    /// than whatever was selected when the toolbar was built.
    @ViewBuilder
    private var bulkEditDestination: some View {
        let ids = bulkSelection.selected(in: model.works).map(\.id)
        if ids.isEmpty {
            ContentUnavailableView(
                "Nothing selected",
                systemImage: "square.and.pencil",
                description: Text("Choose the works to edit, then try again.")
            )
        } else {
            WritingBulkEditDestination(workIDs: ids)
        }
    }

    private func subscriptionTapped() {
        guard auth.isLoggedIn else {
            pendingAuthAction = .subscribe
            showingLoginRequired = true
            return
        }
        guard let form = model.header?.subscriptionForm else { return }
        if form.isSubscribed {
            confirmingUnsubscribe = true
        } else {
            Task { await model.toggleSubscription(auth: auth) }
        }
    }

    private func moderationTapped(_ action: AO3AuthorWebAction) {
        guard auth.isLoggedIn else {
            pendingAuthAction = .moderation(action.kind)
            showingLoginRequired = true
            return
        }
        Task { await model.beginModeration(action: action, auth: auth) }
    }

    /// After the login sheet closes: if the user signed in, refresh the profile
    /// (signed-in forms/actions) and continue Mute / Block / Subscribe.
    ///
    /// The login sheet can disappear while automatic sign-in is still running
    /// (SwiftUI presentation glitches). Wait briefly for that attempt so we
    /// don't drop a Mute/Block/Subscribe that the user already asked for.
    private func resumePendingAuthActionIfNeeded() async {
        guard let pending = pendingAuthAction else { return }
        if auth.status == .signingIn {
            for _ in 0..<100 where auth.status == .signingIn {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        guard auth.isLoggedIn else {
            pendingAuthAction = nil
            return
        }
        pendingAuthAction = nil
        // Header was loaded signed-out; pull signed-in subscription form + action URLs.
        await model.refresh(auth: auth)
        switch pending {
        case .subscribe:
            guard let form = model.header?.subscriptionForm else { return }
            if form.isSubscribed {
                confirmingUnsubscribe = true
            } else {
                await model.toggleSubscription(auth: auth)
            }
        case let .moderation(kind):
            let actions = (model.header?.actions ?? []) + (model.about?.actions ?? [])
            guard let action = actions.first(where: { $0.kind == kind }) else { return }
            await model.beginModeration(action: action, auth: auth)
        }
    }

    private var moderationConfirmPresented: Binding<Bool> {
        Binding(
            get: { model.pendingModerationForm != nil },
            // Dismiss-only: SwiftUI writes `false` here *before* running the
            // tapped button's action, so this must not clear the submit
            // snapshot — that made Confirm a silent no-op. The Cancel button
            // (and only it) calls `cancelPendingModeration()` to drop both.
            set: { if !$0 { model.moderationAlertDidDismiss() } }
        )
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Author unavailable", systemImage: "person.slash")
        } description: {
            Text("AO3 could not find this user or pseud. It may have been renamed or deleted.")
        } actions: {
            Button("Open on AO3") { router.open(model.route.dashboardURL) }
        }
    }

    private func failedProfileView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load author", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { model.retry(auth: auth) }
            Button("Open on AO3") { router.open(model.route.dashboardURL) }
        }
    }

    private var actionMessagePresented: Binding<Bool> {
        Binding(
            get: { model.actionMessage != nil },
            set: { if !$0 { model.clearActionMessage() } }
        )
    }

}

private extension AuthorProfileView {
    // MARK: Toolbar and actions

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if bulkSelection.isSelecting {
            // 1bn's Edit Multiple Works, beside the shared local bulk bar rather
            // than inside it: `RemoteWorkBulkActionBar` is also Search's and
            // Browse's, where the selected works belong to other people and AO3's
            // bulk editor would 404. This one is gated on the works being yours.
            if showsBulkEdit {
                ToolbarItem(placement: .principal) {
                    Button { isBulkEditing = true } label: {
                        Label("Edit Multiple", systemImage: "square.and.pencil")
                    }
                    .disabled(bulkSelection.selection.isEmpty)
                    .accessibilityLabel("Edit selected works on AO3")
                }
            }
            RemoteWorkSelectionToolbar(controller: bulkSelection) {
                bulkSelection.selected(in: model.works)
            }
        } else {
            ActionToolbar(items: [AnyView(profileMenu)])
        }
    }

    private var profileMenu: some View {
        Menu {
            Button { router.open(model.route.dashboardURL) } label: {
                Label("Open on AO3", systemImage: "safari")
            }
            ShareLink(item: model.route.dashboardURL) {
                Label("Share Profile", systemImage: "square.and.arrow.up")
            }

            ForEach(visibleWebActions) { action in
                Button { router.open(action.url) } label: {
                    Label(action.label, systemImage: actionSymbol(action.kind))
                }
            }

            if !showsDashboard, model.selectedTab == .works, !model.works.isEmpty {
                Divider()
                Button { bulkSelection.isSelecting = true } label: {
                    Label("Select Works", systemImage: "checklist")
                }
            }
            if showsDashboard || (!currentContentIsEmpty && model.selectedTab != .about) {
                Divider()
                DisplayModeMenuPicker(mode: $displayMode)
                // Expand All acts on cards, so it has nothing to do in Compact.
                if displayMode != .compact {
                    ExpandAllMenuItem(expandAll: $expandAll)
                }
            }
            if showsDashboard {
                Button { dashboardDestination = .about } label: {
                    Label("About", systemImage: "person.text.rectangle")
                }
            }
        } label: {
            Label("Author actions", systemImage: "ellipsis")
        }
    }

    /// Own-profile management links only — Mute/Block live next to Subscribe in the hero.
    private var visibleWebActions: [AO3AuthorWebAction] {
        guard isOwnProfile else { return [] }
        let values = (model.header?.actions ?? []) + (model.about?.actions ?? [])
        let allowed: Set<AO3AuthorWebAction.Kind> = [
            .profile, .pseuds, .works, .preferences, .dashboard
        ]
        var seen = Set<String>()
        return values.filter {
            allowed.contains($0.kind) && seen.insert($0.url.absoluteString).inserted
        }
    }

    private var muteAction: AO3AuthorWebAction? {
        firstWebAction(kind: .mute)
    }

    private var blockAction: AO3AuthorWebAction? {
        firstWebAction(kind: .block)
    }

    private func firstWebAction(kind: AO3AuthorWebAction.Kind) -> AO3AuthorWebAction? {
        let values = (model.header?.actions ?? []) + (model.about?.actions ?? [])
        return values.first { $0.kind == kind }
    }

    private func actionSymbol(_ kind: AO3AuthorWebAction.Kind) -> String {
        switch kind {
        case .block: "hand.raised"
        case .mute: "speaker.slash"
        case .profile: "person.text.rectangle"
        case .pseuds: "person.2"
        case .works: "doc.text"
        case .preferences: "slider.horizontal.3"
        case .dashboard: "rectangle.grid.2x2"
        case .other: "safari"
        }
    }

    private var currentContentIsEmpty: Bool {
        switch model.selectedTab {
        case .works: model.works.isEmpty
        case .series: model.series.isEmpty
        case .bookmarks: model.bookmarks.isEmpty
        case .about: model.about == nil
        }
    }

}
