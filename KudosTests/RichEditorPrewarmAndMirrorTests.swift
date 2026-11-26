import Foundation
import SwiftUI
import Testing
@testable import Kudos

@MainActor
private final class FakePrewarmHost: RichEditorPrewarmableHost {
    private(set) var hasStartedLoading = false
    private(set) var startLoadCount = 0
    private(set) var appliedColors: [Color] = []
    private(set) var teardownCount = 0

    init(backgroundColor: Color) {
        appliedColors.append(backgroundColor)
    }

    func startLoadingIfNeeded() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        startLoadCount += 1
    }

    func applyNativeBackgroundColor(_ color: Color) {
        appliedColors.append(color)
    }

    func teardown() {
        teardownCount += 1
    }
}

@MainActor
struct RichEditorPrewarmPoolTests {
    @Test func prewarmPoolPreparesSingleHiddenHostReusesOnOpenAndDropsOnMemoryWarning() async {
        let clock = TestWritingClock()
        var createdHosts: [FakePrewarmHost] = []
        let pool = RichEditorPrewarmPool(
            clock: clock,
            observeMemoryWarnings: false,
            makeHost: { color in
                let host = FakePrewarmHost(backgroundColor: color)
                createdHosts.append(host)
                return host
            }
        )

        // Feature flag off: never allocates a hidden WebView.
        pool.prewarmIfNeeded(backgroundColor: .white, isFeatureEnabled: false)
        #expect(createdHosts.isEmpty)
        #expect(!pool.hasWarmHost)

        // Writing screen appears with feature flag on: creates ONE host and starts loading.
        pool.prewarmIfNeeded(backgroundColor: .white, isFeatureEnabled: true)
        #expect(createdHosts.count == 1)
        #expect(pool.hasWarmHost)
        #expect(createdHosts[0].hasStartedLoading)
        #expect(createdHosts[0].startLoadCount == 1)

        // Repeated Writing screen appearances reuse the same warm slot (updating theme color only).
        pool.prewarmIfNeeded(backgroundColor: .black, isFeatureEnabled: true)
        #expect(createdHosts.count == 1)
        #expect(createdHosts[0].appliedColors.last == .black)

        // Opening the editor claims the pre-warmed host with no extra load.
        let claimed = pool.takeOrCreateHost(backgroundColor: .white)
        #expect(claimed === createdHosts[0])
        #expect(pool.reuseCount == 1)
        #expect(!pool.hasWarmHost)
        #expect(createdHosts[0].startLoadCount == 1)

        // Re-warming creates a fresh slot, then W4 memory warning tears it down and starts 60 s cooldown.
        pool.prewarmIfNeeded(backgroundColor: .white, isFeatureEnabled: true)
        #expect(createdHosts.count == 2)
        #expect(pool.hasWarmHost)

        pool.handleMemoryWarning()
        #expect(!pool.hasWarmHost)
        #expect(createdHosts[1].teardownCount == 1)
        #expect(pool.memoryWarningDropCount == 1)
        #expect(pool.isWithinMemoryWarningCooldown)

        // Still blocked at 59 s; allowed again at 60 s.
        await clock.advance(by: .seconds(59))
        pool.prewarmIfNeeded(backgroundColor: .white, isFeatureEnabled: true)
        #expect(createdHosts.count == 2)

        await clock.advance(by: .seconds(1))
        #expect(!pool.isWithinMemoryWarningCooldown)
        pool.prewarmIfNeeded(backgroundColor: .white, isFeatureEnabled: true)
        #expect(createdHosts.count == 3)
    }

