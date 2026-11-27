import Foundation
import Testing
@testable import Kudos

/// The page calls for the keys bar's slide and dictation (T-576e) and a beta's suggestion (T-576f).
@MainActor
struct DraftSessionPhoneAndBetaTests {
    private func session(rich: Bool, text: String = "<p>Ines counted the ribs &amp; the hull twice.</p>")
        async -> (DraftSession, FakeRichTransport, FakeSourceEditor) {
        let source = FakeSourceEditor(text: text)
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: text,
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )
        if rich { #expect(await session.switchToRich() == .switched) }
        return (session, transport, source)
    }

    @Test func richCommandsReachThePageAndReportWhetherTheyApplied() async {
        let (session, transport, _) = await session(rich: true)
        let moved = await session.moveByWord(-2, extend: true)
        #expect(moved)
        #expect(transport.commandCalls.last == RichEditorCommandArgs(
            name: "moveWord", attrs: ["by": .int(-2), "extend": .bool(true)]
        ))
        let inserted = await session.insertDictatedPhrase("as if listening")
        #expect(inserted)
        #expect(transport.commandCalls.last == .insertPhrase("as if listening"))
        let broke = await session.insertParagraphBreak()
        #expect(broke)
        #expect(transport.commandCalls.last?.name == "newParagraph")
        transport.commandHandler = { _ in RichEditorCommandResult(applied: false) }
        let refused = await session.replaceText(in: RichEditorTextRange(from: 3, to: 7), with: "Marta")
        #expect(!refused)
        #expect(transport.commandCalls.last == .replaceText(RichEditorTextRange(from: 3, to: 7), with: "Marta"))
    }

    @Test func htmlModeHasNoSlideOrDictation() async {
        let (session, transport, _) = await session(rich: false)
        let moved = await session.moveByWord(1, extend: false)
        let inserted = await session.insertDictatedPhrase("hello")
        #expect(!moved)
        #expect(!inserted)
        #expect(transport.commandCalls.isEmpty)
    }

    @Test func htmlModeReplacesTextInPlaceEscapedAndOnlyInOneRun() async throws {
        let html = "<p>Ines counted the ribs &amp; the hull twice.</p>"
        let (session, _, source) = await session(rich: false, text: html)
        let current = await session.currentHTML()
        #expect(current == html, "HTML mode's own text is what offsets index into")
        let twice = (html as NSString).range(of: "twice")
        let replaced = await session.replaceText(
            in: RichEditorTextRange(from: twice.location, to: NSMaxRange(twice)), with: "3 < 4 & more"
        )
        #expect(replaced)
        #expect(source.text == "<p>Ines counted the ribs &amp; the hull 3 &lt; 4 &amp; more.</p>")
        #expect(source.canUndo)
    }

    @Test func aRangeOutsideOneRunOfTextIsRefused() {
        let html = "<p>The ribs &amp; the <em>hull</em>.</p>"
        let ns = html as NSString
        func range(_ needle: String, trim: Int = 0) -> RichEditorTextRange {
            let r = ns.range(of: needle)
            return RichEditorTextRange(from: r.location + trim, to: NSMaxRange(r))
        }
        #expect(DraftSession.textRunRange(range("ribs"), in: html) != nil)
        #expect(DraftSession.textRunRange(range("&amp;"), in: html) != nil, "a whole reference is fine")
        #expect(DraftSession.textRunRange(range("&amp;", trim: 1), in: html) == nil, "starts inside a reference")
        #expect(DraftSession.textRunRange(range("the <em>hull"), in: html) == nil, "crosses a tag")
        #expect(DraftSession.textRunRange(range("em"), in: html) == nil, "inside a tag")
        #expect(DraftSession.textRunRange(RichEditorTextRange(from: 5, to: 2), in: html) == nil)
        #expect(DraftSession.textRunRange(RichEditorTextRange(from: 0, to: ns.length + 1), in: html) == nil)
        #expect(DraftSession.escapedText("a<b>&c") == "a&lt;b&gt;&amp;c")
    }
}
