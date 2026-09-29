import SwiftUI

/// 1bn's bulk bar in select mode on your own works: Edit N, Collections,
/// Visibility — the three open AO3's Edit Multiple Works, the last two on
/// their own group — and Delete, which asks first, naming what goes.
struct OwnWorksBulkBar: View {
    let selectedCount: Int
    let isBusy: Bool
    let edit: (EditMultipleWorksView.Focus?) -> Void
    let delete: () -> Void

    var body: some View {
        Group {
            Button(selectedCount > 0 ? "Edit \(selectedCount)" : "Edit") { edit(nil) }
            Spacer()
            Button("Collections") { edit(.collections) }
            Spacer()
            Button("Visibility") { edit(.visibility) }
            Spacer()
            Button("Delete", role: .destructive, action: delete)
            if isBusy { ProgressView().controlSize(.small) }
        }
        .disabled(selectedCount < 1 || isBusy)
    }

    /// 1bo's alert shape: "Delete “Title”?" for one, "Delete 3 works?" for more.
    static func deleteTitle(_ works: [AO3WorkSummary]) -> String {
        works.count == 1 ? "Delete “\(works[0].title)”?" : "Delete \(works.count) works?"
    }

    /// Names every work: a bulk delete is the one place a list is the point.
    /// The single swipe's wording (`AuthorProfileView`), made plural.
    static func deleteMessage(_ works: [AO3WorkSummary]) -> String {
        guard works.count > 1 else {
            return "This removes the work from AO3 for everyone, with its chapters, kudos, comments "
                + "and bookmarks. It cannot be undone."
        }
        let titles = ListFormatter.localizedString(byJoining: works.map { "“\($0.title)”" })
        return "This removes \(titles) from AO3 for everyone, with their chapters, kudos, comments "
            + "and bookmarks. It cannot be undone."
    }
}

/// The bar's Delete: the alert naming the works, then AO3's bulk delete.
/// `pending` holds the works named, fixed when the alert opened, and the
/// session they were selected under, which the write is fenced to.
struct OwnWorksBulkDelete: ViewModifier {
    @Environment(AO3AuthService.self) private var auth
    @Binding var pending: (works: [AO3WorkSummary], generation: Int)?
    @Binding var isDeleting: Bool
    @Binding var errorMessage: String?
    let onDeleted: () async -> Void

    func body(content: Content) -> some View {
        content.alert(
            OwnWorksBulkBar.deleteTitle(pending?.works ?? []),
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button("Delete on AO3", role: .destructive) { confirm() }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text(OwnWorksBulkBar.deleteMessage(pending?.works ?? []))
        }
    }

    private func confirm() {
        guard let named = pending, !isDeleting else { return }
        pending = nil
        isDeleting = true
        Task {
            do {
                _ = try await AO3RequestCoordinator.shared.withSlot {
                    try await auth.deleteWorks(workIDs: named.works.map(\.id), expectedGeneration: named.generation)
                }
                await onDeleted()
            } catch is CancellationError {
                errorMessage = "Your AO3 session changed, so nothing was deleted."
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
            isDeleting = false
        }
    }
}

/// Done, and the bar — at the bottom on iOS, as the shared selection toolbar
/// places its own.
struct OwnWorksSelectionToolbar: ToolbarContent {
    let controller: RemoteWorkSelectionController
    let bar: () -> OwnWorksBulkBar

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button { controller.exitSelectMode() } label: { Image(systemName: "checkmark") }
                .accessibilityLabel("Done")
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) { bar() }
        #else
        ToolbarItemGroup(placement: .primaryAction) { bar() }
        #endif
    }
}
