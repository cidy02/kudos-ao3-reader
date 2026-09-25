import Foundation

// The one markup vocabulary both writing surfaces offer, and the one function
// that writes it.
//
// AO3 sanitizes a comment and a chapter with the *same* allow-list:
// `lib/html_cleaner.rb#sanitize_value` sends every field in
// `FIELDS_ALLOWING_HTML` — `config/config.yml:374` names both
// `comment_content` and `content` — through `Sanitize::Config::ARCHIVE`. The
// only per-field differences are media embeds (`FIELDS_ALLOWING_MEDIA_EMBEDS`)
// and CSS/classes (`FIELDS_ALLOWING_CSS`), and neither toolbar offers either.
// So one vocabulary is the fact here rather than an abstraction: the comment
// tray (artboard 1bf) and the chapter editor differ in what they *offer*, never
// in what a tag means or in what it writes.
//
// `img` is absent although ARCHIVE keeps it: AO3 hosts no images, so the tag
// could only ever point off-site.
//
// Neither surface is a rich text editor. The user types real tags into a plain
// buffer and what posts is exactly what is in that buffer, which is why every
// button is labelled with the tag it writes — the habit has to transfer back to
// the website, where there is no toolbar.

// MARK: - Vocabulary

/// One offered tag: what it is called, what it writes, and which of the two
/// groups both toolbars sort their controls into.
///
/// The enum is the whole list. No view carries a tag string of its own, so
/// adding or removing a tag is one line here and every surface follows.
nonisolated enum AO3MarkupTag: String, CaseIterable, Identifiable, Hashable, Sendable {
    // Text
    case bold, italic, underline, strike, superscript, `subscript`, small, code
    // Blocks & links
    case paragraph, lineBreak, quote, bullets, numbers, heading, divider, link, spoiler

    /// The two sections, in the artboard's order and with its own names. Shared
    /// so the chapter editor groups its row the way the tray groups its rows,
    /// rather than inventing a third arrangement of the same tags.
    enum Group: String, CaseIterable, Identifiable, Sendable {
        case text = "Text"
        case blocksAndLinks = "Blocks & links"

        var id: String { rawValue }
        var title: String { rawValue }

        /// This group's tags within one surface's vocabulary. Argument-taking
        /// because the answer is per-surface: `<p>` is in this group and is a
        /// chapter tag only.
        func tags(in vocabulary: [AO3MarkupTag]) -> [AO3MarkupTag] {
            vocabulary.filter { $0.group == self }
        }
    }

    var id: String { rawValue }

    /// Group, display name, the element actually written, and the button glyph —
    /// one switch rather than four. Seventeen cases repeated four times is
    /// exactly where a name and the tag underneath it drift apart, which on
    /// these screens would be the one unforgivable bug.
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
        case .paragraph: (.blocksAndLinks, "Paragraph", "p", "text.alignleft")
        case .lineBreak: (.blocksAndLinks, "Line break", "br", "arrow.turn.down.left")
        case .quote: (.blocksAndLinks, "Quote", "blockquote", "text.quote")
        case .bullets: (.blocksAndLinks, "Bullets", "ul", "list.bullet")
        case .numbers: (.blocksAndLinks, "Numbers", "ol", "list.number")
        // The artboard labels this one "h1–h6", which is a range rather than
        // something anybody can type. h3 is the default: AO3's own page already
        // spends h1 on the site and h2 on the work's title, so a heading at
        // either outranks the work it sits in.
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

    /// What a surface prints as the tag itself. The same as the element
    /// everywhere except the link, where `a` alone would not tell the reader
    /// that the href is the part they have to fill in.
    var tagLabel: String { self == .link ? "a href" : element }
}

// MARK: - Per-surface vocabularies

extension AO3MarkupTag {
    /// The comment tray (artboard 1bf). `<p>` is absent because AO3 paragraphs a
    /// comment body itself — `add_paragraphs_to_text` — so the button would be a
    /// way to double-space your own comment, and `<br>` follows it: inside an
    /// auto-paragraphed body a bare break is a way to make a mess, not a line.
    static let comments: [AO3MarkupTag] = allCases.filter { $0 != .paragraph && $0 != .lineBreak }

    /// The chapter/summary/notes editor. It posts exactly what the writer typed,
    /// and AO3 then paragraphs it like every other HTML field: outside `<p>`,
    /// lists and headings, one newline becomes `<br>` and a blank line a new
    /// paragraph (`html_cleaner.rb`, `paragraph_maker.rb`;
    /// docs/WRITING_EDITOR_ARCHITECTURE.md §3.4). `<p>` and `<br>` are still the
    /// two tags that screen most needs, because they say exactly what the writer
    /// means instead of leaving it to line breaks, and the rest of the allow-list
    /// is theirs as well.
    static let writing: [AO3MarkupTag] = allCases
}

// MARK: - Pure buffer edits

