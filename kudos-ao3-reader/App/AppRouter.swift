import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The app's top-level sections.
enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case home, library, writing, browse, account, search

    var id: String {
        rawValue
    }

    /// The core tabs in the main tab bar / sidebar. `search` is a global action
    /// presented separately (the iOS search-role slot / a macOS sidebar button).
    /// `account` remains as the Account sheet's navigation scope and to migrate
    /// old restored selections; it is not a tab-bar item.
    /// `writing` appears only when the Writing-tab rule says the account writes.
    static func mainTabs(showsWriting: Bool) -> [AppTab] {
        showsWriting ? [.home, .library, .writing, .browse] : [.home, .library, .browse]
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .writing: "Writing"
        case .browse: "Browse"
        case .account: "Account"
        case .search: "Search"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .writing: "square.and.pencil"
        case .browse: "safari"
        case .account: "person.crop.circle"
        case .search: "magnifyingglass"
        }
    }
}

/// The four AO3-managed reading lists now grouped under Library > On AO3.
enum LibraryAO3Route: String, Hashable, CaseIterable {
    case markedForLater
    case bookmarks
    case subscriptions
    case history
}

/// Destinations owned by the Writing tab.
enum WritingRoute: String, Hashable, CaseIterable {
    case works
    case drafts
    case series
    case collectionsAndChallenges
}

/// Destinations owned by the Home profile/account sheet.
enum AccountSheetRoute: String, Hashable, CaseIterable {
    case dashboard
    case profile
    case inbox
    case preferences
    case moreOnAO3
    case openAO3
    case settings
    case backup
    case about
}

/// Account routes accepted by older deep links and restored navigation state.
/// Keeping this translation pure makes the one-time migration testable without UI.
enum LegacyAccountRoute: String, Hashable, CaseIterable {
    case dashboard
    case works
    case drafts
    case series
    case collections
    case inbox
    case preferences
    case moreOnAO3
    case markedForLater
    case bookmarks
    case subscriptions
    case history
    case settings

    enum Destination: Equatable {
        case account(AccountSheetRoute)
        case writing(WritingRoute)
        case library(LibraryAO3Route)
    }

