import Foundation
import NaturalLanguage

/// Pure, unit-testable function for splitting text into TTS-friendly chunks.
public enum TextChunker {

    /// Splits long text at natural boundaries into chunks of at most `maxLength`.
    /// Short paragraphs stay intact for engines that can manage their own
    /// sentence prosody.
    public static func chunk(text: String, maxLength: Int = 250) -> [String] {
        makeChunks(text: text, maxLength: maxLength, separateSentences: false)
    }

    /// Gives an engine one complete sentence at a time, unless one sentence is
    /// itself too long. This preserves commas and terminal punctuation while
    /// keeping models configured for one sentence from truncating after a
    /// sentence boundary.
    public static func sentenceChunks(text: String, maxLength: Int = 250) -> [String] {
        makeChunks(text: text, maxLength: maxLength, separateSentences: true)
    }

    private static func makeChunks(
        text: String,
        maxLength: Int,
        separateSentences: Bool
    ) -> [String] {
        let maximumLength = max(1, maxLength)
        var chunks: [String] = []

        let paragraphs = text.components(separatedBy: .newlines)

        for paragraph in paragraphs {
            let paragraphText = paragraph.trimmingCharacters(in: .whitespaces)
            guard !paragraphText.isEmpty else { continue }

            if !separateSentences, paragraphText.count <= maximumLength {
                chunks.append(paragraphText)
                continue
            }

            let sentences = splitIntoSentences(paragraphText, maxLength: maximumLength)
            guard !sentences.isEmpty else { continue }

            if separateSentences {
                chunks.append(contentsOf: sentences)
            } else {
                appendPacked(sentences, to: &chunks, maxLength: maximumLength)
            }
        }

        return chunks
    }

    private static func appendPacked(
        _ sentences: [String],
        to chunks: inout [String],
        maxLength: Int
    ) {
        var currentChunk = ""

        for sentence in sentences {
            if currentChunk.isEmpty {
                currentChunk = sentence
            } else if currentChunk.count + sentence.count + 1 <= maxLength {
                currentChunk += " " + sentence
            } else {
                chunks.append(currentChunk)
                currentChunk = sentence
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
    }

    private static func splitIntoSentences(_ text: String, maxLength: Int) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespaces)
            guard !sentence.isEmpty else { return true }

            if sentence.count <= maxLength {
                sentences.append(sentence)
            } else {
                // Harder split for very long sentences
                sentences.append(contentsOf: splitByClauses(sentence, maxLength: maxLength))
            }
            return true
        }
        return sentences
    }

    private static func splitByClauses(_ text: String, maxLength: Int) -> [String] {
        // Simple greedy split on common pause markers
        let delimiters: Set<Character> = [";", ":", "—", ","]
        var pieces: [String] = []
        var currentPiece = ""

        var currentIndex = text.startIndex
        while currentIndex < text.endIndex {
            let char = text[currentIndex]
            currentPiece.append(char)

            if delimiters.contains(char) {
                // Avoid splitting a short sentence merely because it contains a
                // comma; only use a pause marker once it makes a useful chunk.
                if currentPiece.count >= (maxLength / 2) {
                    pieces.append(currentPiece.trimmingCharacters(in: .whitespaces))
                    currentPiece = ""
                }
            }
            currentIndex = text.index(after: currentIndex)
        }

        if !currentPiece.trimmingCharacters(in: .whitespaces).isEmpty {
            pieces.append(currentPiece.trimmingCharacters(in: .whitespaces))
        }

        // Further fallback if a piece is still > maxLength (rare, but possible)
        return pieces.flatMap { piece -> [String] in
            if piece.count <= maxLength {
                return [piece]
            } else {
                return splitByWords(piece, maxLength: maxLength)
            }
        }.filter { !$0.isEmpty }
    }

    private static func splitByWords(_ text: String, maxLength: Int) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var pieces: [String] = []
        var currentPiece = ""

        for word in words {
            if currentPiece.isEmpty {
                currentPiece = word
            } else if currentPiece.count + word.count + 1 <= maxLength {
                currentPiece += " " + word
            } else {
                pieces.append(currentPiece)
                currentPiece = word
            }
        }
        if !currentPiece.isEmpty {
            pieces.append(currentPiece)
        }
        return pieces
    }
}
