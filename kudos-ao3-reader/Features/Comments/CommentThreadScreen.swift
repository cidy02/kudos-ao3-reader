import SwiftUI

/// AO3's Thread / Parent Thread page, natively: one comment and everything under
/// it, on its own pushed screen.
///
/// **Pushed, not scrolled to.** AO3 gives a comment a real isolated-thread URL
/// (`AO3Comment.threadPath`) and navigates to it, so this matches the site rather
/// than approximating it. It also earns its keep structurally: the list can stay
/// shallow and readable precisely because anything deeper now has somewhere to go.
///
/// **No request is made.** The subtree is already on the page the list fetched —
/// which is why this renders straight from `CommentsModel` and, being a live read
/// of it, stays correct when a reply, edit or delete lands while it is open.
struct CommentThreadScreen: View {
    /// The comment this thread is rooted at — the chosen comment itself, not its
    /// top-level ancestor, matching what AO3's own thread page shows.
    let rootID: Int
    let model: CommentsModel
    /// Reply/edit/delete/author actions still belong to `CommentsView`: it owns the
    /// composer, the delete confirmation and the login sheet, and it stays alive
    /// below this on the stack. `onFocusThread` is the one handler replaced here.
    let handlers: CommentThreadHandlers
    /// A "Parent Thread" whose target sits *outside* this subtree can't be shown
    /// here. The screen pops and hands it back to the list instead of silently
    /// doing nothing.
    let onFocusOutsideSubtree: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 390
    @State private var highlightedCommentID: Int?
    @State private var highlightClearTask: Task<Void, Never>?

    private var root: AO3Comment? { model.comment(withID: rootID) }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let root {
                    ForEach(Self.rows(for: root)) { row in
                        CommentConversationRow(
                            item: row.item,
                            workAuthors: model.workAuthors,
                            workAuthorIdentities: model.workAuthorIdentities,
                            // Every comment here belongs to one thread, so the
                            // chapter badge would repeat the same value down the
                            // whole screen.
                            showChapterBadge: false,
                            startsConversation: row.startsConversation,
                            depth: row.depth,
                            isLastSibling: row.isLastSibling,
                            ancestorLines: row.ancestorLines,
                            nextDepth: row.nextDepth,
                            showsParentAttribution: row.showsParentAttribution,
                            // No caret here. This screen exists to show one thread
                            // in full; folding its root would leave a page with a
                            // single comment on it and no way to read what you
                            // navigated here for.
                            collapse: nil
                        )
                        .commentSwipeActions(comment: row.item.actionableComment)
                    }
                    .environment(\.commentHighlightID, highlightedCommentID)
                    .environment(\.commentThreadHandlers, threadHandlers(proxy: proxy))
                } else {
                    // The subtree can vanish under us — deleting the comment this
                    // screen is rooted at is the ordinary way. Say so rather than
                    // showing an empty list.
                    ContentUnavailableView(
                        "Thread Unavailable",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("This comment is no longer part of the loaded page.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .cardList()
            // Same reason as the list's own copy: indent feeds `listRowInsets`,
            // which resolves before a row can measure itself.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .environment(\.commentsContentWidth, width)
            .navigationTitle("Thread")
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .hidesFloatingTabBar()
        }
    }

    /// The subtree, fully expanded.
    ///
    /// Chunking and the "Show N replies" collapse exist to keep the *list* cheap;
    /// opening a thread is an explicit request to see all of it, so both are lifted
    /// here — `Int.max` visible, the root marked expanded.
    private static func rows(for root: AO3Comment) -> [CommentConversationRowItem] {
        CommentConversationBuilder.rows(
            roots: [root],
            repliesByRoot: [root.id: CommentThreadGeometry.flattenedReplies(from: root)],
            expandedRootIDs: [root.id],
            visibleReplyCounts: [root.id: .max]
        )
    }

    private func threadHandlers(proxy: ScrollViewProxy) -> CommentThreadHandlers {
        var handlers = handlers
        handlers.onFocusThread = { target in focus(target, proxy: proxy) }
        return handlers
    }

    /// Everything under this root is already on screen, so a jump within the
    /// subtree scrolls rather than pushing another copy of what's being shown.
    /// "Parent Thread" can point *above* the root, though — that leaves this
    /// screen entirely, so it pops back and lets the list handle it.
    private func focus(_ commentID: Int, proxy: ScrollViewProxy) {
        guard let root,
              CommentsModel.comment(withID: commentID, in: [root]) != nil
        else {
            dismiss()
            onFocusOutsideSubtree(commentID)
            return
        }

        highlightedCommentID = commentID
        highlightClearTask?.cancel()
        highlightClearTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            highlightedCommentID = nil
        }
        withAnimationUnlessReduced(.easeInOut(duration: 0.3), reduceMotion: reduceMotion) {
            proxy.scrollTo(commentID, anchor: .center)
        }
    }
}