    var destination: Destination {
        switch self {
        case .dashboard: .account(.dashboard)
        case .works: .writing(.works)
        case .drafts: .writing(.drafts)
        case .series: .writing(.series)
        case .collections: .writing(.collectionsAndChallenges)
        case .inbox: .account(.inbox)
        case .preferences: .account(.preferences)
        case .moreOnAO3: .account(.moreOnAO3)
        case .markedForLater: .library(.markedForLater)
        case .bookmarks: .library(.bookmarks)
        case .subscriptions: .library(.subscriptions)
        case .history: .library(.history)
        case .settings: .account(.settings)
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
    enum Field {
        case warning, fandom, character, relationship, freeform

        /// The glyph for this tag category. AO3 groups tags by category in its own
        /// markup (`h5.fandoms`, `ul.tags li.characters`, …) and `parseBlurb` already
        /// reads that, so every chip knows which of these it is without asking.
        ///
        /// Chosen to avoid the stat row's vocabulary, which shares the same screen:
        /// `heart` is kudos and `person.2.fill` is the AO3 category (Gen, M/M …),
        /// so relationships take `figure.2` rather than either.
        var symbol: String {
            switch self {
            case .warning: "exclamationmark.triangle"
            case .fandom: "books.vertical"
            case .character: "person"
            case .relationship: "figure.2"
            case .freeform: "tag"
            }
        }

        /// Spoken before the tag, so VoiceOver says "Character, Uzumaki Naruto"
        /// rather than reading a glyph name or nothing at all.
        var accessibilityName: String {
            switch self {
            case .warning: "Warning"
            case .fandom: "Fandom"
            case .character: "Character"
            case .relationship: "Relationship"
            case .freeform: "Tag"
            }
        }
    }
    let field: Field
    let value: String
    /// True when this request switched the user into the Search tab (they were on a
    /// different tab when the chip was tapped). A same-tab tap — a chip on a result
    /// already inside Search's own stack — is a deliberate drill-down (tag A → tag B)
    /// and must not be treated as the start of a brand new, unrelated search.
    let isFreshTabJump: Bool
}

/// A request to show a tag's works page natively (from a tapped AO3 link, e.g. in a
/// work's preface). `url` is AO3's own (already-munged) link; `title` is the readable
/// tag name for the screen title.
struct AO3TagWorksRequest: Hashable {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = Self.worksListing(for: url)
        self.title = title
    }

    /// A tag link in AO3's own markup points at `/tags/<name>`, the tag's *info*
    /// page — an EPUB preface's "Fandom: Frozen (Disney Movies)" is one, and so is
    /// every tag link on a work page. That page carries no work blurbs at all
    /// (measured: 0 vs 20 on `/works`), so this screen loaded it, parsed nothing,
    /// and said "No works found" for tags with hundreds of thousands of works.
    ///
    /// The listing is one path component further on, so add it when it's missing.
    /// Links that already point at `/works` (or at a sub-listing like
    /// `/bookmarks`) are left alone.
    private static func worksListing(for url: URL) -> URL {
        var parts = url.pathComponents.filter { $0 != "/" }
        guard parts.first == "tags", parts.count == 2 else { return url }
        parts.append("works")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        // Rebuilt from the *original* path, not from the decoded components: AO3
        // writes `&` in a tag path as `*a*` and percent-encodes the rest, and
        // re-encoding a decoded component would mangle both.
        components.percentEncodedPath = url.path(percentEncoded: true)
            .hasSuffix("/") ? "\(url.path(percentEncoded: true))works"
            : "\(url.path(percentEncoded: true))/works"
        return components.url ?? url
    }
}

/// Pure rule for whether the Writing tab appears in the tab bar / sidebar (T-513).
///
/// The Writing tab is shown only when a signed-in AO3 account has at least one
/// work, series or draft, or Kudos holds a local draft. Offline or before the
/// account answers, the stored last-known answer is used (never guessing `true`
/// for an account never seen to write). Once shown during an app run, the tab is
/// never removed while the app remains open; logging out removes it.
nonisolated struct WritingTabRule: Equatable, Sendable {
    var isSignedIn: Bool
    var workCount: Int?
    var seriesCount: Int?
    var draftCount: Int?
    var hasLocalDrafts: Bool = false
    var lastKnownWrites: Bool = false
    var alreadyShownThisRun: Bool = false

    var showsWritingTab: Bool {
        guard isSignedIn else { return false }
        if alreadyShownThisRun { return true }
        if hasLocalDrafts { return true }
        if (workCount ?? 0) > 0 || (seriesCount ?? 0) > 0 || (draftCount ?? 0) > 0 {
            return true
        }
        if workCount == 0, seriesCount == 0, draftCount == 0 {
            return false
        }
        return lastKnownWrites
    }
}

/// Persists the last-known "writes" answer per AO3 username so offline launches
/// and pre-response states match the account's last observed writing state
/// without guessing `true` for an unseen account.
nonisolated struct WritingTabStateStore {
    private static let key = "ao3LastKnownWritesByUsername"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastKnownWrites(for username: String?) -> Bool {
        guard let username = normalized(username) else { return false }
        return values[username] ?? false
    }

    func setLastKnownWrites(_ writes: Bool, for username: String?) {
        guard let username = normalized(username) else { return }
        var next = values
        next[username] = writes
        defaults.set(next, forKey: Self.key)
    }

    private var values: [String: Bool] {
        defaults.dictionary(forKey: Self.key) as? [String: Bool] ?? [:]
    }

    private func normalized(_ username: String?) -> String? {
        guard let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

nonisolated enum WritingTabEvents {
    enum Payload: Sendable {
        case authChanged(isSignedIn: Bool, username: String?, authenticationScope: String?)
        case countsChanged(authenticationScope: String)
        case draftSaved(username: String?)
    }

    static let notificationName = Notification.Name("KudosWritingTabInputsDidChange")

    static func notifyAuthChanged(isSignedIn: Bool, username: String?, authenticationScope: String?) {
        post(.authChanged(
            isSignedIn: isSignedIn,
            username: username,
            authenticationScope: authenticationScope
        ))
    }

    static func notifyCountsChanged(authenticationScope: String) {
        post(.countsChanged(authenticationScope: authenticationScope))
    }

    static func notifyDraftSaved(username: String? = nil) {
        post(.draftSaved(username: username))
    }

    private static func post(_ payload: Payload) {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: notificationName, object: payload)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: notificationName, object: payload)
            }
        }
    }
}

