import Foundation
import ReadiumNavigator
import ReadiumShared

/// Which concrete `TTSService` implementation `ReaderSpeechController` should
/// bind. Persisted manual choices use `rawValue`; an empty or unknown value
/// means Automatic. Re-evaluate on every new playback so a finished download
/// becomes available without relaunching the reader.
enum ReaderTTSEngineKind: String, CaseIterable {
    case system
    case kokoro

    var displayName: String {
        switch self {
        case .system: "Apple"
        case .kokoro: "Kokoro (Neural Engine)"
        }
    }

    static func preferred(modelDownloaded: Bool) -> ReaderTTSEngineKind {
        modelDownloaded ? .kokoro : .system
    }

    /// Resolves a persisted manual choice to a safe engine. A requested Kokoro
    /// pack is never treated as available until its files are actually present.
    static func effective(
        requestedRawValue: String,
        modelDownloaded: Bool
    ) -> ReaderTTSEngineKind {
        guard let requested = ReaderTTSEngineKind(rawValue: requestedRawValue) else {
            return preferred(modelDownloaded: modelDownloaded)
        }

        switch requested {
        case .system:
            return .system
        case .kokoro:
            return modelDownloaded ? .kokoro : .system
        }
    }
}

public enum TTSServiceStatus: Equatable {
    case unavailable
    case stopped
    case playing
    case paused
}

/// A piece of source text paired with its Readium location. Engines can split
/// these units for synthesis while preserving an exact range for the reader's
/// transient "currently reading" decoration.
public struct TTSSpeechUnit: Hashable, Sendable {
    public let text: String
    public let locator: Locator?

    public init(text: String, locator: Locator? = nil) {
        self.text = text
        self.locator = locator
    }

    /// Keeps the system engine's existing paragraph-oriented chunking while
    /// retaining a precise source range whenever the generated text occurs in
    /// the element's Readium locator.
    ///
    /// Units split by a `<br>` share a `cssSelector` (they came from one
    /// `<p>`); units from adjacent paragraphs do not. Apple cannot insert
    /// silence inside an `AVSpeechUtterance`, so each seam is its own
    /// utterance and `postUtteranceDelay` (0.22 s, matching Kokoro's
    /// `.line`) carries the pause. `sentenceChunks` groups the same way for
    /// Sherpa, so all three engines agree about where a line ends.
    @MainActor
    public static func packedChunks(
        from units: [TTSSpeechUnit],
        maxLength: Int = 250
    ) -> [TTSSpeechUnit] {
        groupsSeparatedByLineBreakSeams(units).flatMap { group in
            packAdjacent(
                splitIntoContextualSentences(from: group, maxLength: maxLength),
                maxLength: maxLength
            )
        }
    }

    /// Gives Kokoro complete sentences, including those Readium split across
    /// `<br>` / adjacent block elements. G2P is per-word; an isolated fragment
    /// like "read" is pronounced as a citation form instead of the verb in
    /// "began to read the letter".
    @MainActor
    public static func sentenceChunks(
        from units: [TTSSpeechUnit],
        maxLength: Int = 250
    ) -> [TTSSpeechUnit] {
        // Same `<br>` grouping the Apple path uses. Sherpa is the only caller,
        // and without this the iOS 26 engine read chat fic, epistolary works
        // and verse as running prose while Core ML and Apple both broke the
        // lines — three engines disagreeing about the same chapter is worse
        // than any one of them being wrong.
        //
        // Sherpa generates one chunk per call and plays them in sequence, so a
        // split is audible on its own without a pause parameter to thread
        // through.
        groupsSeparatedByLineBreakSeams(units).flatMap { group in
            splitIntoContextualSentences(from: group, maxLength: maxLength)
        }
    }

    /// Semantic + phoneme-aware utterances for Neural Engine Kokoro. Apple
    /// TTS still uses `packedChunks`; this path is Kokoro-only.
    @MainActor
    public static func kokoroUtterances(from units: [TTSSpeechUnit]) -> [KokoroUtterance] {
        KokoroUtterancePacker.pack(units: units)
    }

