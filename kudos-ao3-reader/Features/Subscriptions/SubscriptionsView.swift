import SwiftData
import SwiftUI

/// One destination for subscription updates, followed works, and cleanup.
struct SubscriptionsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case waiting = "Waiting"
        case following = "Following"
        case tidyUp = "Tidy up"

        var id: String { rawValue }
    }

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private struct LoadKey: Hashable {
        let username: String?
        let isLoggedIn: Bool
        let reloadToken: Int
    }

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(SubscriptionScanService.self) private var scan
    @Environment(\.modelContext) private var modelContext
    #if os(iOS)
    @Environment(MailSubscriptionDriver.self) private var mailDriver
    #endif

    @State private var selectedTab = Tab.waiting
    @State private var works: [AO3WorkSummary] = []
    /// Session-only. Not stored: a new visit loads the AO3 page again.
    @State private var unfollowed = Set<Int>()
    @State private var phase = Phase.idle
    @State private var reloadToken = 0
    @State private var showingLogin = false

    private var loadKey: LoadKey {
        LoadKey(
            username: auth.username,
            isLoggedIn: auth.isLoggedIn,
            reloadToken: reloadToken
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Subscription section", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .frame(minHeight: 44)
            .padding(.horizontal, CardListMetrics.sideMargin)
            .padding(.vertical, 8)

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.appTheme.cardBackdrop.ignoresSafeArea())
        .hidesFloatingTabBar()
        .navigationTitle("Subscriptions")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        NavigationLink {
                            SubscriptionsSourcesView()
                        } label: {
                            Label("Update sources", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        NavigationLink {
                            newToYouDestination
                        } label: {
                            Label("New to you", systemImage: "sparkles")
                        }
                        NavigationLink {
                            AO3AccountWorksList(kind: .subscriptions)
                        } label: {
                            Label("All AO3 subscriptions", systemImage: "list.bullet")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .task(id: loadKey) {
                guard auth.isLoggedIn else {
                    works = []
                    phase = .idle
                    return
                }
                await loadFollowing()
            }
            .sheet(isPresented: $showingLogin) { AO3LoginView() }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .waiting:
            waitingContent
        case .following:
            followingContent(scope: .following)
        case .tidyUp:
            followingContent(scope: .tidyUp)
        }
    }

    /// An empty deck would read as "Nothing new to you", which is a loaded result,
    /// so a missing source keeps its own explanation on top of a blank deck.
    @ViewBuilder
    private var newToYouDestination: some View {
        #if os(iOS)
        if mailDriver.isConnected {
            NewToYouMailDeck()
        } else {
            disconnectedNewToYou
        }
        #else
        disconnectedNewToYou
        #endif
    }

    private var disconnectedNewToYou: some View {
        NewToYouCardsView(cards: [], showsEmptyState: false)
            .overlay {
                ContentUnavailableView {
                    Label("Source not connected", systemImage: "sparkles")
                } description: {
                    Text("Kudos has no new works to show until a source is connected.")
                } actions: {
                    NavigationLink("Update sources") {
                        SubscriptionsSourcesView()
                    }
                }
            }
    }

    @ViewBuilder
    private var waitingContent: some View {
        #if os(iOS)
        if mailDriver.isConnected {
            WaitingListView(
                updates: mailDriver.updates,
                showsEmptyState: false,
                mailSince: mailDriver.since,
                unverifiedCount: mailDriver.unverifiedCount,
                refreshError: mailDriver.errorMessage
            )
            .task { await mailDriver.refreshIfNeeded() }
            .refreshable { await mailDriver.refresh() }
        } else {
            scanOrDisconnectedWaiting
        }
        #else
        scanOrDisconnectedWaiting
        #endif
    }

    /// Mail wins while it is connected. Otherwise a scan that has already looked
    /// at follows shows those rows; a cold account keeps the source prompt.
    @ViewBuilder
    private var scanOrDisconnectedWaiting: some View {
        if showsScanWaiting {
            WaitingListView(
                updates: scan.updates,
                showsPosition: true,
                showsEmptyState: false,
                scanStatus: scanStatus,
                baselines: scan.partialBaselines,
                alphabeticalNote: scan.partialBaselines.isEmpty
                    ? nil
                    : SubscriptionScanCopy.alphabeticalHonesty,
                onCheck: canStartScan ? { startScan() } : nil
            )
        } else {
            disconnectedWaiting
        }
    }

    private var showsScanWaiting: Bool {
        scan.phase != .idle
            || !scan.file.followedWorkIDs.isEmpty
            || !scan.snapshots.isEmpty
            || !scan.updates.isEmpty
    }

    private var canStartScan: Bool {
        scan.phase != .running && scan.phase != .paused
    }

    private var scanStatus: WaitingScanStatus {
        let follows = scan.file.followedWorkIDs.count
        let followWord = follows == 1 ? "follow" : "follows"
        return WaitingScanStatus(
            checkedLabel: scan.latestCheckedAt.map {
                "Checked \($0.formatted(.relative(presentation: .named)))"
            },
            waitingCount: scan.updates.count,
            followsLine: "\(follows) \(followWord) · \(checkedFollows) checked",
            checkTitle: scan.dueCount > 0 ? "Check \(scan.dueCount)" : "Scan AO3",
            note: scan.statusNote
        )
    }

    private var checkedFollows: Int {
        switch scan.phase {
        case .running, .paused, .stopped:
            return scan.checked
        case .idle, .finished:
            return scan.snapshots.filter { scan.file.followedWorkIDs.contains($0.workID) }.count
        }
    }

    private func startScan() {
        SubscriptionScanLaunch.start(scan: scan, auth: auth, modelContext: modelContext)
    }

    private var disconnectedWaiting: some View {
        WaitingListView(updates: [], showsEmptyState: false)
            .overlay {
                ContentUnavailableView {
                    Label("Mail source not connected", systemImage: "envelope")
                } description: {
                    Text("Kudos has no Waiting updates to show until a mail source is connected.")
                } actions: {
                    NavigationLink("Update sources") {
                        SubscriptionsSourcesView()
                    }
                }
            }
    }

    @ViewBuilder
    private func followingContent(scope: FollowingListView.Scope) -> some View {
        if !auth.isLoggedIn {
            ContentUnavailableView {
                Label("AO3 Subscriptions", systemImage: "bell")
            } description: {
                Text("Log in to AO3 to see the works you subscribe to.")
            } actions: {
                Button("Log In to AO3") { showingLogin = true }
            }
        } else {
            switch phase {
            case .idle, .loading:
                ProgressView("Loading subscriptions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn't load subscriptions", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { reloadToken += 1 }
                }
            case .loaded:
                FollowingListView(
                    works: works.map { scan.applying($0) },
                    deletedIDs: scan.goneWorkIDs,
                    scope: scope,
                    sourceNote: "Showing the first AO3 page here. Use More → All AO3 subscriptions "
                        + "to browse every page.",
                    unfollowed: $unfollowed
                )
            }
        }
    }

    private func loadFollowing() async {
        phase = .loading
        do {
            // shortcut: load one AO3 page here, use the existing paged list when more pages are needed
            let loaded = try await auth.accountSubscriptions()
            guard !Task.isCancelled else { return }
            works = loaded
            phase = .loaded
        } catch is CancellationError {
            return
        } catch AO3Error.authenticationRequired {
            await auth.sessionDidExpire()
            works = []
            phase = .idle
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private struct SubscriptionsSourcesView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(SubscriptionScanService.self) private var scan
    @Environment(\.modelContext) private var modelContext
    @State private var showingScan = false
    #if os(iOS)
    @Environment(MailSubscriptionDriver.self) private var mailDriver
    #endif

    var body: some View {
        updateSources
            .navigationDestination(isPresented: $showingScan) {
                ColdStartScanView(
                    progress: ColdStartScanView.Progress(scan),
                    unavailableReason: auth.isLoggedIn
                        ? nil
                        : "Log in to AO3 to scan subscriptions.",
                    notice: scan.statusNote,
                    onStart: { startScan() },
                    onPause: { scan.pause() },
                    onResume: { scan.resume() },
                    onCancel: { scan.cancel() }
                )
            }
    }

    private func startScan() {
        guard auth.isLoggedIn else { return }
        SubscriptionScanLaunch.start(scan: scan, auth: auth, modelContext: modelContext)
    }

    @ViewBuilder
    private var updateSources: some View {
        #if os(iOS)
        UpdateSourcesView(
            onScanAO3: {
                startScan()
                showingScan = true
            },
            mailConnected: mailDriver.isConnected,
            onConnectMail: { address, password in
                try await mailDriver.connect(address: address, appPassword: password)
            },
            onDisconnectMail: { try mailDriver.disconnect() }
        )
        #else
        UpdateSourcesView(onScanAO3: {
            startScan()
            showingScan = true
        })
        #endif
    }
}

#Preview {
    let view = NavigationStack { SubscriptionsView() }
        .environment(AO3AuthService())
        .environment(ThemeManager())
        .environment(SubscriptionScanService())
    #if os(iOS)
    view.environment(MailSubscriptionDriver())
    #else
    view
    #endif
}

/// Reads a library snapshot at the moment the user starts a scan. The scan
/// never writes these works back.
@MainActor
private enum SubscriptionScanLaunch {
    static func start(
        scan: SubscriptionScanService,
        auth: AO3AuthService,
        modelContext: ModelContext
    ) {
        scan.start(
            username: auth.username ?? "",
            fetcher: LiveSubscriptionScanFetcher(auth: auth),
            library: libraryHints(in: modelContext)
        )
    }

    private static func libraryHints(
        in modelContext: ModelContext
    ) -> [Int: SubscriptionScanLibraryHint] {
        let works = (try? modelContext.fetch(FetchDescriptor<SavedWork>())) ?? []
        var hints: [Int: SubscriptionScanLibraryHint] = [:]
        for work in works where !work.isPendingDeletion {
            let id = work.ao3WorkID ?? WorkTags.ao3WorkID(from: work.sourceURL)
            guard let id else { continue }
            hints[id] = merged(
                hints[id],
                posted: SubscriptionScanWorkFacts.chapterCounts(work.chapters).posted,
                checked: work.lastUpdateCheck
            )
        }
        return hints
    }

    private static func merged(
        _ current: SubscriptionScanLibraryHint?,
        posted: Int?,
        checked: Date?
    ) -> SubscriptionScanLibraryHint {
        guard let current else {
            return SubscriptionScanLibraryHint(postedChapters: posted, lastChecked: checked)
        }
        let lastChecked: Date? = switch (current.lastChecked, checked) {
        case let (old?, new?): max(old, new)
        case let (old?, nil): old
        case let (nil, new?): new
        case (nil, nil): nil
        }
        return SubscriptionScanLibraryHint(
            postedChapters: posted ?? current.postedChapters,
            lastChecked: lastChecked
        )
    }
}