/// Shared navigation state so other tabs can hand a URL to the browser and
/// switch to it (e.g. opening a saved bookmark).
@Observable
final class AppRouter {
    struct RestoredSelection: Equatable {
        let tab: AppTab
        let presentsAccount: Bool
    }

    var selection: AppTab = .home {
        didSet {
            // Remember where we came from so the focused Search mode's Back button
            // can return there (iOS). Never record Search itself as the target.
            if oldValue != .search { lastNonSearchTab = oldValue }
            if selection != .home, selection != .writing {
                restoredWritingSelection = false
            }
        }
    }

    /// Whether the Writing tab is currently in `mainTabs`.
    private(set) var showsWritingTab = false
    /// Active core tabs derived from `showsWritingTab`.
    var mainTabs: [AppTab] {
        AppTab.mainTabs(showsWriting: showsWritingTab)
    }

    @ObservationIgnored private var writingStateStore: WritingTabStateStore
    @ObservationIgnored private var recoveryStore: WritingTextRecovery
    @ObservationIgnored private var activeUsername: String?
    @ObservationIgnored private var evaluatedAccount: String?
    @ObservationIgnored private var activeAuthenticationScope: String?
    @ObservationIgnored private var restoredWritingSelection = false
    @ObservationIgnored private var writingTabObserver: NSObjectProtocol?

    init(
        writingStateStore: WritingTabStateStore = WritingTabStateStore(),
        recoveryStore: WritingTextRecovery = WritingTextRecovery()
    ) {
        self.writingStateStore = writingStateStore
        self.recoveryStore = recoveryStore
        writingTabObserver = NotificationCenter.default.addObserver(
            forName: WritingTabEvents.notificationName,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let payload = notification.object as? WritingTabEvents.Payload else { return }
            self?.handleWritingTabPayload(payload)
        }
    }

    deinit {
        if let writingTabObserver {
            NotificationCenter.default.removeObserver(writingTabObserver)
        }
    }

    /// The tab the focused Search mode returns to when its Back button is tapped.
    var lastNonSearchTab: AppTab = .library
    /// Home presents Account as a sheet; it is no longer a root tab.
    var isPresentingAccount = false
    private var opensWebsiteAfterAccountDismiss = false
    private var websiteURLAfterAccountDismiss: URL?
    var pendingAccountRoute: AccountSheetRoute?
    var pendingWritingRoute: WritingRoute?
    var pendingLibraryAO3Route: LibraryAO3Route?
    /// A URL the AO3 website sheet should load (set by `open`).
    var pendingURL: URL?
    /// Root-presented AO3 website sheet. Hosted on `ContentView` so `open`
    /// does not switch the user into the Browse tab — Done returns them to
    /// whatever tab/subpage they came from.
    var isPresentingWebBrowser = false
    /// A tag the Library should filter by on its next appearance (e.g. tapped on a
    /// work's detail page). Consumed + cleared by `LibraryView`.
    var pendingLibraryTag: LibraryTagFilter?
    /// A Library section to push on its next appearance (e.g. Home Resume "See all"
    /// → Reading Now). Consumed + cleared by `LibraryView`.
    var pendingLibrarySection: LibrarySectionKind?
    /// An app-level request to reopen a local work in Home's existing reader path.
    /// Read Aloud uses this after its reader-scoped navigation has been dismissed.
    var pendingLocalWorkDestination: LocalWorkDestination?
    /// The focused Comments screen owns its tab's system accessory while its
    /// composer is available; Read Aloud remains visible on other tabs.
    var commentAccessoryTab: AppTab?
    /// The tab that asked for it, drawn as the pushed list's kicker.
    var pendingLibrarySectionOrigin: String?
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
    /// Bumps on every `openAuthorProfile` so tab stacks always observe a change —
    /// including re-tapping the same author (Optional equality would skip `onChange`).
    private(set) var authorProfileNavigationEpoch: UInt = 0
    /// While true, work-card `cardNavigation` links are disabled and any work/reader
    /// push that still lands from the same touch should dismiss itself so the author
    /// profile is not buried under it.
    private(set) var cardNavigationSuppressed = false

