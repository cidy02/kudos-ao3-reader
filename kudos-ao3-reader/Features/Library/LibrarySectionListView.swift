import SwiftUI
import SwiftData

/// The full, vertically scrolling list behind a Library section's `>` chevron.
/// Mirrors `HomeSectionListView`, but adds the Library's per-row swipe actions and,
/// for Saved for Later, also surfaces the user's AO3 "Marked for Later" list in a
/// second section. Navigation resolves through the Library's root stack (which
/// registers the `SavedWork` and `AO3WorkSummary` destinations).
struct LibrarySectionListView: View {
    let kind: LibrarySectionKind

    @Environment(\.modelContext) private var context
    @Environment(PrivacyGate.self) private var gate
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AO3AuthService.self) private var auth
    @AppStorage("hideMatureContent") private var hideMature = true
    @AppStorage("matureContentMode") private var matureMode: MaturePrivacyMode = .obscure
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true

    @Query(sort: \SavedWork.dateAdded, order: .reverse) private var works: [SavedWork]
    @State private var pendingDelete: SavedWork?
    @State private var markedForLater: [AO3WorkSummary] = []

    private func passesPrivacy(_ work: SavedWork) -> Bool {
        !gate.isHidden(work, enabled: hideMature, mode: matureMode)
    }

    private var items: [SavedWork] { kind.works(from: works, visible: passesPrivacy) }

    /// Saved for Later is the one section that merges in a remote (AO3) list.
    private var showsMarkedForLater: Bool { kind == .savedForLater && !markedForLater.isEmpty }

    var body: some View {
        content
            .background((themeManager.appTheme.appBaseBackground ?? Color.clear).ignoresSafeArea())
            .navigationTitle(kind.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .deleteConfirmation(
                for: $pendingDelete,
                title: "Delete this work?",
                confirmLabel: "Delete",
                message: { "“\($0.title)” will be removed from your Library. This can't be undone." },
                perform: { WorkLifecycle.delete($0, in: context) }
            )
            .task(id: auth.isLoggedIn) {
                if kind == .savedForLater { await loadMarkedForLater() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if kind.isPlaceholder {
            ContentUnavailableView {
                Label(kind.title, systemImage: kind.emptyIcon)
            } description: {
                Text(kind.emptyMessage)
            }
        } else if items.isEmpty && !showsMarkedForLater {
            ContentUnavailableView {
                Label(kind.title, systemImage: kind.emptyIcon)
            } description: {
                Text(kind.emptyMessage)
            }
        } else {
            List {
                if !items.isEmpty {
                    Section {
                        ForEach(items, content: row).cardRow()
                    } header: {
                        if showsMarkedForLater { Text("Saved in Kudos") }
                    }
                }
                if showsMarkedForLater {
                    Section("Marked for Later on AO3") {
                        ForEach(markedForLater) { work in
                            AO3WorkRow(work: work).cardNavigation(to: work)
                        }
                        .cardRow()
                    }
                }
            }
            .cardList()
        }
    }

    /// A local work row with the Library's standard swipe actions (save / favorite /
    /// delete). Tapping opens the work via the root `SavedWork` destination.
    private func row(_ work: SavedWork) -> some View {
        SensitiveWorkRow(work: work)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    WorkLifecycle.setSaved(work, !work.isSaved, in: context)
                } label: {
                    Label(work.isSaved ? "Unsave" : "Save",
                          systemImage: work.isSaved ? "bookmark.slash" : "bookmark")
                }
                .tint(.blue)

                Button {
                    work.isFavorite.toggle()
                    try? context.save()
                } label: {
                    Label(work.isFavorite ? "Unfavorite" : "Favorite",
                          systemImage: work.isFavorite ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    if confirmBeforeDelete { pendingDelete = work } else { WorkLifecycle.delete(work, in: context) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func loadMarkedForLater() async {
        markedForLater = await auth.accountWorks(from: AO3Client.markedForLaterURL)
    }
}
