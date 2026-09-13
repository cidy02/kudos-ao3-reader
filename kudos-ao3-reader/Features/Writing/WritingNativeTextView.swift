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

/// `AO3Markup` in the coordinates an `NSRange` world works in.
///
/// The raw `String` tag stays: `WritingTextController.command` is driven by the
/// toolbar with element names, and an unknown one has to be refused rather than
/// trapped. The allow-list is no longer a literal here — it is whatever the
/// chapter editor's vocabulary offers, so a tag reaches the buffer only if a
/// button for it exists.
nonisolated enum WritingMarkup {
    struct Insertion {
        let text: String
        let contentOffset: Int
    }

    static func insertion(tag: String, selected: String, link: String = "") -> Insertion? {
        guard let tag = AO3MarkupTag.writing.first(where: { $0.element == tag }) else { return nil }
        // A link with no usable URL writes nothing at all here, unlike the
        // comment tray, which has nowhere to ask for one and so writes an empty
        // href for the user to fill in. This surface *does* ask, in an alert,
        // before it calls: reaching here without a URL is a refusal, not a
        // half-written tag.
        if tag == .link, !safeLink(link) { return nil }
        // The host has no surrounding text to give: `selected` stands in as the
        // whole buffer, which only `<hr>` reads (for the newlines it needs
        // around itself), and only to decide whether to write one it may not
        // need.
        let splice = AO3Markup.splice(tag, in: selected, over: selected.startIndex..<selected.endIndex, link: link)
        let text = splice.text
        // `command` re-selects the *original* selection length at this offset,
        // so an offset deep enough to push that length past the replacement
        // would hand `UITextView` a range outside its own text. Clamped rather
        // than trusted: the tags that place a caret instead of wrapping (`<hr>`,
        // and with a selection `<details>` or a list) are exactly the ones that
        // can overshoot.
        let offset = min(splice.prefix.utf16.count, max(0, text.utf16.count - selected.utf16.count))
        return Insertion(text: text, contentOffset: offset)
    }

    static func safeLink(_ value: String) -> Bool { AO3Markup.safeLink(value) }
}
