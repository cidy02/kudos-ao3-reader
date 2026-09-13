import SwiftUI

/// A native, plain-text HTML buffer. Inserting tags never parses or normalizes
/// existing markup; the platform text system owns selection, IME and undo.
@MainActor @Observable
final class WritingTextController: NSObject {
    #if os(iOS)
    let textView = UITextView()
    #else
    let scrollView = NSScrollView()
    let textView = NSTextView(frame: .zero)
    #endif
    var onChange: ((String) -> Void)?
    private var lastEmitted: String

    init(text: String) {
        lastEmitted = text
        super.init()
        #if os(iOS)
        textView.text = text
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.accessibilityLabel = "HTML text"
        #else
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.setAccessibilityLabel("HTML text")
        scrollView.drawsBackground = false
        #endif
        textView.delegate = self
    }

    var text: String {
        #if os(iOS)
        textView.text ?? ""
        #else
        textView.string
        #endif
    }

    func setAppearance(_ theme: ReaderTheme, fontSize: Double) {
        #if os(iOS)
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = UIColor(theme.textColor)
        textView.tintColor = UIColor(theme.textColor)
        #else
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor(theme.textColor)
        textView.insertionPointColor = NSColor(theme.textColor)
        #endif
    }

    func command(_ tag: String, link: String = "") {
        commitComposition()
        #if os(iOS)
        textView.becomeFirstResponder()
        #else
        textView.window?.makeFirstResponder(textView)
        #endif
        if tag == "undo" { textView.undoManager?.undo(); emit(); return }
        if tag == "redo" { textView.undoManager?.redo(); emit(); return }
        #if os(iOS)
        let range = textView.selectedRange
        #else
        let range = textView.selectedRange()
        #endif
        guard let selection = Range(range, in: text),
              let insertion = WritingMarkup.insertion(tag: tag, selected: String(text[selection]), link: link)
        else { return }
        replace(range, with: insertion.text)
        let next = NSRange(location: range.location + insertion.contentOffset, length: range.length)
        #if os(iOS)
        textView.selectedRange = next
        textView.scrollRangeToVisible(next)
        #else
        textView.setSelectedRange(next)
        textView.scrollRangeToVisible(next)
        #endif
    }

    /// Recovery is an ordinary undoable replacement, never an implicit load.
    func restore(_ value: String) {
        commitComposition()
        replace(NSRange(location: 0, length: (text as NSString).length), with: value)
    }

    func flush() {
        commitComposition()
        emit()
    }

    private func commitComposition() {
        #if os(iOS)
        if textView.markedTextRange != nil { textView.unmarkText() }
        #else
        if textView.hasMarkedText() { textView.unmarkText() }
        #endif
    }

    private func replace(_ range: NSRange, with value: String) {
        #if os(iOS)
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let target = textView.textRange(from: start, to: end) else { return }
        textView.replace(target, withText: value)
        #else
        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(in: range, replacementString: value) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: value)
        textView.didChangeText()
        #endif
        emit()
    }

    fileprivate func emit() {
        let value = text
        guard value != lastEmitted else { return }
        lastEmitted = value
        onChange?(value)
    }
}

#if os(iOS)
extension WritingTextController: UITextViewDelegate {
    func textViewDidChange(_: UITextView) { emit() }
}

struct WritingNativeTextView: UIViewRepresentable {
    let controller: WritingTextController
    func makeUIView(context: Context) -> UITextView { controller.textView }
    func updateUIView(_: UITextView, context: Context) {}
}
#else
extension WritingTextController: NSTextViewDelegate {
    func textDidChange(_: Notification) { emit() }
}

struct WritingNativeTextView: NSViewRepresentable {
    let controller: WritingTextController
    func makeNSView(context: Context) -> NSScrollView { controller.scrollView }
    func updateNSView(_: NSScrollView, context: Context) {}
}
#endif

nonisolated enum WritingMarkup {
    struct Insertion {
        let text: String
        let contentOffset: Int
    }

    static func insertion(tag: String, selected: String, link: String = "") -> Insertion? {
        guard ["em", "strong", "p", "br", "hr", "a", "blockquote"].contains(tag) else { return nil }
        let opening: String
        if tag == "a" {
            guard safeLink(link) else { return nil }
            let escaped = link.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            opening = "<a href=\"\(escaped)\">"
        } else {
            opening = "<\(tag)>"
        }
        let closing = ["br", "hr"].contains(tag) ? "" : "</\(tag)>"
        return Insertion(text: opening + selected + closing, contentOffset: opening.utf16.count)
    }

    static func safeLink(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return ["https", "http", "mailto"].contains(scheme)
    }
}
