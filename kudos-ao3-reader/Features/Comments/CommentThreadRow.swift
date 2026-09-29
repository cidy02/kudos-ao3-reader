import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Geometry for comment threads — spec artboard 1f.
///
/// **Threads render inline, down to AO3's own nesting limit.** Owner decision
/// 2026-09-24 ("Full 1f, uncapped"), superseding the depth-bounded list of
/// T-151/T-183 (a root, its first two direct replies, then "Continue thread").
/// A conversation is drawn the way 1f draws it and the way AO3 itself does:
/// every reply inline, down to `maxInlineDepth` — otwarchive's
/// `COMMENT_THREAD_MAX_DEPTH`, 5. Only replies deeper than that go behind
/// "Continue thread", which is exactly where AO3 cuts its own page off.
///
/// T-183 bounded the list because every earlier inline tree broke down at depth:
/// the width squeeze, a per-depth fill ladder that washed out, a six-stripe
/// accent gutter. 1f removes each cause instead of tuning around it:
///
/// - **No cards.** A comment sits directly on the page as an avatar column and a
///   content column — no surface, border, radius, shadow or per-depth fill, so
///   there is no fill ladder to wash out and no card edge to nest.
/// - **Neutral hairlines.** Rails are 1pt lines in the app's own separator tone
///   (`glassStroke`), not the accent at stepped opacities, so five levels of them
///   read as quiet structure rather than a stripe of red, in every theme.
/// - **Clamped indent.** Each level steps in by its parent's avatar plus a gap,
///   and stops growing the moment the content column would drop under
///   `minimumContentWidth` — nesting gives up width before legibility does.
/// - **A cap at 5**, AO3's own, so a ten-deep chain costs one "Continue thread"
///   row rather than an indent that walks off the screen.
///
/// Structurally nothing changes from T-183: one `List` row per comment (so a
/// swipe acts on the comment swiped), a flat row list the model precomputes, and
/// connectors drawn per row inside each row's own bounds.
enum CommentThreadGeometry {
    /// Outer margin, matching the "Comments" section rule above the thread.
    static let sideMargin: CGFloat = 16
    /// The comment list's own coordinate space. A row's swipe is measured in
    /// it, so a navigation push or pop — which slides the list and its rows
    /// together — never reads as a swipe.
    static let listSpace = "commentList"
    /// Air on either side of the hairline between two top-level conversations
    /// (1f: 18 below one conversation, 18 above the next).
    static let conversationGap: CGFloat = 18
    /// Air above every other row — a reply, a control, the page's first root
    /// under the section rule (1f: 12). A reply's avatar starts this far below its
    /// row's top edge, which is where the elbow into it has to land.
    static let rowTopPadding: CGFloat = 12
    /// The deepest reply the Comments list draws inline: AO3's own
    /// `COMMENT_THREAD_MAX_DEPTH`. Anything deeper sits behind "Continue thread".
    /// The artboard itself only draws depths 0–2; this is the one line to change
    /// if the owner ever wants the list to stop there.
    static let maxInlineDepth = 5
    static let railWidth: CGFloat = 1
    /// Gap between the bottom of an avatar and the rail it drops (1f: 5).
    static let railAvatarGap: CGFloat = 5

    /// Avatars step down with depth so a reply reads as subordinate without a
    /// heavier frame (1f: 30 / 26 / 22).
    static func avatarSize(forDepth depth: Int) -> CGFloat {
        switch max(0, depth) {
        case 0: 30
        case 1: 26
        default: 22
        }
    }

    /// Gap between the avatar column and the content column (1f: 11 beside the
    /// root's avatar, 10 beside a reply's).
    static func avatarContentSpacing(forDepth depth: Int) -> CGFloat {
        depth <= 0 ? 11 : 10
    }

    /// Corner of the elbow into a reply at `depth` (1f: 21 into a 26pt avatar,
    /// 18 into a 22pt one).
    static func elbowRadius(forDepth depth: Int) -> CGFloat {
        depth <= 1 ? 21 : 18
    }

    /// Reply stacks larger than this start collapsed. Counts every reply the list
    /// would draw — the whole depth-first stack is what expanding renders — not
    /// just the root's direct children.
    static let autoExpandedMaxReplies = 8
    /// Once expanded, reveal this many replies at a time. A 200-reply thread
    /// then builds (and fires avatar `AsyncImage` requests for) one chunk per
    /// "Show more" tap instead of all 200 at once.
    static let repliesChunkSize = 20
    /// Collapsed body height before "Read more".
    static let collapsedBodyLineLimit = 5

    /// Where a reply's avatar would start with the whole screen to spare: its
    /// parent's own indent plus the parent's avatar and gap, so a reply's avatar
    /// lines up under its parent's text (1f: 41, 77, then 32 a level).
    ///
    /// Held at `maxInlineDepth`. Only the thread screen, which renders a subtree
    /// in full, ever draws deeper, and there a reply past AO3's own limit sits
    /// under its parent rather than stepping further in.
    static func idealIndent(forDepth depth: Int) -> CGFloat {
        (0 ..< min(max(0, depth), maxInlineDepth)).reduce(0) {
            $0 + avatarSize(forDepth: $1) + avatarContentSpacing(forDepth: $1)
        }
    }

    /// Leading indent for a reply, clamped to what the screen can spare.
    ///
    /// Avatars and gaps are fixed point values and text is not, so a fixed step
    /// keeps its width while the words beside it grow, starving a deep reply
    /// until its prose spills. Keying that off an accessibility-size *category*
    /// wasn't enough — the sizes just below the threshold starve it just as
    /// badly. So the ideal indent is clamped until the content column (what is
    /// left after the margins, this reply's avatar and its gap) never drops under
    /// `minimumContentWidth`. The indent stops growing instead; wider screens
    /// (iPad, landscape) keep the full step. Deep AO3 chains are the common case,
    /// so depth 5 has to stay readable on a phone.
    static func indent(
        forDepth depth: Int,
        availableWidth: CGFloat,
        typeSize: DynamicTypeSize
    ) -> CGFloat {
        let budget = availableWidth - sideMargin * 2
            - avatarSize(forDepth: depth) - avatarContentSpacing(forDepth: depth)
            - minimumContentWidth(for: typeSize)
        return max(0, min(idealIndent(forDepth: depth), budget))
    }

    /// Width a comment's own content column needs before nesting may take any
    /// more. Grows with text size because that's exactly what the fixed-point
    /// indent fails to account for.
    static func minimumContentWidth(for typeSize: DynamicTypeSize) -> CGFloat {
        if typeSize.isAccessibilitySize { return 280 }
        return typeSize >= .xxLarge ? 240 : 200
    }

    /// Depth-first list of every reply under a root (root itself excluded),
    /// each becoming its own row.
    static func flattenedReplies(from root: AO3Comment) -> [FlattenedReply] {
        var result: [FlattenedReply] = []
        // An explicit stack, not recursion: AO3 doesn't cap reply nesting, and a
        // long reply-to-reply chain would otherwise cost one frame per level. The
        // single accumulator also avoids the O(depth²) copying that `[node] +
        // flatten(children)` incurs at every level.
        var stack: [FlattenedReply] = root.replies.reversed().map {
            FlattenedReply(
                comment: $0, depth: 1, parentAuthor: root.author,
                parentIsViewer: root.editPath != nil
            )
        }
        while let item = stack.popLast() {
            result.append(item)
            for child in item.comment.replies.reversed() {
                stack.append(FlattenedReply(
                    comment: child, depth: item.depth + 1, parentAuthor: item.comment.author,
                    parentIsViewer: item.comment.editPath != nil
                ))
            }
        }
        return result
    }
}

/// How the strip under a comment lays out.
///
/// Signed in, Reply leads and the overflow trails — the board's 40pt row.
/// Signed out, Reply is absent (login lives in the overflow menu) and a 44pt
/// band around that lone button is a tall empty gap under a short comment
/// (T-247). The button stays a 44pt target; the extra overlaps the prose
/// instead of stacking under it.
enum CommentActionRowLayout {
    static let hitTarget: CGFloat = 44
    /// Board 1f's action row `min-height: 40px` when Reply is in the strip.
    static let leadingRowHeight: CGFloat = 40
    /// The overflow capsule, without the empty air `minimumHitTarget` adds
    /// around it. Used when that capsule is the whole strip.
    static let overflowOnlyHeight: CGFloat = 28

    static func showsLeadingReply(canReply: Bool, isLoggedIn: Bool) -> Bool {
        canReply && isLoggedIn
    }

