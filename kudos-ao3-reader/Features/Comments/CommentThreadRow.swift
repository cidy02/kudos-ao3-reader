import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Geometry for comment threads.
///
/// **One card per comment**, in the app's own card language (`cardSurface`,
/// hairline border, shared radius) — a comment reads like every other Kudos
/// card, not like a dense forum row. Nesting is then carried two ways, borrowing
/// the idea from Reddit clients rather than their look: the card is indented per
/// level, and a themed rail runs down the inside of its leading edge.
///
/// The rail is tinted from the **accent** at stepped opacities, not a rainbow —
/// it has to hold up in Light, Dark, Sepia and OLED, and stay recognisably AO3
/// red rather than becoming its own palette.
///
/// This is structural as well as visual: each card belongs to exactly one row,
/// so nothing is shared across rows. The previous design ran one continuous
/// card and one avatar spine *across* rows, which is what let a swipe tear the
/// card apart and made the rail break at every boundary. It also restores
/// information that layout silently dropped — replies used to render identically
/// at every depth, so a reply-to-a-reply looked exactly like a direct reply.
/// How a reply is joined to its parent. A/B while the two are compared on
/// device; one of them should win and the other be deleted.
enum CommentConnectorStyle: String, CaseIterable, Identifiable {
    /// Trunk drops from the parent's avatar and turns into the reply's middle.
    case elbow
    /// Trunk drops straight down the padding band between a card and the reply
    /// nested inside it. The reply steps in by exactly that band, so it is inset
    /// equally on the left and the right — see `CommentThreadGeometry.indent`.
    case straight
    /// No nested cards at all: **one card per conversation**, replies as flat rows
    /// inside it, and a thin generational rail per level in the leading gutter.
    ///
    /// The other two styles nest a card per comment, which costs indent on *both*
    /// sides and needs a fill that differs from its parent — and there are only a
    /// couple of usable fill steps before a card washes out. Both costs scale with
    /// depth, and real threads go deep (The Queen's Mercy's epilogue carries a
    /// ~10-reply chain), which is also exactly where readers engage most.
    ///
    /// A gutter rail costs one small indent step and no fill difference whatsoever,
    /// and it only has to be distinguishable from its immediate neighbours — which
    /// `railColor`'s 4-way cycle already achieves, because adjacent rails are
    /// adjacent columns. So this gets *cheaper* with depth where nesting gets
    /// dearer. It is also what every mature comment client does.
    case flat
    /// The `AO3 Comments.dc.html` concept: **the list is depth-bounded.** A
    /// conversation shows its root and at most two direct replies; everything
    /// deeper is reached through a "Continue thread" row that pushes
    /// `CommentThreadScreen`.
    ///
    /// This is the idea the other three lack, and it is structural rather than
    /// cosmetic: they all try to render an arbitrarily deep tree inline, and every
    /// problem this design went through — the width squeeze, the fill ladder
    /// washing out, the six-rail gutter — came from that. Bounding the list means
    /// only one nesting level is ever drawn, so the hard cases stop existing
    /// instead of being tuned.
    case threads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .elbow: "Elbow"
        case .straight: "Straight"
        case .flat: "Flat"
        case .threads: "Threads"
        }
    }

    /// Whether the list stops at one level of replies and pushes the rest.
    var boundsConversations: Bool { self == .threads }

    static let storageKey = "commentConnectorStyle"
}

enum CommentThreadGeometry {
    static let cardPadding: CGFloat = 14
    /// Comment cards use the app-wide card radius, so a thread card reads exactly
    /// like a Library/Search card rather than a near-miss.
    static let cardCornerRadius = CardListMetrics.cornerRadius
    static let interCardSpacing = CardListMetrics.interCardSpacing
    /// Air above a new top-level conversation — wide enough for the rule that
    /// sits in it to read as a divider between threads rather than card chrome.
    static let conversationGap: CGFloat = 26
    /// Outer margin, matching the other card lists' side margin.
    static let sideMargin: CGFloat = 16
    /// Token indent for levels past `maxIndentedDepth`.
    static let compactIndentStep: CGFloat = 16
    /// Threads style: how far a reply's own card steps in from its parent's.
    ///
    /// Wider than the concept's 30, and the difference is load-bearing rather than
    /// taste. The connector drops from the parent's avatar centre, which sits
    /// `cardPadding + avatarSize/2` = 34pt inside the parent's card; at 30 the
    /// reply's leading edge lands at 30, *left* of that, so the elbow would have to
    /// double back on itself to reach the card it points at. (The concept dodges
    /// this by running its rail in a fixed gutter instead — and then its arm stops
    /// 9pt short of the card.) 48 clears the avatar with room for a visible
    /// forward arm, and the list only ever draws one level of it.
    static let threadsIndentStep: CGFloat = 48
    /// Threads style: levels of indent on the thread screen before it holds.
    static let threadsMaxIndentedDepth = 3
    /// Flat style: content indent for a reply.
    static let flatIndentStep: CGFloat = 16
    /// Flat style: the depth at which indenting stops. **Two.**
    ///
    /// Not a width budget — a legibility one. Depth past a couple of levels is not
    /// information a reader acts on: nobody needs to distinguish the ninth reply
    /// from the tenth. A ten-deep AO3 chain is two people talking, and it should
    /// look like two people talking, in reading order.
    ///
    /// Rendering the real tree was the mistake behind every artefact this design
    /// went through — the width squeeze, the fill ladder that washed out, and the
    /// six-stripe gutter. Those were all symptoms of drawing a structure instead of
    /// designing for what someone reading a comment section does. Structure past
    /// this depth is carried by `CommentPostRow.parentAttribution`, in words, only
    /// on the replies where reading order doesn't already make it obvious.
    static let flatMaxIndentedDepth = 2
    /// Deep AO3 chains would otherwise indent themselves off-screen; past this
    /// the rail opacity keeps changing but the indent stops growing.
    static let maxIndentedDepth = 2
    static let railWidth: CGFloat = 3
    static let railSpacing: CGFloat = 10
    static let avatarSize: CGFloat = 40
    /// Radius of the turn where a trunk elbows into its reply.
    static let elbowRadius: CGFloat = 10
    /// Inner cards sit a touch tighter than the outer conversation card.
    static let nestedCardCornerRadius: CGFloat = 12

    /// Avatars step down with depth so a nested reply reads as subordinate
    /// without needing a heavier frame — the root keeps the full 40pt the
    /// design has always used.
    static func avatarSize(forDepth depth: Int) -> CGFloat {
        switch max(0, depth) {
        case 0: 40
        case 1: 34
        default: 30
        }
    }
    static let avatarContentSpacing: CGFloat = 10
    /// Reply stacks larger than this start collapsed. Counts EVERY reply in the
    /// thread — the whole depth-first stack is what expanding actually renders —
    /// not just the root's direct children.
    static let autoExpandedMaxReplies = 8
    /// Once expanded, reveal this many replies at a time. A 200-reply thread
    /// then builds (and fires avatar `AsyncImage` requests for) one chunk per
    /// "Show more" tap instead of all 200 at once.
    static let repliesChunkSize = 20
    /// Collapsed body height before "Read more".
    static let collapsedBodyLineLimit = 5

