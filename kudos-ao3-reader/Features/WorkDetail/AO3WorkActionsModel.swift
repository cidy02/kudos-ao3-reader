import SwiftUI

/// UI state + drivers for the native "On AO3" actions. Held by the host (Work
/// Detail / Reader) and shared with the actions menu, comments screen, bookmark
/// composer, and result alert via `.ao3WorkActions(…)`.
@MainActor
@Observable
final class AO3WorkActionsModel {
    /// True while a write is in flight (disables re-taps; shows progress).
    var isWorking = false
    /// A short result/info message shown as a host alert.
    var banner: String?

    /// Drives the bookmark composer sheet.
    var showingBookmark = false
    var bookmarkInput = AO3AuthService.BookmarkInput()
    var bookmarkError: String?
    /// True when the composer edits the existing AO3 bookmark (title/labels only —
    /// the submit itself re-detects the real state from the fresh work page).
    private(set) var bookmarkIsUpdate = false

    /// Live subscribed/bookmarked state for the menu labels, fetched lazily the
    /// first time the menu content appears for a work and after each relevant
    /// write. nil = unknown → the menu falls back to its default labels.
    private(set) var workPageStates: AO3WorkActionStates?
    private var workPageStatesWorkID: Int?
    private var isFetchingWorkPageStates = false

    /// One work-page GET, only when signed in and only once per work (or when
    /// `force`d after a write). Advisory labels only — see
    /// `AO3AuthService.workActionStates`.
    func refreshWorkPageStates(workID: Int, auth: AO3AuthService, force: Bool = false) {
        guard auth.isLoggedIn else {
            workPageStates = nil
            workPageStatesWorkID = nil
            return
        }
        if workPageStatesWorkID != workID {
            workPageStates = nil
            workPageStatesWorkID = workID
        } else if workPageStates != nil, !force {
            return
        }
        guard !isFetchingWorkPageStates else { return }
        isFetchingWorkPageStates = true
        Task {
            defer { isFetchingWorkPageStates = false }
            let states = try? await auth.workActionStates(workID: workID)
            // A slow response for a previous work must not label this one.
            guard workPageStatesWorkID == workID else { return }
            workPageStates = states
        }
    }

    /// Drives the native comments screen (sheet). The work context is captured at
    /// tap time — the model itself stays work-agnostic.
    var showingCommentsScreen = false
    var commentsContext = AO3CommentsWorkContext(title: "", authors: [])
    /// The AO3 story chapter to open comments on, when launched from a reader
    /// (chapter-aware button). nil from Work Detail → opens on All comments.
    var commentsInitialChapterPosition: Int?

    func startViewingComments(context: AO3CommentsWorkContext, initialChapterPosition: Int? = nil) {
        commentsContext = context
        commentsInitialChapterPosition = initialChapterPosition
        showingCommentsScreen = true
    }

    func giveKudos(workID: Int, auth: AO3AuthService) {
        run { try await auth.giveKudos(workID: workID) }
    }

    func subscribe(workID: Int, auth: AO3AuthService) {
        run(afterSuccessRefresh: (workID, auth)) { try await auth.toggleSubscribe(workID: workID) }
    }

    func markForLater(workID: Int, auth: AO3AuthService) {
        run { try await auth.markForLater(workID: workID) }
    }

    /// Runs a fire-and-forget write whose result is shown as the host banner.
    /// Pass `afterSuccessRefresh` for writes that change the menu's
    /// subscribed/bookmarked labels so they refetch instead of going stale.
    private func run(
        afterSuccessRefresh: (workID: Int, auth: AO3AuthService)? = nil,
        _ action: @escaping () async throws -> String
    ) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            do {
                banner = try await action()
                if let refresh = afterSuccessRefresh {
                    refreshWorkPageStates(workID: refresh.workID, auth: refresh.auth, force: true)
                }
            } catch {
                banner = Self.message(for: error)
            }
            isWorking = false
        }
    }

    /// Opens the composer — prefilled with the existing bookmark's values when
    /// the fetched state says this work is already bookmarked, blank otherwise.
    func startBookmark() {
        if let existing = workPageStates?.existingBookmark {
            bookmarkInput = existing.input
            bookmarkIsUpdate = true
        } else {
            bookmarkInput = AO3AuthService.BookmarkInput()
            bookmarkIsUpdate = false
        }
        bookmarkError = nil
        showingBookmark = true
    }

    func submitBookmark(workID: Int, auth: AO3AuthService) {
        guard !isWorking else { return }
        let input = bookmarkInput
        isWorking = true
        bookmarkError = nil
        Task {
            do {
                let message = try await auth.saveBookmark(workID: workID, input: input)
                showingBookmark = false
                banner = message
                refreshWorkPageStates(workID: workID, auth: auth, force: true)
            } catch {
                bookmarkError = Self.message(for: error)
            }
            isWorking = false
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Host wiring

extension View {
    /// Presents the comments screen, bookmark composer, and result alert.
    /// Apply on the host that also shows `AO3WorkActionsMenu`.
    func ao3WorkActions(_ actions: AO3WorkActionsModel, workID: Int, auth: AO3AuthService) -> some View {
        modifier(AO3WorkActionsModifier(actions: actions, workID: workID, auth: auth))
    }
}

private struct AO3WorkActionsModifier: ViewModifier {
    @Bindable var actions: AO3WorkActionsModel
    let workID: Int
    let auth: AO3AuthService

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $actions.showingBookmark) {
                AO3BookmarkComposer(actions: actions, workID: workID, auth: auth)
            }
            .commentsSheet(
                isPresented: $actions.showingCommentsScreen,
                workID: workID,
                context: actions.commentsContext,
                initialChapterPosition: actions.commentsInitialChapterPosition
            )
            .alert("AO3", isPresented: bannerPresented) {
                Button("OK", role: .cancel) { actions.banner = nil }
            } message: {
                Text(actions.banner ?? "")
            }
    }

    private var bannerPresented: Binding<Bool> {
        Binding(get: { actions.banner != nil },
                set: { if !$0 { actions.banner = nil } })
    }
}

/// A compose sheet for a native AO3 bookmark: optional notes + tags, and the
/// private / rec toggles, posted to the user's account under their default pseud.
private struct AO3BookmarkComposer: View {
    @Bindable var actions: AO3WorkActionsModel
    let workID: Int
    let auth: AO3AuthService

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Notes") {
                        TextEditor(text: $actions.bookmarkInput.notes)
                            .frame(minHeight: 90)
                            .disabled(actions.isWorking)
                    }
                    Section {
                        TextField("Comma-separated tags", text: $actions.bookmarkInput.tags)
                            .disabled(actions.isWorking)
                    } header: {
                        Text("Tags")
                    } footer: {
                        Text("Your own bookmark tags, separated by commas.")
                    }
                    Section {
                        Toggle("Private", isOn: $actions.bookmarkInput.isPrivate)
                        Toggle("Recommend", isOn: $actions.bookmarkInput.isRec)
                    }
                    if let error = actions.bookmarkError {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .appThemedRows()
            }
            .formStyle(.grouped)
            .appThemedScroll()
            .navigationTitle(actions.bookmarkIsUpdate ? "Edit Bookmark on AO3" : "Bookmark on AO3")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(actions.isWorking)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if actions.isWorking {
                            ProgressView()
                        } else {
                            Button("Save") { actions.submitBookmark(workID: workID, auth: auth) }
                        }
                    }
                }
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(actions.isWorking)
        }
    }
}