    static func layoutHeight(showsLeadingReply: Bool) -> CGFloat {
        showsLeadingReply ? leadingRowHeight : overflowOnlyHeight
    }

    /// How far the 44pt target extends past `layoutHeight`, per side.
    static func verticalOverlap(showsLeadingReply: Bool) -> CGFloat {
        max(0, (hitTarget - layoutHeight(showsLeadingReply: showsLeadingReply)) / 2)
    }
}

/// One row of a rendered conversation. A top-level comment and every reply
/// under it each become their **own** `List` row rather than subviews of a
/// single row, because `.swipeActions` only attaches to a row — packing a whole
/// thread into one row meant a swipe beside any reply fired with the *root*
/// comment's context (copying, editing, or deleting the wrong comment).
///
/// Depth is carried by the row's own indent and rails (see
/// `CommentThreadGeometry`), so nothing is shared between rows.
enum CommentConversationItem: Identifiable {
    /// `parentAuthor` is nil for the root post, set for a reply. `depth` is the
    /// AO3 nesting level (0 = root) and drives the indent and avatar size.
    /// `parentIsViewer` marks a reply aimed at the signed-in reader's own
    /// comment; it defaults so a caller that predates it still compiles.
    case post(comment: AO3Comment, parentAuthor: String?, depth: Int, parentIsViewer: Bool = false)
    /// The "Show N replies" / "Show N more" control, itself a row so it gets a
    /// row's own insets and hit target.
    case expander(rootID: Int, hiddenCount: Int, showsVerb: Bool)
    /// "Continue thread" — the list's exit to the thread screen for replies nested
    /// deeper than `CommentThreadGeometry.maxInlineDepth`.
    ///
    /// Distinct from `.expander`, which reveals more rows in place. This one
    /// navigates, and `hiddenCount` is every reply **deeper than the cap** — so
    /// the row's "N deeper replies" is now literally true. T-183 rejected that
    /// wording because its bounded list counted everything past the first two
    /// direct replies, later *direct* replies included; the inline list draws every
    /// reply down to AO3's own depth, so what's left over is exactly the deeper ones.
    case continueThread(rootID: Int, hiddenCount: Int)

    /// Nesting level for thread-line purposes. The two control rows sit at the
    /// conversation's own edge (1f's "Continue thread" does), outside the rails —
    /// which also means neither reads as one more reply keeping a parent's rail
    /// running past its real last child.
    var connectorDepth: Int {
        switch self {
        case let .post(_, _, depth, _): depth
        case .expander, .continueThread: 0
        }
    }

    var id: String {
        switch self {
        case let .post(comment, _, _, _): "post-\(comment.id)"
        case let .expander(rootID, _, _): "expander-\(rootID)"
        case let .continueThread(rootID, _): "continue-\(rootID)"
        }
    }

    /// The comment a swipe action should act on — nil for the control rows,
    /// which deliberately offer none.
    var actionableComment: AO3Comment? {
        switch self {
        case let .post(comment, _, _, _): comment
        case .expander, .continueThread: nil
        }
    }
}

/// One reply in display order (DFS under a top-level comment).
struct FlattenedReply: Identifiable, Equatable {
    var id: Int { comment.id }
    let comment: AO3Comment
    /// Logical AO3 depth (1 = direct reply to the root card).
    let depth: Int
    /// Display name of whoever this reply is directly answering — the root
    /// card's author at depth 1, or another reply's author deeper in the
    /// chain. The nesting itself (`CommentThreadGeometry`'s avatar spine) is
    /// purely visual and `accessibilityHidden`; this is VoiceOver's only
    /// textual account of "this is a reply, and to whom" (HIG audit UI-2).
    let parentAuthor: String
    /// The comment this reply answers is the **viewer's own**.
    ///
    /// Taken from AO3's own per-session signal — it renders an Edit action only
    /// on the signed-in account's comments — rather than by matching
    /// `parentAuthor` against `auth.username`. A byline is a *pseud*, which need
    /// not equal the account name, so name matching would miss every reply to a
    /// comment left under a non-default pseud and could collide with a stranger
    /// whose pseud happens to match. `editPath` and not `deletePath`: a work's
    /// creator gets Delete on other people's comments too.
    ///
    /// `var` with a default so the memberwise initialiser stays source-compatible
    /// for any caller built before this existed.
    var parentIsViewer = false
}

/// Shared role chip for native Comments and Inbox notification cards.
///
/// **Only informative roles get a chip.** A plain commenter is the overwhelming
/// default, so a "User" badge on nearly every byline said nothing while adding a
/// line of furniture to each one — and it diluted the badge that people actually
/// scan a comment section for. Author / Me / Guest carry real information;
/// `.user` renders nothing.
struct CommentParticipantBadge: View {
    let role: AO3CommentParticipantRole

    private var isEmphasized: Bool { role == .author || role == .me }

    /// `person` — the same symbol the app uses for a work's author everywhere
    /// else (Home cards, the Work Details hero, the Comments info card), so the
    /// badge reads as *that* author rather than as a generic role chip. Only the
    /// author gets one: `Me` and `Guest` say what they mean on their own, and a
    /// symbol on each would just be more furniture in the byline.
    private var symbol: String? {
        role == .author ? "person" : nil
    }

    var body: some View {
        if role != .user {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol)
                        .imageScale(.small)
                }
                Text(role.rawValue)
            }
            .font(.caption2.weight(isEmphasized ? .semibold : .regular))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(isEmphasized ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule())
            .foregroundStyle(isEmphasized ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .fixedSize()
            .layoutPriority(1)
            // One element, one announcement — without this VoiceOver reads the
            // symbol and the word as two separate items.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        switch role {
        case .me: "Your comment"
        case .author: "Work author"
        case .user, .guest: role.rawValue
        }
    }
}

/// The compact comment action used wherever a native Reply entry point appears.
/// Its visible capsule stays tight while the control keeps a 44pt hit target.
struct CommentReplyButton: View {
    var accessibilityLabel = "Reply"
    /// Drop the word: set by deeply nested cards and at accessibility text
    /// sizes, where a full capsule plus the overflow button no longer fits.
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
                .font(.caption.weight(.semibold))
                // Icon-only where the word won't fit. Decided from the
                // environment rather than by `ViewThatFits`: the actions row
                // puts a `Spacer` beside this button, so the proposal it
                // receives is effectively unbounded and every candidate
                // "fits" — the fallback could never fire.
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityLabel)
    }

}

