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
        case .kokoro: "Kokoro Offline"
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
    @MainActor
    public static func packedChunks(
        from units: [TTSSpeechUnit],
        maxLength: Int = 250
    ) -> [TTSSpeechUnit] {
        chunks(from: units, maxLength: maxLength, using: TextChunker.chunk)
    }

    /// Gives the Kokoro engine complete sentence units and carries their
    /// individual source locations into the playback callbacks.
    @MainActor
    public static func sentenceChunks(
        from units: [TTSSpeechUnit],
        maxLength: Int = 250
    ) -> [TTSSpeechUnit] {
        chunks(from: units, maxLength: maxLength, using: TextChunker.sentenceChunks)
    }

    @MainActor
    private static func chunks(
        from units: [TTSSpeechUnit],
        maxLength: Int,
        using chunker: (String, Int) -> [String]
    ) -> [TTSSpeechUnit] {
        units.flatMap { unit in
            let chunkTexts = chunker(unit.text, maxLength)
            guard let locator = unit.locator,
                  let source = locator.text.highlight,
                  !source.isEmpty
            else {
                return chunkTexts.map { TTSSpeechUnit(text: $0, locator: unit.locator) }
            }

            var searchStart = source.startIndex
            var hasExactRange = true
            return chunkTexts.map { text in
                guard hasExactRange,
                      let range = whitespaceInsensitiveRange(
                          matchingWhitespaceIn: text,
                          source: source,
                          startingAt: searchStart
                      )
                else {
                    hasExactRange = false
                    // TextualContentElement.text can differ slightly from
                    // locator text after EPUB whitespace normalization. Keep
                    // the element locator instead of inventing a bad range.
                    return TTSSpeechUnit(text: text, locator: locator)
                }
                searchStart = range.upperBound
                return TTSSpeechUnit(
                    text: text,
                    locator: locator.copy(text: { $0 = $0[range] })
                )
            }
        }
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
