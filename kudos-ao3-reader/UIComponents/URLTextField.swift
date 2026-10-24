#if os(iOS)
import SwiftUI
import UIKit

/// A text field for a web address that wraps over up to `maxLines` lines and is
/// never hyphenated.
///
/// SwiftUI's vertical `TextField` hyphenates a long word as English text
/// ("archiveo- / fourown.org" at the largest text), and a hyphen in an address
/// reads as part of it. Neither a modifier nor `typesettingLanguage` turns that off
/// (a "zxx" typesetting language was tried and the field still hyphenated), so
/// this is a `UITextView` that wraps at any character, as an address bar does: a
/// long word breaks where the line is full, with nothing added. Hyphenation off was
/// not enough: word wrapping still adds a hyphen where it has to split a word wider
/// than the field (T-440 still showed "archiveo-" at AX5). Line breaks are dropped,
/// typed or pasted, and Return ends editing, as the one-line field did.
struct URLTextField: View {
    let placeholder: String
    @Binding var text: String
    var maxLines = 4

    var body: some View {
        URLTextView(
            text: $text, maxLines: maxLines, accessibilityLabel: "URL", accessibilityHint: placeholder
        )
            .overlay(alignment: .topTrailing) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(Color(uiColor: .placeholderText))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        // VoiceOver hears the placeholder as the text view's hint
                        // (`URLTextView.makeTextView`), so hide this copy.
                        .accessibilityHidden(true)
                }
            }
    }
}

struct URLTextView: UIViewRepresentable {
    @Binding var text: String
    let maxLines: Int
    let accessibilityLabel: String
    var accessibilityHint: String?

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        // Trailing, as the field it replaces (`.multilineTextAlignment(.trailing)`).
        let alignment: NSTextAlignment = context.environment.layoutDirection == .rightToLeft ? .left : .right
        let view = Self.makeTextView(
            accessibilityLabel: accessibilityLabel, accessibilityHint: accessibilityHint, alignment: alignment
        )
        view.delegate = context.coordinator
        context.coordinator.attributes = Self.attributes(font: view.font, alignment: alignment)
        context.coordinator.dynamicTypeSize = context.environment.dynamicTypeSize
        view.typingAttributes = context.coordinator.attributes
        context.coordinator.show(text, in: view)
        return view
    }

    /// The configured text view, without its delegate. A factory so a test can inspect what
    /// the representable builds (the VoiceOver hint is the placeholder).
    static func makeTextView(
        accessibilityLabel: String, accessibilityHint: String?, alignment: NSTextAlignment
    ) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byCharWrapping
        view.isScrollEnabled = false
        view.keyboardType = .URL
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.accessibilityLabel = accessibilityLabel
        view.accessibilityHint = accessibilityHint
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.typingAttributes = attributes(font: view.font, alignment: alignment)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        view.accessibilityHint = accessibilityHint
        let size = context.environment.dynamicTypeSize
        if context.coordinator.dynamicTypeSize != size {
            context.coordinator.dynamicTypeSize = size
            context.coordinator.refreshForContentSize(size, in: view)
        }
        if view.text != text { context.coordinator.show(text, in: view) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? uiView.sizeThatFits(
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        ).width
        let needed = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let lineHeight = (uiView.font ?? .preferredFont(forTextStyle: .body)).lineHeight
        let tallest = ceil(lineHeight * CGFloat(maxLines))
        // Past `maxLines` the field scrolls, as `lineLimit(1...4)` did.
        uiView.isScrollEnabled = needed > tallest
        return CGSize(width: width, height: max(ceil(lineHeight), min(needed, tallest)))
    }

    static func attributes(font: UIFont?, alignment: NSTextAlignment) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.hyphenationFactor = 0
        paragraph.usesDefaultHyphenation = false
        return [
            .font: font ?? UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ]
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var attributes: [NSAttributedString.Key: Any] = [:]
        /// The last text size applied, so a Dynamic Type change re-applies the attributes.
        var dynamicTypeSize: DynamicTypeSize?

        init(text: Binding<String>) { self.text = text }

        func show(_ string: String, in view: UITextView) {
            let selection = view.selectedRange
            // The view's current font: it follows Dynamic Type, the stored one would not.
            if let font = view.font { attributes[.font] = font }
            view.attributedText = NSAttributedString(string: string, attributes: attributes)
            view.typingAttributes = attributes
            let length = (string as NSString).length
            view.selectedRange = NSRange(location: min(selection.location, length), length: 0)
        }

        /// Re-applies the font (and the rest of the paragraph attributes) to the existing text
        /// and the typing attributes after a Dynamic Type change, which `show` alone would
        /// leave stale until the next edit.
        func refreshForContentSize(_ size: DynamicTypeSize, in view: UITextView) {
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
            let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
            view.font = font
            attributes[.font] = font
            let length = view.textStorage.length
            if length > 0 { view.textStorage.addAttributes(attributes, range: NSRange(location: 0, length: length)) }
            view.typingAttributes = attributes
            view.invalidateIntrinsicContentSize()
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        /// What a replacement containing line breaks does: the text to insert (line breaks
        /// dropped) and whether editing ends. Only a replacement that is nothing but line
        /// breaks (Return) ends editing; a paste with an address in it does not. `nil` when
        /// the replacement has no line break and goes through untouched.
        struct NewlineEdit: Equatable {
            let insert: String
            let endsEditing: Bool
        }

        static func newlineEdit(for replacement: String) -> NewlineEdit? {
            guard replacement.contains(where: \.isNewline) else { return nil }
            let cleaned = replacement.filter { !$0.isNewline }
            return NewlineEdit(insert: cleaned, endsEditing: cleaned.isEmpty)
        }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String
        ) -> Bool {
            guard let edit = Self.newlineEdit(for: replacement) else { return true }
            if !edit.insert.isEmpty { insert(edit.insert, replacing: range, in: textView) }
            if edit.endsEditing { textView.resignFirstResponder() }
            return false
        }

        /// Inserts through UITextInput so the edit registers with undo (setting
        /// `attributedText` would clear the undo stack), then re-applies the field's
        /// attributes to the inserted text.
        private func insert(_ string: String, replacing range: NSRange, in textView: UITextView) {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            if let font = textView.font { attributes[.font] = font }
            textView.typingAttributes = attributes
            textView.replace(textRange, withText: string)
            let inserted = NSRange(location: range.location, length: (string as NSString).length)
            if NSMaxRange(inserted) <= textView.textStorage.length {
                textView.textStorage.addAttributes(attributes, range: inserted)
            }
            textView.typingAttributes = attributes
            // `replace` calls `textViewDidChange`; this keeps the binding right regardless.
            text.wrappedValue = textView.text
        }
    }
}
#endif
