import SwiftData
import SwiftUI

/// The Account tab: AO3 session state, AO3 account lists (My AO3), the local
/// reading surfaces moved off the old Bookmarks tab, app settings, and help/about.
/// Replaces the standalone Bookmarks and Settings tabs (Part 7 of the refinement).
struct AccountView: View {
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var themeManager

    @State private var path = NavigationPath()
    @State private var showingLogin = false
    @State private var showingAbout = false
    @State private var showingBugReport = false

    /// Pushable Account destinations (the AO3 lists, local lists, and Settings).
    enum Route: Hashable {
        case subscriptions, ao3Bookmarks, markedForLater, ao3History
        case myDashboard, myWorks, myCollections
        case localHistory, localFavorites
        case settings, privacy
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Group {
                    accountStatusSection
                    myAO3Section
                    ao3WebsiteSection
                    localSection
                    appSection
                    helpSection
                }
                .appThemedRows()
            }
            .formStyle(.grouped)
            .appThemedScroll()
            .navigationTitle("Account")
            #if os(iOS)
                .toolbarTitleDisplayMode(.inlineLarge)
            #endif
                .navigationDestination(for: Route.self, destination: destination)
                .navigationDestination(for: AO3AccountWorksList.Kind.self) { AO3AccountWorksList(kind: $0) }
                .navigationDestination(for: SavedWork.self) { WorkDetailView(work: $0) }
                .navigationDestination(for: AO3WorkSummary.self) { WorkDetailView(remote: $0) }
                .sheet(isPresented: $showingLogin) { AO3LoginView() }
                .sheet(isPresented: $showingAbout) { NavigationStack { AboutView() } }
                .sheet(isPresented: $showingBugReport) { BugReportView() }
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .subscriptions: AO3AccountWorksList(kind: .subscriptions)
        case .ao3Bookmarks: AO3AccountWorksList(kind: .bookmarks)
        case .markedForLater: AO3AccountWorksList(kind: .markedForLater)
        case .ao3History: AO3AccountWorksList(kind: .history)
        case .myDashboard: AO3DashboardView()
        case .myWorks: AO3AccountWorksList(kind: .myWorks)
        case .myCollections: AO3CollectionsList()
        case .localHistory: LocalReadingHistoryView()
        case .localFavorites: LocalFavoritesView()
        case .settings: ReaderOptionsForm(includeAppSettings: true).navigationTitle("Settings")
        case .privacy: PrivacyDataView()
        }
    }

    // MARK: Sections

    private var accountStatusSection: some View {
        Section {
            switch auth.status {
            case .restoring:
                // Restoring the AO3 session — show the shape of the signed-in row.
                SkeletonListRow(width: 96, trailingWidth: 120)
            case let .signedIn(username):
                LabeledContent {
                    Text(username)
                } label: {
                    Label("Signed In", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                LabeledContent {
                    sessionHealthValue(auth.sessionHealth)
                } label: {
                    Label("Session", systemImage: "antenna.radiowaves.left.and.right")
                }
                Button {
                    Task { await auth.verifySession() }
                } label: {
                    Label(auth.sessionHealth.isChecking ? "Checking…" : "Verify Session",
                          systemImage: "arrow.clockwise")
                }
                .disabled(auth.sessionHealth.isChecking)
                Button(role: .destructive) {
                    Task { await auth.logout() }
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            case .signedOut, .signingIn, .usingFallback:
                Button {
                    showingLogin = true
                } label: {
                    Label("Log In to AO3…", systemImage: "person.badge.key")
                }
            }
        } header: {
            Text("AO3 Account")
        } footer: {
            if let notice = auth.noticeMessage {
                Text(notice)
            } else {
                Text("Log in to use your AO3 subscriptions, bookmarks, history, and "
                    + "reading list. Your session stays on this device.")
            }
        }
    }

    /// The trailing status pill for the "Session" row, reflecting the last check.
    @ViewBuilder
    private func sessionHealthValue(_ health: AO3SessionHealth) -> some View {
        switch health {
        case .unknown:
            Text("Not checked").foregroundStyle(.secondary)
        case .verifying:
            Label("Checking…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        case let .healthy(at):
            Label(at.formatted(.relative(presentation: .named)), systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .expired:
            Label("Expired", systemImage: "xmark.seal.fill")
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
        case .unreachable:
            Label("Couldn’t verify", systemImage: "wifi.exclamationmark")
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
        }
    }

    private var myAO3Section: some View {
        Section("My AO3") {
            NavigationLink(value: Route.myDashboard) {
                Label("My Dashboard", systemImage: "rectangle.grid.2x2")
            }
            NavigationLink(value: Route.myWorks) {
                Label("My Works", systemImage: "doc.text")
            }
            NavigationLink(value: Route.myCollections) {
                Label("My Collections", systemImage: "square.stack")
            }
            NavigationLink(value: Route.subscriptions) {
                Label("My Subscriptions", systemImage: "bell")
            }
            NavigationLink(value: Route.ao3Bookmarks) {
                Label("My AO3 Bookmarks", systemImage: "bookmark")
            }
            NavigationLink(value: Route.markedForLater) {
                Label("Marked for Later", systemImage: "clock.badge")
            }
            NavigationLink(value: Route.ao3History) {
                Label("My AO3 History", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    /// AO3 account areas kept as a clearly-labeled web fallback — AO3 Preferences is a
    /// large, site-specific settings form, so it opens on the website (no faked UI).
    private var ao3WebsiteSection: some View {
        Section {
            webLink("My Preferences", systemImage: "slider.horizontal.3", path: "/preferences")
        } header: {
            Text("On AO3")
        } footer: {
            Text("Opens your AO3 settings on the website.")
        }
    }

    private var localSection: some View {
        Section {
            NavigationLink(value: Route.localHistory) {
                Label("Local Reading History", systemImage: "clock")
            }
            NavigationLink(value: Route.localFavorites) {
                Label("Favorites", systemImage: "star")
            }
        } header: {
            Text("Local")
        } footer: {
            Text("Stored on this device — distinct from your AO3 account history.")
        }
    }

    private var appSection: some View {
        Section("App") {
            NavigationLink(value: Route.settings) {
                Label("Settings", systemImage: "gearshape")
            }
            NavigationLink(value: Route.privacy) {
                Label("Privacy & Local Data", systemImage: "hand.raised")
            }
        }
    }

    private var helpSection: some View {
        Section("Help & Project") {
            Button { showingAbout = true } label: {
                Label("About Kudos", systemImage: "info.circle")
            }
            Button { showingBugReport = true } label: {
                Label("Report a Bug", systemImage: "ladybug")
            }
            if let url = URL(string: AppLinks.repository) {
                Link(destination: url) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
    }

    // MARK: Helpers

    /// A row that opens an AO3 path on the website (via the Browse tab). Disabled
    /// (with a hint) for account-specific paths when signed out.
    @ViewBuilder
    private func webLink(_ title: String, systemImage: String, path: String) -> some View {
        let needsAccount = path.contains("/users/")
        Button {
            if let url = URL(string: "https://archiveofourown.org\(path)") { router.open(url) }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.forward.square").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(needsAccount && auth.username == nil)
    }
}

// MARK: - Local lists (moved from the retired Bookmarks tab)

/// Local reading history: works whose EPUB was freed after finishing (revisitable
/// by re-downloading). Moved from the old Bookmarks tab.
private struct LocalReadingHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true

    // Queued works whose preservation is pending/failed have hasEPUB == false but are
    // protected; keep them out of the reading-history list. Soft-deleted works belong
    // in Recently Deleted, not history.
    @Query(filter: #Predicate<SavedWork> { !$0.hasEPUB && !$0.isQueuedForLater && !$0.isPendingDeletion },
           sort: \SavedWork.dateAdded, order: .reverse)
    private var history: [SavedWork]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var pendingDelete: SavedWork?
    @State private var expandAll = false
    /// Filters scoped to this history list, applied live to its works.
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    /// Privacy-visible history (the base the filter panel narrows further).
    private var visibleHistory: [SavedWork] {
        history.filter(passesPrivacy)
    }

    /// History after the active filters. With no filter set, the newest-first order is
    /// kept rather than re-sorted by the filter's default sort.
    private var displayedHistory: [SavedWork] {
        filters.hasActiveFilters ? filters.apply(to: visibleHistory) : visibleHistory
    }

    var body: some View {
        Group {
            if history.isEmpty {
                ContentUnavailableView {
                    Label("No history", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Works you finish without saving land here. Their files are freed, "
                        + "but you can re-download and revisit them anytime.")
                }
            } else if visibleHistory.isEmpty {
                MatureContentHiddenView()
            } else {
                List {
                    ForEach(displayedHistory) { work in
                        SensitiveWorkRow(work: work, expandAll: expandAll)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if confirmBeforeDelete { pendingDelete = work } else { remove(work) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                    .cardRow()
                }
                .cardList()
                .overlay {
                    if displayedHistory.isEmpty {
                        ContentUnavailableView {
                            Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("No works in your history match the current filters.")
                        } actions: {
                            Button("Clear Filters") { filters = LibraryFilters() }
                        }
                    }
                }
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle("Local Reading History")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                if !visibleHistory.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 2) {
                            FilterButton(filtersActive: filters.hasActiveFilters,
                                         showingFilters: $showingFilters,
                                         filterHelp: "Filter the works in your history",
                                         onClearFilters: { filters = LibraryFilters() })
                            WorkListMoreMenu {
                                ExpandAllMenuItem(expandAll: $expandAll)
                            }
                        }
                    }
                }
            }
            .inspector(isPresented: $showingFilters) {
                LibraryFilterPanel(filters: $filters, works: visibleHistory, userTagNames: allTags.map(\.name))
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                #if os(iOS)
                    .presentationDragIndicator(.visible)
                #endif
            }
            .deleteConfirmation(
                for: $pendingDelete,
                title: "Remove from History?",
                confirmLabel: "Remove",
                message: { PreservedWorkService.deleteConfirmationMessage(for: $0) },
                perform: remove
            )
    }

    private func remove(_ work: SavedWork) {
        PreservedWorkService.softDelete(work, in: context)
    }
}

/// Local favorites. Moved from the old Bookmarks tab.
private struct LocalFavoritesView: View {
    @Environment(\.modelContext) private var context
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @Query(filter: #Predicate<SavedWork> { $0.isFavorite && !$0.isPendingDeletion },
           sort: \SavedWork.dateAdded, order: .reverse)
    private var favorites: [SavedWork]
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var expandAll = false
    /// Filters scoped to this favorites list, applied live to its works.
    @State private var filters = LibraryFilters()
    @State private var showingFilters = false

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    /// Privacy-visible favorites (the base the filter panel narrows further).
    private var visibleFavorites: [SavedWork] {
        favorites.filter(passesPrivacy)
    }

    /// Favorites after the active filters. With no filter set, the newest-first order is
    /// kept rather than re-sorted by the filter's default sort.
    private var displayedFavorites: [SavedWork] {
        filters.hasActiveFilters ? filters.apply(to: visibleFavorites) : visibleFavorites
    }

    var body: some View {
        Group {
            if favorites.isEmpty {
                ContentUnavailableView {
                    Label("No favorites", systemImage: "star")
                } description: {
                    Text("Swipe a work in your Library, or tap the star on its page, to favorite it.")
                }
            } else if visibleFavorites.isEmpty {
                MatureContentHiddenView()
            } else {
                List {
                    ForEach(displayedFavorites) { work in
                        SensitiveWorkRow(work: work, expandAll: expandAll)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    work.isFavorite = false
                                    work.markModified()
                                    try? context.save()
                                } label: {
                                    Label("Unfavorite", systemImage: "star.slash")
                                }
                                .tint(.yellow)
                            }
                    }
                    .cardRow()
                }
                .cardList()
                .overlay {
                    if displayedFavorites.isEmpty {
                        ContentUnavailableView {
                            Label("No matching works", systemImage: "line.3.horizontal.decrease.circle")
                        } description: {
                            Text("No favorites match the current filters.")
                        } actions: {
                            Button("Clear Filters") { filters = LibraryFilters() }
                        }
                    }
                }
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle("Favorites")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                if !visibleFavorites.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 2) {
                            FilterButton(filtersActive: filters.hasActiveFilters,
                                         showingFilters: $showingFilters,
                                         filterHelp: "Filter your favorites",
                                         onClearFilters: { filters = LibraryFilters() })
                            WorkListMoreMenu {
                                ExpandAllMenuItem(expandAll: $expandAll)
                            }
                        }
                    }
                }
            }
            .inspector(isPresented: $showingFilters) {
                LibraryFilterPanel(filters: $filters, works: visibleFavorites, userTagNames: allTags.map(\.name))
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
                #if os(iOS)
                    .presentationDragIndicator(.visible)
                #endif
            }
    }
}
