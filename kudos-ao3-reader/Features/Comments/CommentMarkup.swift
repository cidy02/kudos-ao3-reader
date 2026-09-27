import Foundation
import SwiftUI

// Artboard **1bf** — the comment formatting tray, and the bar (1ba/1be) that
// opens it.
//
// AO3 gives comments no rich text editor: every comment anyone has ever bolded
// was hand-typed as `<strong>`. So this is NOT a rich text editor either. The
// user types plain text with real HTML tags in it, these controls write the tag
// around the selection, and what posts is exactly what is in the buffer — which
// is also why the tray prints the tag name under every button. The habit has to
// transfer back to the website, where there is no tray.
//
// The tags themselves, and the rules for writing them, are `AO3Markup` in
// Models: AO3 sanitizes a comment and a chapter with one allow-list, so the
// chapter editor's toolbar writes the same tags through the same function. What
// is left here is this surface's own share of it — which tags the tray offers,
// how the two views draw them, and the `TextSelection` bridge that the chapter
// editor, on a `UITextView`, has no use for.

// MARK: - Tags

/// The comment tray's slice of `AO3MarkupTag`, carrying no strings of its own.
///
/// A mirror of fifteen cases rather than a typealias for one reason: this type
/// means "everything the tray offers" to `CommentsView` and to the tests, and
/// the shared list also carries the chapter editor's `<p>` and `<br>`. The
/// `shared` switch below maps the two, and `AO3MarkupTag.comments` is pinned to
/// this case list by `AO3MarkupTests`, so the two can only drift with a red test.
enum CommentMarkupTag: String, CaseIterable, Identifiable, Hashable {
    // Text
    case bold, italic, underline, strike, superscript, `subscript`, small, code
    // Blocks & links
    case quote, bullets, numbers, heading, divider, link, spoiler

    /// Both surfaces sort their controls into the same two sections.
    typealias Group = AO3MarkupTag.Group

    var id: String { rawValue }

    /// The shared entry this row writes. A switch rather than a raw-value
    /// lookup so the compiler, not a test and not a fallback, proves every case
    /// maps.
    var shared: AO3MarkupTag {
        switch self {
        case .bold: .bold
        case .italic: .italic
        case .underline: .underline
        case .strike: .strike
        case .superscript: .superscript
        case .`subscript`: .`subscript`
        case .small: .small
        case .code: .code
        case .quote: .quote
        case .bullets: .bullets
        case .numbers: .numbers
        case .heading: .heading
        case .divider: .divider
        case .link: .link
        case .spoiler: .spoiler
        }
    }

    var group: Group { shared.group }
    var name: String { shared.name }
    /// The element this button writes — `strong`, not `bold`.
    var element: String { shared.element }
    /// SF Symbol for the button.
    var symbol: String { shared.symbol }
    /// What the tray prints under the name. Heading is the board's range
    /// (`h1–h6`), not the one level a tap with no chip selected writes.
    var tagLabel: String {
        self == .heading ? CommentMarkup.headingRangeLabel : shared.tagLabel
    }

    /// The six the compact bar carries before the tray is opened (spec 1be).
    static let quickBar: [CommentMarkupTag] = [.bold, .italic, .underline, .strike, .link, .quote]
}

extension AO3MarkupTag.Group {
    /// The tray's rows for this group. Argument-free, unlike the shared
    /// `tags(in:)`, because the tray asks for its own type: a row hands its tag
    /// straight to `CommentMarkup.apply`.
    var tags: [CommentMarkupTag] { CommentMarkupTag.allCases.filter { $0.group == self } }
}

// MARK: - Pure buffer edits

/// A rewritten buffer and where the selection should sit in it.
struct CommentMarkupResult: Equatable {
    let text: String
    let selection: Range<String.Index>
}