    @Test func draftSessionPreloadPolicyFollowsW2W3AndW4() async {
        // W2 gate checks every condition.
        #expect(DraftSession.shouldPreload(
            isRichEnabled: true, isRichAvailable: true, isInForeground: true,
            now: .seconds(100), lastMemoryWarningAt: nil,
            revision: 2, lastPreloadedRevision: 1,
            characterCount: 1000, maxCharacters: 510_000
        ))
        #expect(!DraftSession.shouldPreload(
            isRichEnabled: false, isRichAvailable: true, isInForeground: true,
            now: .seconds(100), lastMemoryWarningAt: nil,
            revision: 2, lastPreloadedRevision: 1,
            characterCount: 1000, maxCharacters: 510_000
        ))
        #expect(!DraftSession.shouldPreload(
            isRichEnabled: true, isRichAvailable: true, isInForeground: false,
            now: .seconds(100), lastMemoryWarningAt: nil,
            revision: 2, lastPreloadedRevision: 1,
            characterCount: 1000, maxCharacters: 510_000
        ))
        #expect(!DraftSession.shouldPreload(
            isRichEnabled: true, isRichAvailable: true, isInForeground: true,
            now: .seconds(120), lastMemoryWarningAt: .seconds(80),
            revision: 2, lastPreloadedRevision: 1,
            characterCount: 1000, maxCharacters: 510_000
        ))
        #expect(!DraftSession.shouldPreload(
            isRichEnabled: true, isRichAvailable: true, isInForeground: true,
            now: .seconds(100), lastMemoryWarningAt: nil,
            revision: 2, lastPreloadedRevision: 2,
            characterCount: 1000, maxCharacters: 510_000
        ))
        #expect(!DraftSession.shouldPreload(
            isRichEnabled: true, isRichAvailable: true, isInForeground: true,
            now: .seconds(100), lastMemoryWarningAt: nil,
            revision: 2, lastPreloadedRevision: 1,
            characterCount: 510_001, maxCharacters: 510_000
        ))

        // W3: superseded preload result is discarded; latest revision succeeds, then W4 background disposes it.
        let clock = TestWritingClock()
        let source = FakeSourceEditor(text: "<p>Initial</p>")
        let transport = FakeRichTransport()
        var firstLoadContinuation: CheckedContinuation<RichEditorLoadResult, Error>?
        var loadCallIndex = 0
        transport.loadHandler = { args in
            loadCallIndex += 1
            if loadCallIndex == 1 {
                return try await withCheckedThrowingContinuation { continuation in
                    firstLoadContinuation = continuation
                }
            }
            return RichEditorLoadResult(revision: args.revision, loss: .empty, timing: .zero)
        }

        let session = DraftSession(
            initialText: "<p>Initial</p>",
            fieldVariant: .content,
            source: source,
            clock: clock,
            richTransport: transport,
            isRichPreloadEnabled: true
        )

        source.simulateUserEdit("<p>First</p>")
        await clock.advance(by: .milliseconds(1500))
        for _ in 0..<4 { await Task.yield() }
        #expect(transport.loadCalls.count == 1)

        // Newer edit supersedes revision 1 before revision 1 finishes loading.
        source.simulateUserEdit("<p>Second</p>")
        await clock.advance(by: .milliseconds(1500))
        for _ in 0..<10 { await Task.yield() } // load, then the §7.11 check, before it counts as warm
        #expect(transport.loadCalls.count == 2)
        #expect(transport.verifySwitchCalls.last?.direction == .sourceToRich)
        #expect(session.preloadedRichRevision == 2)

        // Late revision 1 arrives — W3 must NOT overwrite revision 2.
        firstLoadContinuation?.resume(
            returning: RichEditorLoadResult(revision: 1, loss: .empty, timing: .zero)
        )
        for _ in 0..<4 { await Task.yield() }
        #expect(session.preloadedRichRevision == 2)

        // W4: backgrounding disposes the idle preload.
        session.handleSceneInactiveOrBackground()
        for _ in 0..<4 { await Task.yield() }
        #expect(session.preloadedRichRevision == nil)
        #expect(transport.disposeCount == 1)
    }
}

@MainActor
struct RichEditorTwoViewsMirrorTests {
    @Test func twoViewPolicyAllowsSideBySideOnlyOnRegularWidth() {
        #expect(RichEditorTwoViewPolicy.supportsSideBySide(isRegularWidth: true))
        #expect(!RichEditorTwoViewPolicy.supportsSideBySide(isRegularWidth: false))
    }

    @Test func htmlMirrorDocumentAppliesResetsAndSplicesAndComputesUTF16Offsets() throws {
        var mirror = HTMLMirrorDocument.seed(from: "placeholder", revision: 0)
        let block = { (html: String, sep: String) in RichEditorMirrorBlock(html: html, separatorAfter: sep) }

        // The page's reset replaces the placeholder seed entirely.
        let applied1 = mirror.apply(RichEditorMirrorBlocksEvent(
            revision: 1, totalBlocks: 3, activeBlockIndex: 0, reset: true, from: 0, to: 0,
            blocks: [block("<p>First ✨</p>", "\n\n"), block("<p>Second</p>", "\n"), block("<p>Third</p>", "")]
        ))
        #expect(applied1)
        #expect(mirror.fullHTML == "<p>First ✨</p>\n\n<p>Second</p>\n<p>Third</p>")

        // A splice replaces blocks [1, 2) with two blocks (Return pressed in the middle one).
        let applied2 = mirror.apply(RichEditorMirrorBlocksEvent(
            revision: 3, totalBlocks: 4, activeBlockIndex: 2, reset: false, from: 1, to: 2,
            blocks: [block("<p>Sec</p>", "\n"), block("<p>ond</p>", "\n")]
        ))
        #expect(applied2)
        #expect(mirror.blocks.map(\.html) == ["<p>First ✨</p>", "<p>Sec</p>", "<p>ond</p>", "<p>Third</p>"])
        #expect(mirror.blocks.map(\.index) == [0, 1, 2, 3])
        #expect(mirror.lastPatchedIndices == [1, 2])
        #expect(mirror.activeBlockIndex == 2)
        #expect(!mirror.needsReset)

        // Stale revisions are ignored; a splice that doesn't fit asks for a reset.
        let applied3 = mirror.apply(RichEditorMirrorBlocksEvent(
            revision: 2, totalBlocks: 1, activeBlockIndex: 0, reset: true, from: 0, to: 0, blocks: [block("x", "")]
        ))
        #expect(!applied3)
        #expect(mirror.blocks.count == 4)
        let applied4 = mirror.apply(RichEditorMirrorBlocksEvent(
            revision: 4, totalBlocks: 4, activeBlockIndex: 0, reset: false, from: 3, to: 9, blocks: []
        ))
        #expect(!applied4)
        #expect(mirror.needsReset)

        // UTF-16 offsets account for multi-byte characters and separators.
        let block0Len = ("<p>First ✨</p>\n\n" as NSString).length
        #expect(mirror.utf16Offset(blockIndex: 0) == 0)
        #expect(mirror.utf16Offset(blockIndex: 1) == block0Len)
    }

