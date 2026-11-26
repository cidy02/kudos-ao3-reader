import Foundation
import Testing
@testable import Kudos

/// The Swift counter against goldens from otwarchive's own WordCounter (`lib/word_counter.rb` at 452391b6, run by
/// `editor-core/test/golden/generate/words.rb`). editor-core's JS counter is tested against the same file, so the two
/// can't drift apart. Inputs: the hand-written cases (`words-cases.json`) and the cleaning corpus (`corpus.json`).
@MainActor
struct AO3WordCounterGoldenTests {
    private struct Case: Decodable { let id: String; let input: String }
    private struct Cases: Decodable { let cases: [Case] }
    private struct Golden: Decodable { let words: [String: Count] }
    /// A count, or the error Ruby raised (Nokogiri's tree-depth limit: AO3 can't save those either).
    private enum Count: Decodable {
        case words(Int)
        case raised(String)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Int.self) { self = .words(n) } else { self = .raised(try c.decode(String.self)) }
        }
    }

    private static let golden = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("editor-core/test/golden")

    private static func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: golden.appendingPathComponent(name)))
    }

    /// Cases where SwiftSoup's tree is not Gumbo's: text the HTML5 parser puts in <head>, or keeps as raw text in the
    /// body, or inside <template>. AO3's cleaner removes all of these elements before a chapter is saved and counted,
    /// so they never reach the count of a posted chapter; the editor's Rich Text count (editor-core) matches here.
    private static let parserDifferences: Set<String> = []

    @Test func everyGoldenCaseCountsAsAO3CountsIt() throws {
        let words = try Self.load("words.golden.json", as: Golden.self).words
        var inputs = try Self.load("words-cases.json", as: Cases.self).cases
        inputs += try Self.load("corpus.json", as: Cases.self).cases
        var checked = 0
        var wrong: [String] = []
        for item in inputs {
            guard let golden = words[item.id] else {
                Issue.record("\(item.id) has no golden: run editor-core/test/golden/generate/words.rb")
                continue
            }
            guard case let .words(expected) = golden else { continue }
            let counted = AO3WordCounter.count(item.input)
            checked += 1
            if counted != expected, !Self.parserDifferences.contains(item.id) {
                wrong.append("\(item.id): AO3 \(expected), Swift \(counted)")
            }
        }
        #expect(checked > 2000)
        #expect(wrong.isEmpty, "\(wrong.count) differ:\n\(wrong.joined(separator: "\n"))")
    }
}