/// `AO3Markup` in the coordinates a SwiftUI `TextEditor` works in.
enum CommentMarkup {
    /// Levels AO3 keeps in a comment (Q20, `Sanitize::Config::ARCHIVE`: h1–h6).
    /// The chapter editor's shared heading stays h3; a comment picks from this
    /// list. h3 is the tap on the Heading tile when no chip is chosen — AO3
    /// already spends h1 on the site and h2 on the work title.
    static let headingLevels = Array(1 ... 6)
    static let defaultHeadingLevel = 3
    /// The board's own label under Heading, en dash included.
    static let headingRangeLabel = "h1–h6"

    /// The element a heading chip writes, or nil when `level` would not survive
    /// the comment sanitizer.
    static func headingElement(level: Int) -> String? {
        guard headingLevels.contains(level) else { return nil }
        return "h\(level)"
    }

    /// Writes `tag` into `text` around `selection`.
    ///
    /// Total by construction: any `(text, selection)` pair returns a buffer, and
    /// a selection that no longer belongs to this string appends at the end
    /// rather than trapping or eating a span it never covered.
    ///
    /// `headingLevel` is read only for `.heading`. Nil uses `defaultHeadingLevel`.
    /// Anything outside `headingLevels` does too, so the buffer never grows an
    /// `<h7>` AO3 would strip.
    static func apply(
        _ tag: CommentMarkupTag,
        to text: String,
        in selection: Range<String.Index>,
        headingLevel: Int? = nil
    ) -> CommentMarkupResult {
        let range = AO3Markup.validRange(selection, in: text)
        let splice = renderedSplice(tag, in: text, over: range, headingLevel: headingLevel)

        var out = text
        out.replaceSubrange(range, with: splice.text)
        // Offsets are counted in UTF-8, not in Characters: concatenation is
        // additive in UTF-8 but not in grapheme clusters. A selection beginning
        // with a combining mark would merge with the `>` written before it and
        // throw a Character count off by one, which is a silently misplaced
        // caret rather than a crash — the worst kind of bug to find later.
        let start = text.utf8.distance(from: text.utf8.startIndex, to: range.lowerBound)
            + splice.prefix.utf8.count
        let lower = out.utf8.index(out.utf8.startIndex, offsetBy: start)
        let upper = out.utf8.index(lower, offsetBy: splice.body.utf8.count)
        return CommentMarkupResult(text: out, selection: lower..<upper)
    }

    /// Heading writes the chosen level here. Every other tag still goes through
    /// `AO3Markup`, so a comment and a chapter spell `<strong>` the same way.
    /// No `link:` — the tray has nowhere to ask for a URL, so the link tag
    /// writes an empty href and puts the caret in it.
    private static func renderedSplice(
        _ tag: CommentMarkupTag,
        in text: String,
        over range: Range<String.Index>,
        headingLevel: Int?
    ) -> AO3Markup.Splice {
        guard tag == .heading else {
            return AO3Markup.splice(tag.shared, in: text, over: range)
        }
        let element = headingElement(level: headingLevel ?? defaultHeadingLevel)
            ?? headingElement(level: defaultHeadingLevel)
            ?? "h3"
        let selected = String(text[range])
        return AO3Markup.Splice(prefix: "<\(element)>", body: selected, suffix: "</\(element)>")
    }
}

// MARK: - SwiftUI selection bridge

extension CommentMarkup {
    /// Applies a tag to a live field and moves its caret.
    ///
    /// `TextEditor(text:selection:)` is iOS 18 / macOS 15 and up and the app
    /// targets 26.5, so a real selection range is available here — the pure
    /// function above does not depend on that, and still does the right thing
    /// given nothing but an insertion point.
    static func apply(
        _ tag: CommentMarkupTag,
        text: inout String,
        selection: inout TextSelection?,
        headingLevel: Int? = nil
    ) {
        let result = apply(
            tag, to: text, in: range(of: selection, in: text), headingLevel: headingLevel
        )
        text = result.text
        selection = TextSelection(range: result.selection)
    }