/// Lets a label style be chosen at runtime — `LabelStyle` is an opaque
/// protocol, so the two branches of a ternary would otherwise be different
/// concrete types.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some LabelStyle) {
        make = { AnyView(Label($0).labelStyle(style)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

extension EnvironmentValues {
    /// Width of the comments list, measured once by `CommentsView`.
    ///
    /// Indent has to be known to set `listRowInsets`, which happens before the
    /// row is laid out — so a row can't measure its own width in time. The
    /// container publishes it instead.
    @Entry var commentsContentWidth: CGFloat = 390
}

// MARK: - Thread environment (highlight + actions)

/// Whether a conversation is folded, and how much folding it hides.
///
/// `replyCount` is every descendant, not the root's direct children — "Show 3"
/// on a thread that opens to eleven rows is a lie the reader catches immediately.
struct CommentCollapseState: Equatable {
    let isCollapsed: Bool
    let replyCount: Int

    /// Deliberately asymmetric. Closed, the control has to say what it would
    /// reveal, because the rows are gone and nothing else does. Open, the count is
    /// visible on screen already, so repeating it is noise.
    var label: String { isCollapsed ? "Show \(replyCount)" : "Hide" }

    var accessibilityLabel: String {
        isCollapsed
            ? "Show \(replyCount) \(replyCount == 1 ? "reply" : "replies")"
            : "Hide replies"
    }
}

/// A pushed isolated-thread screen, identified by the comment it is rooted at.
///
/// A bare `Int` can't drive `navigationDestination(item:)`, and the comment id is
/// the whole route — the subtree is resolved from `CommentsModel` on arrival
/// rather than carried here, so the screen keeps rendering the live comment after
/// an edit or a reply lands.
struct CommentThreadRoute: Identifiable, Hashable {
    let commentID: Int
    var id: Int { commentID }
}

struct CommentThreadHandlers {
    var onReply: (AO3Comment) -> Void
    var onEdit: (AO3Comment) -> Void
    var onDelete: (AO3Comment) -> Void
    var onCopyLink: (AO3Comment) -> Void
    var onFocusThread: (Int) -> Void
    var onRequestLogin: () -> Void
    /// Opens a commenter's native profile (Works/Series/Bookmarks/About). nil is
    /// a valid, common default — `AO3AuthorBylineView` renders plain, untappable
    /// text when no route handler is supplied, matching every other call site.
    /// The `= nil` default (not just an Optional type) is load-bearing: it's
    /// what makes the synthesized memberwise init treat this param as optional
    /// too, so `.noop` below keeps compiling unchanged.
    var onOpenAuthor: ((AO3AuthorRoute) -> Void)?

    static let noop = CommentThreadHandlers(
        onReply: { _ in },
        onEdit: { _ in },
        onDelete: { _ in },
        onCopyLink: { _ in },
        onFocusThread: { _ in },
        onRequestLogin: {}
    )
}

private struct CommentHighlightIDKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

private struct CommentThreadHandlersKey: EnvironmentKey {
    static let defaultValue = CommentThreadHandlers.noop
}

extension EnvironmentValues {
    var commentHighlightID: Int? {
        get { self[CommentHighlightIDKey.self] }
        set { self[CommentHighlightIDKey.self] = newValue }
    }

    var commentThreadHandlers: CommentThreadHandlers {
        get { self[CommentThreadHandlersKey.self] }
        set { self[CommentThreadHandlersKey.self] = newValue }
    }
}

// MARK: - Conversation rows

/// One row of the comments list, already resolved to everything the row view
/// needs. The whole page is precomputed into a flat `[CommentConversationRowItem]`
/// so the `List` gets a single lazy `ForEach`.
///
/// The shape matters for performance, not just tidiness: a nested `ForEach`
/// whose inner data was built inside the outer closure forced that closure to
/// run for *every* conversation on every body pass — allocating a prefix array,
/// an items array and an `enumerated()` array per thread — because SwiftUI has
/// to evaluate it to know the row count. That defeats `List` laziness, and a
/// swipe re-evaluates the body continuously, which is what made swiping stutter.
struct CommentConversationRowItem: Identifiable {
    let item: CommentConversationItem
    /// The top-level comment this row belongs to — the expander's target.
    let rootID: Int
    /// First row of a conversation that isn't the first on the page: gets the
    /// extra air and the rule that separate one conversation from the next.
    let startsConversation: Bool
    /// Nesting level (0 = root), and the two facts needed to draw the thread
    /// lines: whether this is the last child of its parent (so the trunk stops
    /// at its elbow instead of continuing past), and for each *ancestor* level
    /// whether that ancestor still has siblings below (so its vertical line
    /// keeps running down past this row).
    ///
    /// Resolved once in the builder rather than in `body`: a row can't see its
    /// siblings, and re-deriving this per layout pass is the kind of per-frame
    /// tree work that made swiping stutter before.
    let depth: Int
    let isLastSibling: Bool
    let ancestorLines: [Bool]
    /// Depth of the row that follows *within this conversation*, or nil when
    /// this is its last row. `nextDepth == depth + 1` means this comment's first
    /// reply is directly below, so this row starts that reply's rail.
    let nextDepth: Int?
    /// True when this reply's parent is *not* the row directly above it — an
    /// earlier sibling's subtree sits in between, so no connector joins the two
    /// and the reply has to name its parent in text instead.
    let showsParentAttribution: Bool
    /// The comment at each level above this row, root first — what lets a
    /// reply hide the line from an ancestor that is being swiped.
    var ancestorIDs: [Int] = []
    /// Set on a root that has replies: the caret's state and what it would reveal.
    /// nil everywhere else, which is also the "no caret" signal.
    let collapse: CommentCollapseState?

    var id: String { item.id }
}

/// The rails that join a reply to the comment it answers (1f).
///
/// One shape per row, drawn in the row's background, so nothing crosses a row
/// boundary and a swipe moves only its own comment. Consecutive rows touch, so
/// the per-row segments read as one continuous line. Every segment is in one
/// neutral tone, so the whole row strokes a single path.
struct ThreadConnectors: Shape {
    let depth: Int
    let isLastSibling: Bool
    let ancestorLines: [Bool]
    let leadingInset: CGFloat
    /// This row's top inset: its avatar starts this far below the row's top edge,
    /// so the elbow can land on the avatar's vertical centre.
    let topInset: CGFloat
    /// A row with a reply directly beneath it starts that reply's rail itself,
    /// from just under its own avatar to the row's bottom edge. A row can only
    /// paint within its own bounds, so the reply's row picks the line up at its
    /// top edge and the two segments meet.
    let hasChildBelow: Bool
    /// Resolved indent per level, handed down from the chrome. Recomputing it here
    /// would risk the rails and the avatars disagreeing about where a column is
    /// the moment either formula changes.
    let indents: [CGFloat]
    /// The rail level of an ancestor that is being swiped: its line through
    /// this row, and the elbow off it into this reply, are left out so nothing
    /// points at a comment that has slid away. Nil draws everything.
    var hiddenLevel: Int?

    private func indent(forLevel level: Int) -> CGFloat {
        guard level >= 0, level < indents.count else { return indents.last ?? 0 }
        return indents[level]
    }

    /// The rail a comment at `level` drops to its replies: its avatar's centre-x.
    private func railX(forLevel level: Int) -> CGFloat {
        leadingInset + indent(forLevel: level)
            + CommentThreadGeometry.avatarSize(forDepth: level) / 2
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let avatarTop = rect.minY + topInset
        let avatarSize = CommentThreadGeometry.avatarSize(forDepth: depth)

        // This comment's own rail, down from just under its avatar towards the
        // first reply below.
        if hasChildBelow {
            let x = railX(forLevel: depth)
            let startY = avatarTop + avatarSize + CommentThreadGeometry.railAvatarGap
            if startY < rect.maxY {
                path.move(to: CGPoint(x: x, y: startY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }

        guard depth > 0 else { return path }

        // An ancestor with replies still to come keeps its rail running the full
        // height of this row, carrying it past an earlier sibling's subtree to
        // reach the next peer.
        for level in 0 ..< min(depth - 1, ancestorLines.count) where ancestorLines[level] && level != hiddenLevel {
            let x = railX(forLevel: level)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }

        guard hiddenLevel != depth - 1 else { return path }

        // The parent's rail into this reply: down from the top edge, then a rounded
        // elbow that ends at the avatar's left edge, at its vertical centre.
        let x = railX(forLevel: depth - 1)
        let avatarLeft = leadingInset + indent(forLevel: depth)
        let midY = avatarTop + avatarSize / 2
        let run = avatarLeft - x
        path.move(to: CGPoint(x: x, y: rect.minY))
        if run > 0 {
            let radius = min(CommentThreadGeometry.elbowRadius(forDepth: depth), run, midY - rect.minY)
            path.addLine(to: CGPoint(x: x, y: midY - radius))
            path.addQuadCurve(
                to: CGPoint(x: x + radius, y: midY),
                control: CGPoint(x: x, y: midY)
            )
            path.addLine(to: CGPoint(x: avatarLeft, y: midY))
        } else {
            // The indent has been clamped, so this avatar sits under the parent's
            // rail — which simply runs on into its top edge.
            path.addLine(to: CGPoint(x: x, y: avatarTop))
        }

        // A middle child: the parent's rail carries on down to the next sibling.
        // The last child's elbow is where that rail ends.
        if !isLastSibling {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return path
    }
}

/// Builds the flat row list for one top-level conversation.
///
/// Replies were already flattened depth-first (`flattenedReplies`); this only
/// decides which of them are visible and appends the control rows, so the
/// caller can emit one `List` row per item.
enum CommentConversationBuilder {
    /// `replies` is the root's depth-first reply list, precomputed by the model
    /// (`flattenedRepliesByRoot`). Deliberately a parameter rather than walked
    /// here: this runs on every layout pass, and re-walking the tree per frame
    /// is what made swiping a long thread stutter.
    ///
    /// Replies deeper than `maxDepth` are never drawn here. A depth-first list
    /// keeps each one's subtree contiguous, so dropping them leaves every other
    /// reply's position — and the rails between them — intact; they are counted
    /// once, into a trailing "Continue thread" row. That row only appears once
    /// every inline reply is showing: while the expander is still there, it is
    /// the conversation's one way onward.
    static func items(
        root: AO3Comment,
        replies: [FlattenedReply],
        isExpanded: Bool,
        visibleReplyCount: Int,
        maxDepth: Int = .max
    ) -> [CommentConversationItem] {
        let inline = replies.filter { $0.depth <= maxDepth }
        let deeper = representedCount(of: replies.lazy.filter { $0.depth > maxDepth })
        // Gated on every reply the list would draw, because expanding renders
        // every inline descendant, not just the root's direct children.
        let showsReplies = isExpanded
            || inline.count <= CommentThreadGeometry.autoExpandedMaxReplies

        guard !inline.isEmpty, showsReplies else {
            var items: [CommentConversationItem] = [
                .post(comment: root, parentAuthor: nil, depth: 0)
            ]
            if !inline.isEmpty {
                items.append(.expander(rootID: root.id, hiddenCount: representedCount(of: inline), showsVerb: false))
            }
            return items
        }

        let shown = Array(inline.prefix(max(visibleReplyCount, CommentThreadGeometry.autoExpandedMaxReplies)))
        let hidden = representedCount(of: inline.dropFirst(shown.count))
        var items: [CommentConversationItem] = [
            .post(comment: root, parentAuthor: nil, depth: 0)
        ]
        for reply in shown {
            items.append(.post(
                comment: reply.comment,
                parentAuthor: reply.parentAuthor,
                depth: reply.depth,
                parentIsViewer: reply.parentIsViewer
            ))
        }
        if hidden > 0 {
            items.append(.expander(rootID: root.id, hiddenCount: hidden, showsVerb: true))
        } else if deeper > 0 {
            items.append(.continueThread(rootID: root.id, hiddenCount: deeper))
        }
        return items
    }

    /// How many comments `replies` stand for. AO3's cutoff placeholder ("7 more
    /// comments") stands for `cutoffCount`, not one — counting it as one made the
    /// list say "1 deeper reply" while the thread screen said 7. Every count this
    /// builder shows goes through here, so "Show N", the expander and "N deeper
    /// replies" agree.
    static func representedCount(of replies: some Sequence<FlattenedReply>) -> Int {
        replies.reduce(0) { total, reply in
            total + (reply.comment.isThreadCutoff ? max(1, reply.comment.cutoffCount ?? 1) : 1)
        }
    }

    /// Whether another node at exactly `depth` follows `index` under the *same*
    /// parent — the scan stops as soon as the tree pops shallower than `depth`,
    /// because anything past that belongs to a different branch.
    private static func hasLaterPeer(at depth: Int, after index: Int, in depths: [Int]) -> Bool {
        var i = index + 1
        while i < depths.count {
            if depths[i] < depth { return false }
            if depths[i] == depth { return true }
            i += 1
        }
        return false
    }

    /// Flattens every conversation on the page into one row list.
    ///
    /// `maxDepth` is `CommentThreadGeometry.maxInlineDepth` for the Comments list;
    /// the thread screen leaves it unbounded to render its subtree in full.
    static func rows(
        roots: [AO3Comment],
        repliesByRoot: [Int: [FlattenedReply]],
        expandedRootIDs: Set<Int>,
        visibleReplyCounts: [Int: Int],
        collapsedRootIDs: Set<Int> = [],
        maxDepth: Int = .max
    ) -> [CommentConversationRowItem] {
        var rows: [CommentConversationRowItem] = []
        for (conversationIndex, root) in roots.enumerated() {
            let replies = repliesByRoot[root.id] ?? []
            let isCollapsed = collapsedRootIDs.contains(root.id)
            let items: [CommentConversationItem] = if isCollapsed {
                // Folded: the root and nothing else — not even the "Continue
                // thread" row, which would leave a way in that contradicts the
                // caret the reader just closed.
                [.post(comment: root, parentAuthor: nil, depth: 0)]
            } else {
                items(
                    root: root,
                    replies: replies,
                    isExpanded: expandedRootIDs.contains(root.id),
                    visibleReplyCount: visibleReplyCounts[root.id] ?? CommentThreadGeometry.repliesChunkSize,
                    maxDepth: maxDepth
                )
            }
            // The caret hides replies, so it only belongs where replies show — or
            // where the reader already folded them. A root still showing only its
            // initial "Show N replies" row has nothing to hide, and a "Hide" there
            // contradicted the row beneath it.
            let showsReplyPosts = items.contains { item in
                if case let .post(_, _, depth, _) = item { return depth > 0 }
                return false
            }
            let offersCollapse = !replies.isEmpty && (isCollapsed || showsReplyPosts)
            // Depth-first order, so a node's siblings and descendants are all
            // ahead of it — one forward scan per row answers both questions the
            // thread lines need.
            let depths = items.map(\.connectorDepth)
            // The comment at each depth on the way down to the current row.
            var path: [Int] = []
            for (index, item) in items.enumerated() {
                let depth = depths[index]
                let ancestors = Array(path.prefix(depth))
                if case let .post(comment, _, _, _) = item {
                    path = ancestors + [comment.id]
                }
                rows.append(CommentConversationRowItem(
                    item: item,
                    rootID: root.id,
                    startsConversation: index == 0 && conversationIndex > 0,
                    depth: depth,
                    isLastSibling: !Self.hasLaterPeer(at: depth, after: index, in: depths),
                    ancestorLines: (0 ..< max(0, depth - 1)).map { level in
                        Self.hasLaterPeer(at: level + 1, after: index, in: depths)
                    },
                    nextDepth: index + 1 < depths.count ? depths[index + 1] : nil,
                    // Depth-first order means a reply's parent is the row above it
                    // *unless* an earlier sibling's subtree intervenes, which is
                    // exactly when the row above is deeper than this one's parent.
                    showsParentAttribution: depth > 0
                        && (index == 0 || depths[index - 1] != depth - 1),
                    ancestorIDs: ancestors,
                    // Only a root with replies can be folded — keyed on the row's
                    // position, not its depth, because the control rows sit at depth
                    // 0 too. A reply's own caret would compete with its parent's for
                    // the same gesture on overlapping content, and closing a
                    // mid-thread reply leaves a hole rather than a tidier list.
                    collapse: index == 0 && offersCollapse
                        ? CommentCollapseState(isCollapsed: isCollapsed, replyCount: representedCount(of: replies))
                        : nil
                ))
            }
        }
        return rows
    }
}

/// One comment as its own plain `List` row: indent and rails for depth, a
/// hairline between conversations, no card (1f).
struct CommentConversationRow: View {
    let item: CommentConversationItem
    let workAuthors: [String]
    var workAuthorIdentities: [AO3AuthorIdentity] = []
    let showChapterBadge: Bool
    let startsConversation: Bool
    let depth: Int
    let isLastSibling: Bool
    let ancestorLines: [Bool]
    let nextDepth: Int?
    var showsParentAttribution = false
    var collapse: CommentCollapseState?
    /// See `CommentConversationRowItem.ancestorIDs`.
    var ancestorIDs: [Int] = []
    /// Invoked by the expander row.
    var onExpand: () -> Void = {}
    /// Invoked by the "Continue thread" row.
    var onContinueThread: () -> Void = {}
    /// Invoked by a root comment's collapse caret.
    var onToggleCollapse: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CommentRowChrome(
                depth: depth,
                isLastSibling: isLastSibling,
                ancestorLines: ancestorLines,
                nextDepth: nextDepth,
                startsConversation: startsConversation,
                commentID: item.actionableComment?.id,
                ancestorIDs: ancestorIDs
            ))
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case let .post(comment, parentAuthor, _, parentIsViewer):
            CommentPostRow(
                comment: comment,
                workAuthors: workAuthors,
                workAuthorIdentities: workAuthorIdentities,
                showChapterBadge: parentAuthor == nil && showChapterBadge,
                depth: depth,
                replyToAuthor: parentAuthor,
                showsParentAttribution: showsParentAttribution,
                parentIsViewer: parentIsViewer,
                collapse: collapse,
                onToggleCollapse: onToggleCollapse
            )
            .id(comment.id)
        case let .expander(_, hiddenCount, showsVerb):
            expandRepliesButton(
                count: hiddenCount,
                verb: showsVerb ? "more" : nil,
                reduceMotion: reduceMotion,
                action: onExpand
            )
        case let .continueThread(_, hiddenCount):
            continueThreadButton(count: hiddenCount, action: onContinueThread)
        }
    }
}

/// The list's exit to the thread screen, for replies deeper than AO3's own
/// nesting limit (1f: "Continue thread · N deeper replies").
///
/// A *navigation*, not a disclosure, so it says where it goes and carries a
/// chevron rather than the expander's "show more" affordance — the two sit in the
/// same slot in the same list and must not be mistaken for each other.
private func continueThreadButton(count: Int, action: @escaping () -> Void) -> some View {
    let countText = count == 1 ? "1 deeper reply" : "\(count) deeper replies"
    return Button(action: action) {
        HStack(spacing: 7) {
            Text("Continue thread")
                .fontWeight(.medium)
                .foregroundStyle(.tint)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(countText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .foregroundStyle(.tint)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Continue thread, \(countText)")
}

/// Frames a comment row: its insets, the rails joining it to its parent, and the
/// hairline that separates one top-level conversation from the next.
///
/// No card (1f). The comment sits directly on the page, so nothing is shared
/// between rows and there is nothing to seam, bleed or tear under a swipe.
private struct CommentRowChrome: ViewModifier {
    let depth: Int
    let isLastSibling: Bool
    let ancestorLines: [Bool]
    let nextDepth: Int?
    /// True on a root comment that isn't the first on the page: it takes the air
    /// and the hairline that separate one conversation from the next.
    let startsConversation: Bool
    var commentID: Int?
    var ancestorIDs: [Int] = []

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.commentsContentWidth) private var contentWidth
    @Environment(CommentSwipeTracker.self) private var swipeTracker: CommentSwipeTracker?
    /// Where the row sits when nothing is swiping it, and how far it is from
    /// there now. See `trackSwipe`.
    @State private var rest: (minX: CGFloat, width: CGFloat)?
    @State private var swipeOffset: CGFloat = 0

    /// Indent for every level this row draws, resolved once so the avatars and
    /// the rails are guaranteed to agree.
    private var indents: [CGFloat] {
        (0 ... max(0, depth)).map {
            CommentThreadGeometry.indent(
                forDepth: $0, availableWidth: contentWidth, typeSize: dynamicTypeSize
            )
        }
    }

    private var topInset: CGFloat {
        startsConversation
            ? CommentThreadGeometry.conversationGap * 2
            : CommentThreadGeometry.rowTopPadding
    }

    func body(content: Content) -> some View {
        let resolved = indents
        // Measured *before* `listRowInsets`: a geometry modifier between the row
        // traits and the List dropped the insets, so every reply lost its indent
        // while its rails kept it (T-292 regression, owner screenshot 2026-09-29).
        return content
            .onGeometryChange(
                for: CGRect.self,
                of: { $0.frame(in: .named(CommentThreadGeometry.listSpace)) },
                action: trackSwipe
            )
            .listRowInsets(EdgeInsets(
                top: topInset,
                leading: CommentThreadGeometry.sideMargin + (resolved.last ?? 0),
                bottom: 0,
                trailing: CommentThreadGeometry.sideMargin
            ))
            // The rails are the row's *background*, and a swipe translates the
            // whole row, background included (iOS 26.5), so a rail that meets its
            // neighbour at rest breaks mid-swipe. The swipe itself has no API, but
            // SwiftUI does see the row move (measured on device, 2026-09-29): the
            // row's global minX leaves its resting value frame by frame and comes
            // back as it closes. So the swiped row's rails disappear while it is off
            // rest and return when it settles (owner, 2026-09-29).
            .listRowBackground(rowBackground(indents: resolved))
            .listRowSeparator(.hidden)
    }

    /// Takes the resting position the first time the row is laid out, and again
    /// whenever its width changes (rotation, split view, a new indent budget). A
    /// swipe only translates the row, so its width is what tells the two apart;
    /// vertical scrolling moves minY, never minX.
    private func trackSwipe(_ frame: CGRect) {
        guard let rest, abs(rest.width - frame.width) < 0.5 else {
            rest = (frame.minX, frame.width)
            swipeOffset = 0
            return
        }
        swipeOffset = frame.minX - rest.minX
        // Tell the replies. Only on the edge, so a swipe does not re-render
        // every row on every frame.
        guard let swipeTracker, let commentID else { return }
        if isOffRest, swipeTracker.swipedID != commentID {
            swipeTracker.swipedID = commentID
        } else if !isOffRest, swipeTracker.swipedID == commentID {
            swipeTracker.swipedID = nil
        }
    }

    /// Half a point of slack so layout rounding at rest never counts.
    private var isOffRest: Bool { abs(swipeOffset) > 0.5 }

    /// The level of this row's swiped ancestor, if one is being swiped.
    private var hiddenLevel: Int? {
        guard let swiped = swipeTracker?.swipedID else { return nil }
        return ancestorIDs.firstIndex(of: swiped)
    }

    /// Gone the moment the row moves, back the moment it rests (owner: no fade).
    private var railOpacity: Double {
        isOffRest ? 0 : 1
    }

    /// Rails in the app's hairline tone rather than the accent: at up to five
    /// levels an accent ladder was the loudest thing on the screen, and this one
    /// token already holds up in Light, Dark, Sepia and OLED. 0.18 lands on 1f's
    /// own `#36363d` over the dark page.
    private func rowBackground(indents: [CGFloat]) -> some View {
        ThreadConnectors(
            depth: depth,
            isLastSibling: isLastSibling,
            ancestorLines: ancestorLines,
            leadingInset: CommentThreadGeometry.sideMargin,
            topInset: topInset,
            hasChildBelow: nextDepth == depth + 1,
            indents: indents,
            hiddenLevel: hiddenLevel
        )
        .stroke(theme.appTheme.glassStroke(0.18), lineWidth: CommentThreadGeometry.railWidth)
        .opacity(railOpacity)
        .overlay(alignment: .top) {
            if startsConversation { conversationRule }
        }
        .accessibilityHidden(true)
    }

    /// The full-width hairline between two top-level conversations, centred in
    /// the air above this root (1f: `rgba(255,255,255,.12)`, edge to edge).
    private var conversationRule: some View {
        Rectangle()
            .fill(theme.appTheme.glassStroke(0.12))
            .frame(height: 0.5)
            .padding(.top, CommentThreadGeometry.conversationGap)
    }
}

// MARK: - Post row

/// One comment's content: avatar column, then byline, body and actions. Carries
/// no position information — the enclosing `CommentConversationRow` owns the
/// indent and rails; depth only steps the avatar and name size down.
private struct CommentPostRow: View {
    let comment: AO3Comment
    let workAuthors: [String]
    let workAuthorIdentities: [AO3AuthorIdentity]
    let showChapterBadge: Bool
    /// Nesting level, so the avatar can step down with depth.
    var depth: Int = 0
    /// Set for a reply: who it answers. The connector conveys nesting visually but
    /// is `accessibilityHidden`, so this is VoiceOver's only account of it —
    /// always supplied, regardless of whether it is also shown on screen.
    var replyToAuthor: String?
    /// Whether to *render* `replyToAuthor` as well as announce it. Set only where
    /// the connector can't do the job — see `CommentConversationRowItem`.
    var showsParentAttribution = false
    /// This reply answers the viewer's own comment — see
    /// `FlattenedReply.parentIsViewer` for how that is established.
    var parentIsViewer = false
    /// Set on a root with replies; nil means no caret.
    var collapse: CommentCollapseState?
    var onToggleCollapse: () -> Void = {}

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.commentThreadHandlers) private var handlers
    @ScaledMetric(relativeTo: .subheadline) private var rootNameSize: CGFloat = 14

    /// 1f's byline steps down with depth (14 / 13.5 / 13), scaled with Dynamic
    /// Type from the root's size so the three keep their proportions.
    private var nameSize: CGFloat {
        switch depth {
        case ...0: rootNameSize
        case 1: rootNameSize * 13.5 / 14
        default: rootNameSize * 13 / 14
        }
    }

    private var participantRole: AO3CommentParticipantRole {
        .resolve(
            name: comment.author,
            isGuest: comment.isGuest,
            isAnonymousCreator: comment.isAnonymousCreator,
            commenterUsername: commentIdentity?.username,
            currentUsername: auth.username,
            workAuthors: workAuthors,
            workAuthorUsernames: workAuthorIdentities.compactMap(\.username)
        )
    }

    var body: some View {
        // Resolved once here rather than inside the byline: date formatting isn't
        // free, and this runs on every body pass.
        let timestamp = comment.postedText.isEmpty
            ? ""
            : AO3CommentTimestamp.displayText(
                rawText: comment.postedText, date: comment.postedAt
            )

        // 1f: an avatar column and a content column, top-aligned. The avatar has
        // to sit exactly `rowTopPadding` into the row — that is where the elbow
        // into it lands.
        return HStack(
            alignment: .top,
            spacing: CommentThreadGeometry.avatarContentSpacing(forDepth: depth)
        ) {
            authorAvatarControl
            commentBody(timestamp: timestamp)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func commentBody(timestamp: String) -> some View {
        if comment.isThreadCutoff {
            // AO3's own deep-thread cutoff (CAA-7): not a real comment, so no
            // byline/actions — just its own distinct disclosure pointing at
            // AO3's continuation link. Never fetched natively; leaving the app
            // is the whole point of a `Link`.
            threadCutoffRow
        } else if comment.isDeleted {
            // Deleted-comment tombstone, presented the way AO3 itself does: just
            // the placeholder text — no byline, no actions (AO3 renders none).
            // The avatar placeholder stays so the reply rail passes through.
            Text(comment.bodyText.isEmpty ? "(Previous comment deleted.)" : comment.bodyText)
                .font(.subheadline.italic())
                .foregroundStyle(.secondary)
                .frame(minHeight: CommentThreadGeometry.avatarSize(forDepth: depth), alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // Owner, 2026-09-28: the name lines up with the avatar in every
                // row. The byline is exactly the avatar's height and centres what
                // it holds, so a collapse pill or chapter badge can no longer
                // push the name down in some rows and not others.
                byline(timestamp: timestamp)
                    .frame(minHeight: CommentThreadGeometry.avatarSize(forDepth: depth))
                parentAttribution
                if !comment.bodyText.isEmpty {
                    ExpandableCommentBody(text: comment.bodyText)
                }
                actionsRow
            }
        }
    }

    /// AO3's deep-thread cutoff, rendered as its own disclosure — never a bare
    /// "couldn't be read" tombstone. Opens AO3's own continuation page in the
    /// system browser; Kudos does not fetch it itself (CAA-7).
    @ViewBuilder
    private var threadCutoffRow: some View {
        let label = Label(cutoffText, systemImage: "ellipsis.bubble")
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: CommentThreadGeometry.avatarSize(forDepth: depth))
            .contentShape(Rectangle())

        if let url = comment.cutoffThreadURL {
            Link(destination: url) { label }
                .minimumHitTarget()
                .accessibilityHint("Opens the rest of this thread on the AO3 website")
        } else {
            label.foregroundStyle(.secondary)
        }
    }

    private var cutoffText: String {
        guard let count = comment.cutoffCount else { return "More comments in this thread" }
        return "\(count) more \(count == 1 ? "comment" : "comments") in this thread"
    }

    /// "↳ in reply to <author>", for a reply the connector can't reach.
    ///
    /// A drawn line can only state parenthood while both ends are on screen, and
    /// it isn't drawn at all when an earlier sibling's subtree sits between a reply
    /// and its parent. This says it in words instead: no width cost, and it still
    /// reads after the parent has scrolled away.
    ///
    /// Deliberately not shown on every reply. Where the parent is the row directly
    /// above, the connector already says it and this would only repeat the name
    /// above it — which in a thread dominated by one commenter is pure noise.
    /// `accessibilityHidden` because the row's own hint already announces it, and
    /// VoiceOver gets that hint whether or not this is on screen.
    ///
    /// One case outranks all of that: a reply to **your** comment (spec 1f's
    /// "REPLYING TO YOU"). That is the one piece of parentage a reader scans a
    /// comment section for, so it is stated on every such reply rather than only
    /// where the connector can't reach — the connector says *that* this answers
    /// the card above, never that the card above is yours. It replaces the name
    /// rather than sitting beside it, because the name would be your own.
    @ViewBuilder
    private var parentAttribution: some View {
        if parentIsViewer, participantRole != .me {
            // Suppressed on your own reply to your own comment: true, and useless.
            //
            // A kicker rather than a badge: the byline's chips say who someone *is*,
            // and this says what this comment is *doing*, so it sits over the prose
            // it qualifies. `.caption2` and not the spec's fixed 9pt — it sits
            // inside a block of body text that scales, and a kicker that stayed 9pt
            // while the prose grew would read as a rendering fault at accessibility
            // sizes.
            Text("Replying to you".uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.7)
                .foregroundStyle(theme.effectiveTint)
                .lineLimit(1)
                .accessibilityHidden(true)
        } else if showsParentAttribution, let replyToAuthor, !replyToAuthor.isEmpty {
            Label("in reply to \(replyToAuthor)", systemImage: "arrow.turn.down.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityHidden(true)
        }
    }

    /// Name and role pill, then the timestamp trailing — one line, as 1f draws it.
    /// The name is what gives way when the line runs short: everything after it is
    /// fixed-size, so a long pseud truncates rather than pushing the time off.
    ///
    /// Baseline-aligned, not `.top`: `.top` pinned the chapter badge to the top of
    /// the name's hit box, which sits above the name's own cap height.
    private func byline(timestamp: String) -> some View {
        HStack(alignment: .center, spacing: 7) {
            authorIdentity
                .layoutPriority(1)
                // The name gives up its own 28pt hit box (see `authorIdentity`); the
                // whole name-and-pill block opens the profile instead, as does the
                // avatar beside it. `including:` keeps a guest's block inert instead
                // of swallowing taps for a route that doesn't exist.
                .contentShape(Rectangle())
                .highPriorityGesture(
                    TapGesture().onEnded {
                        if let authorRoute { handlers.onOpenAuthor?(authorRoute) }
                    },
                    including: authorRoute == nil ? .subviews : .all
                )
            Spacer(minLength: 4)
            if !timestamp.isEmpty {
                timestampText(timestamp)
            }
            chapterBadge
            collapseControl
        }
    }

    /// Folds a whole conversation shut from its root's byline.
    ///
    /// Lives in the byline rather than the action strip because it acts on the
    /// *thread*, not on this comment — the action strip's Reply and overflow both
    /// address the comment itself, and mixing scopes in one row of controls is how
    /// people end up collapsing something when they meant to reply to it.
    @ViewBuilder
    private var collapseControl: some View {
        if let collapse {
            Button(action: onToggleCollapse) {
                // One line, full size: squeezed, "Hide" wrapped letter by letter
                // into a column that made the root's byline four lines tall. The
                // name is what gives way (see `byline`).
                Text(collapse.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // The 44pt tap area rides in a background, which takes no layout
            // space. `.minimumHitTarget()` made the byline 44pt tall on thread
            // roots only, so their centred name sat below the 30pt avatar while
            // every other row's lined up (owner, 2026-09-29).
            .background {
                // As wide as the pill, 44pt tall.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggleCollapse)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(collapse.accessibilityLabel)
        }
    }

    /// Avatar control: same profile entry as the byline name when the route is
    /// resolvable. Guests, deleted tombstones, and missing handlers stay inert.
    private var authorAvatarControl: some View {
        CommentAuthorAvatarButton(
            comment: comment,
            size: CommentThreadGeometry.avatarSize(forDepth: depth),
            onOpenAuthor: handlers.onOpenAuthor
        )
    }

    /// Tappable, pseud-correct author name — routes to the native profile when
    /// AO3 gave us a resolvable `/users/...` link (registered, non-guest
    /// commenters only); guests and unresolvable bylines render as plain text
    /// via the same component's own fallback.
    private var authorIdentity: some View {
        // Byline defaults to maxWidth: .infinity; role chips must not share that
        // flexible slot or they collapse to a tint/gray capsule with no label.
        //
        // Baseline — not centre — alignment. `AO3AuthorBylineView` gives its
        // tappable name a `minHeight: 28` hit box that is deliberately
        // *top*-aligned (growing downward so the name's baseline doesn't move),
        // which makes the byline view taller than the text inside it. Centring
        // the chip against that taller box therefore parks it below the name
        // instead of beside it; matching baselines puts the chip's own label on
        // the same line as the name, which is what it's meant to read as.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            AO3AuthorBylineView(
                names: [comment.author],
                identities: commentIdentity.map { [$0] } ?? [],
                includesBy: false,
                font: .system(size: nameSize),
                compact: true,
                emphasized: true,
                // Only the work's own author. Accenting every commenter spent the
                // app's loudest colour on its most repeated element, so the tint
                // marked "a person" rather than "worth reading first" — and the
                // author's reply, which is the thing people scan a comment section
                // for, looked like everything else. `.me` keeps plain text too: it
                // already carries a badge, and highlighting your own name tells you
                // nothing you don't know.
                tinted: participantRole == .author,
                // The 28pt hit box is top-aligned and grows downward, so it would
                // show as a gap between the byline and the prose beneath it — and a
                // guest's name has no such box, so registered and guest bylines
                // would be spaced differently for no reason a reader could name.
                // Safe to drop because the avatar beside it (44pt hit target) and
                // the byline block both open the same profile.
                expandsHitTarget: false,
                onOpenRoute: handlers.onOpenAuthor
            )
            CommentParticipantBadge(role: participantRole)
        }
        // The rail conveys "this is a reply, and to whom" only visually and is
        // `accessibilityHidden`, so it has to be said here. This used to ride on
        // the role badge, which no longer renders for a plain commenter — i.e.
        // for most replies (HIG audit UI-2). The drawn "REPLYING TO YOU" kicker is
        // hidden for the same reason, and says its piece through this hint instead,
        // so VoiceOver hears it once rather than twice.
        .accessibilityElement(children: .contain)
        .accessibilityHint(parentAttributionHint)
    }

    /// What the byline announces about who this comment answers. "Your comment"
    /// takes precedence over the name, matching what the kicker draws.
    private var parentAttributionHint: String {
        if parentIsViewer, participantRole != .me { return "Reply to your comment" }
        return replyToAuthor.map { "Reply to \($0)" } ?? ""
    }

    private func timestampText(_ timestamp: String) -> some View {
        Text(timestamp)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var chapterBadge: some View {
        // Empty/whitespace labels still pass `let chapter =` and used to paint a
        // hollow gray capsule on the trailing byline edge (the "gray blob").
        if showChapterBadge,
           let chapter = comment.chapterLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !chapter.isEmpty {
            Text(chapter)
                .font(.caption2)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
        }
    }

    /// The AO3 identity behind this comment's byline, when it's a real
    /// resolvable account — `AO3AuthorBylineView` falls back to plain text for
    /// guests and any comment whose byline link didn't resolve to a route.
    private var commentIdentity: AO3AuthorIdentity? {
        guard !comment.isGuest, let path = comment.userPath else { return nil }
        return AO3AuthorIdentity(displayName: comment.author, href: path)
    }

    /// The profile this byline opens, resolved through the same resolver
    /// `AO3AuthorBylineView` uses internally rather than a second derivation — so
    /// the block-wide tap target and the name's own can never disagree about where
    /// they go, or about whether there is anywhere to go at all.
    private var authorRoute: AO3AuthorRoute? {
        AO3AuthorBylineResolver.tokens(
            names: [comment.author],
            identities: commentIdentity.map { [$0] } ?? [],
            fallbackText: comment.author
        ).first?.route
    }

    /// Bottom strip: Reply bottom-leading, overflow bottom-trailing. Each keeps a
    /// 44pt hit area. Signed out, that area overlaps the comment instead of
    /// opening a gap — see `CommentActionRowLayout`.
    private var actionsRow: some View {
        let showsReply = CommentActionRowLayout.showsLeadingReply(
            canReply: comment.canReply, isLoggedIn: auth.isLoggedIn
        )
        let overlap = CommentActionRowLayout.verticalOverlap(showsLeadingReply: showsReply)
        return HStack(alignment: .center, spacing: 4) {
            if showsReply {
                // 1f's Reply is plain accent text, not a capsule: the actions sit
                // under prose with no card around it, where a filled chip on every
                // comment would be the heaviest thing in the column. The word, not
                // its padding, lines up with the prose above it.
                Button { handlers.onReply(comment) } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(minHeight: CommentActionRowLayout.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .accessibilityLabel("Reply to \(comment.author)")
                .padding(.leading, -10)
            }
            Spacer(minLength: 0)
            Menu {
                if showsReply {
                    Button { handlers.onReply(comment) } label: {
                        Label("Reply", systemImage: "arrowshape.turn.up.left")
                    }
                } else if comment.canReply {
                    Button { handlers.onRequestLogin() } label: {
                        Label("Log in to Reply", systemImage: "person.crop.circle.badge.questionmark")
                    }
                }
                if comment.editPath != nil {
                    Button { handlers.onEdit(comment) } label: {
                        Label("Edit Comment", systemImage: "pencil")
                    }
                }
                Button { handlers.onCopyLink(comment) } label: {
                    Label("Copy Link", systemImage: "link")
                }
                if comment.threadPath != nil {
                    Button { handlers.onFocusThread(comment.id) } label: {
                        Label("Thread", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                if let parentID = comment.parentCommentID {
                    Button { handlers.onFocusThread(parentID) } label: {
                        Label("Parent Thread", systemImage: "arrowshape.turn.up.backward")
                    }
                }
                if comment.deletePath != nil {
                    Button(role: .destructive) { handlers.onDelete(comment) } label: {
                        Label("Delete Comment", systemImage: "trash")
                    }
                }
            } label: {
                CommentOverflowButtonLabel()
            }
            // Without this the menu takes the row's whole width and, signed out,
            // its whole height — the lone button in a tall empty gap.
            .fixedSize(horizontal: true, vertical: true)
            .buttonStyle(.borderless)
            .accessibilityLabel("More actions for \(comment.author)'s comment")
        }
        .padding(.vertical, -overlap)
    }
}

/// Shared per-comment overflow control for Comments and Inbox: a bare mark,
/// as 1f draws it, on a 44pt hit target.
struct CommentOverflowButtonLabel: View {
    var body: some View {
        // 1f: a bare mark on every row, not a chip; the 44pt target stays.
        Image(systemName: "ellipsis")
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Expandable body

/// Comment body with a collapsed line limit and a Read more / Show less control
/// when the text is long enough to need it.
private struct ExpandableCommentBody: View {
    let text: String
    @State private var isExpanded = false
    @State private var clampedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 14

    /// Truncation is a layout fact. A character budget can't know the reader's
    /// Dynamic Type size or the card's width, so it both misses long comments at
    /// accessibility sizes and offers "Read more" on short ones.
    private var needsExpansion: Bool {
        fullHeight > clampedHeight + 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            bodyText
                .lineLimit(isExpanded ? nil : CommentThreadGeometry.collapsedBodyLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                // Snap between the clamped and full layouts rather than
                // animating the line-limit change: SwiftUI can't interpolate one
                // text layout into another, so it cross-fades the two
                // renderings and the glyphs visibly ghost and drift while the
                // frame grows. The card's own growth still animates.
                .animation(nil, value: isExpanded)
                .background(alignment: .top) { truncationProbes }

            if needsExpansion {
                Button {
                    withAnimationUnlessReduced(.easeInOut(duration: 0.2), reduceMotion: reduceMotion) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show less" : "Read more")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityHint(
                    isExpanded
                        ? "Collapses the full comment"
                        : "Expands the full comment"
                )
            }
        }
    }

    private var bodyText: some View {
        Text(text)
            // 1f: 14pt on a relaxed 1.55 line height, a notch under full primary,
            // so the prose reads as prose beside the semibold byline. Scaled with
            // Dynamic Type from `.body`, because this is the content of the screen.
            // The extra line spacing is what makes a multi-paragraph comment scan
            // as prose rather than as a wall.
            .font(.system(size: bodySize))
            .lineSpacing(bodySize * 0.35)
            .foregroundStyle(.primary.opacity(0.8))
    }

    /// Hidden copies of the body laid out at the live width: one clamped to the
    /// collapsed line limit, one unclamped. The unclamped copy being taller is the
    /// only reliable "this truncates" signal. Measured with the clamp always
    /// applied, so the control survives expanding (it becomes "Show less"). Neither
    /// height depends on `needsExpansion`, so this can't feed back into layout.
    private var truncationProbes: some View {
        ZStack(alignment: .top) {
            bodyText
                .lineLimit(CommentThreadGeometry.collapsedBodyLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    clampedHeight = $0
                }
            bodyText
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    fullHeight = $0
                }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared chrome helpers

private extension View {
    /// "Thread"/"Parent Thread" focus tint, sized to the CARD's own shape (not
    /// its content) so the flash reads as the whole card lighting up, edge to
    /// edge, rather than a smaller fill inset behind the row content. Painted
    /// between the card's background fill and its border stroke, so the border
    /// stays crisp on top.
    @ViewBuilder
    func highlightOverlay(_ shape: RoundedRectangle, isHighlighted: Bool) -> some View {
        self
            .overlay {
                if isHighlighted {
                    shape.fill(Color.accentColor.opacity(0.12))
                        .allowsHitTesting(false)
                }
            }
            .animation(unlessReduced: .easeInOut(duration: 0.3), value: isHighlighted)
    }
}

/// `verb` distinguishes the initial collapse ("Show 12 replies", nil) from
/// revealing another chunk of an already-expanded stack ("Show 20 more
/// replies"). A free function can't read `@Environment` itself, so the caller
/// passes its own `\.accessibilityReduceMotion` through explicitly.
private func expandRepliesButton(
    count: Int, verb: String?, reduceMotion: Bool, action: @escaping () -> Void
) -> some View {
    Button {
        withAnimationUnlessReduced(.easeInOut(duration: 0.2), reduceMotion: reduceMotion, action)
    } label: {
        Label(
            verb.map { "Show \(count) \($0) replies" } ?? "Show \(count) replies",
            systemImage: "bubble.left.and.bubble.right"
        )
        .font(.caption.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .accessibilityHint(
        verb == nil ? "Expands nested replies for this comment" : "Reveals more replies for this comment"
    )
}

// MARK: - Avatar

/// Tappable author avatar for comments — uses `AO3Comment.profileRoute` (same
/// gate as byline / composer). Guests, deleted comments, and missing open
/// handlers stay decorative.
///
/// Prefer this over a bare `Button` + `CommentAvatar` in List rows: comment
/// cards do not use `cardNavigation` today, so a plain Button is fine. If a
/// future change puts these rows behind a NavigationLink, switch the open
/// gesture to `highPriorityGesture` (see `AO3AuthorBylineView`) so the row
/// link does not stack on top of the profile.
struct CommentAuthorAvatarButton: View {
    let comment: AO3Comment
    var size: CGFloat = 40
    /// Layout width of the rail column (defaults to `size`). Keeps the spine
    /// geometry stable even when the hit target is larger than the circle.
    var columnWidth: CGFloat?
    var onOpenAuthor: ((AO3AuthorRoute) -> Void)?

    /// Minimum touch target (HIG); visual avatar may be smaller.
    private let minimumHit: CGFloat = 44

    var body: some View {
        let width = columnWidth ?? size
        let visual = CommentAvatar(comment: comment, size: size)
        let hit = max(minimumHit, size)

        // Layout footprint stays `width × size` for the reply rail. The tappable
        // control is overlaid at ≥44×44 and is allowed to extend slightly into
        // neighboring space (no clip) so hit testing is not clamped by the rail.
        //
        // Centred, not top-aligned: top alignment pinned the 44pt box's top to the
        // slot's, which left the visible circle (centred in that box) sitting
        // `(44 - size) / 2` below its own slot — 11pt at 22pt, far enough for the
        // elbow, which aims at the slot's centre, to miss the avatar entirely.
        ZStack {
            Color.clear
                .frame(width: width, height: size)

            if let route = comment.profileRoute, let open = onOpenAuthor {
                Button {
                    open(route)
                } label: {
                    visual
                        .frame(width: size, height: size)
                        .frame(width: hit, height: hit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(comment.author)'s profile")
                .accessibilityHint("Opens author profile")
            } else {
                visual
                    .frame(width: width, height: size, alignment: .top)
            }
        }
        .frame(width: width, height: size)
        // Do not `.clipped()` — overflow is intentional for the expanded hit box.
    }
}

struct CommentAvatar: View {
    private let isGuest: Bool
    private let avatarURL: URL?
    /// Whose avatar this is, used only for the no-image fallback. Optional so a
    /// caller without a name still gets the generic glyph rather than nothing.
    private let name: String?
    var size: CGFloat = 40

    @State private var loadedImage: Image?

    private var imageURL: URL? {
        isGuest ? nil : avatarURL
    }

    init(comment: AO3Comment, size: CGFloat = 40) {
        isGuest = comment.isGuest
        avatarURL = comment.avatarURL
        name = comment.author
        self.size = size
    }

    init(isGuest: Bool, avatarURL: URL?, name: String? = nil, size: CGFloat = 40) {
        self.isGuest = isGuest
        self.avatarURL = avatarURL
        self.name = name
        self.size = size
    }

    var body: some View {
        Group {
            if let loadedImage {
                loadedImage
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary.opacity(0.5), in: Circle())
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        // Hidden when decorative; parent Button supplies the profile label when
        // the avatar is a tappable entry point.
        .accessibilityHidden(true)
        .task(id: imageURL) { await loadImage() }
    }

    private func loadImage() async {
        loadedImage = nil
        guard let imageURL else { return }
        do {
            let data = try await AO3Client.shared.imageData(at: imageURL)
            try Task.checkCancellation()
            loadedImage = Self.image(from: data)
        } catch is CancellationError {
            return
        } catch {
            // The generic avatar is intentionally the fallback: an icon request
            // must never add a visible error or cause an independent retry loop.
            return
        }
    }

    private static func image(from data: Data) -> Image? {
        #if os(iOS)
            UIImage(data: data).map(Image.init(uiImage:))
        #elseif os(macOS)
            NSImage(data: data).map(Image.init(nsImage:))
        #else
            nil
        #endif
    }

    /// Shown when there's no icon to show — which on AO3 is most commenters.
    ///
    /// An initial rather than `person.fill`: a comment section is mostly people
    /// without icons, and the generic glyph made every byline in a long thread
    /// carry the same picture, so the avatar column said nothing and a
    /// back-and-forth between two people looked like a crowd.
    ///
    /// Guests keep the glyph deliberately. AO3 shows every guest as "Guest", so an
    /// initial there would either be a letter they didn't choose or a "G" repeated
    /// down the page — the glyph is the honest answer for someone with no identity.
    @ViewBuilder
    private var placeholder: some View {
        if !isGuest, let initial {
            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.43, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// First character of the display name, uppercased.
    ///
    /// Grapheme-clustered, not `first` on unicode scalars: AO3 usernames carry
    /// emoji and combining marks, and taking a scalar can split one visible
    /// character into a fragment that renders as a box. nil for a name with no
    /// usable character at all, which falls back to the glyph.
    private var initial: String? {
        guard let character = name?.trimmingCharacters(in: .whitespacesAndNewlines).first
        else { return nil }
        return String(character).uppercased()
    }
}

// MARK: - Swipe actions

extension View {
    /// Native swipe actions for one comment row.
    ///
    /// Split by consequence, which is also the iOS convention: the leading edge
    /// (swipe right) carries the single most common action, Reply, so it keeps
    /// a full-swipe shortcut; the trailing edge carries the rest. Full swipe is
    /// deliberately **off** on the trailing edge — Delete lives there, and a
    /// fast flick must never destroy a comment without a deliberate tap.
    ///
    /// Every action is still in the "…" menu. Swipe is an accelerator, not a
    /// replacement: the menu stays the discoverable path and the one VoiceOver
    /// and Full Keyboard Access users rely on.
    ///
    /// `comment` is nil for the expander row, which gets no actions at all.
    func commentSwipeActions(comment: AO3Comment?) -> some View {
        modifier(CommentSwipeActions(comment: comment))
    }
}

/// Reads its handlers from the environment rather than taking them as a
/// parameter: building a `CommentThreadHandlers` per row meant allocating seven
/// escaping closures for every comment on every layout pass, which a swipe
/// triggers repeatedly. The environment value is built once by the list.
private struct CommentSwipeActions: ViewModifier {
    let comment: AO3Comment?

    @Environment(\.commentThreadHandlers) private var handlers
    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.screenTint) private var screenTint

    @ViewBuilder
    func body(content: Content) -> some View {
        if let comment, !comment.isDeleted, !comment.isThreadCutoff {
            content
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if comment.canReply {
                        Button {
                            if auth.isLoggedIn {
                                handlers.onReply(comment)
                            } else {
                                handlers.onRequestLogin()
                            }
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                        }
                        .tint(screenTint ?? themeManager.effectiveTint)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Declared destructive-last so Delete sits furthest from the
                    // edge the thumb arrives at, not directly under it.
                    Button {
                        handlers.onCopyLink(comment)
                    } label: {
                        Label("Copy Link", systemImage: "link")
                    }
                    .tint(.gray)

                    if comment.editPath != nil {
                        Button {
                            handlers.onEdit(comment)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }

                    if comment.deletePath != nil {
                        Button(role: .destructive) {
                            handlers.onDelete(comment)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        } else {
            content
        }
    }
}

/// Which comment row is being swiped, shared across a comment list so that
/// row's replies can drop the line that joins them to it (owner, 2026-09-29).
@Observable
final class CommentSwipeTracker {
    var swipedID: Int?
}