    /// Rail tint for a nesting level: always the accent, stepped down in opacity
    /// and cycling, so adjacent levels are always distinguishable without
    /// introducing colours the theme doesn't own.
    static func railColor(forDepth depth: Int) -> Color {
        // Muted, and deliberately so. At full strength the accent made a hairline
        // of *furniture* the loudest thing on the screen, competing with the prose
        // it was only supposed to be joining — the same mistake as accenting every
        // commenter's name. The top of this ramp lands near the reference design's
        // own rail (`#5A1A1E`, which is this accent at ~37% over a near-black
        // page), so a connector reads as structure you can follow when you look
        // for it and ignore when you don't.
        //
        // The cycle still only has to separate *adjacent* levels, so the range is
        // tighter than it was: each step is roughly 1.4× its neighbour, which stays
        // legible without any of them shouting.
        let opacities: [Double] = [0.38, 0.28, 0.20, 0.14]
        return Color.accentColor.opacity(opacities[max(0, depth) % opacities.count])
    }


    /// Leading indent for a nesting level, clamped to what the screen can spare.
    ///
    /// **Elbow** steps in by the parent's whole avatar column — card padding,
    /// avatar, avatar gap — so a reply begins exactly where the words it answers
    /// do, and the trunk (which drops from the parent's avatar centre) stays to
    /// the *left* of the child's card edge, so the turn always runs forward into
    /// the card rather than doubling back on itself. Avatars shrink with depth,
    /// so that step is computed per level rather than being one constant.
    ///
    /// **Straight** steps in by one `cardPadding` — exactly what `nestedInset`
    /// takes off the trailing edge — so a reply is inset by the same amount on
    /// both sides and reads as sitting squarely inside its parent, instead of
    /// carrying a 64pt gap on the left against 14pt on the right. It can afford
    /// the narrower step because its trunk drops down that padding band rather
    /// than having to clear the parent's avatar. The tradeoff is deliberate:
    /// nesting is far subtler than the elbow's, so depth leans on the rail, the
    /// avatar step-down and the per-level surface shading to carry what the
    /// indent no longer says by itself.
    ///
    /// Both are then clamped, because avatars and padding are fixed point values
    /// and text is not: a fixed step keeps its width while the words inside a
    /// card grow, starving a nested card until its content spills. Keying that
    /// off an accessibility-size *category* wasn't enough — the sizes just below
    /// the threshold starve the card just as badly. So the ideal indent is
    /// computed first, then clamped so the content column never drops under
    /// `minimumContentWidth`. Nesting gives up width before legibility does, and
    /// it adapts to the real container, which also makes wider screens (iPad,
    /// landscape) keep the full indent.
    static func indent(
        forDepth depth: Int,
        availableWidth: CGFloat,
        typeSize: DynamicTypeSize,
        style: CommentConnectorStyle = .elbow
    ) -> CGFloat {
        var ideal: CGFloat = 0
        var budget = availableWidth - sideMargin * 2 - minimumContentWidth(for: typeSize)
        switch style {
        case .threads:
            // The *list* never renders past depth 1 — anything deeper is behind
            // "Continue thread" — so this cap only ever binds on the thread screen,
            // which walks a real tree. Three levels there, then it holds: at 48pt a
            // step, a deep chain would otherwise spend the screen on indent, and
            // the lesson from the other styles is that past a few levels depth
            // stops being information anyone acts on.
            ideal = threadsIndentStep * CGFloat(min(max(0, depth), threadsMaxIndentedDepth))
        case .flat:
            ideal = flatIndentStep * CGFloat(min(max(0, depth), flatMaxIndentedDepth))
        case .straight:
            ideal = CGFloat(max(0, depth)) * cardPadding
            // Symmetry means this indent comes off the *trailing* edge as well
            // (`CommentRowChrome.nestedInset`), so it may only spend half the
            // budget — spending all of it would starve the content column to
            // twice the depth the clamp believes it is protecting against.
            budget /= 2
        case .elbow:
            for level in 0 ..< max(0, depth) {
                let step = cardPadding + avatarSize(forDepth: level) + avatarContentSpacing
                ideal += level >= maxIndentedDepth ? compactIndentStep : step
            }
        }
        return max(0, min(ideal, budget))
    }

    /// Width a comment's own content needs before nesting may take any more.
    /// Grows with text size because that's exactly what the fixed-point indent
    /// fails to account for.
    static func minimumContentWidth(for typeSize: DynamicTypeSize) -> CGFloat {
        if typeSize.isAccessibilitySize { return 280 }
        return typeSize >= .xxLarge ? 240 : 200
    }

    /// Inset applied to a nested card's trailing and bottom edges per level.
    ///
    /// Deliberately *not* the elbow style's leading indent: mirroring a 64pt
    /// avatar-column step on both sides would starve a deep reply of width. It
    /// only has to read as sitting inside its parent. The straight style meets it
    /// from the other direction instead — its leading step *is* this inset, so
    /// there the two edges match. See `indent(forDepth:availableWidth:typeSize:style:)`.
    static func nestedInset(forLevel level: Int) -> CGFloat {
        CGFloat(max(0, level)) * cardPadding
    }

    /// Depth-first list of every reply under a root (root itself excluded),
    /// each becoming its own nested card.
    static func flattenedReplies(from root: AO3Comment) -> [FlattenedReply] {
        var result: [FlattenedReply] = []
        // An explicit stack, not recursion: AO3 doesn't cap reply nesting, and a
        // long reply-to-reply chain would otherwise cost one frame per level. The
        // single accumulator also avoids the O(depth²) copying that `[node] +
        // flatten(children)` incurs at every level.
        var stack: [FlattenedReply] = root.replies.reversed().map {
            FlattenedReply(comment: $0, depth: 1, parentAuthor: root.author)
        }
        while let item = stack.popLast() {
            result.append(item)
            for child in item.comment.replies.reversed() {
                stack.append(FlattenedReply(comment: child, depth: item.depth + 1, parentAuthor: item.comment.author))
            }
        }
        return result
    }
}