    @MainActor
    private static func splitIntoContextualSentences(
        from units: [TTSSpeechUnit],
        maxLength: Int
    ) -> [TTSSpeechUnit] {
        let joined = concatenateForSentenceContext(units)
        guard !joined.text.isEmpty else { return [] }

        let sentences = TextChunker.sentenceChunks(text: joined.text, maxLength: maxLength)
        var searchStart = joined.text.startIndex
        var highlightSearchStart: [Int: String.Index] = [:]
        return sentences.map { sentence in
            let range = whitespaceInsensitiveRange(
                matchingWhitespaceIn: sentence,
                source: joined.text,
                startingAt: searchStart
            ) ?? joined.text.range(of: sentence, range: searchStart ..< joined.text.endIndex)
            if let range {
                searchStart = range.upperBound
                return TTSSpeechUnit(
                    text: sentence,
                    locator: locator(
                        covering: range,
                        in: joined,
                        highlightSearchStart: &highlightSearchStart
                    )
                )
            }
            // Fall back to the span we are *currently* inside, not
            // `spans.first` — that sent the reader's highlight back to the top
            // of the chapter whenever a sentence failed to match.
            return TTSSpeechUnit(
                text: sentence,
                locator: span(containing: searchStart, in: joined)?.locator
            )
        }
    }

    /// The span owning `index`, for the no-match fallback. Spans are built in
    /// document order, so the last one starting at or before `index` contains it.
    private static func span(
        containing index: String.Index,
        in joined: JoinedSpeechText
    ) -> (range: Range<String.Index>, locator: Locator?)? {
        joined.spans.last { $0.range.lowerBound <= index } ?? joined.spans.first
    }

    @MainActor
    private static func packAdjacent(
        _ sentences: [TTSSpeechUnit],
        maxLength: Int
    ) -> [TTSSpeechUnit] {
        let maximumLength = max(1, maxLength)
        var packed: [TTSSpeechUnit] = []
        var currentText = ""
        var currentLocator: Locator?

        for sentence in sentences {
            if currentText.isEmpty {
                currentText = sentence.text
                currentLocator = sentence.locator
            } else if currentText.count + 1 + sentence.text.count <= maximumLength {
                currentText += " " + sentence.text
            } else {
                packed.append(TTSSpeechUnit(text: currentText, locator: currentLocator))
                currentText = sentence.text
                currentLocator = sentence.locator
            }
        }
        if !currentText.isEmpty {
            packed.append(TTSSpeechUnit(text: currentText, locator: currentLocator))
        }
        return packed
    }

    private struct JoinedSpeechText {
        let text: String
        let spans: [(range: Range<String.Index>, locator: Locator?)]
    }

    /// Units split by a `<br>` share a cssSelector; adjacent `<p>`s do not.
    /// Same discriminator as `KokoroSemanticDocument.isLineBreakSeam`. A
    /// `nil` selector never matches — that would make the seam vacuous.
    /// Selector is taken from the unit just absorbed, not the one the run
    /// opened with, so a cross-paragraph join cannot hide the `<br>` inside
    /// the next paragraph.
    private static func groupsSeparatedByLineBreakSeams(
        _ units: [TTSSpeechUnit]
    ) -> [[TTSSpeechUnit]] {
        var groups: [[TTSSpeechUnit]] = []
        var current: [TTSSpeechUnit] = []
        var lastSelector: String?

        for unit in units {
            let piece = unit.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }

            let selector = unit.locator?.locations.cssSelector
            if let lastSelector, let selector, lastSelector == selector, !current.isEmpty {
                groups.append(current)
                current = [unit]
            } else {
                current.append(unit)
            }
            lastSelector = selector
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    /// Space-joins Readium content elements so a sentence broken across
    /// adjacent blocks (or a split inline run) is one G2P input. No extra
    /// space before attaching punctuation. Callers that must honour a
    /// `<br>` seam (shared cssSelector) partition first; see `packedChunks`.
    private static func concatenateForSentenceContext(_ units: [TTSSpeechUnit]) -> JoinedSpeechText {
        var text = ""
        var spans: [(range: Range<String.Index>, locator: Locator?)] = []

        for unit in units {
            let piece = unit.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }

            if !text.isEmpty, needsJoinSpace(before: piece, in: text) {
                text.append(" ")
            }
            let start = text.endIndex
            text.append(piece)
            spans.append((start ..< text.endIndex, unit.locator))
        }
        return JoinedSpeechText(text: text, spans: spans)
    }

