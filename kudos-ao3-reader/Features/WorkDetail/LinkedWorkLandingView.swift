import SwiftData
import SwiftUI

/// A link has only an AO3 id; load the same metadata value Work Detail uses for a
/// remote summary. Existing library copies need no network request.
struct LinkedWorkLandingView: View {
    let workID: Int

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AO3AuthService.self) private var auth
    @State private var localWork: SavedWork?
    @State private var summary: AO3WorkSummary?
    @State private var error: String?
    @State private var needsLogin = false
    @State private var showingLogin = false

    var body: some View {
        NavigationStack {
            Group {
                if let localWork {
                    WorkDetailView(work: localWork)
                } else if let summary {
                    WorkDetailView(remote: summary)
                } else if needsLogin {
                    ContentUnavailableView {
                        Label("Log In to AO3", systemImage: "lock")
                    } description: {
                        Text("This work may be available only to logged-in AO3 readers.")
                    } actions: {
                        Button("Log In to AO3") { showingLogin = true }
                    }
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn't Open Work", systemImage: "exclamationmark.triangle")
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
        }
        .sheet(isPresented: $showingLogin) {
            AO3LoginView(contextMessage: "This work may be available only to logged-in AO3 readers.")
        }
        .onChange(of: auth.isLoggedIn) { _, signedIn in
            if signedIn && needsLogin { Task { await load() } }
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        needsLogin = false
        let works = (try? context.fetch(FetchDescriptor<SavedWork>())) ?? []
        if let existing = WorkIdentityIndex(works).existingWork(
            ao3WorkID: workID, sourceURL: AO3Client.workURL(workID: workID).absoluteString
        ), !existing.isPendingDeletion {
            localWork = existing
            return
        }
        do {
            let metadata = try await WorkMetadataRefresh.remoteMetadata(workID: workID, auth: auth)
            summary = metadata.summaryValue
        } catch let ao3Error as AO3Error where !auth.isLoggedIn
            && (ao3Error == .notFound || ao3Error == .authenticationRequired || ao3Error == .parse) {
            needsLogin = true
            showingLogin = true
        } catch {
            self.error = WorkMetadataRefresh.message(for: error)
        }
    }
}