/// One row of a rendered conversation. A top-level comment and every reply
/// under it each become their **own** `List` row rather than subviews of a
/// single row, because `.swipeActions` only attaches to a row — packing a whole
/// thread into one row meant a swipe beside any reply fired with the *root*
/// comment's context (copying, editing, or deleting the wrong comment).
///
/// Depth is carried by the row's own indent and rail (see
/// `CommentThreadGeometry`), so nothing is shared between rows.
enum CommentConversationItem: Identifiable {
    /// `parentAuthor` is nil for the root post, set for a reply. `depth` is the
    /// AO3 nesting level (0 = root) and drives the indent and rail colour.
    case post(comment: AO3Comment, parentAuthor: String?, depth: Int)
    /// The "Show N replies" / "Show N more" control, itself a row so it sits
    /// inside the same continuous card.
    case expander(rootID: Int, hiddenCount: Int, showsVerb: Bool)
    /// "Continue thread" — the bounded list's exit to the thread screen.
    ///
    /// Distinct from `.expander`, which reveals more rows in place. This one
    /// navigates, and `hiddenCount` is every remaining **descendant**, not just
    /// the direct children left over. Counting direct children (as the concept's
    /// own mock does) hides a root with two replies and eight grandchildren behind
    /// no affordance at all.
    case continueThread(rootID: Int, hiddenCount: Int)

    /// Nesting level for thread-line purposes. The expander belongs to the
    /// replies it reveals, so it sits at their depth rather than the root's.
    var connectorDepth: Int {
        switch self {
        case let .post(_, _, depth): depth
        case .expander, .continueThread: 1
        }
    }

    var id: String {
        switch self {
        case let .post(comment, _, _): "post-\(comment.id)"
        case let .expander(rootID, _, _): "expander-\(rootID)"
        case let .continueThread(rootID, _): "continue-\(rootID)"
        }
    }

    /// The comment a swipe action should act on — nil for the control rows,
    /// which deliberately offer none.
    var actionableComment: AO3Comment? {
        switch self {
        case let .post(comment, _, _): comment
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
    var onOpenAuthor: ((AO3AuthorRoute) -> Void)? = nil

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
    /// this is its last row. An enclosing card at level `j` closes here exactly
    /// when `nextDepth <= j` — that's the whole test for where a nested card's
    /// bottom edge lands.
    let nextDepth: Int?
    /// True when this reply's parent is *not* the row directly above it — an
    /// earlier sibling's subtree sits in between, so no connector joins the two
    /// and the reply has to name its parent in text instead.
    let showsParentAttribution: Bool
    /// Set on a root that has replies: the caret's state and what it would reveal.
    /// nil everywhere else, which is also the "no caret" signal.
    let collapse: CommentCollapseState?

    var id: String { item.id }
}

/// The elbow-and-trunk lines that join a reply to its parent.
///
/// One shape per row, drawn in the row's *background* alongside the card, so
/// nothing crosses a row boundary and a swipe still moves only its own comment.
/// Consecutive rows touch, so the trunk segments read as one continuous line.
struct ThreadConnectors: Shape {
    let depth: Int
    let isLastSibling: Bool
    let ancestorLines: [Bool]
    let leadingInset: CGFloat
    /// The reply card's own top/bottom insets within the row, so the elbow can
    /// meet the card's vertical middle — the trunk then reads as running from
    /// just under the parent down into the centre of the reply it points at.
    let cardTopInset: CGFloat
    let cardBottomInset: CGFloat
    /// A row with a reply directly beneath it draws the *start* of that reply's
    /// trunk itself, from under its own avatar to its bottom edge. The line has
    /// to begin inside the parent — a row can only paint within its own bounds,
    /// so the reply's row picks it up at its top edge and the two segments meet.
    let hasChildBelow: Bool
    /// Centre of this row's avatar, where that descender starts — *behind* the
    /// picture, not below it. `CommentRowChrome.avatarBacking` paints an opaque
    /// disc over this stretch, so the line emerges tangent to the circle's lowest
    /// point with no gap, as if it ran out from under the picture.
    let avatarCenterY: CGFloat
    /// Resolved indent per level, handed down from the chrome. Recomputing it
    /// here would risk the lines and the cards disagreeing about where an edge
    /// is the moment either formula changes.
    let indents: [CGFloat]
    let style: CommentConnectorStyle
    /// Draw only the segments belonging to this nesting level.
    ///
    /// A row can carry lines for several levels at once — an ancestor's trunk,
    /// its own elbow, and the start of its child's trunk — and a `Shape` takes a
    /// single stroke colour. Emitting them all as one path meant a row painted
    /// every line in *its* colour, so one continuous trunk changed colour each
    /// time it crossed into a differently-nested row. The caller now strokes one
    /// filtered shape per level, each in that level's own colour.
    let level: Int
    let cornerRadius: CGFloat

    /// Horizontal centre of the trunk that joins a comment at `parentDepth` to
    /// its replies — the centre of that parent's avatar, so the line drops out
    /// of the picture rather than out of the margin beside it.
    private func indent(forLevel level: Int) -> CGFloat {
        guard level >= 0, level < indents.count else { return indents.last ?? 0 }
        return indents[level]
    }

    private func trunkX(parentDepth: Int) -> CGFloat {
        leadingInset
            + indent(forLevel: parentDepth)
            + CommentThreadGeometry.cardPadding
            + CommentThreadGeometry.avatarSize(forDepth: parentDepth) / 2
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // The flat style draws no connectors at all — `CommentRowChrome` never asks
        // it to. One rail per generation stacked six-deep in a single gutter is a
        // barcode, not structure, and painting it in the *accent* made the loudest
        // thing on screen the least meaningful. A hairline divider and reading
        // order do the job instead.

        // Descender into the reply below: starts at this comment's avatar centre,
        // on the column that reply's own connector will rise from. The stretch
        // from there to the circle's lowest point is hidden by the avatar backing,
        // so the line reads as running out from underneath the picture.
        if hasChildBelow, level == depth {
            let childX = trunkX(parentDepth: depth)
            // Threads leaves from the card's **bottom edge**, not from under the
            // avatar. Its cards are self-contained rather than nested, so a line
            // starting at the avatar has to run the whole height of the card —
            // past the body and the actions row — before it gets anywhere, and
            // that reads as something crossing the comment rather than leaving it.
            // The nesting styles keep the avatar origin: there the line is a trunk
            // the reply hangs off, and it belongs to the card it starts in.
            let startY = style == .threads
                ? rect.maxY - cardBottomInset
                : rect.minY + avatarCenterY
            // A row shorter than its own avatar column would otherwise emit a
            // segment running backwards, or a zero-length one — which a round cap
            // renders as a filled dot rather than as nothing at all.
            if startY < rect.maxY {
                path.move(to: CGPoint(x: childX, y: startY))
                path.addLine(to: CGPoint(x: childX, y: rect.maxY))
            }
        }

        guard depth > 0 else { return path }

        // An ancestor that still has siblings below keeps a straight line
        // running the full height of this row.
        //
        // For the straight style this stretch is what carries a line *past* an
        // earlier sibling's whole subtree to reach the next peer. It runs at that
        // ancestor's own avatar column, which this style's one-`cardPadding` indent
        // leaves inside the cards it passes — it is not drawn over them, because
        // `CommentRowChrome` paints each level's card in front of the lines
        // belonging to shallower levels. It is hidden behind the cards it passes
        // and reappears in the gaps between them.
        if level < depth - 1, level < ancestorLines.count, ancestorLines[level] {
            let x = trunkX(parentDepth: level)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }

        guard level == depth - 1 else { return path }

        // Straight style: no turn. Down from the row's top edge to the top edge of
        // this reply's own card, where the descender the parent drew from under its
        // avatar meets it — so the finished line reads as one segment from the
        // bottom of the parent's picture to the top of the reply. Nothing is cut
        // short to avoid the card: the card is painted in front of this line, so
        // the stretch that passes behind it is masked, including the stroke's round
        // cap. A middle sibling keeps the line running to the next peer instead of
        // ending at its own card.
        if style == .straight {
            let x = trunkX(parentDepth: depth - 1)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: isLastSibling ? rect.minY + cardTopInset : rect.maxY))
            return path
        }

        // This row's own level: down from the top, then a rounded turn into the
        // card's leading edge.
        let x = trunkX(parentDepth: depth - 1)
        let cardMidY = (rect.minY + cardTopInset + rect.maxY - cardBottomInset) / 2
        let y = min(max(cardMidY, rect.minY + cornerRadius), rect.maxY)
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: y - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: x + cornerRadius, y: y),
            control: CGPoint(x: x, y: y)
        )
        path.addLine(to: CGPoint(
            x: leadingInset + indent(forLevel: depth),
            y: y
        ))

        // A middle child's trunk carries on down to the next sibling's elbow.
        if !isLastSibling {
            path.move(to: CGPoint(x: x, y: y - cornerRadius))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return path
    }
}

