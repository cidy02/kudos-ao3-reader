import SwiftUI

/// The app's top-level sections.
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case home, library, browse, account, search

    var id: String { rawValue }

    /// The four core tabs in the main tab bar / sidebar. `search` is a global action
    /// presented separately (the iOS search-role slot / a macOS sidebar button);
    /// Settings and the old Bookmarks lists now live inside Account.
    static let mainTabs: [AppTab] = [.home, .library, .browse, .account]

    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .browse: "Browse"
        case .account: "Account"
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .browse: "safari"
        case .account: "person.crop.circle"
        case .search: "magnifyingglass"
        }
    }
}

/// A request to filter the Library by a single tag, handed across tabs (e.g. from
/// a work's detail page). Mirrors `pendingURL` for the Browse tab.
struct LibraryTagFilter: Equatable {
    enum Field { case userTag, fandom, character, relationship, additional }
    let field: Field
    let value: String
}

/// A request to run an AO3 search for a single tag, handed to the Search tab (e.g.
/// from a tapped fandom/character/relationship/freeform chip).
struct AO3TagSearch: Equatable {
    enum Field { case warning, fandom, character, relationship, freeform }
    let field: Field
    let value: String
}

/// Shared navigation state so other tabs can hand a URL to the browser and
/// switch to it (e.g. opening a saved bookmark).
@Observable
final class AppRouter {
    var selection: AppTab = .home {
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
    /// A tag the Library should filter by on its next appearance (e.g. tapped on a
    /// work's detail page). Consumed + cleared by `LibraryView`.
    var pendingLibraryTag: LibraryTagFilter?
    /// A tag the Search tab should search AO3 for (e.g. a tapped fandom/character/
    /// relationship chip). Consumed + cleared by `SearchView`.
    var pendingTagSearch: AO3TagSearch?

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

    /// Switches to the Library and filters it to works containing `value` in `field`.
    func filterLibrary(_ field: LibraryTagFilter.Field, _ value: String) {
        pendingLibraryTag = LibraryTagFilter(field: field, value: value)
        selection = .library
    }

    /// Switches to Search and runs an AO3 search for `value` in the given tag `field`
    /// (a tapped fandom/character/relationship/freeform chip → "more works with this").
    func searchAO3(_ field: AO3TagSearch.Field, _ value: String) {
        pendingTagSearch = AO3TagSearch(field: field, value: value)
        selection = .search
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
