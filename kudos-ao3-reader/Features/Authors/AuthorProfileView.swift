import SwiftData
import SwiftUI

struct AuthorProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme

    @State private var model: AO3AuthorProfileModel
    @State private var expandAll = false
    @State private var isSelecting = false
    @State private var selection = Set<Int>()
    @State private var isProcessingBatch = false
    @State private var batchTask: Task<Void, Never>?
    @State private var batchActionError: String?
    @State private var resolvedQueueWorks: [SavedWork] = []
    @State private var resolvedCollectionWorks: [SavedWork] = []
    @State private var showingAddToQueue = false
    @State private var showingAddToCollection = false
    @State private var confirmingUnsubscribe = false
    /// Signed-out Mute/Block/Subscribe — same prompt for all profile write actions.
    @State private var showingLoginRequired = false
    @State private var showingLogin = false
    /// Resume after the login sheet succeeds (cleared on cancel / failed login).
    @State private var pendingAuthAction: PendingAuthAction?
    /// Nav bar title. Account's **My Dashboard** reuses this surface for the
    /// signed-in user's home (`/users/:login`) under the title "Dashboard".
    private let navigationTitle: String

    init(route: AO3AuthorRoute, navigationTitle: String = "Author") {
        _model = State(initialValue: AO3AuthorProfileModel(route: route))
        self.navigationTitle = navigationTitle
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
            .sheet(isPresented: $showingAddToQueue) {
                AddToQueueView(works: resolvedQueueWorks)
            }
            .sheet(isPresented: $showingAddToCollection) {
                AddToCollectionView(works: resolvedCollectionWorks)
            }
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
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        showingLogin = true
                    }
                }
            } message: {
                Text("This action requires an AO3 account, log in first.")
            }
            .alert("Action Failed", isPresented: batchErrorPresented) {
                Button("OK", role: .cancel) { batchActionError = nil }
            } message: {
                Text(batchActionError ?? "")
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
                exitSelectMode()
                model.activate(auth: auth)
            }
            .onDisappear {
                model.cancel()
                batchTask?.cancel()
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
        AO3AuthorProfileFetcher.authenticationScope(for: auth)
    }

    private var profileList: some View {
        List {
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

            if let header = model.header, header.pseuds.count > 1 {
                Section {
                    pseudSelector(header.pseuds)
                        .cardRow()
                }
            }

            Section {
                Picker("Profile Content", selection: tabSelection) {
                    ForEach(AO3AuthorProfileTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .cardRow()
            }

            if model.isShowingStaleCache {
                Section {
                    Label("Showing cached AO3 data", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .cardRow()
                }
            }

            AO3AuthorFandomFilterSection(model: model, onWillChange: exitSelectMode)

            contentRows
        }
        .cardList()
        .refreshable { await model.refresh(auth: auth) }
    }

    private var tabSelection: Binding<AO3AuthorProfileTab> {
        Binding(
            get: { model.selectedTab },
            set: { tab in
                exitSelectMode()
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
                        exitSelectMode()
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
                        exitSelectMode()
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
                isSelecting: isSelecting,
                selection: selection,
                onToggleSelection: toggleSelection
            )
        case .series:
            AO3AuthorSeriesSection(model: model)
        case .bookmarks:
            AO3AuthorBookmarksSection(model: model, expandAll: expandAll)
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
                            exitSelectMode()
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
    private func toggleSelection(_ work: AO3WorkSummary) {
        if selection.contains(work.id) {
            selection.remove(work.id)
        } else {
            selection.insert(work.id)
        }
    }

    private var selectedSummaries: [AO3WorkSummary] {
        model.works.filter { selection.contains($0.id) }
    }

    private var isOwnProfile: Bool {
        auth.username?.localizedCaseInsensitiveCompare(model.route.username) == .orderedSame
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
            set: { if !$0 { model.cancelPendingModeration() } }
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

    private var batchErrorPresented: Binding<Bool> {
        Binding(
            get: { batchActionError != nil },
            set: { if !$0 { batchActionError = nil } }
        )
    }
}

private extension AuthorProfileView {
    // MARK: Toolbar and actions

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: exitSelectMode)
            }
            #if os(iOS)
            ToolbarItemGroup(placement: .bottomBar) { bulkActionBar }
            #else
            ToolbarItemGroup(placement: .primaryAction) { bulkActionBar }
            #endif
        } else {
            ToolbarItem(placement: .primaryAction) {
                profileMenu
            }
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

            if model.selectedTab == .works, !model.works.isEmpty {
                Divider()
                Button { isSelecting = true } label: {
                    Label("Select Works", systemImage: "checklist")
                }
            }
            if !currentContentIsEmpty, model.selectedTab != .about {
                ExpandAllMenuItem(expandAll: $expandAll)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Author actions")
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

    @ViewBuilder
    private var bulkActionBar: some View {
        Button {
            batchTask = Task { await bulkSave() }
        } label: {
            Label("Save", systemImage: "bookmark")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        Spacer()

        Button {
            batchTask = Task { await bulkSaveForLater() }
        } label: {
            Label("Save for Later", systemImage: "clock.arrow.circlepath")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        Spacer()

        Button {
            batchTask = Task { await bulkAddToCollection() }
        } label: {
            Label("Add to Collection", systemImage: "square.stack")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        Spacer()

        Button {
            batchTask = Task { await bulkAddToQueue() }
        } label: {
            Label("Add to Queue", systemImage: "list.bullet.rectangle")
        }
        .disabled(selection.isEmpty || isProcessingBatch)

        if isProcessingBatch { ProgressView().controlSize(.small) }
    }

    private func exitSelectMode() {
        isSelecting = false
        selection.removeAll()
    }

    private func bulkSave() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selectedSummaries, in: context) { works in
            for work in works { WorkLifecycle.setSaved(work, true, in: context) }
        }
    }

    private func bulkSaveForLater() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await bulkSaveForLaterRemote(selectedSummaries, in: context)
    }

    private func bulkAddToCollection() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selectedSummaries, in: context) { works in
            resolvedCollectionWorks = works
            showingAddToCollection = true
        }
    }

    private func bulkAddToQueue() async {
        guard !isProcessingBatch else { return }
        isProcessingBatch = true
        defer { isProcessingBatch = false }
        batchActionError = await resolveSelectedRemoteWorks(selectedSummaries, in: context) { works in
            resolvedQueueWorks = works
            showingAddToQueue = true
        }
    }
}
