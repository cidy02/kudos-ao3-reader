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
// Only the tags AO3's sanitizer keeps are offered. Anything else it strips
// silently, and a button that produces nothing is a lie. Image is deliberately
// absent for the same reason in reverse: AO3 hosts no images, so the tag could
// only ever point off-site.
//
// Nesting order matters — AO3's parser rewrites mismatched closing tags and
// auto-closes anything left open at the end of the field — which is why
// `apply` returns a selection that still covers the *words*, not the words plus
// the tags it just wrote. Bold then italic gives `<strong><em>x</em></strong>`,
// properly nested, rather than a crossed pair.

// MARK: - Tags

/// One entry in the tray: what it is called, what it writes, and which of the
/// artboard's two groups it belongs to.
///
/// The enum is the whole list. Neither view carries a tag string of its own, so
/// adding or removing a tag is one line here and both surfaces follow.
enum CommentMarkupTag: String, CaseIterable, Identifiable, Hashable {
    // Text
    case bold, italic, underline, strike, superscript, `subscript`, small, code
    // Blocks & links
    case quote, bullets, numbers, heading, divider, link, spoiler

    /// The artboard's two sections, in its own order and with its own names.
    enum Group: String, CaseIterable, Identifiable {
        case text = "Text"
        case blocksAndLinks = "Blocks & links"

        var id: String { rawValue }
        var title: String { rawValue }
        var tags: [CommentMarkupTag] { CommentMarkupTag.allCases.filter { $0.group == self } }
    }

    var id: String { rawValue }

    /// Group, display name, the element actually written, and the button glyph —
    /// one switch rather than four. Fifteen cases repeated four times is exactly
    /// where a name and the tag underneath it drift apart, which on this screen
    /// would be the one unforgivable bug.
    private var spec: (group: Group, name: String, element: String, symbol: String) {
        // swiftlint:disable:previous large_tuple
        // (a private lookup table, not a four-field API anything else can reach)
        switch self {
        case .bold: (.text, "Bold", "strong", "bold")
        case .italic: (.text, "Italic", "em", "italic")
        case .underline: (.text, "Underline", "u", "underline")
        case .strike: (.text, "Strike", "s", "strikethrough")
        case .superscript: (.text, "Superscript", "sup", "textformat.superscript")
        case .`subscript`: (.text, "Subscript", "sub", "textformat.subscript")
        case .small: (.text, "Small", "small", "textformat.size.smaller")
        case .code: (.text, "Code", "code", "chevron.left.forwardslash.chevron.right")
        case .quote: (.blocksAndLinks, "Quote", "blockquote", "text.quote")
        case .bullets: (.blocksAndLinks, "Bullets", "ul", "list.bullet")
        case .numbers: (.blocksAndLinks, "Numbers", "ol", "list.number")
        // The artboard labels this one "h1–h6", which is a range rather than
        // something anybody can type. h3 is the default: AO3's own page already
        // spends h1 on the site and h2 on the work's title, so a comment heading
        // at either outranks the work it is a comment on.
        case .heading: (.blocksAndLinks, "Heading", "h3", "textformat.size")
        case .divider: (.blocksAndLinks, "Divider", "hr", "minus")
        case .link: (.blocksAndLinks, "Link", "a", "link")
        case .spoiler: (.blocksAndLinks, "Spoiler", "details", "chevron.down")
        }
    }

    var group: Group { spec.group }
    var name: String { spec.name }
    /// The element this button writes — `strong`, not `bold`.
    var element: String { spec.element }
    /// SF Symbol for the button. Every name here is checked against the system
    /// symbol list; a typo renders as an empty box rather than failing to build.
    var symbol: String { spec.symbol }

    /// What the tray prints under the name. The same as the element everywhere
    /// except the link, where `a` alone would not tell the reader that the href
    /// is the part they have to fill in.
    var tagLabel: String { self == .link ? "a href" : element }

    /// The six the compact bar carries before the tray is opened (spec 1be).
    static let quickBar: [CommentMarkupTag] = [.bold, .italic, .underline, .strike, .link, .quote]
}

// MARK: - Pure buffer edits

/// A rewritten buffer and where the selection should sit in it.
struct CommentMarkupResult: Equatable {
    let text: String
    let selection: Range<String.Index>
}

