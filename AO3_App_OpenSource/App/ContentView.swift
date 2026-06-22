import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Root of the app. On macOS it's a sidebar split with the Settings button pinned
/// at the bottom of the sidebar; on iOS it's an adaptive tab bar / sidebar.
struct ContentView: View {
    @State private var router = AppRouter()
    @State private var privacyGate = PrivacyGate()
    @State private var theme = ThemeManager()
    @State private var auth = AO3AuthService()
    @State private var downloadQueue = DownloadQueue()

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
            .onChange(of: theme.appTheme, initial: true) { _, t in
                applySegmentedControlAppearance(for: t)
            }
            .task {
                await auth.restoreSession()
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

    /// The Settings button shown as a sidebar footer (macOS) / tab accessory (iOS).
    /// Toggles the Settings inspector rather than presenting a sheet.
    private var settingsButton: some View {
        Button {
            router.toggle(.settings)
        } label: {
            Label("Settings", systemImage: "gearshape")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The reading/display options, shown in the right inspector — consistent with
    /// the Reader's Chapters and Display Options panels.
    private var settingsInspector: some View {
        ReaderOptionsForm(includeAppSettings: true)
            .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
    }

    /// The detail content for the selected section.
    @ViewBuilder
    private func destination(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .search: SearchView()
        case .browse: BrowseView()
        case .library: LibraryView()
        case .bookmarks: BookmarksView()
        case .settings:
            NavigationStack {
                ReaderOptionsForm(includeAppSettings: true)
                    .navigationTitle("Settings")
            }
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
                settingsButton
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        } detail: {
            destination(for: router.selection)
                .inspector(isPresented: router.isShowing(.settings)) {
                    settingsInspector
                }
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
            // The Settings button uses iOS 26's search-role slot so the system
            // lays it out as a separate circular button beside the tab bar and
            // reserves space for it — the same relationship Apple Books gives its
            // Search button, instead of an overlay that grazes the last tab.
            Tab(AppTab.settings.title, systemImage: AppTab.settings.symbol,
                value: AppTab.settings, role: .search) {
                destination(for: .settings)
            }
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(visionOS)
        .inspector(isPresented: router.isShowing(.settings)) {
            settingsInspector
        }
        .tabViewBottomAccessory {
            settingsButton
        }
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [SavedWork.self, Tag.self, Bookmark.self, CustomFont.self, WorkCollection.self], inMemory: true)
}
