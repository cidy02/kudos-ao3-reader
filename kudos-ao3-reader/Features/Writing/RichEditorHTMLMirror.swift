import Foundation
import SwiftUI

/// Side-by-side eligibility for §7.10 ("Two views at once").
/// Regular widths (open Duo, iPad, Mac) can show Rich Text beside a read-only
/// HTML mirror; phones keep one view at a time.
nonisolated enum RichEditorTwoViewPolicy {
    static func supportsSideBySide(isRegularWidth: Bool) -> Bool {
        isRegularWidth
    }
}

/// One top-level HTML block rendered in the §7.10 read-only mirror.
nonisolated struct HTMLMirrorBlock: Identifiable, Equatable, Hashable, Sendable {
    let index: Int
    var html: String
    var separatorAfter: String

    var id: Int { index }
}

/// Incremental top-level block store for the §7.10 read-only HTML mirror.
///
/// Updated exclusively from debounced `mirrorBlocks` events (never on the
/// keystroke path) so untouched blocks keep their exact source bytes (S16)
/// and tapping a block maps directly to its UTF-16 offset in HTML mode.
nonisolated struct HTMLMirrorDocument: Equatable, Sendable {
    private(set) var revision: Int = 0
    private(set) var blocks: [HTMLMirrorBlock] = []
    private(set) var activeBlockIndex: Int?
    /// Block indices mutated by the most recent applied `mirrorBlocks` event.
    private(set) var lastPatchedIndices: Set<Int> = []
    /// Total number of `mirrorBlocks` events applied since seeding.
    private(set) var patchApplyCount: Int = 0

    /// Seeds the mirror from the authoritative HTML when entering Rich Text.
    /// Splits on blank lines (`\n\n`) while preserving exact separators so
    /// `fullHTML` matches `html` verbatim.
    static func seed(from html: String, revision: Int = 0) -> HTMLMirrorDocument {
        let parsed = splitPreservingSeparators(html)
        return HTMLMirrorDocument(
            revision: revision,
            blocks: parsed,
            activeBlockIndex: parsed.isEmpty ? nil : 0,
            lastPatchedIndices: [],
            patchApplyCount: 0
        )
    }

    /// Whether the last event left the mirror out of step with the page (the native side asks for a reset).
    private(set) var needsReset = false

    /// Applies a `mirrorBlocks` event: a reset replaces every block, a splice replaces blocks `[from, to)`. Rejects
    /// stale revisions and splices that don't fit; a block count that disagrees with the page marks `needsReset`.
    @discardableResult
    mutating func apply(_ event: RichEditorMirrorBlocksEvent) -> Bool {
        guard event.revision >= revision else { return false }
        let incoming = event.blocks.map { HTMLMirrorBlock(index: 0, html: $0.html, separatorAfter: $0.separatorAfter) }
        var next = blocks
        let start: Int
        if event.reset {
            next = incoming
            start = 0
        } else {
            guard event.from >= 0, event.from <= event.to, event.to <= next.count else {
                needsReset = true
                return false
            }
            next.replaceSubrange(event.from..<event.to, with: incoming)
            start = event.from
        }
        for idx in next.indices { next[idx] = HTMLMirrorBlock(index: idx, html: next[idx].html, separatorAfter: next[idx].separatorAfter) }
        needsReset = next.count != event.totalBlocks
        blocks = next
        revision = event.revision
        if let active = event.activeBlockIndex, active >= 0, active < blocks.count {
            activeBlockIndex = active
        } else if blocks.isEmpty {
            activeBlockIndex = nil
        }
        lastPatchedIndices = Set(start..<(start + incoming.count))
        patchApplyCount += 1
        return true
    }

    /// Concatenated HTML across all blocks.
    var fullHTML: String {
        blocks.map { $0.html + $0.separatorAfter }.joined()
    }

    /// Computes the UTF-16 offset in `fullHTML` for `(blockIndex, localUTF16Offset)`
    /// so tapping into the mirror places the HTML caret at that block (§7.5, §7.10).
    func utf16Offset(blockIndex: Int, localUTF16Offset: Int = 0) -> Int {
        guard !blocks.isEmpty else { return 0 }
        let clampedBlock = min(max(blockIndex, 0), blocks.count - 1)
        var offset = 0
        for idx in 0..<clampedBlock {
            offset += blocks[idx].html.utf16.count + blocks[idx].separatorAfter.utf16.count
        }
        let localMax = blocks[clampedBlock].html.utf16.count
        return offset + min(max(localUTF16Offset, 0), localMax)
    }

    private static func splitPreservingSeparators(_ html: String) -> [HTMLMirrorBlock] {
        guard !html.isEmpty else {
            return [HTMLMirrorBlock(index: 0, html: "", separatorAfter: "")]
        }
        var result: [HTMLMirrorBlock] = []
        var cursor = html.startIndex
        var blockIndex = 0

        while cursor < html.endIndex {
            if let range = html.range(of: "\n\n", range: cursor..<html.endIndex) {
                var sepEnd = range.upperBound
                while sepEnd < html.endIndex, html[sepEnd] == "\n" {
                    sepEnd = html.index(after: sepEnd)
                }
                let slice = String(html[cursor..<range.lowerBound])
                let separator = String(html[range.lowerBound..<sepEnd])
                result.append(HTMLMirrorBlock(index: blockIndex, html: slice, separatorAfter: separator))
                blockIndex += 1
                cursor = sepEnd
            } else {
                let slice = String(html[cursor..<html.endIndex])
                result.append(HTMLMirrorBlock(index: blockIndex, html: slice, separatorAfter: ""))
                break
            }
        }
        return result
    }
}

/// Read-only HTML mirror displayed beside Rich Text on regular-width layouts
/// (open Duo, iPad, Mac; docs/WRITING_EDITOR_ARCHITECTURE.md §7.10).
///
/// Renders blocks lazily, highlights and scrolls to the block containing the
/// Rich Text caret, and switches ownership to HTML at the tapped block's offset.
struct RichEditorHTMLMirrorView: View {
    @Environment(ThemeManager.self) private var theme
    let document: HTMLMirrorDocument
    let fontSize: CGFloat
    let onTapOffset: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("HTML")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondaryInk)
                Spacer(minLength: 0)
                Text("Tap to edit")
                    .font(.caption2)
                    .foregroundStyle(.secondaryInk)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.appTheme.glassStroke(0.12))
                    .frame(height: 0.5)
                    .accessibilityHidden(true)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(document.blocks) { block in
                            let isActive = document.activeBlockIndex == block.index
                            Button {
                                onTapOffset(document.utf16Offset(blockIndex: block.index))
                            } label: {
                                Text(block.html.isEmpty ? " " : block.html)
                                    .font(.system(size: max(12, fontSize - 2), design: .monospaced))
                                    .foregroundStyle(theme.appTheme.textColor)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(
                                                isActive
                                                    ? theme.effectiveTint.opacity(
                                                        theme.appTheme.isDarkFamily ? 0.20 : 0.10
                                                    )
                                                    : Color.clear
                                            )
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(block.index)
                            .accessibilityLabel("HTML block \(block.index + 1)")
                            .accessibilityHint("Switches to HTML mode at this block")
                        }
                    }
                    .padding(10)
                }
                .onChange(of: document.activeBlockIndex) { _, nextIndex in
                    guard let nextIndex else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        proxy.scrollTo(nextIndex, anchor: .center)
                    }
                }
            }
        }
        .background(theme.appTheme.backgroundColor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Read-only HTML mirror")
    }
}
