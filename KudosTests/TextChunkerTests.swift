import XCTest
@testable import Kudos

final class TextChunkerTests: XCTestCase {
    
    func testEmptyInput() {
        let chunks = TextChunker.chunk(text: "")
        XCTAssertTrue(chunks.isEmpty)
    }
    
    func testSingleShortSentence() {
        let text = "This is a short sentence."
        let chunks = TextChunker.chunk(text: text)
        XCTAssertEqual(chunks, [text])
    }
    
    func testParagraphBoundary() {
        let text = "First paragraph.\n\nSecond paragraph."
        let chunks = TextChunker.chunk(text: text)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0], "First paragraph.")
        XCTAssertEqual(chunks[1], "Second paragraph.")
    }
    
    func testLongParagraphSplitsAtSentence() {
        let sentence1 = String(repeating: "A", count: 150) + "."
        let sentence2 = String(repeating: "B", count: 150) + "."
        let text = sentence1 + " " + sentence2
        
        let chunks = TextChunker.chunk(text: text, maxLength: 250)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0], sentence1)
        XCTAssertEqual(chunks[1], sentence2)
    }
    
    func testVeryLongSentenceSplitsAtComma() {
        let clause1 = String(repeating: "A", count: 150)
        let clause2 = String(repeating: "B", count: 150)
        let text = clause1 + ", " + clause2 + "."
        
        let chunks = TextChunker.chunk(text: text, maxLength: 250)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0], clause1 + ",")
        XCTAssertEqual(chunks[1], clause2 + ".")
    }
    
    func testExtremelyLongSentenceWithoutPunctuationSplitsByWords() {
        let word = "word "
        // Need enough words to exceed maxLength
        var text = ""
        for _ in 0..<60 {
            text += word
        }
        text = text.trimmingCharacters(in: .whitespaces)
        
        let chunks = TextChunker.chunk(text: text, maxLength: 250)
        XCTAssertTrue(chunks.count > 1)
        for chunk in chunks {
            XCTAssertTrue(chunk.count <= 250)
        }
    }
}
