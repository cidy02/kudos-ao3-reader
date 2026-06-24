import SwiftUI
import SwiftData

/// Account → App → Privacy & Local Data (Part 9). Makes the app's privacy promise
/// concrete: explains what's stored on-device, and gives controls to clear caches,
/// remove the AO3 session, and clear local reading history. No analytics or tracking.
struct PrivacyDataView: View {
    @Environment(\.modelContext) private var context
    @Environment(AO3AuthService.self) private var auth

    @Query(filter: #Predicate<SavedWork> { !$0.hasEPUB }, sort: \SavedWork.dateAdded, order: .reverse)
    private var history: [SavedWork]

    @State private var confirmClearHistory = false
    @State private var browseCacheCleared = false

    var body: some View {
        Form {
            Group {
                Section {
                    Label("No ads, analytics, tracking, or hidden data collection.",
                          systemImage: "hand.raised")
                        .font(.subheadline)
                } footer: {
                    Text("Everything Kudos stores — your library, reading progress, tags, "
                         + "collections, and AO3 session — stays on this device. Nothing is sent "
                         + "anywhere except AO3 itself, to load the works you ask for.")
                }

                Section {
                    switch auth.status {
                    case .signedIn(let username):
                        LabeledContent("Signed in", value: username)
                        Button(role: .destructive) {
                            Task { await auth.logout() }
                        } label: {
                            Label("Remove AO3 Session", systemImage: "person.badge.minus")
                        }
                    default:
                        Text("Not signed in.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AO3 Session")
                } footer: {
                    Text("Your AO3 session is stored only on this device and is never shared.")
                }

                Section {
                    Button {
                        FandomCatalog.shared.clearCache()
                        browseCacheCleared = true
                    } label: {
                        Label(browseCacheCleared ? "Browse Cache Cleared" : "Clear Browse Cache",
                              systemImage: "trash")
                    }
                    .disabled(browseCacheCleared)
                } header: {
                    Text("Caches")
                } footer: {
                    Text("Cached AO3 fandom and category data used to show Browse instantly. Safe "
                         + "to clear — it rebuilds the next time you open Browse.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmClearHistory = true
                    } label: {
                        Label("Clear Reading History", systemImage: "clock.badge.xmark")
                    }
                    .disabled(history.isEmpty)
                } header: {
                    Text("Local Data")
                } footer: {
                    Text("\(history.count) finished work\(history.count == 1 ? "" : "s") in your "
                         + "local reading history (their files were already freed). Your saved and "
                         + "downloaded works aren't affected.")
                }
            }
            .appThemedRows()
        }
        .formStyle(.grouped)
        .appThemedScroll()
        .navigationTitle("Privacy & Local Data")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            "Clear Reading History?",
            isPresented: $confirmClearHistory,
            titleVisibility: .visible
        ) {
            Button("Clear \(history.count) Work\(history.count == 1 ? "" : "s")", role: .destructive) {
                for work in history { context.delete(work) }
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes your local reading-history records. The works themselves can be "
                 + "re-downloaded from AO3 anytime.")
        }
    }
}
