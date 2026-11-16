import SwiftData
import SwiftUI

/// A link has only an AO3 id; load the same metadata value Work Detail uses for a
/// remote summary. Existing library copies need no network request.
struct LinkedWorkLandingView: View {
    let workID: Int
    var chapterID: Int? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AO3AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @State private var path = NavigationPath()
    @State private var localWork: SavedWork?
    @State private var summary: AO3WorkSummary?
    @State private var error: String?
    @State private var isNotFound = false
    @State private var needsLogin = false
    @State private var showingBrowser = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let localWork {
                    WorkDetailView(work: localWork, linkedChapterID: chapterID)
                } else if let summary {
                    WorkDetailView(remote: summary, linkedChapterID: chapterID)
                } else if needsLogin {
                    ContentUnavailableView {
                        Label("Log In to AO3", systemImage: "lock")
                    } description: {
                        Text("This work may be available only to logged-in AO3 readers.")
                    } actions: {
                        Button("Log In to AO3") {
                            router.requestLinkedWorkLogin(sessionGeneration: auth.sessionGeneration)
                        }
                    }
                } else if let error {
                    ContentUnavailableView {
                        Label(isNotFound ? "Work Not Found" : "Couldn't Open Work",
                              systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { Task { await load() } }
                    }
                } else {
                    ProgressView("Opening work…")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(for: AO3CommentsRoute.self) { route in
                CommentsView(workID: route.workID, context: route.context,
                             initialFocusesChapter: route.focusesChapter,
                             initialComposes: route.composes)
            }
            .navigationDestination(for: AO3AuthorRoute.self) { AuthorProfileView(route: $0) }
            .navigationDestination(for: AO3SeriesSummary.self) { AO3SeriesDetailView(series: $0) }
            .navigationDestination(for: RemoteWorkReaderRoute.self) {
                RemoteWorkReaderDestination(summary: $0.work)
            }
            .navigationDestination(for: AO3TagWorksRequest.self) { TagWorksView(request: $0) }
        }
        .presentationDragIndicator(.visible)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
        .sheet(isPresented: $showingBrowser, onDismiss: {
            router.isPresentingWebBrowser = false
        }) { AO3WebBrowserView() }
        .onChange(of: router.isPresentingWebBrowser) { _, presented in
            showingBrowser = presented
        }
        .onChange(of: router.authorProfileNavigationEpoch) { _, _ in
            if let route = router.consumePendingAuthorProfile() { path.append(route) }
        }
        .onChange(of: router.pendingLandingTagWorks, initial: true) { _, request in
            guard let request else { return }
            router.pendingLandingTagWorks = nil
            path.append(request)
        }
        .onChange(of: router.pendingLandingTagSearch) { _, request in
            guard let request else { return }
            router.pendingLandingTagSearch = nil
            let slug = request.value
                .replacingOccurrences(of: "/", with: "*s*")
                .replacingOccurrences(of: "&", with: "*a*")
                .replacingOccurrences(of: ".", with: "*d*")
                .replacingOccurrences(of: "?", with: "*q*")
                .replacingOccurrences(of: "#", with: "*h*")
            if let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "https://archiveofourown.org/tags/\(encoded)/works") {
                path.append(AO3TagWorksRequest(url: url, title: request.value))
            }
        }
        .task(id: auth.status) {
            if !needsLogin || auth.isLoggedIn { await load() }
        }
        .onChange(of: auth.sessionGeneration) { _, _ in
            if needsLogin && auth.isLoggedIn { Task { await load() } }
        }
    }

    private func load() async {
        error = nil
        isNotFound = false
        needsLogin = false
        localWork = nil
        summary = nil
        let works = (try? context.fetch(FetchDescriptor<SavedWork>(
            predicate: #Predicate<SavedWork> { !$0.isPendingDeletion }
        ))) ?? []
        if let existing = WorkIdentityIndex(works).existingWork(
            ao3WorkID: workID, sourceURL: AO3Client.workURL(workID: workID).absoluteString
        ), !existing.isPendingDeletion {
            localWork = existing
            return
        }
        if !Self.canFetchRemote(status: auth.status) { return }
        do {
            let metadata = try await WorkMetadataRefresh.remoteMetadata(workID: workID, auth: auth)
            guard !Task.isCancelled, router.pendingWorkLink?.id == workID,
                  router.pendingWorkLink?.chapterID == chapterID else { return }
            summary = metadata.summaryValue
        } catch let ao3Error as AO3Error where Self.requiresLogin(ao3Error, isLoggedIn: auth.isLoggedIn) {
            guard !Task.isCancelled, router.pendingWorkLink?.id == workID,
                  router.pendingWorkLink?.chapterID == chapterID else { return }
            needsLogin = true
            router.requestLinkedWorkLogin(sessionGeneration: auth.sessionGeneration)
        } catch {
            guard !Task.isCancelled, router.pendingWorkLink?.id == workID,
                  router.pendingWorkLink?.chapterID == chapterID else { return }
            isNotFound = (error as? AO3Error) == .notFound
            self.error = WorkMetadataRefresh.message(for: error)
        }
    }

    static func canFetchRemote(status: AO3AuthStatus) -> Bool {
        // Bounded by LiveAO3SessionValidator's 20 s request timeout when restoring a session.
        status != .restoring
    }

    static func requiresLogin(_ error: AO3Error, isLoggedIn: Bool) -> Bool {
        error == .authenticationRequired || (!isLoggedIn && error == .parse)
    }
}
