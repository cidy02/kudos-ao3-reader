import SwiftUI
import Testing
import UIKit
@testable import Kudos

/// T-358: the editor's Preview and its recovery sheet with a chapter at AO3's 510,000-character
/// limit. Drawn whole, the first layout took 0.72 s (Preview) and 0.26 s (recovery copy) on the
/// Mac's simulator, several times that on an iPhone 11; lazy, 0.02 s and 0.03 s. Each test times
/// both in the same run and asks the editor's view to be at least three times faster than the
/// whole drawing, so the check holds on a busy machine.
@MainActor
struct WritingLargeChapterLayoutTests {
    static let chapter: String = {
        var html = ""
        var paragraph = 0
        while html.utf8.count < 510_000 {
            html += "<p>" + String(repeating: "the quiet letter waited by the window while rain fell ", count: 8)
                + "\(paragraph)</p>\n"
            paragraph += 1
        }
        return html
    }()

    private func firstLayout(_ view: some View) -> Duration {
        let host = UIHostingController(rootView: view)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        return ContinuousClock().measure { host.view.layoutIfNeeded() }
    }

    @Test func previewOfAFullChapter() throws {
        guard case let .rendered(document) = WritingBufferPreview.state(for: Self.chapter) else {
            Issue.record("the chapter did not parse")
            return
        }
        _ = firstLayout(Text("warm-up"))
        let whole = firstLayout(ScrollView { AO3RichTextView(document: document) }.environment(AppRouter()))
        let lazy = firstLayout(WritingRenderedPreview(document: document, fontSize: 17).environment(AppRouter()))
        print("T358 PREVIEW blocks=\(document.blocks.count) whole \(whole) lazy \(lazy)")
        #expect(lazy * 3 < whole, "the Preview lays out only what is on screen")
    }

    @Test func recoveryCopyOfAFullChapter() {
        _ = firstLayout(Text("warm-up"))
        let whole = firstLayout(
            ScrollView { Text(Self.chapter).font(.body.monospaced()).textSelection(.enabled) }
        )
        let lazy = firstLayout(WritingRecoveryCopyText(text: Self.chapter))
        print("T358 RECOVERY chars=\(Self.chapter.utf8.count) whole \(whole) lazy \(lazy)")
        #expect(lazy * 3 < whole, "the recovery copy lays out only what is on screen")
    }
}
