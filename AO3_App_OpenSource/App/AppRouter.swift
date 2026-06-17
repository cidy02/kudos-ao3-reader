import SwiftUI

/// The app's top-level sections.
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case search, browse, library, bookmarks, settings

    var id: String { rawValue }

    /// The tabs shown in the main tab bar / sidebar. Settings is presented
    /// separately: a trailing search-style button on iOS, a sidebar footer on macOS.
    static let mainTabs: [AppTab] = [.search, .browse, .library, .bookmarks]

    var title: String {
        switch self {
        case .search: "Search"
        case .browse: "Browse"
        case .library: "Library"
        case .bookmarks: "Bookmarks"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .browse: "safari"
        case .library: "books.vertical"
        case .bookmarks: "bookmark"
        case .settings: "gearshape"
        }
    }
}

/// Shared navigation state so other tabs can hand a URL to the browser and
/// switch to it (e.g. opening a saved bookmark).
@Observable
final class AppRouter {
    var selection: AppTab = .search {
        didSet {
            // Remember where we came from so the focused Search mode's Back button
            // can return there (iOS). Never record Search itself as the target.
            if oldValue != .search { lastNonSearchTab = oldValue }
        }
    }
    /// The tab the focused Search mode returns to when its Back button is tapped.
    var lastNonSearchTab: AppTab = .library
    /// A URL the Browse tab should load on its next appearance.
    var pendingURL: URL?

    /// The one right-hand inspector panel open anywhere in the app. Routing every
    /// panel (Settings, Search filters, Reader chapters/display) through a single
    /// shared value guarantees only one inspector is ever presented at a time —
    /// two presented simultaneously crash AppKit's layout.
    var panel: Panel = .none

    enum Panel: Equatable {
        case none, settings, searchFilters, libraryFilters, readerChapters, readerDisplay
    }

    /// Opens a URL in the Browse tab.
    func open(_ url: URL) {
        pendingURL = url
        selection = .browse
    }

    /// Leaves the focused Search mode, returning to the last non-Search tab.
    func exitSearch() {
        selection = lastNonSearchTab
    }

    /// Toggles a panel open/closed (opening it closes any other).
    func toggle(_ p: Panel) {
        panel = (panel == p) ? .none : p
    }

    /// A Bool binding for `.inspector(isPresented:)` that's true while `p` is open.
    func isShowing(_ p: Panel) -> Binding<Bool> {
        Binding(get: { self.panel == p }, set: { self.panel = $0 ? p : .none })
    }
}
