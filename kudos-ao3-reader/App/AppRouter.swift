import SwiftUI

/// The app's top-level sections.
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case home, library, browse, account, search

    var id: String {
        rawValue
    }

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

/// A request to show a tag's works page natively (from a tapped AO3 link, e.g. in a
/// work's preface). `url` is AO3's own (already-munged) link; `title` is the readable
/// tag name for the screen title.
struct AO3TagWorksRequest: Hashable {
    let url: URL
    let title: String
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
    /// A tag's works page to show natively in Browse (e.g. an AO3 link tapped in a
    /// work's preface). Consumed + cleared by `BrowseView`.
    var pendingTagWorks: AO3TagWorksRequest?
    /// A verified account/pseud destination to push in the currently-selected tab's
    /// navigation stack. Every root stack consumes this through the shared author
    /// navigation modifier, so reader/comment/byline links use one route.
    var pendingAuthorProfile: AO3AuthorRoute?

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

    /// Routes an AO3 link (e.g. tapped in a work's preface) to the matching native
    /// action where one exists — a tag's `/tags/<name>/works` page opens a native
    /// works list — falling back to the in-app web view for everything else.
    func openAO3Link(_ url: URL) {
        if let author = Self.authorRoute(for: url) {
            openAuthorProfile(author)
            return
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        if (url.host ?? "").contains("archiveofourown.org"),
           parts.first == "tags", parts.count >= 2 {
            pendingTagWorks = AO3TagWorksRequest(url: url, title: Self.unmungeTag(parts[1]))
            selection = .browse
            return
        }
        open(url)
    }

    /// Pushes a verified author route without changing tabs. Keeping the current
    /// stack means a byline tap returns to the exact work, comment, or reader entry
    /// point on Back.
    func openAuthorProfile(_ route: AO3AuthorRoute) {
        pendingAuthorProfile = route
    }

    static func authorRoute(for url: URL) -> AO3AuthorRoute? {
        AO3AuthorRoute(url: url)
    }

    /// Turns an AO3 tag URL slug back into a readable name (AO3 escapes `/ & . ? #`).
    static func unmungeTag(_ slug: String) -> String {
        (slug.removingPercentEncoding ?? slug)
            .replacingOccurrences(of: "*s*", with: "/")
            .replacingOccurrences(of: "*a*", with: "&")
            .replacingOccurrences(of: "*d*", with: ".")
            .replacingOccurrences(of: "*q*", with: "?")
            .replacingOccurrences(of: "*h*", with: "#")
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
    func toggle(_ targetPanel: Panel) {
        panel = (panel == targetPanel) ? .none : targetPanel
    }

    /// A Bool binding for `.inspector(isPresented:)` that's true while `targetPanel` is open.
    func isShowing(_ targetPanel: Panel) -> Binding<Bool> {
        Binding(
            get: { self.panel == targetPanel },
            set: { self.panel = $0 ? targetPanel : .none }
        )
    }
}
