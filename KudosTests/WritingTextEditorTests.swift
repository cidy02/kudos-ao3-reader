import Foundation
import Testing
import SwiftUI
@testable import Kudos

struct WritingTextEditorTests {
    @Test func recoveryPreservesMarkupAndSeparatesAccountsAndFields() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WritingTextRecovery(directory: directory)
        let url = store.fileURL(account: "Writer", target: "work:17", field: "content")
        let markup = "<p class='custom'>A &amp; B 👩🏽‍💻</p>\n<unknown data-x='1'>keep me</unknown>"
        try store.save(text: markup, original: "before", to: url)
        #expect(try store.load(from: url)?.text == markup)
        #expect(try store.load(from: url)?.originalDigest == WritingTextRecovery.digest("before"))
        #expect(url == store.fileURL(account: "writer", target: "work:17", field: "content"))
        #expect(url != store.fileURL(account: "another", target: "work:17", field: "content"))
        #expect(url != store.fileURL(account: "Writer", target: "work:17", field: "notes"))
        try store.save(text: "", original: "before", to: url)
        #expect(try store.load(from: url)?.text == "")
        let first = url.deletingPathExtension().appendingPathExtension("first.json")
        let second = url.deletingPathExtension().appendingPathExtension("second.json")
        try store.save(text: "first composition", original: "", to: first)
        try store.save(text: "second composition", original: "", to: second)
        #expect(Set(try store.copies(for: url).map(\.entry.text)).isSuperset(of: ["first composition", "second composition"]))
    }

    @Test func tagInsertionPreservesSelectedMarkupAndEscapesLinkAttributes() throws {
        let selected = "<unknown data-x='1'>👩🏽‍💻 &amp; 世界</unknown>"
        let insertion = try #require(WritingMarkup.insertion(tag: "strong", selected: selected))
        #expect(insertion.text == "<strong>" + selected + "</strong>")
        #expect(insertion.contentOffset == 8)
        #expect(WritingMarkup.insertion(tag: "script", selected: selected) == nil)
        #expect(WritingMarkup.insertion(tag: "a", selected: selected, link: "javascript:alert(1)") == nil)
        let link = try #require(WritingMarkup.insertion(tag: "a", selected: "site",
                                                       link: "https://example.com/?a=1&b=2"))
        #expect(link.text == "<a href=\"https://example.com/?a=1&amp;b=2\">site</a>")
        #expect(WritingMarkup.insertion(tag: "br", selected: "keep")?.text == "<br>keep")
    }

    @Test @MainActor func nativeEditorPreservesSourceSelectionUndoAndRecovery() async throws {
        let original = "<p class='keep'>Hello 👩🏽‍💻 &amp; 世界</p>\n<custom>keep</custom>"
        let controller = WritingTextController(text: original)
        #if os(iOS)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.addSubview(controller.textView)
        controller.textView.frame = window.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        controller.textView.becomeFirstResponder()
        #else
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = controller.scrollView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.textView)
        defer { window.orderOut(nil) }
        #endif
        // Edits are counted, not emitted: the text is read only when a
        // checkpoint asks for it (docs/WRITING_EDITOR_ARCHITECTURE.md D8).
        var edits = 0
        controller.onEdit = { edits += 1 }
        controller.setAppearance(.sepia, fontSize: 23)
        controller.commitComposition()
        #expect(controller.text == original)
        #expect(controller.takeCheckpoint() == nil)
        let selected = (original as NSString).range(of: "👩🏽‍💻 &amp; 世界")
        #if os(iOS)
        controller.textView.selectedRange = selected
        #else
        controller.textView.setSelectedRange(selected)
        #endif
        let undo = try #require(controller.textView.undoManager)
        controller.command("strong")
        try await Task.sleep(for: .milliseconds(50))
        let edited = original.replacingOccurrences(of: "👩🏽‍💻 &amp; 世界",
                                                  with: "<strong>👩🏽‍💻 &amp; 世界</strong>")
        #expect(controller.text == edited)
        #expect(edits > 0)
        #expect(controller.takeCheckpoint() == edited)
        // Nothing changed since: the next checkpoint writes nothing.
        #expect(controller.takeCheckpoint() == nil)
        #expect(undo.canUndo)
        controller.command("undo")
        #expect(controller.text == original)
        #expect(controller.takeCheckpoint() == original)
        controller.command("redo")
        #expect(controller.text == edited)
        try await Task.sleep(for: .milliseconds(50))
        controller.restore("<table><tr><td>Recovered</td></tr></table>")
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.takeCheckpoint() == "<table><tr><td>Recovered</td></tr></table>")
        controller.command("undo")
        #expect(controller.text == edited)
        #if os(iOS)
        controller.textView.selectedRange = NSRange(location: (edited as NSString).length, length: 0)
        controller.textView.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0))
        controller.textView.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0))
        controller.commitComposition()
        #expect(controller.textView.markedTextRange == nil)
        #expect(controller.takeCheckpoint() == edited + "日本")
        #endif
    }

}

/// Recovery copies are full chapters. Two rules keep them from becoming an
/// invisible, unbounded pile of the reader's unpublished writing.
struct WritingTextRecoveryBoundsTests {
    private func makeStore() -> (WritingTextRecovery, URL) {
        var store = WritingTextRecovery()
        store.directory = URL.temporaryDirectory
            .appendingPathComponent("recovery-bounds-\(UUID().uuidString)", isDirectory: true)
        return (store, store.fileURL(account: "writer", target: "work/42", field: "content"))
    }

    @Test func savingKeepsOnlyTheNewestFewCopiesOfAField() throws {
        let (store, key) = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        // Each editor session writes under its own UUID, so without pruning this
        // is one full copy of the chapter per session, forever.
        for index in 0..<(WritingTextRecovery.copyLimit + 4) {
            let sessionURL = key.deletingPathExtension()
                .appendingPathExtension(UUID().uuidString)
                .appendingPathExtension("json")
            try store.save(text: "draft \(index)", original: "original", to: sessionURL)
        }

        #expect(try store.copies(for: key).count <= WritingTextRecovery.copyLimit)
    }

    @Test func theNewestCopySurvivesPruning() throws {
        let (store, key) = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        var last = ""
        for index in 0..<(WritingTextRecovery.copyLimit + 2) {
            last = "draft \(index)"
            let sessionURL = key.deletingPathExtension()
                .appendingPathExtension(UUID().uuidString)
                .appendingPathExtension("json")
            try store.save(text: last, original: "original", to: sessionURL)
        }

        #expect(try store.copies(for: key).first?.entry.text == last)
    }
}
