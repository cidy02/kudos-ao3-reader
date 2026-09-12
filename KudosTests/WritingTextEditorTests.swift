import Foundation
import Testing
import WebKit
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

    @Test func unsupportedAndActiveMarkupStaysInSourceMode() {
        #expect(WritingHTMLDocument.supportsRichEditing("<p class='keep'>Hello <em>world</em></p>"))
        for html in ["<script>alert(1)</script>", "<img src='https://example.com/tracker'>",
                     "<p onclick='alert(1)'>text</p>", "<a href='javascript:alert(1)'>link</a>",
                     "<p style='color:red'>keep styling</p>", "<custom>keep this tag</custom>"] {
            #expect(!WritingHTMLDocument.supportsRichEditing(html))
        }
        #expect(!WritingHTMLDocument.safeLink("javascript:alert(1)"))
        #expect(WritingHTMLDocument.safeLink("https://archiveofourown.org/works/1"))
    }

    @Test @MainActor func webEditorPreservesUntouchedSourceAndEditsSelection() async throws {
        let original = "<p class='keep'>Hello &amp; 世界</p>\n"
        let controller = WritingHTMLController(text: original)
        defer { controller.stop() }
        for _ in 0..<100 where !controller.isReady { try await Task.sleep(for: .milliseconds(50)) }
        #expect(controller.isReady)
        var emitted: String?
        controller.onChange = { emitted = $0 }
        let web = controller.webView
        _ = try await web.callAsyncJavaScript("window.writing.set(value, true)",
                                             arguments: ["value": original], contentWorld: .defaultClient)
        let source = try await web.callAsyncJavaScript("return document.getElementById('source').value",
                                                      contentWorld: .defaultClient) as? String
        #expect(source == original)
        #expect(emitted == nil)
        _ = try await web.callAsyncJavaScript("""
        const el = document.getElementById('source'); el.focus(); el.setSelectionRange(16, 21);
        window.writing.command('strong', '');
        """, contentWorld: .defaultClient)
        let edited = try await web.callAsyncJavaScript("return document.getElementById('source').value",
                                                      contentWorld: .defaultClient) as? String
        #expect(edited == "<p class='keep'><strong>Hello</strong> &amp; 世界</p>\n")
        _ = try await web.callAsyncJavaScript("window.writing.command('undo', '')", contentWorld: .defaultClient)
        let undone = try await web.callAsyncJavaScript("return document.getElementById('source').value",
                                                      contentWorld: .defaultClient) as? String
        #expect(undone == original)
        // Loading formatted mode must not emit a normalized replacement to the binding.
        emitted = nil
        _ = try await web.callAsyncJavaScript("window.writing.set(value, false)",
                                             arguments: ["value": original], contentWorld: .defaultClient)
        #expect(emitted == nil)
    }
}