    /// The one stack allowed to consume the pending author route. Account owns a
    /// separate sheet stack even though Home remains the selected root tab.
    var authorNavigationTarget: AppTab {
        isPresentingAccount ? .account : selection
    }

    /// The one right-hand inspector panel open anywhere in the app. Routing every
    /// panel (Search filters, Reader chapters/display) through a single
    /// shared value guarantees only one inspector is ever presented at a time —
    /// two presented simultaneously crash AppKit's layout.
    var panel: Panel = .none

    enum Panel: Equatable {
        case none, searchFilters, libraryFilters, readerChapters, readerDisplay, readerFind
    }

    /// Opens a URL in the in-app AO3 website sheet without changing tabs.
    ///
    /// Scheme + host gates live at this sink, not at the call sites.
    /// `javascript:` / `data:` / `file:` are refused (not handed to the
    /// system opener). Non-AO3 `http(s)` is routed to the system browser so
    /// it never shares the AO3 cookie store. Only `https` AO3 hosts present
    /// the in-app sheet (`AO3AuthorRoute.isAO3URL` is https-only).
    func open(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return }
        if isPresentingAccount || opensWebsiteAfterAccountDismiss {
            openWebsiteAfterDismissingAccount(url)
            return
        }
        if !AO3AuthorRoute.isAO3URL(url) {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
            return
        }
        pendingURL = url
        isPresentingWebBrowser = true
    }

    /// Presents the AO3 website sheet at its home page (Browse toolbar entry).
    /// Does not change the selected tab.
    func openWebsite() {
        // Leave pendingURL alone if something just queued a deep link; otherwise
        // the sheet opens on AO3 home (BrowserModel's default load).
        isPresentingWebBrowser = true
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
        // Same host gate as `open(_:)` (`isAO3URL`: https-only, apex or
        // subdomain) — a substring check here would treat a lookalike host
        // like `archiveofourown.org.evil.example` as native-eligible and hand
        // its URL straight to `AO3Client.worksPage(at:)`.
        if AO3AuthorRoute.isAO3URL(url),
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
        // Suppress first so the same-touch row NavigationLink can still be disabled /
        // auto-dismissed before we hand the route to the active tab stack.
        cardNavigationSuppressed = true
        pendingAuthorProfile = route
        authorProfileNavigationEpoch &+= 1
        Task { @MainActor in
            // Long enough for List to commit + for deferred dismiss of a spurious
            // work push; short enough not to block intentional card taps after.
            try? await Task.sleep(for: .milliseconds(700))
            cardNavigationSuppressed = false
        }
    }

    /// An author route requested mid-modal (a Comments sheet's byline or reply-quote
    /// tap) that must wait for the *current* sheet/full-screen-cover chain to actually
    /// finish tearing down before it pushes — see `requestAuthorProfileAfterDismiss`.
    ///
    /// At most one is ever queued: it doubles as the app-wide "an author push is
    /// already in flight" flag, so a second byline tap mid-dismiss is dropped rather
    /// than landing the same profile on the stack twice — including when the two taps
    /// come from *different* views (a comment byline and the composer's reply-quote
    /// byline are separate `View` structs and cannot see each other's local state).
    private(set) var pendingAuthorProfileAfterDismiss: AO3AuthorRoute?

    /// Queues an author route to open once the caller's modal presentation reports
    /// its dismiss animation complete. Callers still call `dismiss()` themselves right
    /// after; the presenter's own `.sheet`/`.fullScreenCover` `onDismiss` closure must
    /// call `openPendingAuthorProfileAfterDismiss()` to actually push it — that closure
    /// only fires once SwiftUI's dismiss transition genuinely finishes, replacing a
    /// guessed-duration sleep with the real completion signal. See `CommentsSheetModifier`.
    ///
    /// **Presenter contract:** every modal presenter that can host a view calling this
    /// must drain it from its own `onDismiss` (draining is a no-op when nothing is
    /// queued, so over-hooking is safe — *under*-hooking is the hazard: a route queued
    /// under a presenter that never drains would strand here and then fire on some
    /// later, unrelated dismissal). `CommentsSheetModifier` additionally cancels any
    /// stale route when it opens, so a strand cannot outlive one Comments presentation.
    ///
    /// - Returns: `false` when a route is already queued, in which case nothing is
    ///   overwritten and the caller should leave its own presentation alone — first
    ///   tap wins, matching the re-entrancy guard this replaced.
    @discardableResult
    func requestAuthorProfileAfterDismiss(_ route: AO3AuthorRoute) -> Bool {
        guard pendingAuthorProfileAfterDismiss == nil else { return false }
        pendingAuthorProfileAfterDismiss = route
        return true
    }

    /// Call from a modal presenter's `onDismiss` closure. No-ops if nothing is queued
    /// (e.g. the presentation the closure belongs to wasn't the one a route was queued
    /// against) — safe to call from more than one presenter in a nested-sheet chain.
    func openPendingAuthorProfileAfterDismiss() {
        guard let route = pendingAuthorProfileAfterDismiss else { return }
        pendingAuthorProfileAfterDismiss = nil
        openAuthorProfile(route)
    }

    /// Drops a queued route without opening it. Called when a Comments presentation
    /// *begins* so a route left over from an earlier presentation can never push a
    /// profile the user didn't ask for. Safe by construction: queuing only ever
    /// happens on the way out of a presentation, never as one opens.
    func cancelPendingAuthorProfileAfterDismiss() {
        pendingAuthorProfileAfterDismiss = nil
    }

    /// Active tab stack takes the pending route (if any) and clears it.
    func consumePendingAuthorProfile() -> AO3AuthorRoute? {
        let route = pendingAuthorProfile
        pendingAuthorProfile = nil
        return route
    }

    /// Migrates a persisted Account-tab selection to Home + the Account sheet,
    /// and falls back to Home when a persisted Writing-tab selection is restored
    /// while the Writing tab is hidden.
    static func restoredSelection(from rawValue: String?, showsWriting: Bool = false) -> RestoredSelection {
        guard let rawValue, let tab = AppTab(rawValue: rawValue) else {
            return RestoredSelection(tab: .home, presentsAccount: false)
        }
        if tab == .account {
            return RestoredSelection(tab: .home, presentsAccount: true)
        }
        if tab == .writing, !showsWriting {
            return RestoredSelection(tab: .home, presentsAccount: false)
        }
        return RestoredSelection(tab: tab, presentsAccount: false)
    }

    func restoreSelection(from rawValue: String?) {
        let wantsWriting = (rawValue == AppTab.writing.rawValue)
        let restored = Self.restoredSelection(from: rawValue, showsWriting: showsWritingTab)
        selection = restored.tab
        isPresentingAccount = restored.presentsAccount
        restoredWritingSelection = wantsWriting && !showsWritingTab
    }

    @discardableResult
    func evaluateWritingTab(
        isSignedIn: Bool,
        username: String? = nil,
        workCount: Int? = nil,
        seriesCount: Int? = nil,
        draftCount: Int? = nil,
        hasLocalDrafts: Bool? = nil
    ) -> Bool {
        let effectiveUsername = username ?? activeUsername
        let normalizedUser = Self.normalizedAccount(effectiveUsername)
        let accountSwitched = isSignedIn
            && evaluatedAccount != nil
            && normalizedUser != evaluatedAccount
        if isSignedIn {
            evaluatedAccount = normalizedUser
        } else {
            evaluatedAccount = nil
        }
        if accountSwitched {
            restoredWritingSelection = false
            pendingWritingRoute = nil
        }
        let resolvedHasLocalDrafts = isSignedIn
            ? (hasLocalDrafts ?? recoveryStore.hasLocalDrafts(for: effectiveUsername))
            : false
        if isSignedIn {
            if resolvedHasLocalDrafts || (workCount ?? 0) > 0 || (seriesCount ?? 0) > 0 || (draftCount ?? 0) > 0 {
                writingStateStore.setLastKnownWrites(true, for: effectiveUsername)
            } else if workCount == 0, seriesCount == 0, draftCount == 0 {
                writingStateStore.setLastKnownWrites(false, for: effectiveUsername)
            }
        }
        let rule = WritingTabRule(
            isSignedIn: isSignedIn,
            workCount: workCount,
            seriesCount: seriesCount,
            draftCount: draftCount,
            hasLocalDrafts: resolvedHasLocalDrafts,
            lastKnownWrites: writingStateStore.lastKnownWrites(for: effectiveUsername),
            alreadyShownThisRun: accountSwitched ? false : showsWritingTab
        )
        return applyWritingTabRule(rule)
    }

    @discardableResult
    func evaluateWritingTab(_ rule: WritingTabRule) -> Bool {
        applyWritingTabRule(rule)
    }

    @discardableResult
    func evaluateWritingTab(
        from header: AO3AuthorHeader,
        route: AO3AuthorRoute,
        username: String?,
        isSignedIn: Bool
    ) -> Bool {
        let effectiveUsername = username ?? route.username
        // A header with no count but a recent work or series is still proof of writing;
        // an empty list without a count proves nothing (unknown, never zero).
        let workCount = header.listCount(for: .works, route: route)
            ?? header.recentWorks.flatMap { $0.isEmpty ? nil : $0.count }
        let seriesCount = header.listCount(for: .series, route: route)
            ?? header.recentSeries.flatMap { $0.isEmpty ? nil : $0.count }
        let draftCount = header.draftsListCount()
        return evaluateWritingTab(
            isSignedIn: isSignedIn,
            username: effectiveUsername,
            workCount: workCount,
            seriesCount: seriesCount,
            draftCount: draftCount,
            hasLocalDrafts: recoveryStore.hasLocalDrafts(for: effectiveUsername)
        )
    }

    func noteDraftSaved(username: String? = nil) {
        let effectiveUsername = username ?? activeUsername
        writingStateStore.setLastKnownWrites(true, for: effectiveUsername)
        _ = evaluateWritingTab(
            isSignedIn: true,
            username: effectiveUsername,
            draftCount: 1,
            hasLocalDrafts: true
        )
    }

    /// Shows the Writing tab for the current session without writing to
    /// persistent account defaults (used by DEBUG screenshot routes).
    func revealWritingTabForSession() {
        showsWritingTab = true
    }

    private func applyWritingTabRule(_ rule: WritingTabRule) -> Bool {
        let next = rule.showsWritingTab
        if next {
            showsWritingTab = true
            if (restoredWritingSelection || pendingWritingRoute != nil),
               selection == .home,
               !isPresentingAccount {
                selection = .writing
            }
            restoredWritingSelection = false
        } else {
            if selection == .writing {
                selection = .home
            }
            showsWritingTab = false
            if !rule.isSignedIn {
                restoredWritingSelection = false
            }
        }
        return next
    }

    private static func normalizedAccount(_ username: String?) -> String? {
        guard let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private func handleWritingTabPayload(_ payload: WritingTabEvents.Payload) {
        switch payload {
        case let .authChanged(isSignedIn, username, authenticationScope):
            activeUsername = isSignedIn ? username : nil
            activeAuthenticationScope = isSignedIn ? authenticationScope : nil
            guard isSignedIn else {
                _ = evaluateWritingTab(isSignedIn: false)
                return
            }
            let workCount = authenticationScope.flatMap {
                AO3AccountListCountsCache.shared.count(for: .myWorks, authenticationScope: $0)?.knownCount
            }
            let seriesCount = authenticationScope.flatMap {
                AO3AccountListCountsCache.shared.count(for: .series, authenticationScope: $0)?.knownCount
            }
            let draftCount = authenticationScope.flatMap {
                AO3AccountListCountsCache.shared.count(for: .drafts, authenticationScope: $0)?.knownCount
            }
            _ = evaluateWritingTab(
                isSignedIn: true,
                username: username,
                workCount: workCount,
                seriesCount: seriesCount,
                draftCount: draftCount,
                hasLocalDrafts: recoveryStore.hasLocalDrafts(for: username)
            )
        case let .countsChanged(authenticationScope):
            guard let username = activeUsername else { return }
            let scope = activeAuthenticationScope ?? authenticationScope
            guard scope == authenticationScope else { return }
            let cache = AO3AccountListCountsCache.shared
            let workCount = cache.count(for: .myWorks, authenticationScope: scope)?.knownCount
            let seriesCount = cache.count(for: .series, authenticationScope: scope)?.knownCount
            let draftCount = cache.count(for: .drafts, authenticationScope: scope)?.knownCount
            _ = evaluateWritingTab(
                isSignedIn: true,
                username: username,
                workCount: workCount,
                seriesCount: seriesCount,
                draftCount: draftCount,
                hasLocalDrafts: recoveryStore.hasLocalDrafts(for: username)
            )
        case let .draftSaved(username):
            if let username, let activeUsername,
               Self.normalizedAccount(username) != Self.normalizedAccount(activeUsername) {
                return
            }
            guard activeUsername != nil || username != nil else { return }
            noteDraftSaved(username: username ?? activeUsername)
        }
    }

    func showAccount(_ route: AccountSheetRoute? = nil) {
        selection = .home
        pendingAccountRoute = route
        isPresentingAccount = true
    }

    func openWebsiteAfterDismissingAccount(_ url: URL? = nil) {
        opensWebsiteAfterAccountDismiss = true
        websiteURLAfterAccountDismiss = url
        isPresentingAccount = false
    }

    func accountDidDismiss() {
        guard opensWebsiteAfterAccountDismiss else { return }
        let url = websiteURLAfterAccountDismiss
        opensWebsiteAfterAccountDismiss = false
        websiteURLAfterAccountDismiss = nil
        if let url {
            open(url)
        } else {
            openWebsite()
        }
    }

    func openLegacyAccountRoute(_ route: LegacyAccountRoute) {
        switch route.destination {
        case let .account(destination):
            showAccount(destination)
        case let .writing(destination):
            pendingWritingRoute = destination
            selection = showsWritingTab ? .writing : .home
        case let .library(destination):
            pendingLibraryAO3Route = destination
            selection = .library
        }
    }

    func consumePendingAccountRoute() -> AccountSheetRoute? {
        defer { pendingAccountRoute = nil }
        return pendingAccountRoute
    }

    func consumePendingWritingRoute() -> WritingRoute? {
        defer { pendingWritingRoute = nil }
        return pendingWritingRoute
    }

    func consumePendingLibraryAO3Route() -> LibraryAO3Route? {
        defer { pendingLibraryAO3Route = nil }
        return pendingLibraryAO3Route
    }

    /// True while an author byline navigation is settling — work/reader destinations
    /// opened by the same List row touch should `dismiss()` (async, not in the
    /// same navigation transaction as the push).
    var shouldSuppressCardNavigation: Bool {
        cardNavigationSuppressed
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

    /// Switches to the Library and pushes the full list for `kind` (e.g. Home Resume
    /// "See all" → `.readingNow`).
    func showLibrarySection(_ kind: LibrarySectionKind, from origin: String? = nil) {
        pendingLibrarySection = kind
        pendingLibrarySectionOrigin = origin
        selection = .library
    }

    func openReader(_ work: SavedWork) {
        pendingLocalWorkDestination = .reader(work)
        selection = .home
    }

    /// Switches to Search and runs an AO3 search for `value` in the given tag `field`
    /// (a tapped fandom/character/relationship/freeform chip → "more works with this").
    func searchAO3(_ field: AO3TagSearch.Field, _ value: String) {
        let isFreshTabJump = selection != .search
        pendingTagSearch = AO3TagSearch(field: field, value: value, isFreshTabJump: isFreshTabJump)
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