    @Test func draftSessionMirrorNeverUpdatesOnKeystrokesAndOnlyAppliesMirrorBlocks() async {
        let initial = "<p>Untouched top</p>\n<p>Middle</p>\n<p>Untouched bottom</p>"
        let source = FakeSourceEditor(text: initial)
        let transport = FakeRichTransport()
        let session = DraftSession(
            initialText: initial,
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        #expect(await session.switchToRich() == .switched)
        #expect(session.mirrorDocument.patchApplyCount == 0)
        let block = { (html: String, sep: String) in RichEditorMirrorBlock(html: html, separatorAfter: sep) }
        transport.emit(.mirrorBlocks(RichEditorMirrorBlocksEvent(
            revision: 0, totalBlocks: 3, activeBlockIndex: 0, reset: true, from: 0, to: 0,
            blocks: [block("<p>Untouched top</p>", "\n"), block("<p>Middle</p>", "\n"), block("<p>Untouched bottom</p>", "")]
        )))
        #expect(session.mirrorDocument.fullHTML == initial)

        // Rapid keystroke `edited` events must NEVER mutate the mirror (D8 / §7.10).
        transport.emit(.edited(revision: 1))
        transport.emit(.edited(revision: 2))
        transport.emit(.edited(revision: 3))
        #expect(session.mirrorDocument.patchApplyCount == 1)

        // Debounced `mirrorBlocks` splices only the block before the edit and the edited one.
        transport.emit(.mirrorBlocks(RichEditorMirrorBlocksEvent(
            revision: 3, totalBlocks: 3, activeBlockIndex: 1, reset: false, from: 0, to: 2,
            blocks: [block("<p>Untouched top</p>", "\n"), block("<p>Middle updated</p>", "\n")]
        )))
        #expect(session.mirrorDocument.patchApplyCount == 2)
        #expect(session.mirrorDocument.blocks.map(\.html) == ["<p>Untouched top</p>", "<p>Middle updated</p>", "<p>Untouched bottom</p>"])
    }

    @Test func tappingMirrorSwitchesToHTMLAndPlacesCaretAtTappedOffsetForUneditedAndEditedText() async {
        let initial = "<B>First</B>\n\n<p>Second</p>"
        let source = FakeSourceEditor(text: initial)
        let transport = FakeRichTransport()
        transport.storedCaretOffset = 0
        let session = DraftSession(
            initialText: initial,
            fieldVariant: .content,
            source: source,
            clock: TestWritingClock(),
            richTransport: transport
        )

        // Case 1: unedited Rich Text (R1) — tap block 1 in mirror restores source bytes verbatim & lands caret there.
        #expect(await session.switchToRich() == .switched)
        let tappedBlock1 = session.mirrorDocument.utf16Offset(blockIndex: 1)
        #expect(tappedBlock1 == ("<B>First</B>\n\n" as NSString).length)

        let uneditedOutcome = await session.switchToSourceFromMirrorTap(atUTF16Offset: tappedBlock1)
        #expect(uneditedOutcome == .switched)
        #expect(session.state == .sourceOwned)
        #expect(source.text == initial)
        #expect(source.caretOffsetUTF16 == tappedBlock1)
        #expect(source.focusCount == 1)

        // Case 2: edited Rich Text — tap block 1 switches, commits rich HTML, and places caret at tapped offset.
        #expect(await session.switchToRich() == .switched)
        transport.storedRevision = 1
        transport.storedHTML = "<p><b>First</b></p>\n\n<p>Second edited</p>"
        transport.storedCaretOffset = 3
        transport.storedWords = 3
        transport.emit(.edited(revision: 1))
        transport.emit(.mirrorBlocks(RichEditorMirrorBlocksEvent(
            revision: 1, totalBlocks: 2, activeBlockIndex: 1, reset: true, from: 0, to: 0,
            blocks: [
                RichEditorMirrorBlock(html: "<p><b>First</b></p>", separatorAfter: "\n\n"),
                RichEditorMirrorBlock(html: "<p>Second edited</p>", separatorAfter: ""),
            ]
        )))

        let editedTapOffset = session.mirrorDocument.utf16Offset(blockIndex: 1)
        let editedOutcome = await session.switchToSourceFromMirrorTap(atUTF16Offset: editedTapOffset)
        #expect(editedOutcome == .switched)
        #expect(session.state == .sourceOwned)
        #expect(source.text == "<p><b>First</b></p>\n\n<p>Second edited</p>")
        #expect(source.caretOffsetUTF16 == editedTapOffset)
        #expect(source.clearedUndoHistoryCount == 1)
        #expect(source.focusCount == 2)
    }
}
