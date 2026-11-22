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
    typealias BookmarkHandler = @MainActor (Int, AO3AuthService.BookmarkInput, AO3AuthService) async throws -> String

    /// True while a write is in flight (disables re-taps; shows progress).
    var isWorking = false
    /// A short error or non-kudos/bookmark result shown as a host alert.
    var banner: String?
    /// Set only after AO3 accepts kudos, so a menu opened again in this screen
    /// immediately shows the filled, disabled state even for an unsaved work.
    private(set) var kudosGivenWorkID: Int?
    /// Set as soon as AO3 accepts a bookmark, without waiting for the advisory
    /// work-page refresh that follows the write.
    private var bookmarkedWorkID: Int?
    private var bookmarkedWorkGeneration: Int?
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
    private var bookmarkGeneration: Int?
    /// Normalized lowercase username that owns the open bookmark composer, or
    /// nil when opened while signed out (bound once `auth.isLoggedIn` is true).
    private var bookmarkOwnerUsername: String?
    private var bookmarkComposerRevision = 0
    private var lastSyncedGeneration: Int?

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
    private var dismissalTask: Task<Void, Never>?
    private let subscribeHandler: SubscribeHandler
    private let workActionStatesHandler: WorkActionStatesHandler
    private let bookmarkHandler: BookmarkHandler
    private let bookmarkDismissalSleep: @Sendable () async -> Void

    init(
        using client: AO3Client = .shared,
        subscribeHandler: SubscribeHandler? = nil,
        workActionStatesHandler: WorkActionStatesHandler? = nil,
        bookmarkHandler: BookmarkHandler? = nil,
        bookmarkDismissalSleep: (@Sendable () async -> Void)? = nil
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
        self.bookmarkHandler = bookmarkHandler ?? { workID, input, auth in
            try await auth.saveBookmark(workID: workID, input: input, using: client)
        }
        self.bookmarkDismissalSleep = bookmarkDismissalSleep ?? {
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// The subscribed state this model knows for `workID` under the current sign-in, or nil when
    /// it knows nothing for that work and session (never another account's or another work's).
    func knownSubscribed(workID: Int, generation: Int) -> Bool? {
        guard workPageStatesWorkID == workID, workPageStatesGeneration == generation else { return nil }
        return workPageStates?.isSubscribed
    }

    func waitForCurrentTask() async {
        await activeTask?.value
    }

    func waitForStateFetch() async {
        await stateFetchTask?.value
    }

    func waitForBookmarkDismissal() async {
        await dismissalTask?.value
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
                // Insights D11: a bookmark this page already shows (made on AO3, say).
                if let bookmark = states.existingBookmark {
                    OwnAO3ActionLog.recordSeenBookmark(isPrivate: bookmark.input.isPrivate, ao3WorkID: workID)
                }
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

    func isBookmarked(workID: Int, auth: AO3AuthService) -> Bool {
        (bookmarkedWorkID == workID && bookmarkedWorkGeneration == auth.sessionGeneration)
            || (workPageStatesWorkID == workID
                && workPageStatesGeneration == auth.sessionGeneration
                && workPageStates?.existingBookmark != nil)
    }

    /// Opens the composer — prefilled with the existing bookmark's values when
    /// the fetched state says this work is already bookmarked, blank otherwise.
    func startBookmark(workID: Int, auth: AO3AuthService) {
        dismissalTask?.cancel()
        dismissalTask = nil
        bookmarkComposerRevision += 1
        // Only syncSession advances lastSyncedGeneration: opening the composer must not
        // swallow a session change whose cached work-page state has not been dropped yet.
        bookmarkGeneration = auth.sessionGeneration
        bookmarkOwnerUsername = Self.normalizedOwner(for: auth)
        if workPageStatesWorkID == workID,
           workPageStatesGeneration == auth.sessionGeneration,
           let existing = workPageStates?.existingBookmark {
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

    /// Synchronizes cached work-page state and any open bookmark composer with
    /// `auth`'s current generation and login status. Safe to call repeatedly on
    /// every `sessionGeneration` and `status` change (including `accept()`'s
    /// generation bump before `finishAccepting` sets `.signedIn`).
    func syncSession(auth: AO3AuthService) {
        if lastSyncedGeneration != auth.sessionGeneration {
            lastSyncedGeneration = auth.sessionGeneration
            workPageStatesRevision += 1
            workPageStates = nil
            workPageStatesWorkID = nil
            workPageStatesGeneration = nil
            hasSyncedWorkPageStates = false
            isFetchingWorkPageStates = false
            bookmarkedWorkID = nil
            bookmarkedWorkGeneration = nil
        }

        guard showingBookmark else { return }

        let currentOwner = Self.normalizedOwner(for: auth)
        if let owner = bookmarkOwnerUsername {
            // Once owned by a signed-in account, leaving that account (sign-out,
            // expiry, replacement login, or a different username) clears and
            // closes the composer. Case-only differences stay the same account.
            if let currentOwner, currentOwner == owner {
                bookmarkGeneration = auth.sessionGeneration
                return
            }
            clearBookmarkComposer()
            return
        }

        // Opened while signed out: keep the reader's draft across intermediate
        // `.signingIn`/`.restoring` transitions, and bind + arm Save once
        // `auth.isLoggedIn` becomes true.
        if let currentOwner {
            bookmarkOwnerUsername = currentOwner
            bookmarkGeneration = auth.sessionGeneration
        }
    }

    private func clearBookmarkComposer() {
        dismissalTask?.cancel()
        dismissalTask = nil
        bookmarkComposerRevision += 1
        bookmarkGeneration = nil
        bookmarkOwnerUsername = nil
        bookmarkInput = AO3AuthService.BookmarkInput()
        bookmarkError = nil
        bookmarkSuccess = nil
        bookmarkIsUpdate = false
        showingBookmark = false
    }

    func submitBookmark(workID: Int, auth: AO3AuthService) {
        let currentOwner = Self.normalizedOwner(for: auth)
        guard !isWorking,
              bookmarkGeneration == auth.sessionGeneration,
              bookmarkOwnerUsername == currentOwner
        else { return }
        let expectedGeneration = auth.sessionGeneration
        let expectedRevision = bookmarkComposerRevision
        let input = bookmarkInput
        isWorking = true
        bookmarkError = nil
        activeTask = Task {
            defer {
                isWorking = false
                activeTask = nil
            }
            do {
                let message = try await bookmarkHandler(workID, input, auth)
                guard auth.sessionGeneration == expectedGeneration else { return }
                bookmarkedWorkID = workID
                bookmarkedWorkGeneration = expectedGeneration
                // Insights D11: when, and whether public or private.
                OwnAO3ActionLog.record(.bookmarked(isPrivate: input.isPrivate), ao3WorkID: workID)
                AccessibilityNotification.Announcement(message).post()
                writeSuccesses += 1
                refreshWorkPageStates(workID: workID, auth: auth, force: true)
                guard message == "Bookmark updated." else {
                    showingBookmark = false
                    return
                }
                bookmarkSuccess = message
                dismissalTask?.cancel()
                dismissalTask = Task {
                    await bookmarkDismissalSleep()
                    guard !Task.isCancelled,
                          bookmarkComposerRevision == expectedRevision,
                          bookmarkSuccess == message,
                          auth.sessionGeneration == bookmarkGeneration,
                          Self.normalizedOwner(for: auth) == currentOwner
                    else { return }
                    bookmarkSuccess = nil
                    showingBookmark = false
                }
            } catch is CancellationError {
                return
            } catch {
                guard auth.sessionGeneration == expectedGeneration else { return }
                bookmarkError = Self.message(for: error)
                writeFailures += 1
            }
        }
    }

    private static func normalizedOwner(for auth: AO3AuthService) -> String? {
        guard auth.isLoggedIn, let username = auth.username else { return nil }
        return username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? UserFacingError.message(for: error)
    }
}

// MARK: - Host wiring

extension View {
    /// Presents the comments screen, bookmark composer, and result alert.
    /// Apply on the host that also shows `AO3WorkActionsMenu`.
    /// Passing a nil `workID` keeps the modifier attached unconditionally (so
    /// late-resolved IDs never flip SwiftUI view identity) while gating off
    /// sheet presentation.
    func ao3WorkActions(
        _ actions: AO3WorkActionsModel,
        workID: Int?,
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
    let workID: Int?
    let auth: AO3AuthService
    var readerSections: [ReaderSection]
    var onOpenReaderChapter: ((Int) -> Void)?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: bookmarkPresented) {
                if let workID {
                    AO3BookmarkComposer(actions: actions, workID: workID, auth: auth)
                    #if os(iOS)
                        .modifier(ScopeSurfaceAccent())
                    #endif
                }
            }
            .onAppear {
                actions.syncSession(auth: auth)
            }
            .onChange(of: auth.sessionGeneration) { _, _ in
                actions.syncSession(auth: auth)
            }
            .onChange(of: auth.status) { _, _ in
                actions.syncSession(auth: auth)
            }
            .commentsSheet(
                isPresented: commentsPresented,
                workID: workID ?? 0,
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

    private var bookmarkPresented: Binding<Bool> {
        Binding(
            get: { workID != nil && actions.showingBookmark },
            set: { actions.showingBookmark = $0 }
        )
    }

    private var commentsPresented: Binding<Bool> {
        Binding(
            get: { workID != nil && actions.showingCommentsScreen },
            set: { actions.showingCommentsScreen = $0 }
        )
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
