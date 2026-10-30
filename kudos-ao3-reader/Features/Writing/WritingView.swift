import SwiftData
import SwiftUI

/// The signed-in creator launchpad introduced by T-460. Every figure and row is
/// backed by an AO3 page the app already reads; there are no synthetic goals,
/// streaks, or challenge deadlines.
struct WritingView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AO3InboxModel.self) private var inboxModel
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Query(filter: #Predicate<SavedWork> { !$0.isPendingDeletion }) private var localWorks: [SavedWork]

    @State private var path = NavigationPath()
    @State private var profileModel: AO3AuthorProfileModel?
    @State private var stats: AO3UserStats?
    @State private var statsError: String?
    @State private var isLoadingStats = false
    @State private var statsReload = 0
    @State private var activeStatsRequestID: UUID?
    @State private var drafts: AO3DraftsPage?
    @State private var draftsError: String?
    @State private var isLoadingDrafts = false
    @State private var draftsReload = 0
    @State private var editingWorkID: Int?
    @State private var postingPseudName: String?
    @State private var showingLogin = false

    private enum Destination: Hashable {
        case inbox
        case stats
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if auth.isLoggedIn {
                    identitySection
                    draftSection
                    statsSection
                    commentsSection
                    worksSection
                    writingLinksSection
                } else {
                    signedOutSection
                }
            }
            .cardList()
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle("Writing")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inlineLarge)
            #endif
            // Not `subjectScreenWash`: that hides the tab bar, for pushed screens.
            // This is a tab root, so there would be no way out of it.
            .subjectScreenSurface(.content, palette: theme.scopePalette)
            .hidesNavigationBarChrome()
            .navigationDestination(for: WritingRoute.self, destination: writingDestination)
            .navigationDestination(item: $editingWorkID) {
                WritingWorkDestination(workID: $0) { draftsReload += 1 }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .inbox: inboxDestination
                case .stats: WritingStatsView()
                }
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
            .toolbar {
                if auth.isLoggedIn {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            WritingWorkDestination(workID: nil) { draftsReload += 1 }
                        } label: {
                            Label("New Work", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingLogin) { AO3LoginView() }
            #if DEBUG
            .task {
                try? await Task.sleep(for: .seconds(1.5))
                DebugLaunchRoute.applyWriting(to: &path)
                editingWorkID = DebugLaunchRoute.accountEditWorkID
            }
            #endif
            .task(id: activationKey) { await activate() }
            .task(id: statsActivationKey) { await loadStats() }
            .onChange(of: auth.username, initial: true) { _, _ in syncProfileModel() }
            .onChange(of: router.pendingWritingRoute, initial: true) { _, route in
                guard let route else { return }
                path = NavigationPath()
                path.append(route)
                router.pendingWritingRoute = nil
            }
            .refreshable { await refresh() }
            .onDisappear { profileModel?.cancel() }
        }
    }

    private var activationKey: String {
        "\(router.selection == .writing)|\(auth.sessionGeneration)|\(auth.username ?? "")|\(draftsReload)"
    }

    private var identitySection: some View {
        Section {
            WritingPseudMenu(
                profileModel: profileModel,
                postingPseudName: $postingPseudName
            )
            .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
        } header: {
            SectionRuleHeader(title: auth.username ?? "AO3 Account")
                .pageBodyRow(top: 14, gutter: 0)
        }
    }

    @ViewBuilder
    private var draftSection: some View {
        Section {
            if let draft = latestDraft {
                NavigationLink {
                    WritingWorkDestination(workID: draft.id) { draftsReload += 1 }
                } label: {
                    WritingDraftHero(work: draft)
                }
                .buttonStyle(.plain)
                .cardRow(tintHue: CoverArt.workHue(fandoms: draft.fandoms, title: draft.title))
            } else if isLoadingDrafts {
                ProgressView("Loading drafts…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardRow()
            } else if let draftsError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(draftsError).font(.footnote).foregroundStyle(.secondary)
                    Button("Try Again") { draftsReload += 1 }
                }
                .cardRow()
            } else {
                Button {
                    path.append(WritingRoute.drafts)
                } label: {
                    AccountNavCardLabel(title: "No drafts on AO3", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.plain)
                .accountControlCardRow()
            }
        } header: {
            SectionRuleHeader(
                title: "Last Edited Draft",
                onSeeAll: { path.append(WritingRoute.drafts) }
            )
            .pageBodyRow(top: 18, gutter: 0)
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        Section {
            switch inboxModel.phase {
            case .idle, .loading:
                ProgressView("Loading comments…").frame(maxWidth: .infinity, alignment: .leading)
                    .cardRow()
            case let .failed(message):
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .cardRow()
            case .loaded, .paginationFailed:
                if newComments.isEmpty {
                    Text("No unread comments in your AO3 Inbox.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .cardRow()
                } else {
                    ForEach(newComments.prefix(3)) { item in
                        Button { openInboxItem(item) } label: {
                            WritingCommentPreviewRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .cardRow()
                    }
                }
            }
        } header: {
            SectionRuleHeader(
                title: "New Comments",
                count: inboxModel.unreadCount,
                onSeeAll: { path.append(Destination.inbox) }
            )
            .pageBodyRow(top: 18, gutter: 0)
        }
    }

    @ViewBuilder
    private var worksSection: some View {
        Section {
            if recentWorks.isEmpty {
                if profileModel?.contentPhase == .loading || profileModel?.headerPhase == .loading {
                    ForEach(0 ..< 2, id: \.self) { _ in
                        AO3WorkRowSkeleton().cardRow(chrome: .plain)
                    }
                } else {
                    Text("Your posted works will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .cardRow()
                }
            } else {
                ForEach(recentWorks) { work in
                    AO3WorkRow(
                        work: work,
                        presentation: .searchLedger,
                        showsPerformance: true
                    )
                    .cardNavigation(to: work, accessibilityLabel: work.title)
                    .cardRow(chrome: .plain)
                }
            }
        } header: {
            SectionRuleHeader(
                title: "Your Works",
                countText: cachedCount(.myWorks),
                onSeeAll: { path.append(WritingRoute.works) }
            )
            .pageBodyRow(top: 18, gutter: 0)
        }
    }

    private var writingLinksSection: some View {
        Section {
            VStack(spacing: 0) {
                writingLink(.drafts, title: "Drafts", symbol: "doc.badge.clock", count: draftCount)
                SubjectRowSeparator()
                writingLink(.series, title: "Series", symbol: "square.stack.3d.up", count: cachedCount(.series))
                SubjectRowSeparator()
                writingLink(
                    .collectionsAndChallenges,
                    title: "Collections & Challenges",
                    symbol: "person.3.sequence",
                    count: cachedCount(.collections)
                )
            }
            .subjectPanel()
            .pageBodyRow(top: 10, gutter: SubjectMetrics.accountGutter)
        } header: {
            SectionRuleHeader(title: "Manage")
                .pageBodyRow(top: 18, gutter: 0)
        }
    }

    private var signedOutSection: some View {
        Section {
            ContentUnavailableView(
                "Log in to write",
                systemImage: "square.and.pencil",
                description: Text("Sign in to AO3 to continue drafts, read comments, and manage your works.")
            )
            Button("Log In") { showingLogin = true }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .pageBodyRow(top: 12, gutter: SubjectMetrics.accountGutter)
        }
    }

    private func writingLink(
        _ route: WritingRoute, title: String, symbol: String, count: String?
    ) -> some View {
        Button { path.append(route) } label: {
            AccountNavCardLabel(title: title, systemImage: symbol, count: count)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func writingDestination(_ route: WritingRoute) -> some View {
        switch route {
        case .works: ownProfile(title: "Works", tab: .works)
        case .drafts: WritingDraftsView()
        case .series: ownProfile(title: "Series", tab: .series)
        case .collectionsAndChallenges: AO3CollectionsList()
        }
    }

    @ViewBuilder
    private func ownProfile(title: String, tab: AO3AuthorProfileTab) -> some View {
        if let username = auth.username, let route = AO3AuthorRoute(username: username) {
            AuthorProfileView(route: route, navigationTitle: title, initialTab: tab)
        } else {
            ContentUnavailableView("Not signed in", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    private var inboxDestination: some View {
        AccountInboxScreen(
            model: inboxModel,
            onOpen: openInboxItem,
            onReply: openInboxReply,
            onOpenChapter: openInboxChapter,
            workContext: knownWorkContext,
            metadataTaskID: inboxMetadataTaskID,
            onEnrichVisible: enrichVisibleInboxWorkContexts
        )
        .onAppear { inboxModel.activate(auth: auth) }
    }

    private var latestDraft: AO3WorkSummary? {
        drafts?.page.works.first
    }

    private var draftCount: String? {
        guard let page = drafts?.page else { return nil }
        if let total = page.summary?.total { return total.formatted() }
        return page.totalPages == 1 ? page.works.count.formatted() : nil
    }

    private var recentWorks: [AO3WorkSummary] {
        Array((profileModel?.works ?? []).prefix(3))
    }

    private var newComments: [AO3InboxItem] {
        inboxModel.items.filter(\.isUnread)
    }

    private func cachedCount(_ kind: AO3AccountListKind) -> String? {
        AO3AccountListCountsCache.shared.count(
            for: kind,
            authenticationScope: AO3AuthorProfileFetcher.sessionScopedCacheScope(for: auth)
        )?.displayText
    }

    private func syncProfileModel() {
        guard let username = auth.username, let route = AO3AuthorRoute(username: username) else {
            profileModel = nil
            drafts = nil
            postingPseudName = nil
            return
        }
        if profileModel?.route.username.localizedCaseInsensitiveCompare(username) != .orderedSame {
            profileModel = AO3AuthorProfileModel(route: route)
        }
        postingPseudName = auth.preferredPostingPseudName
        profileModel?.activate(auth: auth)
    }

    private func activate() async {
        guard router.selection == .writing else { return }
        syncProfileModel()
        inboxModel.activate(auth: auth)
        await loadDrafts()
    }

    private func refresh() async {
        guard auth.isLoggedIn else { return }
        if let profileModel { await profileModel.refresh(auth: auth) }
        await inboxModel.refresh(auth: auth)
        await loadDrafts()
        await loadStats()
    }

    private func loadDrafts() async {
        guard auth.isLoggedIn else {
            drafts = nil
            draftsError = nil
            return
        }
        let generation = auth.sessionGeneration
        isLoadingDrafts = true
        draftsError = nil
        do {
            let loaded = try await auth.loadDrafts(page: 1)
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            drafts = loaded
        } catch {
            guard !Task.isCancelled, generation == auth.sessionGeneration else { return }
            draftsError = UserFacingError.message(for: error)
        }
        isLoadingDrafts = false
    }

    private var inboxMetadataTaskID: String {
        let ids = inboxModel.items.compactMap(\.workID).map(String.init).joined(separator: ",")
        return "\(auth.sessionGeneration)|\(inboxModel.metadataRevision)|\(ids)"
    }

    private func enrichVisibleInboxWorkContexts() async {
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

private extension WritingView {
    var statsActivationKey: String {
        "\(router.selection == .writing)|\(auth.sessionGeneration)|\(auth.username ?? "")|\(statsReload)"
    }

    @ViewBuilder
    var statsSection: some View {
        Section {
            if let stats, !stats.isEmpty {
                Button { path.append(Destination.stats) } label: {
                    WritingStatsTotalsPanel(stats: stats)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open stats by work, All Years")
                .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
            } else if isLoadingStats {
                ProgressView("Loading stats…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardRow()
            } else if let statsError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(statsError).font(.footnote).foregroundStyle(.secondary)
                    Button("Try Again") { statsReload += 1 }
                }
                .cardRow()
            } else {
                Text("AO3 has no posted-work statistics yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .cardRow()
            }
        } header: {
            SectionRuleHeader(
                title: "Stats",
                countText: "All Years",
                onSeeAll: { path.append(Destination.stats) }
            )
            .pageBodyRow(top: 18, gutter: 0)
        }
    }

    func loadStats() async {
        guard router.selection == .writing, auth.isLoggedIn else {
            stats = nil
            statsError = nil
            isLoadingStats = false
            return
        }
        let requestID = UUID()
        activeStatsRequestID = requestID
        isLoadingStats = true
        statsError = nil
        stats = nil
        defer {
            if activeStatsRequestID == requestID { isLoadingStats = false }
        }
        do {
            let loaded = try await auth.loadUserStats()
            guard activeStatsRequestID == requestID, !Task.isCancelled else { return }
            stats = loaded
        } catch is CancellationError {
            return
        } catch {
            guard activeStatsRequestID == requestID, !Task.isCancelled else { return }
            statsError = UserFacingError.message(for: error)
        }
    }
}

private struct WritingDraftHero: View {
    let work: AO3WorkSummary

    @Environment(ThemeManager.self) private var theme
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 25

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SubjectKicker(
                text: "Continue",
                palette: theme.appTheme.subjectPalette(
                    hue: CoverArt.workHue(fandoms: work.fandoms, title: work.title)
                ),
                ruleWidth: 34,
                ruleSpacing: 7
            )
            Text(work.title.isEmpty ? "Untitled" : work.title)
                .font(.system(size: titleSize, weight: .bold, design: .serif))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !work.fandoms.isEmpty {
                Text(work.fandoms.map(FandomDisplayName.bareTitle).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                if !work.dateUpdated.isEmpty { Label(work.dateUpdated, systemImage: "clock") }
                if let words = work.words { Text("\(words.formatted()) words") }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct WritingCommentPreviewRow: View {
    let item: AO3InboxItem

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            AO3AuthorAvatar(
                url: item.avatarURL,
                name: item.commenterName,
                size: 38,
                isCircular: true
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(.accentFill).frame(width: 7, height: 7)
                    Text(item.commenterName).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(item.postedAgo).font(.caption2).foregroundStyle(.tertiary)
                }
                if !item.subjectTitle.isEmpty {
                    Text(item.subjectTitle).font(.footnote.weight(.medium)).lineLimit(1)
                }
                if !item.excerpt.isEmpty {
                    Text(item.excerpt).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

private struct WritingPseudMenu: View {
    var profileModel: AO3AuthorProfileModel?
    @Binding var postingPseudName: String?

    @Environment(AO3AuthService.self) private var auth

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Posting as").font(.caption).foregroundStyle(.secondary)
                Menu {
                    Button {
                        setPseud(nil)
                    } label: {
                        Label("Account Default", systemImage: postingPseudName == nil ? "checkmark" : "person")
                    }
                    ForEach(availablePseuds) { pseud in
                        Button {
                            setPseud(pseud.name)
                        } label: {
                            Label(
                                pseud.name,
                                systemImage: postingPseudName == pseud.name ? "checkmark" : "person"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(postingPseudName ?? auth.username ?? "Account Default")
                            .font(.headline)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .accessibilityElement(children: .contain)
    }

    private var availablePseuds: [AO3AuthorPseud] {
        var pseuds = profileModel?.header?.pseuds ?? []
        if let selected = postingPseudName,
           !pseuds.contains(where: { $0.name.localizedCaseInsensitiveCompare(selected) == .orderedSame }),
           let username = auth.username,
           let route = AO3AuthorRoute(username: username, pseud: selected) {
            pseuds.append(AO3AuthorPseud(name: selected, route: route, avatarURL: nil))
        }
        return pseuds
    }

    private func setPseud(_ name: String?) {
        postingPseudName = name
        auth.setPreferredPostingPseudName(name)
    }
}
