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
/// this is a `UITextView` whose paragraph style has hyphenation off: a long word
/// still breaks where it must, with nothing added. Line breaks are dropped, typed
/// or pasted, and Return ends editing, as the one-line field did.
struct URLTextField: View {
    let placeholder: String
    @Binding var text: String
    var maxLines = 4

    var body: some View {
        URLTextView(text: $text, maxLines: maxLines, accessibilityLabel: "URL")
            .overlay(alignment: .topTrailing) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(Color(uiColor: .placeholderText))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct URLTextView: UIViewRepresentable {
    @Binding var text: String
    let maxLines: Int
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.keyboardType = .URL
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.accessibilityLabel = accessibilityLabel
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Trailing, as the field it replaces (`.multilineTextAlignment(.trailing)`).
        let alignment: NSTextAlignment = context.environment.layoutDirection == .rightToLeft ? .left : .right
        context.coordinator.attributes = Self.attributes(font: view.font, alignment: alignment)
        view.typingAttributes = context.coordinator.attributes
        context.coordinator.show(text, in: view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
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

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String
        ) -> Bool {
            guard replacement.contains(where: \.isNewline) else { return true }
            let cleaned = replacement.filter { !$0.isNewline }
            if !cleaned.isEmpty {
                let updated = (textView.text as NSString).replacingCharacters(in: range, with: cleaned)
                show(updated, in: textView)
                textView.selectedRange = NSRange(location: range.location + (cleaned as NSString).length, length: 0)
                text.wrappedValue = updated
            }
            textView.resignFirstResponder()
            return false
        }
    }
}
#endif
