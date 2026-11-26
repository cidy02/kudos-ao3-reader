import Foundation
import Testing
@testable import Kudos

/// `DraftSession.apply` is the one door from the native chrome (Format panel, keys bar, edit menu, key commands) to
/// the editor that owns the text (docs §7.2 `command`, U1).
@MainActor
struct DraftSessionFormatCommandTests {
    private func richSession() async -> (DraftSession, FakeRichTransport, FakeSourceEditor) {
        let source = FakeSourceEditor(text: "<p>Hello</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Hello</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )
        #expect(await session.switchToRich() == .switched)
        return (session, transport, source)
    }

    private func settle() async {
        for _ in 0..<6 { await Task.yield() }
    }

    @Test func formatCommandsReachThePageOnlyWhileRichTextOwnsTheText() async {
        let (session, transport, _) = await richSession()
        session.apply(.toggleMark(.bold))
        session.apply(.setBlock(.foldOut))
        session.apply(.insertImage(FormatImageSpec(address: "https://example.com/a.png", description: "A", width: 10)))
        session.apply(.openTableInHTML) // native only: nothing reaches the page
        await settle()
        #expect(transport.commandCalls == [
            RichEditorCommandArgs(name: "toggleMark", attrs: ["mark": .string("bold")]),
            RichEditorCommandArgs(name: "setBlock", attrs: ["block": .string("foldOut")]),
            RichEditorCommandArgs(name: "insertImage", attrs: [
                "address": .string("https://example.com/a.png"), "description": .string("A"), "width": .int(10),
            ]),
        ])
    }

    @Test func hostCommandsMapToTheKeysBarPageCommands() async {
        let (session, transport, _) = await richSession()
        session.apply(.insertEmDash)
        session.apply(.insertQuotationMarks)
        session.apply(.moveCaret(.left))
        session.apply(.openFormatPanel) // native UI: nothing reaches the page
        await settle()
        #expect(transport.commandCalls.map(\.name) == ["insertText", "insertQuotes", "moveCaret"])
        #expect(transport.commandCalls.first?.attrs == ["text": .string("—")])
    }

    @Test func undoAndRedoGoToTheOwnersHistory() async {
        let source = FakeSourceEditor(text: "<p>x</p>")
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>x</p>",
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )
        session.apply(.undo)
        session.apply(.toggleMark(.italic)) // HTML mode owns the text: formatting doesn't go to the page
        await settle()
        #expect(source.undoCount == 1)
        #expect(transport.commandCalls.isEmpty)
        #expect(await session.switchToRich() == .switched)
        session.apply(.redo)
        await settle()
        #expect(transport.commandCalls.map(\.name) == ["redo"])
    }

    @Test func eachPasteIsNumberedSoTheReportShowsOncePerPaste() async {
        let (session, transport, _) = await richSession()
        #expect(session.lastPaste == nil)
        let loss = RichEditorLossReport(dropped: .init(elements: ["font": 1]))
        transport.emit(.paste(RichEditorPasteEvent(loss: loss, words: 12, kind: "html")))
        #expect(session.lastPaste?.sequence == 1)
        #expect(session.lastPaste?.event.words == 12)
        transport.emit(.paste(RichEditorPasteEvent(loss: .empty, words: 3, kind: "text")))
        #expect(session.lastPaste?.sequence == 2)
        #expect(session.lastPaste?.event.kind == "text")
    }

    @Test func showingTheMirrorTellsThePageOnce() async {
        let (session, transport, _) = await richSession()
        session.setMirrorVisible(true)
        session.setMirrorVisible(true)
        session.setMirrorVisible(false)
        await settle()
        #expect(transport.setMirrorCalls == [true, false])
    }

    @Test func formatStateFollowsThePagesToolbarState() async {
        let (session, transport, _) = await richSession()
        transport.emit(.toolbarState(RichEditorToolbarState(
            marks: ["bold", "smaller"], block: "numberedList", align: "justify", dir: "rightToLeft",
            canUndo: true, canRedo: false, undoTitle: "Bold", inLink: true, linkURL: "https://x.org/"
        )))
        let state = session.formatState
        #expect(state.activeMarks == [.bold, .smaller])
        #expect(state.block == .numberedList)
        #expect(state.alignment == .justify)
        #expect(state.direction == .rightToLeft)
        #expect(state.isInLink)
        #expect(state.currentLinkURL == "https://x.org/")
        #expect(session.toolbarState.undoMenuTitle == "Undo Bold")
    }
}

/// Notes in the text, TKs and names (T-576d): the page's events land in the session, and the session's calls reach it.
@MainActor
struct DraftSessionAnnotationTests {
    private func richSession() async -> (DraftSession, FakeRichTransport) {
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: "<p>Marta</p>",
            fieldVariant: .content,
            source: FakeSourceEditor(text: "<p>Marta</p>"),
            clock: TestWritingClock(),
            richTransport: transport
        )
        #expect(await session.switchToRich() == .switched)
        return (session, transport)
    }

    @Test func tapsTKsAndTheWordAtTheCaretAreRecorded() async throws {
        let (session, transport) = await richSession()
        transport.emit(.annotationTapped(id: "n1"))
        transport.emit(.annotationTapped(id: "n1"))
        #expect(session.lastAnnotationTap == DraftAnnotationTap(sequence: 2, id: "n1"))
        transport.emit(.tkTyped(RichEditorTextRange(from: 3, to: 5)))
        #expect(session.lastTypedTK?.range == RichEditorTextRange(from: 3, to: 5))
        transport.emit(.wordAtCaret(prefix: "Ma"))
        #expect(session.wordAtCaret == "Ma")
        transport.emit(.wordAtCaret(prefix: nil))
        #expect(session.wordAtCaret == nil)
        let decoded = try RichEditorEvent.decode(from: ["type": "wordAtCaret", "prefix": NSNull()])
        #expect(decoded == .wordAtCaret(prefix: nil))
    }

    @Test func annotationsAndWordCompletionReachThePage() async {
        let (session, transport) = await richSession()
        let placed = await session.setAnnotations([RichEditorAnnotationItem(id: "n1", kind: "note", from: 3, to: 8)])
        #expect(placed.map(\.found) == [true])
        session.completeWord("Marta’s")
        for _ in 0..<6 { await Task.yield() }
        #expect(transport.commandCalls.last == RichEditorCommandArgs(name: "completeWord", attrs: ["text": .string("Marta’s")]))
        #expect(await session.selectionForAnchoring() == nil, "the fake page has no selection")
    }
}
