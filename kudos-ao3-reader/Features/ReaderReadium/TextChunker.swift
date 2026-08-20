import Foundation

/// Pure, unit-testable function for splitting long text into TTS-friendly chunks.
public enum TextChunker {

    /// Splits long text at natural boundaries (sentence-ending punctuation, paragraph breaks, dialogue markers)
    /// into chunks of roughly 150-250 characters.
    public static func chunk(text: String, maxLength: Int = 250) -> [String] {
        var chunks: [String] = []

        let paragraphs = text.components(separatedBy: .newlines)

        for paragraph in paragraphs {
            let paragraphText = paragraph.trimmingCharacters(in: .whitespaces)
            guard !paragraphText.isEmpty else { continue }

            if paragraphText.count <= maxLength {
                chunks.append(paragraphText)
            } else {
                let sentences = splitIntoSentences(paragraphText, maxLength: maxLength)
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
        }

        return chunks
    }

    private static func splitIntoSentences(_ text: String, maxLength: Int) -> [String] {
        var sentences: [String] = []
        let range = text.startIndex ..< text.endIndex

        text.enumerateSubstrings(in: range, options: .bySentences) { substring, _, _, _ in
            guard let sentence = substring?.trimmingCharacters(in: .whitespaces), !sentence.isEmpty else { return }

            if sentence.count <= maxLength {
                sentences.append(sentence)
            } else {
                // Harder split for very long sentences
                sentences.append(contentsOf: splitByClauses(sentence, maxLength: maxLength))
            }
        }
        return sentences
    }

    private static func splitByClauses(_ text: String, maxLength: Int) -> [String] {
        // Simple greedy split on common pause markers
        let delimiters: Set<Character> = [";", ":", "—", ",", "”", "\""]
        var pieces: [String] = []
        var currentPiece = ""

        var currentIndex = text.startIndex
        while currentIndex < text.endIndex {
            let char = text[currentIndex]
            currentPiece.append(char)

            if delimiters.contains(char) {
                // Check if the current piece is long enough to be worth splitting
                // or if it's a quote, which is a good natural boundary
                if currentPiece.count >= (maxLength / 2) || char == "”" || char == "\"" {
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
        let words = text.split(separator: " ").map { String($0) }
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