/// Builds the flat row list for one top-level conversation.
///
/// Replies were already flattened depth-first (`flattenedReplies`); this only
/// decides which of them are visible and appends the expander control, so the
/// caller can emit one `List` row per item.
enum CommentConversationBuilder {
    /// `replies` is the root's depth-first reply list, precomputed by the model
    /// (`flattenedRepliesByRoot`). Deliberately a parameter rather than walked
    /// here: this runs on every layout pass, and re-walking the tree per frame
    /// is what made swiping a long thread stutter.
    /// Bounded form: the root, its first `boundedDirectReplies` **direct** replies,
    /// and a "Continue thread" row for everything else.
    ///
    /// `hidden` counts all remaining *descendants*, not the direct children left
    /// over — a root with two replies that each carry a subtree has nothing left
    /// over by the direct-child measure, and would silently drop its grandchildren.
    static func boundedItems(
        root: AO3Comment,
        replies: [FlattenedReply]
    ) -> [CommentConversationItem] {
        var items: [CommentConversationItem] = [
            .post(comment: root, parentAuthor: nil, depth: 0)
        ]
        let shown = replies.filter { $0.depth == 1 }.prefix(boundedDirectReplies)
        for reply in shown {
            items.append(.post(
                comment: reply.comment, parentAuthor: reply.parentAuthor, depth: reply.depth
            ))
        }
        let hidden = replies.count - shown.count
        if hidden > 0 {
            items.append(.continueThread(rootID: root.id, hiddenCount: hidden))
        }
        return items
    }

    /// How many direct replies a bounded conversation shows before deferring to the
    /// thread screen. Two, per the concept — enough to show a conversation started,
    /// few enough that a long comment section stays scannable.
    static let boundedDirectReplies = 2

    static func items(
        root: AO3Comment,
        replies: [FlattenedReply],
        isExpanded: Bool,
        visibleReplyCount: Int
    ) -> [CommentConversationItem] {
        // Gated on the total reply count, because expanding renders every
        // descendant, not just the root's direct children.
        let showsReplies = isExpanded
            || replies.count <= CommentThreadGeometry.autoExpandedMaxReplies

        guard !replies.isEmpty, showsReplies else {
            var items: [CommentConversationItem] = [
                .post(comment: root, parentAuthor: nil, depth: 0)
            ]
            if !replies.isEmpty {
                items.append(.expander(rootID: root.id, hiddenCount: replies.count, showsVerb: false))
            }
            return items
        }

        let shown = Array(replies.prefix(max(visibleReplyCount, CommentThreadGeometry.autoExpandedMaxReplies)))
        let hidden = replies.count - shown.count
        var items: [CommentConversationItem] = [
            .post(comment: root, parentAuthor: nil, depth: 0)
        ]
        for reply in shown {
            items.append(.post(
                comment: reply.comment,
                parentAuthor: reply.parentAuthor,
                depth: reply.depth
            ))
        }
        if hidden > 0 {
            items.append(.expander(rootID: root.id, hiddenCount: hidden, showsVerb: true))
        }
        return items
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
    static func rows(
        roots: [AO3Comment],
        repliesByRoot: [Int: [FlattenedReply]],
        expandedRootIDs: Set<Int>,
        visibleReplyCounts: [Int: Int],
        collapsedRootIDs: Set<Int> = [],
        bounded: Bool = false
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
            } else if bounded {
                boundedItems(root: root, replies: replies)
            } else {
                items(
                    root: root,
                    replies: replies,
                    isExpanded: expandedRootIDs.contains(root.id),
                    visibleReplyCount: visibleReplyCounts[root.id] ?? CommentThreadGeometry.repliesChunkSize
                )
            }
            // Depth-first order, so a node's siblings and descendants are all
            // ahead of it — one forward scan per row answers both questions the
            // thread lines need.
            let depths = items.map(\.connectorDepth)
            for (index, item) in items.enumerated() {
                let depth = depths[index]
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
                    // Only a root with replies can be folded. A reply's own caret
                    // would compete with its parent's for the same gesture on
                    // overlapping content, and closing a mid-thread reply leaves a
                    // hole rather than a tidier list.
                    collapse: depth == 0 && !replies.isEmpty
                        ? CommentCollapseState(isCollapsed: isCollapsed, replyCount: replies.count)
                        : nil
                ))
            }
        }
        return rows
    }
}