    private static func needsJoinSpace(before piece: String, in text: String) -> Bool {
        guard let last = text.last, let first = piece.first else { return false }
        if last.isWhitespace || first.isWhitespace { return false }
        switch first {
        case ".", ",", ";", ":", "!", "?", "…", ")", "]", "}":
            return false
        default:
            return true
        }
    }

    @MainActor
    private static func locator(
        covering range: Range<String.Index>,
        in joined: JoinedSpeechText,
        highlightSearchStart: inout [Int: String.Index]
    ) -> Locator? {
        guard let spanIndex = joined.spans.firstIndex(where: { $0.range.overlaps(range) }) else {
            return nil
        }
        // Spans are in document order, so everything overlapping `range` is
        // contiguous from `spanIndex`. A full `filter` rescanned every span in
        // the chapter for every sentence in it.
        let overlapCount = joined.spans[spanIndex...]
            .prefix { $0.range.overlaps(range) }
            .count
        let first = joined.spans[spanIndex]
        guard overlapCount == 1, let locator = first.locator else {
            return first.locator?.copy(text: {
                $0 = Locator.Text(highlight: String(joined.text[range]))
            })
        }

        guard let source = locator.text.highlight, !source.isEmpty else {
            return locator
        }
        let spoken = String(joined.text[range])
        let start = highlightSearchStart[spanIndex] ?? source.startIndex
        if let sliced = whitespaceInsensitiveRange(
            matchingWhitespaceIn: spoken,
            source: source,
            startingAt: start
        ) {
            highlightSearchStart[spanIndex] = sliced.upperBound
            return locator.copy(text: { $0 = $0[sliced] })
        }
        return locator
    }

    /// Resolves an AVSpeechSynthesizer word/phrase range back into this unit's
    /// raw Readium locator quote. If normalization makes an exact alignment
    /// impossible, the full unit remains the safe visual fallback.
    @MainActor
    public func locator(
        forSpokenRange range: Range<String.Index>,
        in spokenText: String
    ) -> Locator? {
        guard let locator,
              let source = locator.text.highlight,
              !source.isEmpty
        else {
            return locator
        }

        let prefix = String(spokenText[..<range.lowerBound])
        let start: String.Index
        if prefix.isEmpty {
            start = Self.firstNonWhitespaceIndex(in: source, startingAt: source.startIndex)
        } else if let prefixRange = Self.anchoredWhitespaceInsensitiveRange(
            matchingWhitespaceIn: prefix,
            source: source,
            startingAt: source.startIndex
        ) {
            start = prefixRange.upperBound
        } else {
            return locator
        }

        guard let sourceRange = Self.matchingRange(
            of: String(spokenText[range]),
            in: source,
            startingAt: start
        ) else {
            return locator
        }
        return locator.copy(text: { $0 = $0[sourceRange] })
    }

    /// Finds `text` in an XHTML locator quote while treating every contiguous
    /// whitespace run as equivalent. Readium normalizes spoken text but keeps
    /// its locator quote verbatim, including indentation around inline tags.
    @MainActor
    private static func whitespaceInsensitiveRange(
        matchingWhitespaceIn text: String,
        source: String,
        startingAt start: String.Index
    ) -> Range<String.Index>? {
        var candidate = start
        while candidate < source.endIndex {
            if let range = matchingRange(of: text, in: source, startingAt: candidate) {
                return range
            }
            candidate = source.index(after: candidate)
        }
        return nil
    }

