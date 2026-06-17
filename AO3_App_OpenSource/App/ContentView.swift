import SwiftUI
import SwiftData

/// Root of the app. On macOS it's a sidebar split with the Settings button pinned
/// at the bottom of the sidebar; on iOS it's an adaptive tab bar / sidebar.
struct ContentView: View {
    @State private var router = AppRouter()
    @State private var privacyGate = PrivacyGate()
    @State private var theme = ThemeManager()

    var body: some View {
        content
            .environment(router)
            .environment(privacyGate)
            .environment(theme)
            // The app theme drives the whole app's light/dark appearance (the reader
            // overrides this for itself when its theme is unlinked).
            .preferredColorScheme(theme.appTheme.colorScheme)
            // Sepia has no system scheme, so it also re-tints controls/links warm.
            // Light/Dark return nil here and keep the default accent.
            .tint(theme.appTheme.appTint)
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
        .modelContainer(for: [SavedWork.self, Tag.self, Bookmark.self, CustomFont.self], inMemory: true)
}