    /// `TextSelection` reduced to the one range this buffer works in.
    ///
    /// A multi-selection takes its outer span: pressing Bold on two separate
    /// runs has to produce one well-nested pair, and wrapping only the first run
    /// would quietly ignore half of what the user highlighted.
    static func range(of selection: TextSelection?, in text: String) -> Range<String.Index> {
        switch selection?.indices {
        case .selection(let range):
            return range
        case .multiSelection(let set):
            guard let first = set.ranges.first, let last = set.ranges.last else {
                return text.endIndex..<text.endIndex
            }
            return first.lowerBound..<last.upperBound
        case nil:
            // No selection yet — a field that has never been focused. Append.
            return text.endIndex..<text.endIndex
        @unknown default:
            return text.endIndex..<text.endIndex
        }
    }
}

// MARK: - Format bar

/// The compact row artboards 1ba/1be pin to the bottom edge of the composer,
/// directly above the keyboard: the six tags worth reaching for without opening
/// anything, then the control that opens the full tray.
///
/// Deliberately dumb — it holds the composer's two bindings and nothing else, so
/// it can sit in a `safeAreaInset`, a toolbar, or the sheet body unchanged.
struct CommentFormatBar: View {
    @Binding var text: String
    @Binding var selection: TextSelection?
    var onOpenTray: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CommentMarkupTag.quickBar) { tag in
                GlassCircleButton(accessibilityName: tag.name) {
                    CommentMarkup.apply(tag, text: &text, selection: &selection)
                } label: {
                    Image(systemName: tag.symbol)
                }
            }

            Spacer(minLength: 0)

            GlassCircleButton(accessibilityName: "More formatting") {
                onOpenTray()
            } label: {
                Image(systemName: "ellipsis")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.appTheme.glassStroke(0.10))
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Tray layout

/// Artboard 1bf's grid. Four columns at reading sizes; fewer once Dynamic Type
/// is an accessibility size, so "blockquote" under "Quote" still fits.
enum CommentFormattingLayout {
    /// The board's `grid-template-columns: repeat(4, 1fr)` and `gap: 7px`.
    static let restingColumnCount = 4
    static let gridGap: CGFloat = 7
    /// The board's tile: 58pt tall, 11pt corner.
    static let tileMinHeight: CGFloat = 58
    static let tileCornerRadius: CGFloat = 11
    /// Inside the tile, so the glyph and the two labels are not flush to the edge.
    static let tilePaddingH: CGFloat = 6
    static let tilePaddingV: CGFloat = 8

    static func columnCount(for typeSize: DynamicTypeSize) -> Int {
        if typeSize >= .accessibility3 { return 1 }
        if typeSize.isAccessibilitySize { return 2 }
        return restingColumnCount
    }
}

// MARK: - Formatting tray

