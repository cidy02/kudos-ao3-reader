import Foundation
import NaturalLanguage
import ReadiumShared

/// One Kokoro inference: packed semantic text plus the pause that should
/// follow it after the engine's own edge silence is stripped.
nonisolated public struct KokoroUtterance: Equatable, Sendable {
    public var text: String
    public var locator: Locator?
    public var pauseAfter: KokoroBoundary
}

nonisolated enum KokoroUtterancePacker {
    static func pack(
        units: [TTSSpeechUnit],
        estimator: KokoroPhonemeEstimator = KokoroPhonemeEstimator()
    ) -> [KokoroUtterance] {
        let blocks = KokoroSemanticDocument.blocks(from: units)
        var utterances: [KokoroUtterance] = []

        for (index, block) in blocks.enumerated() {
            if block.kind == .sceneBreak {
                if var last = utterances.last {
                    last.pauseAfter = max(last.pauseAfter, .scene)
                    utterances[utterances.count - 1] = last
                }
                continue
            }

            let pause: KokoroBoundary
            if block.kind == .heading {
                pause = .chapter
            } else {
                let next = blocks.dropFirst(index + 1).first { $0.kind != .sceneBreak }
                if next == nil {
                    pause = .paragraph
                } else if next?.kind == .heading {
                    pause = .chapter
                } else {
                    pause = .paragraph
                }
            }

            let pieces = packBlock(block, estimator: estimator)
            guard !pieces.isEmpty else { continue }
            for pieceIndex in pieces.indices {
                let isLast = pieceIndex == pieces.count - 1
                utterances.append(KokoroUtterance(
                    text: pieces[pieceIndex],
                    locator: block.locator,
                    pauseAfter: isLast ? pause : .continuation
                ))
            }
        }

        if let last = blocks.last, last.kind == .sceneBreak, var tail = utterances.last {
            tail.pauseAfter = max(tail.pauseAfter, .scene)
            utterances[utterances.count - 1] = tail
        }

        return utterances.filter { !$0.text.isEmpty }
    }

    /// Spoken text in document order, for reconstruction tests.
    static func reconstructedText(from utterances: [KokoroUtterance]) -> String {
        utterances.map(\.text).joined(separator: " ")
    }

    private static func packBlock(
        _ block: KokoroSemanticBlock,
        estimator: KokoroPhonemeEstimator
    ) -> [String] {
        let text = KokoroSpeechNormalizer.normalize(block.text)
        guard !text.isEmpty else { return [] }

        let sentences = completeSentences(text).flatMap { sentence in
            splitOnlyOverBudget(sentence, estimator: estimator)
        }
        let merged = mergeShort(sentences, estimator: estimator)
        return packWholeSentences(merged, estimator: estimator)
    }

    /// NLTokenizer sentences only. No character-count clause split — a long
    /// complete sentence stays one unit unless it cannot fit the model.
    static func completeSentences(in text: String) -> [String] {
        completeSentences(text)
    }

    private static func completeSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        return sentences.isEmpty ? [text] : sentences
    }

    /// Split a *single* sentence only when it would overflow the split
    /// budget. Prefer `;` `:` `—`, then comma, then words. Never used to
    /// chase the 175 grouping target.
    ///
    /// The budget is `splitThreshold` (400), not the 510 model cap: Kokoro
    /// rushes before it throws, so the cap is far too late to start cutting.
    private static func splitOnlyOverBudget(
        _ text: String,
        estimator: KokoroPhonemeEstimator
    ) -> [String] {
        if estimator.estimatePhonemeLength(text) <= KokoroPhonemeBudget.splitThreshold {
            return [text]
        }
        for delimiters in [Character(";") as Character, ":", "—"] {
            let parts = splitKeepingDelimiter(text, delimiters: [delimiters], estimator: estimator)
            if parts.count > 1 { return parts.flatMap { splitOnlyOverBudget($0, estimator: estimator) } }
        }
        let commaParts = splitKeepingDelimiter(text, delimiters: [","], estimator: estimator)
        if commaParts.count > 1 {
            return commaParts.flatMap { splitOnlyOverBudget($0, estimator: estimator) }
        }
        return splitByWordsUnderBudget(text, estimator: estimator)
    }

    private static func splitKeepingDelimiter(
        _ text: String,
        delimiters: [Character],
        estimator: KokoroPhonemeEstimator
    ) -> [String] {
        var pieces: [String] = []
        var current = ""
        var inQuote = false
        for ch in text {
            current.append(ch)
            if ch == "\"" { inQuote.toggle() }
            if !inQuote, delimiters.contains(ch),
               estimator.estimatePhonemeLength(current) >= KokoroPhonemeBudget.splitThreshold / 2
            {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { pieces.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces.count > 1 ? pieces : [text]
    }

    private static func splitByWordsUnderBudget(
        _ text: String,
        estimator: KokoroPhonemeEstimator
    ) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count > 1 else { return [text] }
        var pieces: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if !current.isEmpty,
               estimator.estimatePhonemeLength(candidate) > KokoroPhonemeBudget.splitThreshold
            {
                pieces.append(current)
                current = word
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    private static func mergeShort(
        _ sentences: [String],
        estimator: KokoroPhonemeEstimator
    ) -> [String] {
        var merged: [String] = []
        var index = 0
        while index < sentences.count {
            var current = sentences[index]
            var estimate = estimator.estimatePhonemeLength(current)
            index += 1
            while estimate < KokoroPhonemeBudget.shortFragment, index < sentences.count {
                let next = sentences[index]
                let combined = current + " " + next
                let combinedEstimate = estimator.estimatePhonemeLength(combined)
                if combinedEstimate > KokoroPhonemeBudget.preferredMax { break }
                current = combined
                estimate = combinedEstimate
                index += 1
            }
            merged.append(current)
        }
        return merged
    }

    /// Pack whole sentences together up to `preferredMax`. A sentence longer
    /// than that still goes out as one inference.
    private static func packWholeSentences(
        _ sentences: [String],
        estimator: KokoroPhonemeEstimator
    ) -> [String] {
        var groups: [[String]] = []
        var current: [String] = []
        var currentEstimate = 0

        for sentence in sentences {
            let estimate = estimator.estimatePhonemeLength(sentence)
            if current.isEmpty {
                current = [sentence]
                currentEstimate = estimate
            } else if currentEstimate + estimate <= KokoroPhonemeBudget.preferredMax {
                current.append(sentence)
                currentEstimate += estimate
            } else {
                groups.append(current)
                current = [sentence]
                currentEstimate = estimate
            }
        }
        if !current.isEmpty { groups.append(current) }

        if groups.count >= 2,
           let last = groups.last,
           estimator.estimatePhonemeLength(last.joined(separator: " ")) < KokoroPhonemeBudget.preferredMin,
           groups[groups.count - 2].count >= 2
        {
            var previous = groups[groups.count - 2]
            let stolen = previous.removeLast()
            groups[groups.count - 2] = previous
            groups[groups.count - 1] = [stolen] + last
            if groups[groups.count - 2].isEmpty {
                groups.remove(at: groups.count - 2)
            }
        }

        return groups
            .filter { !$0.isEmpty }
            .map { $0.joined(separator: " ") }
    }
}
