#if os(iOS)
import Foundation
import ReadiumShared

/// Pause that should follow an utterance, chosen from EPUB structure rather
/// than whatever silence Kokoro emitted at the clip edge.
nonisolated public enum KokoroBoundary: Int, Sendable, Comparable {
    case none = 0
    case continuation = 1
    /// A `<br>` inside one `<p>`. Weaker than a paragraph and stronger than a
    /// mid-sentence packer split; `max` still promotes to `.paragraph` /
    /// `.scene` / `.chapter` when the lookahead asks for it. Raw values are
    /// in-memory only, so renumbering is safe.
    case line = 2
    case paragraph = 3
    case scene = 4
    case chapter = 5

    public static func < (lhs: KokoroBoundary, rhs: KokoroBoundary) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Read from `ReaderSpeechTuning` rather than hard-coded, so the developer
    /// panel changes real playback and not just the audition sample. Every
    /// value defaults to the constant it replaced, so an untouched install is
    /// byte-for-byte the same behaviour.
    public var pauseSeconds: Double {
        let tuning = ReaderSpeechTuning.current
        switch self {
        case .none: return 0
        case .continuation: return tuning.continuationPause
        case .line: return tuning.linePause
        case .paragraph: return tuning.paragraphPause
        case .scene: return tuning.scenePause
        case .chapter: return tuning.chapterPause
        }
    }
}

nonisolated struct KokoroSemanticBlock: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case heading
        case paragraph
        case dialogue
        case blockquote
        case sceneBreak
    }

    var kind: Kind
    var text: String
    var locator: Locator?
    var selector: String?
    /// True when the next unit shared this block's cssSelector — Readium's
    /// signal that a `<br>` split one `<p>`. The last line of that `<p>` is
    /// a normal paragraph end and keeps this false.
    var endsAtLineBreak: Bool = false
}

