import SwiftData
import SwiftUI
import WebKit
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
    @State private var lastForegroundFolderSyncAt: Date?

    /// Automatic sync triggers only run more than once a minute when the scene keeps
    /// flipping active (Control Center, quick app-switches); an explicit dirty change
    /// or a manual Sync Now still goes through immediately regardless of this gate.
    private static let foregroundSyncThrottle: TimeInterval = 60

    /// First-launch onboarding gate, persisted locally.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Library Sync Folder onboarding gates — separate from the welcome gate above so
    /// completing one never implies the other. Mirrors FolderSyncOnboardingState's keys
    /// so this view re-renders when either changes (a plain UserDefaults read wouldn't).
    @AppStorage(FolderSyncOnboardingState.configuredKey) private var hasConfiguredSyncFolder = false
    @AppStorage(FolderSyncOnboardingState.permanentlyDismissedKey)
    private var syncOnboardingDismissedPermanently = false
    /// In-memory only — dismissing without "Don't remind me again" should still let the
    /// user into the app for the rest of THIS launch, without touching either persisted
    /// flag above (so it reappears next launch, per the required behavior).
    @State private var dismissedSyncFolderOnboardingThisSession = false
    /// Shake-to-report bug reporter (also reachable from Settings → About).
    @State private var showingBugReport = false
    #if os(iOS)
    /// The screen snapshot grabbed at shake time, offered for attaching to the report.
    @State private var bugReportScreenshot: UIImage?
    #endif

    var body: some View {
        @Bindable var router = router
        content
            // Warms WebKit at launch instead of on first real use (the AO3 login
            // sheet, or Browse) — see WebKitPrewarmView.
            .background { WebKitPrewarmView() }
            // Overlay first so the environments below wrap it too — otherwise the
            // banner sits outside the .environment scope and can't find the queue.
            .overlay(alignment: .bottom) { DownloadQueueBanner() }
            // AO3 website sheet is root-hosted so `router.open` never switches the
            // user into Browse — Done returns them to the tab they left.
            .sheet(isPresented: $router.isPresentingWebBrowser) {
                AO3WebBrowserView()
            }
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
                // Independent of folder sync — a local Recently Deleted item past its
                // 90-day window is swept whether or not Auto Sync is even on.
                PreservedWorkService.sweepExpired(in: modelContext)
                // Backfills the derived search text for records that predate indexing,
                // arrived via an older backup, or were indexed under an older schema.
                await WorkSearchIndex.rebuildIfNeeded(in: modelContext)
                guard FolderSyncService.snapshot().autoSyncEnabled else { return }
                lastForegroundFolderSyncAt = Date()
                _ = try? await FolderSyncService.syncDown(in: modelContext)
                // Catches up anything a prior session's debounce lost to a force-quit —
                // the dirty flag is durable across launches, unlike the debounce Task.
                if FolderSyncService.snapshot().isDirty {
                    _ = try? await FolderSyncService.syncUp(in: modelContext)
                }
                #if os(iOS)
                FolderSyncBackgroundTask.scheduleNext()
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                guard FolderSyncService.snapshot().autoSyncEnabled else { return }
                switch phase {
                case .active:
                    let now = Date()
                    if let last = lastForegroundFolderSyncAt,
                       now.timeIntervalSince(last) < Self.foregroundSyncThrottle,
                       !FolderSyncService.snapshot().isDirty {
                        return
                    }
                    lastForegroundFolderSyncAt = now
                    Task { @MainActor in
                        _ = try? await FolderSyncService.syncDown(in: modelContext)
                    }
                case .inactive, .background:
                    folderSyncUpTask?.cancel()
                    #if os(iOS)
                    // Submitting right before backgrounding is the pattern most
                    // likely to actually get honored by the OS soon.
                    FolderSyncBackgroundTask.scheduleNext()
                    #endif
                    guard FolderSyncService.snapshot().isDirty else { return }
                    Task { @MainActor in
                        _ = try? await FolderSyncService.syncUp(in: modelContext)
                    }
                @unknown default:
                    break
                }
            }
            .onChange(of: folderSyncChangeToken) { _, _ in
                FolderSyncService.markDirty()
                scheduleFolderSyncUp()
            }
            // Settings that ship in the backup manifest (reader/privacy prefs) live in
            // SettingsView's own @AppStorage bindings — it marks sync dirty itself via
            // NotificationCenter since it isn't always mounted while ContentView is.
            .onReceive(NotificationCenter.default.publisher(for: .kudosSyncRelevantSettingChanged)) { _ in
                FolderSyncService.markDirty()
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
        // First-launch welcome, then (once that's done) sync-folder onboarding — never
        // both at once, never sync-onboarding in place of welcome. The theme is
        // re-injected because presented covers/sheets don't inherit it here.
        #if os(iOS)
            .fullScreenCover(isPresented: onboardingPresented) {
                WelcomeView(onContinue: { hasCompletedOnboarding = true })
                    .environment(theme)
                    .tint(theme.effectiveTint)
            }
            .fullScreenCover(isPresented: syncFolderOnboardingPresented) {
                SyncFolderOnboardingView(onFinished: { dismissedSyncFolderOnboardingThisSession = true })
                    .environment(theme)
                    .tint(theme.effectiveTint)
            }
        #else
            .sheet(isPresented: onboardingPresented) {
                WelcomeView(onContinue: { hasCompletedOnboarding = true })
                    .environment(theme)
                    .tint(theme.effectiveTint)
            }
            .sheet(isPresented: syncFolderOnboardingPresented) {
                SyncFolderOnboardingView(onFinished: { dismissedSyncFolderOnboardingThisSession = true })
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

    /// Presents once welcome is done and sync-folder onboarding hasn't been configured
    /// or permanently dismissed. Dismissing without "Don't remind me again" doesn't touch
    /// either persisted flag — `dismissedSyncFolderOnboardingThisSession` is what actually
    /// closes the cover for the rest of this launch, so it correctly reappears next time.
    private var syncFolderOnboardingPresented: Binding<Bool> {
        Binding(
            get: {
                hasCompletedOnboarding
                    && !hasConfiguredSyncFolder
                    && !syncOnboardingDismissedPermanently
                    && !dismissedSyncFolderOnboardingThisSession
            },
            set: { isPresented in
                if !isPresented { dismissedSyncFolderOnboardingThisSession = true }
            }
        )
    }

    /// Fingerprint of library content that should mark the sync folder dirty.
    ///
    /// Quantizes timestamps to whole seconds so high-frequency progress stamps
    /// (if any path still advances `lastModifiedAt` mid-read) cannot reschedule
    /// a full package `syncUp` many times per second. Debounced Readium writes
    /// deliberately leave `lastModifiedAt` alone; this is a second line of defense.
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
        // Floor to whole seconds: sub-second stamp churn is never a distinct
        // sync-worthy event for the full-package uploader.
        floor(dates.max()?.timeIntervalSince1970 ?? 0)
    }

    private func scheduleFolderSyncUp() {
        let snapshot = FolderSyncService.snapshot()
        guard snapshot.isConnected, snapshot.autoSyncEnabled else { return }
        folderSyncUpTask?.cancel()
        folderSyncUpTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await FolderSyncService.syncUp(in: modelContext)
        }
    }

    /// Warms `UISegmentedControl` for Sepia (resets to default for Light/Dark).
    /// Colors are bridged from `ReaderTheme`'s existing semantic surface/text
    /// tokens — the same ones `.appThemedRows()`/`.appThemedScroll()` use for
    /// every Sepia Form/List row — instead of restating their RGB values here, so
    /// this proxy can never silently drift out of sync with the rest of the Sepia
    /// palette.
    private func applySegmentedControlAppearance(for readerTheme: ReaderTheme) {
        #if canImport(UIKit)
        let proxy = UISegmentedControl.appearance()
        guard readerTheme == .sepia else {
            proxy.selectedSegmentTintColor = nil
            proxy.backgroundColor = nil
            proxy.setTitleTextAttributes(nil, for: .normal)
            proxy.setTitleTextAttributes(nil, for: .selected)
            return
        }
        // Recessed warm track + raised light-cream selected segment + brown text —
        // the same appBaseBackground/appElevatedBackground/textColor pairing every
        // other Sepia surface already uses (ReaderStyle.swift).
        proxy.backgroundColor = readerTheme.appBaseBackground.map(UIColor.init)
        proxy.selectedSegmentTintColor = readerTheme.appElevatedBackground.map(UIColor.init)
        let brown = UIColor(readerTheme.textColor)
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

/// Warms WebKit's shared WebContent/Networking process pool at launch instead of
/// on first real use. The very first `WKWebView` load in a process incurs a
/// one-time process spin-up that's markedly slower on Simulator and under this
/// app's ad-hoc "Sign to Run Locally" debug signing — several seconds, enough to
/// read as a freeze right after whichever screen first needs a webview (commonly
/// the AO3 login sheet, since Comments/Account don't otherwise use one). Loads a
/// local `about:blank` "page" — no network request, no AO3 traffic — in its own
/// throwaway webview that's entirely decoupled from `AO3AuthService`'s login
/// webview, so it can never race or get pulled away from it mid-login.
///
/// Needs a real window to avoid WebKit throttling/suspending an off-screen
/// content process (see the same concern noted in `AO3LoginView`), so this stays
/// mounted (tiny, invisible) for the app's lifetime rather than firing once and
/// tearing down — once warm, an idle 1×1 webview costs nothing further.
private struct WebKitPrewarmView: View {
    @State private var webView: WKWebView?

    var body: some View {
        Group {
            if let webView {
                WebView(webView: webView)
            }
        }
        .frame(width: 1, height: 1)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard webView == nil else { return }
            // Let the first frame settle before spending WebKit's spin-up cost,
            // so this never competes with cold-launch rendering itself.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, webView == nil else { return }
            let configuration = WKWebViewConfiguration()
            // Matches AO3WebLoginCoordinator's configuration so this also warms
            // the .default() datastore's on-disk cookie-store initialization.
            // (WKProcessPool sharing is a no-op on modern iOS — pools are shared
            // automatically — so we only pin the data store here.)
            configuration.websiteDataStore = .default()
            let created = WKWebView(frame: .zero, configuration: configuration)
            webView = created
            created.load(URLRequest(url: URL(string: "about:blank")!))
        }
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
