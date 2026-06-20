import SwiftUI

/// The "Marked for Later" segment of the Bookmarks tab: the user's AO3 reading
/// queue (`/users/<name>/readings?show=to-read`), fetched with their session via
/// `AO3AuthService`. Reuses the search result card + pagination, and navigates to
/// `AO3WorkDetailView` through the Bookmarks tab's own navigation stack (so the
/// host must register an `AO3WorkSummary` destination).
struct MarkedForLaterList: View {
    @Environment(AO3AuthService.self) private var auth

    @State private var works: [AO3WorkSummary] = []
    @State private var currentPage = 1
    @State private var totalPages = 1
    @State private var phase: Phase = .idle
    @State private var showLogin = false

    private enum Phase: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var body: some View {
        Group {
            if auth.isLoggedIn {
                signedInContent
            } else {
                signedOutPrompt
            }
        }
        .task(id: auth.isLoggedIn) {
            // Load on first appearance and again right after a sign-in; skip the
            // signed-out state so we don't fire an unauthenticated request.
            if auth.isLoggedIn, phase == .idle { await load(page: 1) }
        }
        .sheet(isPresented: $showLogin) { AO3LoginView() }
    }

    // MARK: Signed in

    @ViewBuilder
    private var signedInContent: some View {
        switch phase {
        case .loaded where works.isEmpty:
            ContentUnavailableView {
                Label("Nothing marked for later", systemImage: "bookmark")
            } description: {
                Text("Tap “Mark for Later” on a work on AO3 to queue it up here.")
            }

        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load your list", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load(page: currentPage) } }
            }

        case .loading where works.isEmpty:
            ProgressView("Loading your reading list…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        default:
            worksList
        }
    }

    private var worksList: some View {
        List {
            if showPagination {
                Section { paginationRow }
            }
            Section {
                ForEach(works) { work in
                    NavigationLink(value: work) { AO3WorkRow(work: work) }
                }
                .cardRow()
            }
            if showPagination {
                Section { paginationRow }
            }
        }
        .cardList()
        .overlay {
            if phase == .loading { ProgressView().controlSize(.large) }
        }
        .refreshable { await load(page: currentPage) }
    }

    private var showPagination: Bool { totalPages > 1 && !works.isEmpty }

    private var paginationRow: some View {
        SearchPaginationBar(currentPage: currentPage, totalPages: totalPages) { page in
            Task { await load(page: page) }
        }
        .cardRow()
    }

    // MARK: Signed out

    private var signedOutPrompt: some View {
        ContentUnavailableView {
            Label("Marked for Later", systemImage: "bookmark")
        } description: {
            Text("Log in to AO3 to see the works you've marked to read later.")
        } actions: {
            Button("Log In to AO3") { showLogin = true }
        }
    }

    // MARK: Loading

    private func load(page: Int) async {
        guard let username = auth.username,
              let url = AO3Client.markedForLaterURL(username: username, page: page)
        else {
            phase = .failed("You need to be logged in to AO3.")
            return
        }
        phase = .loading
        do {
            let request = try auth.authenticatedRequest(for: url)
            let result = try await AO3Client.shared.worksPage(for: request, page: page)
            works = result.works
            currentPage = result.currentPage
            totalPages = result.totalPages
            phase = .loaded
        } catch AO3Error.authenticationRequired {
            await auth.sessionDidExpire()
            works = []
            phase = .idle   // back to the signed-out prompt
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