/// The tag-aware text buffer. Pure, synchronous, and the only place markup is
/// spelled out — both views call in here.
enum CommentMarkup {
    /// Writes `tag` into `text` around `selection`.
    ///
    /// Total by construction: any `(text, selection)` pair returns a buffer, and
    /// a selection that no longer belongs to this string appends at the end
    /// rather than trapping or eating a span it never covered.
    static func apply(
        _ tag: CommentMarkupTag,
        to text: String,
        in selection: Range<String.Index>
    ) -> CommentMarkupResult {
        let range = validated(selection, in: text)
        let selected = String(text[range])

        switch tag {
        case .divider:
            // `<hr>` has no closing tag and wraps nothing, so the selection is
            // left standing and the rule goes in after it, on a line of its own.
            // Replacing the selection would silently delete the user's words,
            // which no formatting button should ever do.
            let caret = range.upperBound..<range.upperBound
            let opensLine = range.upperBound == text.startIndex
                || text[text.index(before: range.upperBound)] == "\n"
            // End of buffer counts as *not* closing the line: without the break
            // the next thing typed would land on the rule's own line, which is
            // the one thing `<hr>` must not share.
            let closesLine = range.upperBound < text.endIndex && text[range.upperBound] == "\n"
            let rule = (opensLine ? "" : "\n") + "<\(tag.element)>" + (closesLine ? "" : "\n")
            return splice(text, caret, prefix: rule, body: "", suffix: "")

        case .bullets, .numbers:
            let items = selected
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { "<li>\($0)</li>" }
            guard !items.isEmpty else {
                // Nothing selected, or nothing but blank lines: one empty item
                // with the caret inside it, ready to type into.
                return splice(
                    text, range,
                    prefix: "<\(tag.element)>\n<li>", body: "",
                    suffix: "</li>\n</\(tag.element)>"
                )
            }
            // The selection comes back over the items rather than over the whole
            // block, so a second tag nests inside the list instead of wrapping
            // `<ul>` in `<em>`, which AO3's parser would rewrite.
            return splice(
                text, range,
                prefix: "<\(tag.element)>\n", body: items.joined(separator: "\n"),
                suffix: "\n</\(tag.element)>"
            )

        case .link:
            // The caret lands inside the empty href: the URL is the one thing
            // the tag cannot be completed without, and the text it labels is
            // already selected.
            return splice(
                text, range,
                prefix: "<\(tag.element) href=\"", body: "",
                suffix: "\">\(selected)</\(tag.element)>"
            )

        case .spoiler:
            // `<summary>` is the only part a reader sees before they open the
            // spoiler, and an empty one renders as the browser's own word
            // ("Details"), so the caret goes there — the same reasoning as the
            // link href. Whatever was selected becomes the hidden body.
            return splice(
                text, range,
                prefix: "<\(tag.element)><summary>", body: "",
                suffix: "</summary>\(selected)</\(tag.element)>"
            )

        default:
            return splice(
                text, range,
                prefix: "<\(tag.element)>", body: selected, suffix: "</\(tag.element)>"
            )
        }
    }

    /// Replaces `range` with `prefix + body + suffix` and returns the buffer with
    /// the selection covering `body` — collapsed between prefix and suffix where
    /// `body` is empty, which is what puts the caret inside a fresh tag pair.
    private static func splice(
        _ text: String,
        _ range: Range<String.Index>,
        prefix: String,
        body: String,
        suffix: String
    ) -> CommentMarkupResult {
        var out = text
        out.replaceSubrange(range, with: prefix + body + suffix)
        // Offsets are counted in UTF-8, not in Characters: concatenation is
        // additive in UTF-8 but not in grapheme clusters. A selection beginning
        // with a combining mark would merge with the `>` written before it and
        // throw a Character count off by one, which is a silently misplaced
        // caret rather than a crash — the worst kind of bug to find later.
        let start = text.utf8.distance(from: text.utf8.startIndex, to: range.lowerBound)
            + prefix.utf8.count
        let lower = out.utf8.index(out.utf8.startIndex, offsetBy: start)
        let upper = out.utf8.index(lower, offsetBy: body.utf8.count)
        return CommentMarkupResult(text: out, selection: lower..<upper)
    }

    /// A selection can outlive the string it was taken from — the field's text is
    /// replaced, a draft is restored, an undo lands. `String.Index(_:within:)` is
    /// the only check that answers "is this index real here" without trapping.
    ///
    /// The fallback is the end of the buffer rather than a clamp: a stale index
    /// clamped into range names a span the user never selected, and wrapping that
    /// span would move text the user did not ask to move. Appending loses
    /// nothing.
    private static func validated(
        _ selection: Range<String.Index>,
        in text: String
    ) -> Range<String.Index> {
        guard let lower = String.Index(selection.lowerBound, within: text),
              let upper = String.Index(selection.upperBound, within: text) else {
            return text.endIndex..<text.endIndex
        }
        return min(lower, upper)..<max(lower, upper)
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
    static func apply(_ tag: CommentMarkupTag, text: inout String, selection: inout TextSelection?) {
        let result = apply(tag, to: text, in: range(of: selection, in: text))
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

// MARK: - Formatting tray

/// Artboard 1bf's sheet. Every tag AO3 keeps, grouped as the artboard groups
/// them, each row printing the literal tag under the human name.
///
/// Printing the tag is the entire point of the screen: the tray is training
/// wheels for the website, where the user will type `<strong>` by hand. A row
/// that said only "Bold" would teach nothing.
///
/// The artboard draws the two groups as 4-column tiles. Rows instead: the tile
/// has room for a glyph and two words, and "blockquote" beside "Quote" is the
/// pairing that has to be legible at accessibility text sizes.
struct CommentFormattingTray: View {
    @Binding var text: String
    @Binding var selection: TextSelection?
    /// Where the tray is not presented as a sheet. Defaults to the environment's
    /// own dismiss, so a plain `.sheet { CommentFormattingTray(…) }` needs no
    /// callback and Done still closes it.
    var onDone: (() -> Void)?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            titleRow

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(CommentMarkupTag.Group.allCases) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            SubjectFieldLabel(text: group.title, style: .formGroup)
                            panel(for: group)
                        }
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
        .padding(.top, 14)
    }

    private func panel(for group: CommentMarkupTag.Group) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(group.tags.enumerated()), id: \.element) { index, tag in
                if index > 0 {
                    SubjectRowSeparator()
                }
                row(tag)
            }
        }
        .subjectPanel()
    }

    /// `SubjectFormRow`'s own metrics (14×12, gap 10) with a leading glyph, which
    /// that row has no slot for. The trailing tag is `SubjectFormValue`'s
    /// monospaced style, so the tag here and a date on a settings screen are set
    /// in the same face.
    private func row(_ tag: CommentMarkupTag) -> some View {
        Button {
            CommentMarkup.apply(tag, text: &text, selection: &selection)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tag.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 22)

                Text(tag.name)
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)

                SubjectFormValue(text: tag.tagLabel, isMonospaced: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tag.name), \(tag.tagLabel)")
    }
}
