import Accessibility
import SwiftUI

/// UI state + drivers for the native "On AO3" actions. Held by the host (Work
/// Detail / Reader) and shared with the actions menu, comments screen, bookmark
/// composer, and result alert via `.ao3WorkActions(…)`.
@MainActor
@Observable
final class AO3WorkActionsModel {
    typealias SubscribeHandler = @MainActor (Int, Bool, AO3AuthService) async throws -> String
    typealias WorkActionStatesHandler = @MainActor (Int, AO3AuthService) async throws -> AO3WorkActionStates

    /// True while a write is in flight (disables re-taps; shows progress).
    var isWorking = false
    /// A short error or non-kudos/bookmark result shown as a host alert.
    var banner: String?
    /// Set only after AO3 accepts kudos, so a menu opened again in this screen
    /// immediately shows the filled, disabled state even for an unsaved work.
    private(set) var kudosGivenWorkID: Int?
    /// Set as soon as AO3 accepts a bookmark, without waiting for the advisory
    /// work-page refresh that follows the write.
    private(set) var bookmarkedWorkID: Int?
    /// Bumped by the write handlers when AO3 accepts / rejects a write — the haptic
    /// triggers (never a value that also changes when a page loads).
    private(set) var writeSuccesses = 0
    private(set) var writeFailures = 0

    /// Drives the bookmark composer sheet.
    var showingBookmark = false
    var bookmarkInput = AO3AuthService.BookmarkInput()
    var bookmarkError: String?
    /// An update has no icon state to change, so confirm it briefly in the sheet.
    private(set) var bookmarkSuccess: String?
    /// True when the composer edits the existing AO3 bookmark (title/labels only —
    /// the submit itself re-detects the real state from the fresh work page).
    private(set) var bookmarkIsUpdate = false

    /// Live subscribed/bookmarked state for the menu labels, fetched lazily the
    /// first time the menu content appears for a work and after each relevant
    /// write. nil = unknown → the menu falls back to its default labels.
    private(set) var workPageStates: AO3WorkActionStates?
    private var workPageStatesWorkID: Int?
    private var workPageStatesGeneration: Int?
    private var hasSyncedWorkPageStates = false
    private var isFetchingWorkPageStates = false
    private var workPageStatesRevision = 0
    private var activeTask: Task<Void, Never>?
    private var stateFetchTask: Task<Void, Never>?
    private let subscribeHandler: SubscribeHandler
    private let workActionStatesHandler: WorkActionStatesHandler

    init(
        using client: AO3Client = .shared,
        subscribeHandler: SubscribeHandler? = nil,
        workActionStatesHandler: WorkActionStatesHandler? = nil
    ) {
        self.subscribeHandler = subscribeHandler ?? { workID, want, auth in
            try await auth.toggleSubscribe(workID: workID, to: want, using: client)
        }
        if let workActionStatesHandler {
            self.workActionStatesHandler = workActionStatesHandler
        } else if subscribeHandler != nil {
            self.workActionStatesHandler = { _, _ in throw CancellationError() }
        } else {
            self.workActionStatesHandler = { workID, auth in
                try await auth.workActionStates(workID: workID, using: client)
            }
        }
    }

    func waitForCurrentTask() async {
        await activeTask?.value
    }

    func waitForStateFetch() async {
        await stateFetchTask?.value
    }