/// The tag-aware buffer. Pure, synchronous, and the only place markup is spelled
/// out — every surface calls in here.
nonisolated enum AO3Markup {
    /// What a tag writes over the selection, in the three pieces a caller needs
    /// to place a caret without re-deriving the edit.
    ///
    /// Returning the pieces rather than a finished buffer is what lets the two
    /// hosts share this: a SwiftUI `TextEditor` wants a `Range<String.Index>`
    /// into the new string, a `UITextView` wants a UTF-16 offset for an
    /// `NSRange`, and each is a count away from `prefix` and `body`.
    struct Splice: Equatable, Sendable {
        /// Written before the new selection.
        let prefix: String
        /// What the new selection covers, and the caret's home when it is empty.
        let body: String
        /// Written after it.
        let suffix: String

        /// The replacement for the range this splice was made over.
        var text: String { prefix + body + suffix }
    }

    /// Writes `tag` over `range` of `text`.
    ///
    /// The selection comes back over the *words*, never over the words plus the
    /// tags just written, so a second tag nests inside the first: bold then
    /// italic gives `<strong><em>x</em></strong>` rather than a crossed pair
    /// that AO3's parser would rewrite.
    static func splice(
        _ tag: AO3MarkupTag,
        in text: String,
        over range: Range<String.Index>,
        link: String = ""
    ) -> Splice {
        let selected = String(text[range])

        switch tag {
        case .divider:
            // `<hr>` has no closing tag and wraps nothing, so the selection is
            // left standing and the rule goes in after it, on a line of its own.
            // Replacing the selection would silently delete the user's words,
            // which no formatting button should ever do. (The chapter editor's
            // own toolbar used to write `<hr>` in front of the selection, which
            // puts prose on the rule's line — the one thing a rule must not
            // share.)
            let opensLine = range.upperBound == text.startIndex
                || text[text.index(before: range.upperBound)] == "\n"
            // End of buffer counts as *not* closing the line: without the break
            // the next thing typed would land on the rule's own line.
            let closesLine = range.upperBound < text.endIndex && text[range.upperBound] == "\n"
            let rule = (opensLine ? "" : "\n") + "<\(tag.element)>" + (closesLine ? "" : "\n")
            return Splice(prefix: selected + rule, body: "", suffix: "")

        case .lineBreak:
            // The tag then the words, the one place a tag goes in front of the
            // selection: `<br>` ends the line above it, so writing it after the
            // selection would break the line the writer just chose, not the one
            // before it.
            return Splice(prefix: "<\(tag.element)>", body: selected, suffix: "")

        case .bullets, .numbers:
            let items = selected
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { "<li>\($0)</li>" }
            guard !items.isEmpty else {
                // Nothing selected, or nothing but blank lines: one empty item
                // with the caret inside it, ready to type into.
                return Splice(
                    prefix: "<\(tag.element)>\n<li>", body: "",
                    suffix: "</li>\n</\(tag.element)>"
                )
            }
            // The selection comes back over the items rather than over the whole
            // block, so a second tag nests inside the list instead of wrapping
            // `<ul>` in `<em>`.
            return Splice(
                prefix: "<\(tag.element)>\n", body: items.joined(separator: "\n"),
                suffix: "\n</\(tag.element)>"
            )

        case .link where safeLink(link):
            // A URL the caller already has (the chapter editor asks for one in
            // an alert before it writes anything). Escaped, because an href is
            // the one attribute value either surface ever writes and an
            // unescaped `&` in a query string is the common, silent corruption.
            return Splice(prefix: "<a href=\"\(escapedAttribute(link))\">", body: selected, suffix: "</a>")

        case .link:
            // No URL, or one whose scheme is not ours to write. The caret lands
            // inside the empty href: the URL is the one thing the tag cannot be
            // completed without, and the text it labels is already selected.
            // Falling back here rather than embedding an unvetted string is
            // deliberate — this function never emits a scheme it did not check.
            return Splice(prefix: "<a href=\"", body: "", suffix: "\">\(selected)</a>")

        case .spoiler:
            // `<summary>` is the only part a reader sees before they open the
            // spoiler, and an empty one renders as the browser's own word
            // ("Details"), so the caret goes there — the same reasoning as the
            // link href. Whatever was selected becomes the hidden body.
            return Splice(
                prefix: "<\(tag.element)><summary>", body: "",
                suffix: "</summary>\(selected)</\(tag.element)>"
            )

        default:
            return Splice(prefix: "<\(tag.element)>", body: selected, suffix: "</\(tag.element)>")
        }
    }

    /// A selection can outlive the string it was taken from — the field's text is
    /// replaced, a draft is restored, an undo lands. `String.Index(_:within:)` is
    /// the only check that answers "is this index real here" without trapping.
    ///
    /// The fallback is the end of the buffer rather than a clamp: a stale index
    /// clamped into range names a span the user never selected, and wrapping that
    /// span would move text the user did not ask to move. Appending loses
    /// nothing.
    static func validRange(_ selection: Range<String.Index>, in text: String) -> Range<String.Index> {
        guard let lower = String.Index(selection.lowerBound, within: text),
              let upper = String.Index(selection.upperBound, within: text) else {
            return text.endIndex..<text.endIndex
        }
        return min(lower, upper)..<max(lower, upper)
    }

    /// Schemes an href may carry. Anything else — `javascript:`, `data:`, a bare
    /// relative path — is refused rather than written, because what this buffer
    /// posts is what AO3 stores and hands to every future reader of the page.
    static func safeLink(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return ["https", "http", "mailto"].contains(scheme)
    }

    /// Escapes a value going into a double-quoted attribute. `&` first, or the
    /// ampersands of the other three escapes would be escaped again.
    private static func escapedAttribute(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
