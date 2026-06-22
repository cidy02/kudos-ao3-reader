import SwiftUI
import SwiftData

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
            .navigationDestination(for: SavedWork.self) { WorkDetailView(work: $0) }
            .navigationDestination(for: AO3WorkSummary.self) { AO3WorkDetailView(work: $0, path: $path) }
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
        case .localHistory: LocalReadingHistoryView()
        case .localFavorites: LocalFavoritesView()
        case .settings: ReaderOptionsForm(includeAppSettings: true).navigationTitle("Settings")
        case .privacy: PrivacyDataView()
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var accountStatusSection: some View {
        Section {
            switch auth.status {
            case .restoring:
                HStack { ProgressView(); Text("Checking AO3 session…") }
            case .signedIn(let username):
                LabeledContent {
                    Text(username)
                } label: {
                    Label("Signed In", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
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

    private var myAO3Section: some View {
        Section("My AO3") {
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

    /// AO3 account areas not yet implemented natively — opened on AO3's website as a
    /// clearly-labeled fallback (Part 7 §3). No faked functionality.
    private var ao3WebsiteSection: some View {
        Section {
            webLink("My Dashboard", systemImage: "rectangle.grid.2x2", path: "/users/\(usernameOrEmpty)")
            webLink("My Works", systemImage: "doc.text", path: "/users/\(usernameOrEmpty)/works")
            webLink("My Collections", systemImage: "square.stack", path: "/users/\(usernameOrEmpty)/collections")
            webLink("My Preferences", systemImage: "slider.horizontal.3", path: "/preferences")
        } header: {
            Text("On AO3")
        } footer: {
            Text("These open on the AO3 website.")
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

    private var usernameOrEmpty: String { auth.username ?? "" }

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

    @Query(filter: #Predicate<SavedWork> { !$0.hasEPUB }, sort: \SavedWork.dateAdded, order: .reverse)
    private var history: [SavedWork]
    @State private var pendingDelete: SavedWork?

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    var body: some View {
        Group {
            if history.isEmpty {
                ContentUnavailableView {
                    Label("No history", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Works you finish without saving land here. Their files are freed, but you can re-download and revisit them anytime.")
                }
            } else if history.filter(passesPrivacy).isEmpty {
                MatureContentHiddenView()
            } else {
                List {
                    ForEach(history.filter(passesPrivacy)) { work in
                        SensitiveWorkRow(work: work)
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
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle("Local Reading History")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .deleteConfirmation(
            for: $pendingDelete,
            title: "Remove from History?",
            confirmLabel: "Remove",
            message: { "“\($0.title)” will be removed from your History." },
            perform: remove
        )
    }

    private func remove(_ work: SavedWork) {
        context.delete(work)
        try? context.save()
    }
}

/// Local favorites. Moved from the old Bookmarks tab.
private struct LocalFavoritesView: View {
    @Environment(\.modelContext) private var context
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure

    @Query(filter: #Predicate<SavedWork> { $0.isFavorite }, sort: \SavedWork.dateAdded, order: .reverse)
    private var favorites: [SavedWork]

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    var body: some View {
        Group {
            if favorites.isEmpty {
                ContentUnavailableView {
                    Label("No favorites", systemImage: "star")
                } description: {
                    Text("Swipe a work in your Library, or tap the star on its page, to favorite it.")
                }
            } else if favorites.filter(passesPrivacy).isEmpty {
                MatureContentHiddenView()
            } else {
                List {
                    ForEach(favorites.filter(passesPrivacy)) { work in
                        SensitiveWorkRow(work: work)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    work.isFavorite = false
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
            }
        }
        .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
        .navigationTitle("Favorites")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