    /// One work-page GET, only when signed in and only once per work/session
    /// (or when `force`d after a write). Advisory labels only — see
    /// `AO3AuthService.workActionStates`.
    func refreshWorkPageStates(workID: Int, auth: AO3AuthService, force: Bool = false) {
        guard auth.isLoggedIn else {
            workPageStatesRevision += 1
            workPageStates = nil
            workPageStatesWorkID = nil
            workPageStatesGeneration = nil
            hasSyncedWorkPageStates = false
            isFetchingWorkPageStates = false
            return
        }
        let expectedGeneration = auth.sessionGeneration
        if workPageStatesWorkID != workID || workPageStatesGeneration != expectedGeneration {
            workPageStatesRevision += 1
            workPageStates = nil
            workPageStatesWorkID = workID
            workPageStatesGeneration = expectedGeneration
            hasSyncedWorkPageStates = false
            isFetchingWorkPageStates = false
        } else if force {
            workPageStatesRevision += 1
            isFetchingWorkPageStates = false
        } else if hasSyncedWorkPageStates {
            return
        }
        guard !isFetchingWorkPageStates else { return }
        isFetchingWorkPageStates = true
        let revision = workPageStatesRevision
        stateFetchTask = Task {
            defer {
                if workPageStatesWorkID == workID,
                   workPageStatesGeneration == expectedGeneration,
                   workPageStatesRevision == revision {
                    isFetchingWorkPageStates = false
                }
            }
            let states = try? await workActionStatesHandler(workID, auth)
            // A slow response for a previous work or session must not label this one.
            guard auth.sessionGeneration == expectedGeneration,
                  workPageStatesWorkID == workID,
                  workPageStatesGeneration == expectedGeneration,
                  workPageStatesRevision == revision
            else { return }
            if let states {
                workPageStates = states
                hasSyncedWorkPageStates = true
            }
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

    func giveKudos(
        workID: Int,
        auth: AO3AuthService,
        onSuccess: (() -> Void)? = nil
    ) {
        let expectedGeneration = auth.sessionGeneration
        run(auth: auth, presentsSuccess: false) {
            let message = try await auth.giveKudos(workID: workID)
            guard auth.sessionGeneration == expectedGeneration else { throw CancellationError() }
            self.kudosGivenWorkID = workID
            onSuccess?()
            return message
        }
    }

    func subscribe(workID: Int, to want: Bool, auth: AO3AuthService, onSubscribed: (() -> Void)? = nil) {
        let expectedGeneration = auth.sessionGeneration
        run(auth: auth) {
            let message = try await self.subscribeHandler(workID, want, auth)
            guard auth.sessionGeneration == expectedGeneration else { throw CancellationError() }
            if self.workPageStatesWorkID == nil || self.workPageStatesWorkID == workID {
                let sameScope = self.workPageStatesWorkID == workID
                    && self.workPageStatesGeneration == expectedGeneration
                let hadStates = sameScope && self.workPageStates != nil
                let existingBookmark = sameScope ? self.workPageStates?.existingBookmark : nil
                self.workPageStatesWorkID = workID
                self.workPageStatesGeneration = expectedGeneration
                self.workPageStatesRevision += 1
                self.isFetchingWorkPageStates = false
                self.workPageStates = AO3WorkActionStates(
                    isSubscribed: want, existingBookmark: existingBookmark
                )
                if !hadStates {
                    self.refreshWorkPageStates(workID: workID, auth: auth, force: true)
                }
            }
            if want { onSubscribed?() }
            return message
        }
    }

    func markForLater(workID: Int, auth: AO3AuthService) {
        run(auth: auth) { try await auth.markForLater(workID: workID) }
    }

    /// Runs a fire-and-forget write. Kudos announces success in place; the
    /// other actions continue to show their result in the host alert.
    private func run(
        auth: AO3AuthService,
        presentsSuccess: Bool = true,
        _ action: @escaping () async throws -> String
    ) {
        guard !isWorking else { return }
        let expectedGeneration = auth.sessionGeneration
        isWorking = true
        activeTask = Task {
            defer {
                isWorking = false
                activeTask = nil
            }
            do {
                let message = try await action()
                guard auth.sessionGeneration == expectedGeneration else { return }
                if presentsSuccess {
                    banner = message
                } else {
                    AccessibilityNotification.Announcement(message).post()
                }
                writeSuccesses += 1
            } catch is CancellationError {
                return
            } catch AO3Error.authenticationRequired {
                guard auth.sessionGeneration == expectedGeneration else { return }
                let expired = await auth.sessionDidExpire(expectedGeneration: expectedGeneration)
                guard !Task.isCancelled else { return }
                if expired {
                    workPageStatesRevision += 1
                    workPageStates = nil
                    workPageStatesWorkID = nil
                    workPageStatesGeneration = nil
                    hasSyncedWorkPageStates = false
                    isFetchingWorkPageStates = false
                    banner = AO3Error.authenticationRequired.errorDescription
                    writeFailures += 1
                }
            } catch {
                guard auth.sessionGeneration == expectedGeneration else { return }
                banner = Self.message(for: error)
                writeFailures += 1
            }
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
        bookmarkSuccess = nil
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
                bookmarkedWorkID = workID
                AccessibilityNotification.Announcement(message).post()
                writeSuccesses += 1
                refreshWorkPageStates(workID: workID, auth: auth, force: true)
                isWorking = false
                guard message == "Bookmark updated." else {
                    showingBookmark = false
                    return
                }
                bookmarkSuccess = message
                try? await Task.sleep(for: .seconds(2))
                guard bookmarkSuccess == message else { return }
                bookmarkSuccess = nil
                showingBookmark = false
            } catch {
                bookmarkError = Self.message(for: error)
                writeFailures += 1
                isWorking = false
            }
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? UserFacingError.message(for: error)
    }
}

// MARK: - Host wiring

extension View {
    /// Presents the comments screen, bookmark composer, and result alert.
    /// Apply on the host that also shows `AO3WorkActionsMenu`.
    func ao3WorkActions(
        _ actions: AO3WorkActionsModel,
        workID: Int,
        auth: AO3AuthService,
        readerSections: [ReaderSection] = [],
        onOpenReaderChapter: ((Int) -> Void)? = nil
    ) -> some View {
        modifier(AO3WorkActionsModifier(
            actions: actions,
            workID: workID,
            auth: auth,
            readerSections: readerSections,
            onOpenReaderChapter: onOpenReaderChapter
        ))
    }
}

private struct AO3WorkActionsModifier: ViewModifier {
    @Bindable var actions: AO3WorkActionsModel
    let workID: Int
    let auth: AO3AuthService
    var readerSections: [ReaderSection]
    var onOpenReaderChapter: ((Int) -> Void)?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $actions.showingBookmark) {
                AO3BookmarkComposer(actions: actions, workID: workID, auth: auth)
                #if os(iOS)
                    .modifier(ScopeSurfaceAccent())
                #endif
            }
            .commentsSheet(
                isPresented: $actions.showingCommentsScreen,
                workID: workID,
                context: actions.commentsContext,
                initialChapterPosition: actions.commentsInitialChapterPosition,
                readerSections: readerSections,
                onOpenReaderChapter: onOpenReaderChapter
            )
            .sensoryFeedback(.success, trigger: actions.writeSuccesses)
            .sensoryFeedback(.error, trigger: actions.writeFailures)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                        Text("Separate your bookmark tags with commas.")
                    }
                    Section {
                        toggle("Private", isOn: $actions.bookmarkInput.isPrivate)
                        toggle("Recommend", isOn: $actions.bookmarkInput.isRec)
                    }
                    if let error = actions.bookmarkError {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }
                    if let success = actions.bookmarkSuccess {
                        Section {
                            Label(success, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.accentInk)
                        }
                    }
                }
                .appThemedRows()
            }
            .formStyle(.grouped)
            .appThemedScroll()
            .wrappingInlineTitle(actions.bookmarkIsUpdate ? "Edit Bookmark on AO3" : "Bookmark on AO3")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(actions.isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if actions.isWorking {
                        ProgressView().accentFill()
                    } else if actions.bookmarkSuccess != nil {
                        Label("Saved", systemImage: "checkmark")
                    } else {
                        Button("Save") { actions.submitBookmark(workID: workID, auth: auth) }
                    }
                }
            }
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(actions.isWorking)
        }
    }

    /// The label over its switch at the accessibility sizes: beside it,
    /// "Recommend" broke as "Recom- / mend". VoiceOver reads the toggle's own label.
    @ViewBuilder
    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).accessibilityHidden(true)
                Toggle(title, isOn: isOn).labelsHidden().accentFill()
            }
        } else {
            Toggle(title, isOn: isOn).accentFill()
        }
    }
}
