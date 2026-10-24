#if os(iOS)
import Testing
import SwiftUI
import UIKit
@testable import Kudos

/// The parent work's URL wraps at any character. Word wrapping hyphenated a word wider
/// than the field ("archiveo- / fourown.org" at AX5) even with hyphenation off (T-443).
struct URLTextFieldWrappingTests {
    @Test func theURLWrapsAtAnyCharacterWithNoHyphen() {
        let style = URLTextView.attributes(font: nil, alignment: .right)[.paragraphStyle] as? NSParagraphStyle
        #expect(style?.lineBreakMode == .byCharWrapping)
        #expect(style?.hyphenationFactor == 0)
    }

    private typealias Edit = URLTextView.Coordinator.NewlineEdit

    /// Fails if `endsEditing` goes back to "any line break ends editing" (the paste case) or the
    /// lone Return stops ending editing.
    @Test func aLoneReturnEndsEditingAndInsertsNothing() {
        #expect(URLTextView.Coordinator.newlineEdit(for: "\n") == Edit(insert: "", endsEditing: true))
        #expect(URLTextView.Coordinator.newlineEdit(for: "\r\n") == Edit(insert: "", endsEditing: true))
    }

    /// Fails if a paste that ends in a line break ends editing, or keeps the line break.
    @Test func aPastedAddressWithATrailingLineBreakKeepsEditing() {
        #expect(
            URLTextView.Coordinator.newlineEdit(for: "https://a.org/works/1\n")
                == Edit(insert: "https://a.org/works/1", endsEditing: false)
        )
        #expect(
            URLTextView.Coordinator.newlineEdit(for: "https://a.org/\r\nworks/1\r\n")
                == Edit(insert: "https://a.org/works/1", endsEditing: false)
        )
    }

    /// Fails if text without a line break is no longer left to UIKit (it must not be rewritten).
    @Test func textWithoutALineBreakIsLeftAlone() {
        #expect(URLTextView.Coordinator.newlineEdit(for: "https://a.org") == nil)
        #expect(URLTextView.Coordinator.newlineEdit(for: "") == nil)
    }

    /// A paste that ends in a line break, through the real delegate in a window: the address goes in
    /// without the break, editing goes on, and the paste can be undone (`show` cleared undo).
    @MainActor @Test func aPastedAddressKeepsEditingAndCanBeUndone() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 200))
        let view = URLTextView.makeTextView(accessibilityLabel: "URL", accessibilityHint: nil, alignment: .right)
        view.frame = window.bounds
        window.addSubview(view)
        window.makeKeyAndVisible()
        var bound = "https://a.org/"
        let coordinator = URLTextView.Coordinator(text: Binding(get: { bound }, set: { bound = $0 }))
        view.delegate = coordinator
        view.text = bound
        #expect(view.becomeFirstResponder())
        let end = NSRange(location: (bound as NSString).length, length: 0)
        #expect(!coordinator.textView(view, shouldChangeTextIn: end, replacementText: "works/1\n"))
        #expect(view.text == "https://a.org/works/1")
        #expect(bound == "https://a.org/works/1")
        #expect(view.isFirstResponder, "a paste does not end editing")
        let undo = try #require(view.undoManager)
        #expect(undo.canUndo, "the paste is on the undo stack")
        undo.undo()
        #expect(view.text == "https://a.org/")
    }

    /// Fails if the placeholder is not passed to the text view as its VoiceOver hint.
    @Test func theTextViewExposesThePlaceholderAsItsAccessibilityHint() {
        let placeholder = "https://archiveofourown.org/works/…"
        let view = URLTextView.makeTextView(
            accessibilityLabel: "URL", accessibilityHint: placeholder, alignment: .right
        )
        #expect(view.accessibilityLabel == "URL")
        #expect(view.accessibilityHint == placeholder)
    }
}
#endif
