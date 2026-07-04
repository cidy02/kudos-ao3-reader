import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Root of the app. On macOS it's a sidebar split with the Settings button pinned
/// at the bottom of the sidebar; on iOS it's an adaptive tab bar / sidebar.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var folderSyncWorks: [SavedWork]
    @Query private var folderSyncBookmarks: [Bookmark]
    @Query private var folderSyncFonts: [CustomFont]
    @Query private var folderSyncCollections: [WorkCollection]
    @Query private var folderSyncQueues: [ReadingQueue]
    @Query private var folderSyncMemberships: [ReadingQueueMembership]
    @Query private var folderSyncTombstones: [SyncTombstone]
    @State private var router = AppRouter()
    @State private var privacyGate = PrivacyGate()
    @State private var theme = ThemeManager()
    @State private var auth = AO3AuthService()
    @State private var downloadQueue = DownloadQueue()
    @State private var folderSyncUpTask: Task<Void, Never>?

    /// First-launch onboarding gate, persisted locally.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Shake-to-report bug reporter (also reachable from Settings → About).
    @State private var showingBugReport = false
    #if os(iOS)
    /// The screen snapshot grabbed at shake time, offered for attaching to the report.
    @State private var bugReportScreenshot: UIImage?
    #endif

    var body: some View {
        content
            // Overlay first so the environments below wrap it too — otherwise the
            // banner sits outside the .environment scope and can't find the queue.
            .overlay(alignment: .bottom) { DownloadQueueBanner() }
            .environment(router)
            .environment(privacyGate)
            .environment(theme)
            .environment(auth)
            .environment(downloadQueue)
            // The app theme drives the whole app's light/dark appearance (the reader
            // overrides this for itself when its theme is unlinked).
            .preferredColorScheme(theme.appTheme.colorScheme)
            // App accent: Sepia keeps its warm brown; Light/Dark use the user's
            // accent colour (default AO3 red).
            .tint(theme.effectiveTint)
            // Segmented controls (UISegmentedControl) draw a white selected segment
            // in Sepia's light scheme; warm them via the appearance proxy. Reset for
            // Light/Dark. `initial` covers launch; new controls pick it up on change.
            .onChange(of: theme.appTheme, initial: true) { _, appTheme in
                applySegmentedControlAppearance(for: appTheme)
            }
            .task {
                await auth.restoreSession()
                ReadingQueueService.ensureSavedForLaterQueue(in: modelContext)
                ReadingQueueService.normalizeAllQueuedWorks(in: modelContext)
                await PersistenceMigrationService.runIfNeeded(in: modelContext)
                _ = try? await FolderSyncService.syncDown(in: modelContext)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    Task { @MainActor in
                        _ = try? await FolderSyncService.syncDown(in: modelContext)
                    }
                case .inactive, .background:
                    folderSyncUpTask?.cancel()
                    Task { @MainActor in
                        _ = try? await FolderSyncService.syncUp(in: modelContext)
                    }
                @unknown default:
                    break
                }
            }
            .onChange(of: folderSyncChangeToken) { _, _ in
                scheduleFolderSyncUp()
            }
            // Shake the device to report a bug, from anywhere in the app (iOS).
            .onShake {
                #if os(iOS)
                // Grab the screen now, before the report sheet covers it.
                bugReportScreenshot = ScreenshotCapture.captureKeyWindow()
                #endif
                showingBugReport = true
            }
            .sheet(isPresented: $showingBugReport) {
                #if os(iOS)
                BugReportView(screenshot: bugReportScreenshot)
                #else
                BugReportView()
                #endif
            }
        // First-launch welcome, shown before normal navigation. The theme is
        // re-injected because presented covers/sheets don't inherit it here.
        #if os(iOS)
            .fullScreenCover(isPresented: onboardingPresented) {
                WelcomeView(onContinue: { hasCompletedOnboarding = true })
                    .environment(theme)
                    .tint(theme.effectiveTint)
            }
        #else
            .sheet(isPresented: onboardingPresented) {
                WelcomeView(onContinue: { hasCompletedOnboarding = true })
                    .environment(theme)
                    .tint(theme.effectiveTint)
            }
        #endif
    }

    /// Presents onboarding until the user completes it (persisted via `@AppStorage`).
    private var onboardingPresented: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )
    }

    private var folderSyncChangeToken: String {
        [
            "\(folderSyncWorks.count):\(newestDate(folderSyncWorks.map(\.lastModifiedAt)))",
            "\(folderSyncBookmarks.count):\(newestDate(folderSyncBookmarks.map(\.dateAdded)))",
            "\(folderSyncFonts.count):\(newestDate(folderSyncFonts.map(\.dateAdded)))",
            "\(folderSyncCollections.count):\(newestDate(folderSyncCollections.map(\.lastModifiedAt)))",
            "\(folderSyncQueues.count):\(newestDate(folderSyncQueues.map(\.dateUpdated)))",
            "\(folderSyncMemberships.count):\(newestDate(folderSyncMemberships.map(\.lastModifiedAt)))",
            "\(folderSyncTombstones.count):\(newestDate(folderSyncTombstones.map(\.lastModifiedAt)))"
        ].joined(separator: "|")
    }

    private func newestDate(_ dates: [Date]) -> TimeInterval {
        dates.max()?.timeIntervalSince1970 ?? 0
    }

    private func scheduleFolderSyncUp() {
        guard FolderSyncService.snapshot().isConnected else { return }
        folderSyncUpTask?.cancel()
        folderSyncUpTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await FolderSyncService.syncUp(in: modelContext)
        }
    }

    /// Warms `UISegmentedControl` for Sepia (resets to default for Light/Dark).
    private func applySegmentedControlAppearance(for theme: ReaderTheme) {
        #if canImport(UIKit)
        let proxy = UISegmentedControl.appearance()
        guard theme == .sepia else {
            proxy.selectedSegmentTintColor = nil
            proxy.backgroundColor = nil
            proxy.setTitleTextAttributes(nil, for: .normal)
            proxy.setTitleTextAttributes(nil, for: .selected)
            return
        }
        // Recessed warm track + raised light-cream selected segment + brown text.
        proxy.backgroundColor = UIColor(red: 0.886, green: 0.831, blue: 0.718, alpha: 1)
        proxy.selectedSegmentTintColor = UIColor(red: 0.992, green: 0.965, blue: 0.910, alpha: 1)
        let brown = UIColor(red: 0.357, green: 0.275, blue: 0.212, alpha: 1)
        proxy.setTitleTextAttributes([.foregroundColor: brown], for: .normal)
        proxy.setTitleTextAttributes([.foregroundColor: brown], for: .selected)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        sidebarSplit
        #else
        tabs
        #endif
    }

    /// The global Search action, shown as a sidebar footer (macOS) / tab accessory
    /// (visionOS). Settings now lives in the Account tab.
    private var searchButton: some View {
        Button {
            router.selection = .search
        } label: {
            Label("Search", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The detail content for the selected section.
    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .library: LibraryView()
        case .browse: BrowseView()
        case .account: AccountView()
        case .search: SearchView()
        }
    }

    // MARK: macOS — sidebar with Settings pinned at the bottom

    private var sidebarSplit: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(AppTab.mainTabs) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 280)
            .safeAreaInset(edge: .bottom) {
                searchButton
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        } detail: {
            destination(for: router.selection)
        }
    }

    private var sidebarSelection: Binding<AppTab?> {
        Binding(
            get: { router.selection },
            set: { if let new = $0 { router.selection = new } }
        )
    }

    // MARK: iOS — adaptive tab bar / sidebar

    private var tabs: some View {
        TabView(selection: $router.selection) {
            ForEach(AppTab.mainTabs) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    destination(for: tab)
                }
            }
            #if os(iOS)
            // Global Search uses iOS 26's search-role slot so the system lays it out
            // as a separate circular button beside the tab bar (the same relationship
            // Apple Books gives its Search button), distinct from the four core tabs.
            Tab(AppTab.search.title, systemImage: AppTab.search.symbol,
                value: AppTab.search, role: .search) {
                    destination(for: .search)
                }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(visionOS)
            .tabViewBottomAccessory {
                searchButton
            }
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self
        ], inMemory: true)
}
