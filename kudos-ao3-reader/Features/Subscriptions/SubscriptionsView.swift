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
                            // An empty deck would read as "Nothing new to you", which is a loaded result.
                            NewToYouCardsView(works: [], showsEmptyState: false)
                                .overlay {
                                    ContentUnavailableView {
                                        Label("Source not connected", systemImage: "sparkles")
                                    } description: {
                                        Text(
                                            "Kudos has no new works to show until a source is connected."
                                        )
                                    } actions: {
                                        NavigationLink("Update sources") {
                                            SubscriptionsSourcesView()
                                        }
                                    }
                                }
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
            disconnectedWaiting
        }
        #else
        disconnectedWaiting
        #endif
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
                    works: works,
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
    @State private var showingScan = false
    #if os(iOS)
    @Environment(MailSubscriptionDriver.self) private var mailDriver
    #endif

    var body: some View {
        updateSources
            .navigationDestination(isPresented: $showingScan) {
                ColdStartScanView(
                    progress: .init(),
                    unavailableReason: "The paced AO3 scan driver is not connected yet."
                )
            }
    }

    @ViewBuilder
    private var updateSources: some View {
        #if os(iOS)
        UpdateSourcesView(
            onScanAO3: { showingScan = true },
            mailConnected: mailDriver.isConnected,
            onConnectMail: { address, password in
                try await mailDriver.connect(address: address, appPassword: password)
            },
            onDisconnectMail: { try mailDriver.disconnect() }
        )
        #else
        UpdateSourcesView(onScanAO3: { showingScan = true })
        #endif
    }
}

#Preview {
    let view = NavigationStack { SubscriptionsView() }
        .environment(AO3AuthService())
        .environment(ThemeManager())
    #if os(iOS)
    view.environment(MailSubscriptionDriver())
    #else
    view
    #endif
}
