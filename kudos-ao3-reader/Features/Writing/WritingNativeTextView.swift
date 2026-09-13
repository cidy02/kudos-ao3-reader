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
              let insertion = WritingMarkup.insertion(tag: tag, in: text, over: selection, link: link)
        else { return }
        replace(range, with: insertion.text)
        // The insertion's own length, never `range.length`: a tag that places a
        // caret rather than wrapping returns an empty body, and re-selecting the
        // old length there covers markup the next keystroke would overwrite.
        let next = NSRange(location: range.location + insertion.contentOffset, length: insertion.contentLength)
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
        /// UTF-16 length of what should end up selected.
        ///
        /// Not the caller's original selection length. `<hr>`, `<details>` and
        /// the lists all return a body that is a different length from what was
        /// selected — a caret, or the `<li>` items rather than the raw lines —
        /// and re-selecting the old length there lands the selection on the
        /// markup instead of the words. For `<details>` that was destructive:
        /// select `secret`, tap the tag, and the six characters now covered are
        /// `</summ`, so typing the summary the tag just invited overwrites its
        /// own closing tag and posts malformed markup.
        let contentLength: Int
    }

    /// Context-free entry point, kept because the toolbar and
    /// `WritingTextEditorTests` both drive it with a bare selection string.
    /// `<hr>` is the only tag that reads beyond the selection, and with nothing
    /// around it to read it assumes it needs its own newlines on both sides.
    static func insertion(tag: String, selected: String, link: String = "") -> Insertion? {
        insertion(tag: tag, in: selected, over: selected.startIndex..<selected.endIndex, link: link)
    }

    /// What `command` calls: the whole buffer, so `<hr>` can see whether the
    /// lines around it already exist instead of writing breaks it may not need.
    static func insertion(
        tag: String, in text: String, over range: Range<String.Index>, link: String = ""
    ) -> Insertion? {
        guard let tag = AO3MarkupTag.writing.first(where: { $0.element == tag }) else { return nil }
        let selected = String(text[range])
        // A link with no usable URL writes nothing at all here, unlike the
        // comment tray, which has nowhere to ask for one and so writes an empty
        // href for the user to fill in. This surface *does* ask, in an alert,
        // before it calls: reaching here without a URL is a refusal, not a
        // half-written tag.
        if tag == .link, !safeLink(link) { return nil }
        let splice = AO3Markup.splice(tag, in: text, over: range, link: link)
        // Offset and length both come from the splice, so the selection lands on
        // the body the shared core chose — the same place the comment surface
        // puts it. No clamp: a length taken from the body it describes cannot
        // reach past the text that body is part of.
        return Insertion(
            text: splice.text,
            contentOffset: splice.prefix.utf16.count,
            contentLength: splice.body.utf16.count
        )
    }

    static func safeLink(_ value: String) -> Bool { AO3Markup.safeLink(value) }
}