nonisolated enum KokoroSemanticDocument {
    static func blocks(from units: [TTSSpeechUnit]) -> [KokoroSemanticBlock] {
        var open: KokoroSemanticBlock?
        var result: [KokoroSemanticBlock] = []

        func flush(endsAtLineBreak: Bool = false) {
            guard var block = open else { return }
            block.text = KokoroSpeechNormalizer.normalize(block.text)
            block.endsAtLineBreak = endsAtLineBreak
            if !block.text.isEmpty || block.kind == .sceneBreak {
                result.append(block)
            }
            open = nil
        }

        // A note span runs from its heading to the end of the blockquote that
        // follows it. Measured across 12 works, 489 of 518 note headings are
        // followed immediately by a blockquote, so that is a precise and
        // self-bounding signal.
        //
        // The obvious alternative — suppress until the next heading — is
        // dangerous: in the same corpus the gap to the next heading has a
        // median of 38 blocks and over half never reach one at all, so it
        // would silently swallow chapters of narrative. The 29 headings
        // followed by a plain paragraph are left spoken on purpose; reading a
        // note that was meant to be skipped is a far better failure than
        // skipping a chapter that was meant to be read.
        let readsNotes = ReaderSpeechPreferences.readAuthorNotes
        var inSuppressedNote = false

        for unit in units {
            let trimmed = unit.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if KokoroBoilerplateFilter.isBoilerplate(trimmed) {
                inSuppressedNote = !readsNotes && KokoroBoilerplateFilter.isNoteLabel(trimmed)
                continue
            }
            let raw = KokoroBoilerplateFilter.sanitizingURLs(in: trimmed)
            let selector = unit.locator?.locations.cssSelector
            let kind = classify(text: raw, selector: selector)

            if inSuppressedNote {
                // Still inside the note's blockquote; anything else ends it.
                if kind == .blockquote { continue }
                inSuppressedNote = false
            }

            if kind == .sceneBreak {
                flush()
                result.append(KokoroSemanticBlock(
                    kind: .sceneBreak,
                    text: "",
                    locator: unit.locator,
                    selector: selector
                ))
                continue
            }

            if let current = open, isLineBreakSeam(current, kind: kind, selector: selector) {
                flush(endsAtLineBreak: true)
            } else if let current = open, canJoin(current, kind: kind) {
                open?.text = join(current.text, raw)
                // Track the selector of the unit just absorbed, not the one
                // the block opened with. A paragraph that does not end a
                // sentence joins into the *next* paragraph's first line, and
                // if the block kept its original selector the `<br>` seam
                // that follows inside that next paragraph would be compared
                // against the wrong element and silently missed.
                open?.selector = selector
                continue
            }

            flush()
            open = KokoroSemanticBlock(
                kind: kind,
                text: raw,
                locator: unit.locator,
                selector: selector
            )
        }
        flush()
        return result
    }

    private static func classify(text: String, selector: String?) -> KokoroSemanticBlock.Kind {
        if looksLikeSceneBreak(text: text, selector: selector) { return .sceneBreak }
        if looksLikeHeading(text: text, selector: selector) { return .heading }
        if let selector, selector.range(
            of: #"(^|[\s>+~])blockquote(\b|[:.\[])"#,
            options: .regularExpression
        ) != nil {
            return .blockquote
        }
        let normalized = KokoroSpeechNormalizer.normalize(text)
        if normalized.first == KokoroSpeechNormalizer.openQuote { return .dialogue }
        return .paragraph
    }

    private static func looksLikeHeading(text: String, selector: String?) -> Bool {
        if let selector, selector.range(
            of: #"(^|[\s>+~])h[1-6](\b|[:.\[])"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        let trimmed = KokoroSpeechNormalizer.normalize(text)
        guard trimmed.count <= 80 else { return false }
        return trimmed.range(
            of: #"^(Chapter|Epilogue|Prologue|Preface|Afterword|Interlude|Part)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func looksLikeSceneBreak(text: String, selector: String?) -> Bool {
        if let selector, selector.range(
            of: #"(^|[\s>+~])hr(\b|[:.\[])"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        let compact = text.filter { !$0.isWhitespace }
        guard (3...12).contains(compact.count) else { return false }
        return compact.allSatisfy { "*•·●◦▪-–—_=~#".contains($0) }
    }

    private static func canJoin(
        _ open: KokoroSemanticBlock,
        kind: KokoroSemanticBlock.Kind
    ) -> Bool {
        if open.kind == .heading || open.kind == .sceneBreak { return false }
        if kind == .heading || kind == .sceneBreak { return false }
        if endsUtterance(open.text) { return false }
        // Dialogue is a different delivery from narration: the voice pack
        // indexes style by phoneme count, so a short quoted line glued into
        // surrounding prose is voiced as long-form. hexgrad improved Kokoro's
        // short utterances; use that rather than merging it away.
        // Adjacent dialogue still joins — a back-and-forth that arrived as
        // fragments of one paragraph must not become one inference per line.
        // `<br>` seams are a different boundary (shared cssSelector) and
        // still flush before this runs, so quoted chat-fic lines keep the
        // audible `.line` pause.
        // Toggleable so the barrier can be A/B'd by ear against merging.
        let barrierEnabled = ReaderSpeechTuning.current.dialogueBarrier
        let exactlyOneIsDialogue = (open.kind == .dialogue) != (kind == .dialogue)
        if barrierEnabled, exactlyOneIsDialogue { return false }
        return isBody(open.kind) && isBody(kind)
    }

    /// Units split by a `<br>` share a cssSelector (they came from one
    /// `<p>`); units from adjacent paragraphs do not. Matching selectors
    /// used to force a merge before `endsUtterance` ran, which is why chat
    /// fic, verse, and transcripts were read as running prose. Headings and
    /// scene breaks still never participate — they rejected that shortcut
    /// too, and a heading that started joining would swallow the title.
    private static func isLineBreakSeam(
        _ open: KokoroSemanticBlock,
        kind: KokoroSemanticBlock.Kind,
        selector: String?
    ) -> Bool {
        if open.kind == .heading || open.kind == .sceneBreak { return false }
        if kind == .heading || kind == .sceneBreak { return false }
        guard ReaderSpeechTuning.current.lineBreakPauses else { return false }
        guard let left = open.selector, let right = selector else { return false }
        return left == right
    }

    private static func isBody(_ kind: KokoroSemanticBlock.Kind) -> Bool {
        switch kind {
        case .paragraph, .dialogue, .blockquote: true
        case .heading, .sceneBreak: false
        }
    }

    /// Internal rather than private so the Apple chunker can classify its own
    /// boundaries with the same rules instead of duplicating them.
    static func endsUtterance(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        if ")]}\"".contains(last) {
            let inner = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
            return inner.last.map { ".!?…".contains($0) } ?? false
        }
        return ".!?…".contains(last)
    }

    private static func join(_ left: String, _ right: String) -> String {
        let piece = right.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = left.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return piece }
        if needsSpace(before: piece, in: text) {
            text.append(" ")
        }
        text.append(piece)
        return text
    }

    private static func needsSpace(before piece: String, in text: String) -> Bool {
        guard let last = text.last, let first = piece.first else { return false }
        if last.isWhitespace || first.isWhitespace { return false }
        switch first {
        case ".", ",", ";", ":", "!", "?", "…", ")", "]", "}":
            return false
        default:
            return true
        }
    }
}
#endif