/// One comment as its own plain `List` row: indent + rail for depth, hairline
/// separators between rows, no card.
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
    /// Invoked by the expander row.
    var onExpand: () -> Void = {}
    /// Invoked by the "Continue thread" row.
    var onContinueThread: () -> Void = {}
    /// Invoked by a root comment's collapse caret.
    var onToggleCollapse: () -> Void = {}

    @Environment(ThemeManager.self) private var theme
    @Environment(AO3AuthService.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The work author's own replies are what readers scan a comment section
    /// for, so their rail takes the accent at full strength regardless of how
    /// deep the reply sits — depth still reads from the indent.
    private var isWorkAuthorComment: Bool {
        guard case let .post(comment, _, _) = item else { return false }
        let identity: AO3AuthorIdentity? = {
            guard !comment.isGuest, let path = comment.userPath else { return nil }
            return AO3AuthorIdentity(displayName: comment.author, href: path)
        }()
        return AO3CommentParticipantRole.resolve(
            name: comment.author,
            isGuest: comment.isGuest,
            isAnonymousCreator: comment.isAnonymousCreator,
            commenterUsername: identity?.username,
            currentUsername: auth.username,
            workAuthors: workAuthors,
            workAuthorUsernames: workAuthorIdentities.compactMap(\.username)
        ) == .author
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CommentThreadGeometry.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CommentRowChrome(
                depth: depth,
                isLastSibling: isLastSibling,
                ancestorLines: ancestorLines,
                nextDepth: nextDepth,
                startsConversation: startsConversation,
                isWorkAuthor: isWorkAuthorComment,
                half: CommentThreadGeometry.interCardSpacing / 2
            ))
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case let .post(comment, parentAuthor, _):
            CommentPostRow(
                comment: comment,
                workAuthors: workAuthors,
                workAuthorIdentities: workAuthorIdentities,
                showChapterBadge: parentAuthor == nil && showChapterBadge,
                depth: depth,
                replyToAuthor: parentAuthor,
                showsParentAttribution: showsParentAttribution,
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

/// The bounded list's exit to the thread screen.
///
/// A *navigation*, not a disclosure, so it says where it goes and carries a
/// chevron rather than the expander's "show more" affordance — the two sit in the
/// same slot in the same list and must not be mistaken for each other.
private func continueThreadButton(count: Int, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Continue thread")
                    .font(.subheadline.weight(.semibold))
                Text(count == 1
                    ? "1 more reply in this thread"
                    : "\(count) more replies in this thread")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .minimumHitTarget()
}

/// Frames a comment row: the app's card, plus the hairline that separates one
/// top-level conversation from the next.
private struct CommentRowChrome: ViewModifier {
    let depth: Int
    let isLastSibling: Bool
    let ancestorLines: [Bool]
    let nextDepth: Int?
    /// True on a root comment that isn't the first on the page — its card gets
    /// extra air above it and a rule, so consecutive conversations don't read as
    /// one long run of identical cards.
    let startsConversation: Bool
    /// The work author's own comments get an accent-tinted card, not just a
    /// tinted rail. Their replies are what readers scan a comment section for,
    /// and a card you can pick out at arm's length beats a 3pt stripe. Kept to a
    /// low opacity so body text stays readable on every theme, including OLED's
    /// true black and Sepia's warm paper.
    let isWorkAuthor: Bool
    let half: CGFloat

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.commentsContentWidth) private var contentWidth
    @AppStorage(CommentConnectorStyle.storageKey) private var connectorStyleRaw = CommentConnectorStyle.elbow.rawValue

    private var connectorStyle: CommentConnectorStyle {
        CommentConnectorStyle(rawValue: connectorStyleRaw) ?? .elbow
    }

    /// Indent for every level this row draws, resolved once so the cards and
    /// the connectors are guaranteed to agree.
    private var indents: [CGFloat] {
        (0 ... max(0, depth)).map {
            CommentThreadGeometry.indent(
                forDepth: $0, availableWidth: contentWidth,
                typeSize: dynamicTypeSize, style: connectorStyle
            )
        }
    }

    private var topGap: CGFloat {
        startsConversation ? CommentThreadGeometry.conversationGap : half
    }

    private var indent: CGFloat { indents[min(depth, indents.count - 1)] }

    /// Trailing (and bottom) inset for a level's card.
    ///
    /// `CommentThreadGeometry.nestedInset` is the general rule. The straight style
    /// mirrors its own *resolved* leading indent instead, so the two edges stay
    /// equal even at the depths where the width clamp shortens the indent and the
    /// two formulas would otherwise drift apart — which is the whole point of
    /// that style's narrower step.
    private func nestedInset(forLevel level: Int) -> CGFloat {
        switch connectorStyle {
        // One card for the whole conversation, so there is no nesting to inset
        // from: every row reaches the card's own trailing edge.
        case .flat: 0
        // Cards sit *beside* each other with an indent, never inside each other,
        // so a reply's card reaches the same trailing edge its parent's does.
        case .threads: 0
        case .straight: indents[min(max(0, level), indents.count - 1)]
        case .elbow: CommentThreadGeometry.nestedInset(forLevel: level)
        }
    }

    /// Vertical inset of this row's own card, so the connector can find the
    /// card's middle rather than the row's — the row also carries the gap above
    /// and below the card.
    private var cardTopInset: CGFloat { topGap }
    private var cardBottomInset: CGFloat {
        // Threads cards are never continued by the row below, so every one takes
        // its own bottom gap — `closesCard` is a containment question that doesn't
        // apply. Getting this wrong leaves the actions row hanging below its card.
        if connectorStyle == .threads { return half }
        return closesCard(atLevel: depth)
            ? half + nestedInset(forLevel: depth)
            : 0
    }

    private var avatarSize: CGFloat { CommentThreadGeometry.avatarSize(forDepth: depth) }

    /// Centre of this row's avatar, measured from the row's top and leading edge.
    private var avatarCenterY: CGFloat {
        topGap + CommentThreadGeometry.cardPadding + avatarSize / 2
    }

    private var avatarCenterX: CGFloat {
        CommentThreadGeometry.sideMargin + indent + CommentThreadGeometry.cardPadding + avatarSize / 2
    }

    /// An opaque disc exactly where this row's avatar sits, in the card's own
    /// colour, drawn after every connector line.
    ///
    /// The descender now starts *behind* the avatar rather than below it, so
    /// something has to hide that stretch — and the avatar itself cannot. Its
    /// fallback backing is `.quaternary.opacity(0.5)` (`CommentAvatar`), so the
    /// line would show through for every guest and every icon that hasn't loaded
    /// yet. Filling this disc with the same stack the card already paints there
    /// makes it invisible in its own right: it changes no pixel except the ones
    /// the line would have covered.
    @ViewBuilder
    private var avatarBacking: some View {
        let disc = Circle().frame(width: avatarSize, height: avatarSize)
        if connectorStyle == .threads {
            // Must match `standaloneCard`, which fills from `cardSurface` with no
            // nesting tint — `cardFill` would add one at odd depths and leave a
            // visibly different disc sitting on the card.
            disc
                .foregroundStyle(theme.appTheme.cardSurface)
                .overlay {
                    if isWorkAuthor {
                        Circle()
                            .fill(theme.effectiveTint.opacity(0.12))
                            .frame(width: avatarSize, height: avatarSize)
                    }
                }
                .position(x: avatarCenterX, y: avatarCenterY)
        } else {
            cardFill(Circle(), forLevel: depth)
                .frame(width: avatarSize, height: avatarSize)
                .position(x: avatarCenterX, y: avatarCenterY)
        }
    }

    /// The exact fill stack a level's card paints: surface, depth step, and the
    /// work-author tint. Shared by the card and by `avatarBacking`, so the disc
    /// that hides the connector can't drift out of colour with the card round it.
    @ViewBuilder
    private func cardFill(_ shape: some Shape, forLevel level: Int) -> some View {
        shape
            .fill(surface(forLevel: level))
            .overlay { shape.fill(nestingTint(forLevel: level)) }
            .overlay {
                // The author tint belongs to the author's *own* card, so it keys
                // off `level == depth`, never an ancestor. An author's reply sits
                // inside its parent's card too, and tinting by row alone painted
                // the shared outer card accent for just that row — a red band down
                // one slice of an otherwise plain conversation.
                if isWorkAuthor, level == depth {
                    shape.fill(theme.effectiveTint.opacity(0.12))
                }
            }
    }

    private func connectorLine(forLevel level: Int) -> some View {
        ThreadConnectors(
            depth: depth,
            isLastSibling: isLastSibling,
            ancestorLines: ancestorLines,
            leadingInset: CommentThreadGeometry.sideMargin,
            cardTopInset: cardTopInset,
            cardBottomInset: cardBottomInset,
            hasChildBelow: nextDepth == depth + 1,
            avatarCenterY: avatarCenterY,
            indents: indents,
            style: connectorStyle,
            level: level,
            cornerRadius: CommentThreadGeometry.elbowRadius
        )
        .stroke(
            CommentThreadGeometry.railColor(forDepth: level),
            style: StrokeStyle(lineWidth: CommentThreadGeometry.railWidth, lineCap: .round)
        )
    }

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(
                top: topGap,
                leading: CommentThreadGeometry.sideMargin + indent,
                // Must match the card's own bottom inset exactly. The card is
                // drawn in the row *background* and pulls its bottom edge up by
                // `nestedInset` so it sits inside its parent — content insets
                // that stop at `half` leave the actions row hanging that far
                // below the card it belongs to.
                bottom: cardBottomInset,
                // Keeps a nested card *within* its parent's padding on both sides
                // rather than running flush to the parent's right edge and
                // reading as an overlap.
                trailing: CommentThreadGeometry.sideMargin + nestedInset(forLevel: depth)
            ))
            // The card is the row's *background*, matching `.cardRow()` in every
            // other card list. It stops a swipe tearing a card that spans several
            // rows: background and content translate together, so the card moves
            // as one piece with its comment instead of the text sliding out of it.
            //
            // **It does not hold the card still.** An earlier version of this
            // comment claimed a swipe "translates content only" and left the
            // background anchored; observed on device (iOS 26.5), the whole row —
            // background included — translates. Anything in here that has to line
            // up with a *neighbouring* row therefore breaks mid-swipe: the swiped
            // row's connector slides away while the unswiped row's stays.
            //
            // **Accepted, 2026-07-29 (owner call) — see TASKS.md.** The only fix
            // that keeps cross-row lines is replacing `.swipeActions` with a custom
            // gesture, so the lines can sit outside the translated layer; that
            // means re-implementing full-swipe, snap points, haptics and VoiceOver
            // rotor integration, whose failure modes are worse than the cosmetic
            // problem. Note it is a cost of cross-row connectors *specifically*:
            // the flat style draws none, so it doesn't have the issue at all.
            .listRowBackground(enclosingCards)
            .listRowSeparator(.hidden)
    }

    /// Every card enclosing this row, outermost first, with each level's connector
    /// line drawn directly on top of that level's card.
    ///
    /// A comment is its own `List` row (so it can carry swipe actions), which
    /// means a parent card can't *contain* its replies as subviews. Instead each
    /// row paints the whole stack of cards it sits inside: the level-`j` card is
    /// rounded at the top only on the ancestor's own row, rounded at the bottom
    /// only on the last row of that ancestor's subtree, and square between —
    /// consecutive rows touch, so the fills join into one continuous enclosing
    /// card. Same visual nesting as true subview nesting, without giving up the
    /// per-comment swipe that subview nesting makes impossible.
    ///
    /// **The interleaving is load-bearing, not tidiness.** Card and line alternate
    /// per level, so the level-`j` line sits *above* the level-`j` card and *below*
    /// the level-`j+1` card. That is what lets a thread line run a row's full
    /// height and still never appear over a nested card: the card in front masks
    /// the stretch it passes behind, and it re-emerges in the gaps between cards.
    /// The straight style depends on it — its lines run down their own level's
    /// avatar column, which its one-`cardPadding` indent leaves *inside* the next
    /// level's card. Painting every line over every card (the previous
    /// `ZStack { cards; lines }`) drew them straight across the replies; cutting
    /// them short to compensate instead severed a reply from a parent further up.
    ///
    /// **The flat style takes none of this.** It paints one card for the whole
    /// conversation — level 0 only, which the same open/close rules already spread
    /// across every row of it — and its rails sit in a gutter column no content
    /// occupies. So no card stack, no interleaving, no avatar occlusion: the entire
    /// apparatus above exists to serve nesting a card per comment.
    @ViewBuilder
    private var enclosingCards: some View {
        ZStack {
            if connectorStyle == .threads {
                // Interleaved for the same reason the nesting styles are, with one
                // card instead of a stack. The elbow *into* this card is drawn
                // first so the card masks where the arm meets its edge; the
                // descender *out of* this comment is drawn after, because it runs
                // down over its own card from under the avatar.
                if depth > 0 { connectorLine(forLevel: depth - 1) }
                standaloneCard
                // No `avatarBacking`: nothing runs behind the avatar in this style
                // now that the line leaves from the card's bottom edge, so there is
                // nothing to occlude.
                connectorLine(forLevel: depth)
            } else if connectorStyle == .flat {
                card(forLevel: 0)
                rowDivider
            } else {
                ForEach(0 ... depth, id: \.self) { level in
                    card(forLevel: level)
                    connectorLine(forLevel: level)
                }
                avatarBacking
            }
        }
        // Confines every line and card to this row.
        //
        // 1. **Stroke caps.** A line that spans the row runs `minY`…`maxY`, and a
        //    round cap extends half a line width past each end — a 3pt circle of
        //    rail colour sitting just outside the row. On a masked line that stray
        //    cap is the *only* part that shows, so it reads as a red dot floating
        //    beside a card. Clipping trims the caps flat exactly at the boundary,
        //    where the next row's segment continues, while endpoints *inside* the
        //    row (a descender starting under an avatar) keep their round cap.
        // 2. **Card shadows** at a seam. A card continuing into the next row has no
        //    bottom padding, so its shadow fell across the join — a dark band
        //    through the middle of what should read as one unbroken card.
        .clipped()
        .accessibilityHidden(true)
        .overlay(alignment: .top) {
            // Sits in the gap above the card, not on it, so it reads as a
            // divider between conversations rather than a card border.
            //
            // Neutral `.primary`, not `cardBorder`: that token is **`.clear` on
            // Dark and OLED**, where the card's own contrast normally does the
            // separating — so this rule, whose whole job is to separate two cards
            // from each other, was invisible on exactly the themes where cards sit
            // closest in tone. Same trap as the nested-reply fill.
            if startsConversation {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 0.5)
                    .padding(.horizontal, CommentThreadGeometry.sideMargin)
                    // Centred in the *empty band* between the two cards, which is
                    // not the same as half this row's top gap. The previous
                    // conversation's card closes `half` above the row boundary
                    // (its level-0 bottom inset), and this one opens `topGap`
                    // below it — so the gap runs from `-half` to `+topGap` and its
                    // middle is `(topGap - half) / 2`, below the boundary rather
                    // than above it. Offsetting by `-topGap / 2` put the rule 13pt
                    // *up* into a card that ends 6pt up, drawing it across the
                    // previous comment instead of between the two.
                    .offset(y: (topGap - half) / 2)
                    .accessibilityHidden(true)
            }
        }
    }

    /// One self-contained card for this comment alone, stepped in by its depth.
    ///
    /// No containment, so none of the open/close corner logic applies: a card is
    /// never continued by the row below it, so it is simply rounded on all four
    /// sides and always takes its own top and bottom gap. That is the whole reason
    /// this style avoids the machinery the nesting ones need — nothing is shared
    /// across rows, so nothing can seam, mask, or tear.
    ///
    /// Definition comes from an inset hairline rather than the shadow: the shadow
    /// is `.clear` on Dark and OLED, where a nested card previously had nothing at
    /// all distinguishing it.
    private var standaloneCard: some View {
        let shape = RoundedRectangle(
            cornerRadius: CommentThreadGeometry.cardCornerRadius, style: .continuous
        )
        return shape
            .fill(theme.appTheme.cardSurface)
            .overlay {
                // Keyed on `isWorkAuthor` alone, not `level == depth` as the nested
                // styles need: a standalone card is only ever its own comment's, so
                // there is no ancestor card here to tint by mistake.
                if isWorkAuthor { shape.fill(theme.effectiveTint.opacity(0.12)) }
            }
            .overlay {
                shape.strokeBorder(
                    isWorkAuthor
                        ? theme.effectiveTint.opacity(0.55)
                        : Color.primary.opacity(0.08),
                    lineWidth: isWorkAuthor ? 1 : 0.5
                )
            }
            .padding(.leading, CommentThreadGeometry.sideMargin + indent)
            .padding(.trailing, CommentThreadGeometry.sideMargin)
            .padding(.top, topGap)
            .padding(.bottom, half)
            .shadow(
                color: theme.appTheme.cardShadow.color,
                radius: theme.appTheme.cardShadow.radius,
                x: 0, y: theme.appTheme.cardShadow.y
            )
    }

    /// Hairline between consecutive comments inside a conversation card.
    ///
    /// With no nested cards and no rails, this is the only thing marking where one
    /// comment ends and the next begins — and that is the whole point: a divider's
    /// job is to be found when looked for and ignored otherwise. Inset to the
    /// content column, in a neutral `.primary` tint rather than the accent, so it
    /// reads as furniture. `cardBorder` can't be used: it is `.clear` on Dark and
    /// OLED, where the card's own contrast normally does that work.
    ///
    /// Every row after a conversation's first is a reply, so `depth > 0` is the
    /// whole test. Consecutive *root* comments are separate conversations, hence
    /// separate cards, and already separated by the gap between them.
    @ViewBuilder
    private var rowDivider: some View {
        if depth > 0 {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
                .padding(.leading, CommentThreadGeometry.sideMargin
                    + CommentThreadGeometry.cardPadding + indent)
                .padding(.trailing, CommentThreadGeometry.sideMargin
                    + CommentThreadGeometry.cardPadding)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func card(forLevel level: Int) -> some View {
        cardFill(cardShape(forLevel: level), forLevel: level)
                    .overlay {
                        // Only the outermost card is stroked. The nested levels
                        // read as depth through their surface alone, which also
                        // sidesteps drawing a border that would have to skip its
                        // own top or bottom edge to avoid seaming between rows.
                        if level == 0 {
                            cardShape(forLevel: 0)
                                .strokeBorder(theme.appTheme.cardBorder, lineWidth: 0.5)
                        }
                        if isWorkAuthor, level == depth {
                            cardShape(forLevel: level)
                                .strokeBorder(theme.effectiveTint.opacity(0.55), lineWidth: 1)
                        }
                    }
                    .padding(.leading, CommentThreadGeometry.sideMargin + indents[min(level, indents.count - 1)])
                    .padding(.trailing, CommentThreadGeometry.sideMargin + nestedInset(forLevel: level))
                    .padding(.top, level == depth ? topGap : (opensCard(atLevel: level) ? topGap : 0))
                    // A nested card has to stop short of the card it sits
                    // inside, or the two share a bottom edge and the inner one
                    // reads as breaking out of its parent. Deeper levels take
                    // proportionally more bottom inset, mirroring the leading
                    // and trailing indent.
                    .padding(.bottom, closesCard(atLevel: level)
                        ? half + nestedInset(forLevel: level)
                        : 0)
                    // Only the outermost card carries the drop shadow. It encloses
                    // every nested card on this row — widest on both sides, and
                    // spanning the row's full height whenever it isn't the level
                    // opening or closing — so its rect *is* the silhouette the
                    // shadow was previously cast from when it wrapped the whole
                    // stack. Casting per level instead would stack shadows inside
                    // the card, and the shadow can no longer wrap the stack now
                    // that the stack contains the connector lines.
                    .shadow(
                        color: level == 0 ? theme.appTheme.cardShadow.color : .clear,
                        radius: theme.appTheme.cardShadow.radius,
                        x: 0, y: theme.appTheme.cardShadow.y
                    )
    }

    /// This row is where the level-`j` card starts — true only on the ancestor's
    /// own row, which is the row whose depth *is* `j`.
    private func opensCard(atLevel level: Int) -> Bool { depth == level }

    /// The level-`j` card ends here when nothing deeper follows it.
    private func closesCard(atLevel level: Int) -> Bool {
        guard let nextDepth else { return true }
        return nextDepth <= level
    }

    private func cardShape(forLevel level: Int) -> UnevenRoundedRectangle {
        let radius = level == 0
            ? CommentThreadGeometry.cardCornerRadius
            : CommentThreadGeometry.nestedCardCornerRadius
        let top = opensCard(atLevel: level) ? radius : 0
        let bottom = closesCard(atLevel: level) ? radius : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
    }

    /// Every card starts from the one card surface; `nestingTint` supplies the
    /// alternation on top of it.
    private func surface(forLevel level: Int) -> Color {
        theme.appTheme.cardSurface
    }

    /// The odd levels' half of the alternation, for the themes whose surface
    /// tokens can't supply it.
    ///
    /// Light and Sepia deliberately resolve `nestedCardSurface` to `cardSurface`
    /// and separate cards by elevation instead — but a nested card casts no shadow
    /// of its own here (the shadow comes from the outermost card's silhouette,
    /// which encloses every nested one) and only level 0 is stroked. So on those
    /// themes the two tones were the same colour and a direct reply did not read
    /// as a card at all. This is the step they can't get from the tokens.
    ///
    /// Dark and OLED do get a real second tone from `nestedCardSurface`, and take
    /// this on top of it — one tint on one parity, so the two-tone gap stays the
    /// same at every depth rather than accumulating.
    ///
    /// Derived from `.primary`, so it darkens on the light themes and lightens on
    /// the dark ones instead of baking in a grey.
    private func nestingTint(forLevel level: Int) -> Color {
        Color.primary.opacity(level.isMultiple(of: 2) ? 0 : 0.05)
    }
}

// MARK: - Post row

/// One comment's content: byline, body, actions. Carries no depth or position
/// information — the enclosing `CommentConversationRow` owns the indent and
/// rail, so this view is the same at every nesting level.
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
    var replyToAuthor: String? = nil
    /// Whether to *render* `replyToAuthor` as well as announce it. Set only where
    /// the connector can't do the job — see `CommentConversationRowItem`.
    var showsParentAttribution = false
    /// Set on a root with replies; nil means no caret.
    var collapse: CommentCollapseState?
    var onToggleCollapse: () -> Void = {}

    @Environment(AO3AuthService.self) private var auth
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.commentThreadHandlers) private var handlers

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
        // Formatted once and handed to both byline candidates: `ViewThatFits` builds
        // every candidate in order to measure it, and the date formatting isn't free.
        let timestamp = comment.postedText.isEmpty
            ? ""
            : AO3CommentTimestamp.displayText(
                rawText: comment.postedText, date: comment.postedAt
            )

        return HStack(alignment: .top, spacing: CommentThreadGeometry.avatarContentSpacing) {
            // A leading column again, not inline in the byline. A 40pt avatar has
            // no text baseline to align to, so sitting it inside the byline's
            // `.firstTextBaseline` row dragged the name and role chip out of
            // line with each other — the misalignment this is fixing.
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
                byline(timestamp: timestamp)
                parentAttribution
                if !comment.bodyText.isEmpty {
                    ExpandableCommentBody(text: comment.bodyText)
                }
                // Tighter gap above the action strip so bottom padding matches the
                // card’s side inset instead of a tall empty actions band.
                actionsRow
                    .padding(.top, 2)
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
    @ViewBuilder
    private var parentAttribution: some View {
        if showsParentAttribution, let replyToAuthor, !replyToAuthor.isEmpty {
            Label("in reply to \(replyToAuthor)", systemImage: "arrow.turn.down.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityHidden(true)
        }
    }

    private func byline(timestamp: String) -> some View {
        // Prefer author + timestamp on one line; when the timestamp won't fit
        // next to the name (long names, Author/Guest + chapter badge), drop it
        // onto the line under the author.
        ViewThatFits(in: .horizontal) {
            bylineSingleLine(timestamp: timestamp)
            bylineWrappedTimestamp(timestamp: timestamp)
        }
    }

    /// Author, role badge, and timestamp on one row (preferred when space allows).
    ///
    /// Baseline-aligned, matching `authorIdentity`'s own alignment. Centring
    /// here instead meant the name + role chip were baseline-aligned *to each
    /// other* and then centred as a block against the timestamp and chapter
    /// badge — and since that block is taller than its text (the byline's 28pt
    /// hit box), the chapter badge could never sit on the name's baseline.
    private func bylineSingleLine(timestamp: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            authorIdentity
            if !timestamp.isEmpty {
                timestampText(timestamp)
            }
            Spacer(minLength: 4)
            chapterBadge
            collapseControl
        }
    }

    /// Timestamp under the author when the single-line layout is too wide.
    ///
    /// Also baseline-aligned: `.top` pinned the chapter badge to the top of the
    /// name's hit box, which sits above the name's own cap height.
    private func bylineWrappedTimestamp(timestamp: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                authorIdentity
                if !timestamp.isEmpty {
                    timestampText(timestamp)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
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
                Text(collapse.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.5), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
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
                font: .subheadline,
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
                onOpenRoute: handlers.onOpenAuthor
            )
            CommentParticipantBadge(role: participantRole)
        }
        // The rail conveys "this is a reply, and to whom" only visually and is
        // `accessibilityHidden`, so it has to be said here. This used to ride on
        // the role badge, which no longer renders for a plain commenter — i.e.
        // for most replies (HIG audit UI-2).
        .accessibilityElement(children: .contain)
        .accessibilityHint(replyToAuthor.map { "Reply to \($0)" } ?? "")
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

    /// Compact bottom strip: Reply bottom-leading, overflow bottom-trailing.
    /// The capsule itself stays visually tight; each button reserves a 44pt
    /// minimum hit area around it (same convention as `expandRepliesButton`/
    /// `CommentAuthorAvatarButton` elsewhere in this file) so the small capsule
    /// doesn't fall below the app's own tap-target minimum.
    private var actionsRow: some View {
        HStack(alignment: .center, spacing: 4) {
            if comment.canReply && auth.isLoggedIn {
                // Match the overflow chip: quaternary capsule so Reply reads as
                // the same class of control rather than faint borderless text.
                CommentReplyButton(
                    accessibilityLabel: "Reply to \(comment.author)",
                    compact: depth >= CommentThreadGeometry.maxIndentedDepth
                        || dynamicTypeSize.isAccessibilitySize,
                    action: { handlers.onReply(comment) }
                )
            }
            Spacer(minLength: 0)
            Menu {
                if comment.canReply && auth.isLoggedIn {
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
            .buttonStyle(.borderless)
            .accessibilityLabel("More actions for \(comment.author)'s comment")
        }
    }
}

/// Shared visual language for per-comment overflow actions in Comments and
/// Inbox. The visible capsule stays compact while its hit target remains 44pt.
struct CommentOverflowButtonLabel: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
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
            // `.body`, not `.subheadline`. AO3 comments are paragraphs of prose,
            // not metadata — this is the content of the screen, and in a reading
            // app it should be set at reading size. The extra line spacing is
            // what makes a multi-paragraph comment scan as prose rather than as
            // a wall.
            .font(.body)
            .lineSpacing(2)
            .foregroundStyle(.primary)
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
        ZStack(alignment: .top) {
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
        .frame(width: width, height: size, alignment: .top)
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
                        .tint(.accentColor)
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
