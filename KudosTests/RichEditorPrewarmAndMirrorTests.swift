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
        for _ in 0..<4 { await Task.yield() }
        #expect(transport.loadCalls.count == 2)
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

    @Test func htmlMirrorDocumentUpdatesOnlyReportedBlocksAndComputesUTF16Offsets() throws {
        let initial = "<p>First ✨</p>\n\n<p>Second</p>\n\n<p>Third</p>"
        var mirror = HTMLMirrorDocument.seed(from: initial, revision: 0)
        #expect(mirror.blocks.count == 3)
        #expect(mirror.fullHTML == initial)

        // Patch only block 1; blocks 0 and 2 remain untouched verbatim.
        let event = RichEditorMirrorBlocksEvent(
            revision: 3,
            totalBlocks: 3,
            changes: [
                RichEditorMirrorBlockPatch(index: 1, html: "<p><em>Second edited</em></p>", separatorAfter: nil),
            ],
            activeBlockIndex: 1
        )
        let appliedEvent = mirror.apply(event)
        #expect(appliedEvent)
        #expect(mirror.lastPatchedIndices == [1])
        #expect(mirror.patchApplyCount == 1)
        #expect(mirror.activeBlockIndex == 1)
        #expect(mirror.blocks[0].html == "<p>First ✨</p>")
        #expect(mirror.blocks[1].html == "<p><em>Second edited</em></p>")
        #expect(mirror.blocks[2].html == "<p>Third</p>")
        #expect(mirror.fullHTML == "<p>First ✨</p>\n\n<p><em>Second edited</em></p>\n\n<p>Third</p>")

        // Stale revision is ignored.
        let stale = RichEditorMirrorBlocksEvent(
            revision: 2,
            totalBlocks: 1,
            changes: [RichEditorMirrorBlockPatch(index: 0, html: "<p>Stale</p>", separatorAfter: "")],
            activeBlockIndex: 0
        )
        let appliedStale = mirror.apply(stale)
        #expect(!appliedStale)
        #expect(mirror.blocks.count == 3)

        // UTF-16 offset accounts for multi-byte characters and separators.
        let block0Len = ("<p>First ✨</p>\n\n" as NSString).length
        #expect(mirror.utf16Offset(blockIndex: 0) == 0)
        #expect(mirror.utf16Offset(blockIndex: 1) == block0Len)

        // Event decoding matches documented JSON shape.
        let decoded = try RichEditorEvent.decode(from: [
            "type": "mirrorBlocks",
            "revision": 4,
            "totalBlocks": 2,
            "activeBlockIndex": 0,
            "changes": [
                ["index": 0, "html": "<p>Changed</p>", "separatorAfter": "\n\n"],
            ],
        ])
        #expect(decoded == .mirrorBlocks(RichEditorMirrorBlocksEvent(
            revision: 4,
            totalBlocks: 2,
            changes: [RichEditorMirrorBlockPatch(index: 0, html: "<p>Changed</p>", separatorAfter: "\n\n")],
            activeBlockIndex: 0
        )))
    }

    @Test func draftSessionMirrorNeverUpdatesOnKeystrokesAndOnlyAppliesMirrorBlocks() async {
        let initial = "<p>Untouched top</p>\n\n<p>Middle</p>\n\n<p>Untouched bottom</p>"
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
        #expect(session.mirrorDocument.blocks.count == 3)
        #expect(session.mirrorDocument.patchApplyCount == 0)

        // Rapid keystroke `edited` events must NEVER mutate the mirror (D8 / §7.10).
        transport.emit(.edited(revision: 1))
        transport.emit(.edited(revision: 2))
        transport.emit(.edited(revision: 3))
        #expect(session.mirrorDocument.patchApplyCount == 0)
        #expect(session.mirrorDocument.fullHTML == initial)

        // Debounced `mirrorBlocks` updates only block 1.
        transport.emit(.mirrorBlocks(RichEditorMirrorBlocksEvent(
            revision: 3,
            totalBlocks: 3,
            changes: [RichEditorMirrorBlockPatch(index: 1, html: "<p>Middle updated</p>", separatorAfter: nil)],
            activeBlockIndex: 1
        )))
        #expect(session.mirrorDocument.patchApplyCount == 1)
        #expect(session.mirrorDocument.lastPatchedIndices == [1])
        #expect(session.mirrorDocument.blocks[0].html == "<p>Untouched top</p>")
        #expect(session.mirrorDocument.blocks[1].html == "<p>Middle updated</p>")
        #expect(session.mirrorDocument.blocks[2].html == "<p>Untouched bottom</p>")
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
            revision: 1,
            totalBlocks: 2,
            changes: [
                RichEditorMirrorBlockPatch(index: 0, html: "<p><b>First</b></p>", separatorAfter: "\n\n"),
                RichEditorMirrorBlockPatch(index: 1, html: "<p>Second edited</p>", separatorAfter: ""),
            ],
            activeBlockIndex: 1
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