    /// Matches from the only valid source position. This is deliberately
    /// stricter than `whitespaceInsensitiveRange`: if speech cleanup changed a
    /// non-whitespace character (for example a soft hyphen), callers must use
    /// their full-unit fallback instead of re-aligning at a repeated phrase.
    @MainActor
    private static func anchoredWhitespaceInsensitiveRange(
        matchingWhitespaceIn text: String,
        source: String,
        startingAt start: String.Index
    ) -> Range<String.Index>? {
        let sourceStart = text.first?.isWhitespace == true
            ? start
            : firstNonWhitespaceIndex(in: source, startingAt: start)
        return matchingRange(of: text, in: source, startingAt: sourceStart)
    }

    @MainActor
    private static func firstNonWhitespaceIndex(
        in source: String,
        startingAt start: String.Index
    ) -> String.Index {
        var index = start
        while index < source.endIndex, source[index].isWhitespace {
            index = source.index(after: index)
        }
        return index
    }

    @MainActor
    private static func matchingRange(
        of text: String,
        in source: String,
        startingAt start: String.Index
    ) -> Range<String.Index>? {
        var textIndex = text.startIndex
        var sourceIndex = start

        while textIndex < text.endIndex {
            guard sourceIndex < source.endIndex else { return nil }

            if text[textIndex].isWhitespace {
                guard source[sourceIndex].isWhitespace else { return nil }
                while textIndex < text.endIndex, text[textIndex].isWhitespace {
                    textIndex = text.index(after: textIndex)
                }
                while sourceIndex < source.endIndex, source[sourceIndex].isWhitespace {
                    sourceIndex = source.index(after: sourceIndex)
                }
            } else {
                guard text[textIndex] == source[sourceIndex] else { return nil }
                textIndex = text.index(after: textIndex)
                sourceIndex = source.index(after: sourceIndex)
            }
        }

        return start ..< sourceIndex
    }
}

/// The public surface of a TTS service that matches the shape expected by ReaderSpeechController.
/// The controller can swap out the Readium synthesizer for an implementation of this protocol.
public protocol TTSService: AnyObject {
    /// The current state of playback.
    var status: TTSServiceStatus { get }

    /// The sentence currently being spoken.
    var spokenText: String { get }

    /// 0...1 instantaneous energy from the current word being spoken (for equalizer).
    var speechEnergy: Double { get }

    /// Random seed representing the current fragment.
    var speechEnergySeed: Double { get }

    /// Voices available from this engine.
    var availableVoices: [TTSVoice] { get }

    /// Callback when the engine's status changes.
    var onStatusChange: ((TTSServiceStatus) -> Void)? { get set }

    /// Callback when the spoken text changes.
    var onSpokenTextChange: ((String) -> Void)? { get set }

    /// Callback when speech energy changes (pulsed per fragment).
    var onSpeechEnergyPulse: ((Double, Double) -> Void)? { get set }

    /// Per-band energy for the equalizer. Kokoro measures it from its own PCM;
    /// Apple infers it from the spelling, because its samples are never ours.
    /// See `SpeechSpectrum`.
    var onSpeechSpectrum: ((SpeechSpectrum) -> Void)? { get set }

    /// Callback for page syncing.
    var onAdvance: ((Locator) -> Void)? { get set }

    /// Callback when a locator range becomes audible. Unlike `onAdvance`,
    /// this must not drive reader navigation for every Apple word callback.
    var onSpokenRange: ((Locator) -> Void)? { get set }

    /// Starts speaking locator-bearing source units. An engine may chunk a unit
    /// for synthesis, but must report the matching unit locator through
    /// `onAdvance` when it begins.
    func speak(units: [TTSSpeechUnit]) async throws

    /// Pauses playback.
    func pause()

    /// Resumes playback.
    func resume()

    /// Stops playback and clears queues.
    func stop()

    /// Updates configuration.
    func setVoice(id: String)
    func setRate(_ rate: Float)
    func setPitch(_ pitch: Float)
}