/// Artboard 1bf's sheet. Every tag AO3 keeps, grouped as the artboard groups
/// them, each tile printing the literal tag under the human name.
///
/// Printing the tag is the entire point of the screen: the tray is training
/// wheels for the website, where the user will type `<strong>` by hand. A tile
/// that said only "Bold" would teach nothing.
///
/// Heading is one tile labelled `h1–h6`, then a row of `SubjectChip`s for the
/// levels Q20 keeps. The chip's own insets are its internal padding — this
/// row does not draw a bare label in their place.
struct CommentFormattingTray: View {
    @Binding var text: String
    @Binding var selection: TextSelection?
    /// Where the tray is not presented as a sheet. Defaults to the environment's
    /// own dismiss, so a plain `.sheet { CommentFormattingTray(…) }` needs no
    /// callback and Done still closes it.
    var onDone: (() -> Void)?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            titleRow

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(CommentMarkupTag.Group.allCases) { group in
                        groupSection(group)
                    }
                }
                .padding(.horizontal, SubjectMetrics.accountGutter)
                .padding(.vertical, 14)
            }
            .appThemedScroll()
        }
        // `subjectWash`, not `subjectScreenWash`: the latter also hides the
        // floating tab bar and empties the navigation bar, which is right for a
        // pushed screen and wrong for a sheet presented over one.
        .subjectWash(theme.scopePalette, height: 320)
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            Text("Formatting")
                .font(.system(size: 14, weight: .semibold))

            Spacer(minLength: 0)

            Button {
                if let onDone { onDone() } else { dismiss() }
            } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(theme.appTheme.glassFill(0.16)))
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
        }
        .padding(.horizontal, SubjectMetrics.accountGutter)
        .frame(minHeight: 44)
    }

    private func groupSection(_ group: CommentMarkupTag.Group) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // `.field` is the label that sits over a cluster of chips (10pt,
            // tracking .1em). The board's group titles are that, not a form-row
            // header and not `SectionRuleHeader`'s page rule.
            SubjectFieldLabel(text: group.title, style: .field)
            tileGrid(for: group)
            if group == .blocksAndLinks {
                headingLevelChips
            }
        }
    }

    private func tileGrid(for group: CommentMarkupTag.Group) -> some View {
        let count = CommentFormattingLayout.columnCount(for: dynamicTypeSize)
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: CommentFormattingLayout.gridGap),
            count: count
        )
        return LazyVGrid(columns: columns, spacing: CommentFormattingLayout.gridGap) {
            ForEach(group.tags) { tag in
                tile(tag)
            }
        }
    }

    private func tile(_ tag: CommentMarkupTag) -> some View {
        Button {
            let level = tag == .heading ? CommentMarkup.defaultHeadingLevel : nil
            CommentMarkup.apply(tag, text: &text, selection: &selection, headingLevel: level)
        } label: {
            CommentFormatTileFace(tag: tag)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tag.name), \(tag.tagLabel)")
    }

    /// One chip per level the sanitizer keeps. `SubjectChip` pads its label
    /// (11×6 on the rect); that padding is the chip, not a margin around it.
    private var headingLevelChips: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 52), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(CommentMarkup.headingLevels, id: \.self) { level in
                Button {
                    CommentMarkup.apply(
                        .heading, text: &text, selection: &selection, headingLevel: level
                    )
                } label: {
                    SubjectChip(
                        text: CommentMarkup.headingElement(level: level) ?? "",
                        style: .neutral
                    )
                }
                .buttonStyle(.plain)
                .minimumHitTarget(36)
                .accessibilityLabel("Heading \(level)")
            }
        }
        .padding(.top, 2)
    }
}

/// One 1bf tile: glyph, name, and the tag it writes, with padding inside the fill.
private struct CommentFormatTileFace: View {
    let tag: CommentMarkupTag

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 3) {
            glyph
                .frame(height: 19)
            Text(tag.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(tag.tagLabel)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, CommentFormattingLayout.tilePaddingH)
        .padding(.vertical, CommentFormattingLayout.tilePaddingV)
        .frame(maxWidth: .infinity, minHeight: CommentFormattingLayout.tileMinHeight)
        .background(
            RoundedRectangle(cornerRadius: CommentFormattingLayout.tileCornerRadius, style: .continuous)
                .fill(theme.appTheme.glassFill(0.09))
        )
        .contentShape(
            RoundedRectangle(cornerRadius: CommentFormattingLayout.tileCornerRadius, style: .continuous)
        )
    }

    @ViewBuilder
    private var glyph: some View {
        switch tag {
        case .bold:
            Text("B").font(.system(size: 16, weight: .bold, design: .serif))
        case .italic:
            Text("I").font(.system(size: 16, design: .serif)).italic()
        case .underline:
            Text("U").font(.system(size: 16, design: .serif))
        case .strike:
            Text("S").font(.system(size: 16, design: .serif))
        case .superscript:
            scriptedTwo(raised: true)
        case .`subscript`:
            scriptedTwo(raised: false)
        case .small:
            Text("Aa").font(.system(size: 11, design: .serif))
        case .code:
            Text("</>").font(.system(size: 12, design: .monospaced))
        case .heading:
            Text("H").font(.system(size: 15, weight: .bold))
        default:
            Image(systemName: tag.symbol)
                .font(.system(size: 15, weight: .medium))
        }
    }

    private func scriptedTwo(raised: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("A").font(.system(size: 15, design: .serif))
            Text("2")
                .font(.system(size: 9, design: .serif))
                .baselineOffset(raised ? 6 : -4)
        }
    }
}
