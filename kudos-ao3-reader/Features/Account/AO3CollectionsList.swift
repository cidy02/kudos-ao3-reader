import SwiftUI

/// The signed-in user's AO3 collections (native, read-only). Tapping a collection
/// pushes its works (reusing `AO3AccountWorksList` via the `.collection` kind, routed
/// by the host's `AO3AccountWorksList.Kind` navigation destination).
struct AO3CollectionsList: View {
    @Environment(AO3AuthService.self) private var auth

    @State private var collections: [AO3Collection] = []
    @State private var phase: Phase = .idle
    @State private var showLogin = false

    private enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    var body: some View {
        Group {
            if auth.isLoggedIn { signedInContent } else { signedOutPrompt }
        }
        .navigationTitle("My Collections")
        #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .hidesFloatingTabBar()
            .task(id: auth.isLoggedIn) {
                if auth.isLoggedIn, phase == .idle { await load() }
            }
            .sheet(isPresented: $showLogin) { AO3LoginView() }
    }

    @ViewBuilder
    private var signedInContent: some View {
        switch phase {
        case .loaded where collections.isEmpty:
            ContentUnavailableView {
                Label("No collections", systemImage: "square.stack")
            } description: {
                Text("Collections you create or maintain on AO3 show up here.")
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn't load collections", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        case .loading where collections.isEmpty:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            List {
                Section {
                    ForEach(collections) { collection in
                        NavigationLink(value: AO3AccountWorksList.Kind.collection(
                            name: collection.name, title: collection.title)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(collection.title).foregroundStyle(.primary)
                                    if !collection.byline.isEmpty {
                                        Text(collection.byline)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                    }
                    .cardRow()
                }
            }
            .cardList()
            .refreshable { await load() }
        }
    }

    private var signedOutPrompt: some View {
        ContentUnavailableView {
            Label("My Collections", systemImage: "square.stack")
        } description: {
            Text("Log in to AO3 to see your collections.")
        } actions: {
            Button("Log In to AO3…") { showLogin = true }
        }
    }

    private func load() async {
        guard auth.isLoggedIn, let username = auth.username,
              let url = AO3Client.collectionsURL(username: username, page: 1) else { return }
        if collections.isEmpty { phase = .loading }
        do {
            let request = try auth.authenticatedRequest(for: url)
            collections = try await AO3Client.shared.collectionsPage(for: request)
            phase = .loaded
        } catch let error as AO3Error {
            phase = .failed(error.errorDescription ?? "Something went wrong.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
