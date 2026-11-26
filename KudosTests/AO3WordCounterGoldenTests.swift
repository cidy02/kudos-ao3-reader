import Foundation
import Testing
@testable import Kudos

/// The Swift counter against goldens from otwarchive's own WordCounter (`lib/word_counter.rb` at 452391b6, run by
/// `editor-core/test/golden/generate/words.rb`). editor-core's JS counter is tested against the same file and matches
/// all of it, so the two can't drift apart.
@MainActor
struct AO3WordCounterGoldenTests {
    private struct Case: Decodable { let id: String; let input: String }
    private struct Cases: Decodable { let cases: [Case] }
    private struct Golden: Decodable { let words: [String: Count]; let stored: [String: Count] }
    private struct Cleaned: Decodable {
        struct Field: Decodable { let html: String? }
        let id: String
        let content: Field
    }
    private struct CleanedCases: Decodable { let cases: [Cleaned] }
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

    /// What AO3 shows: it sanitizes a field before saving it (`ApplicationController#sanitize_params`) and counts the
    /// stored text. Every corpus case's cleaned content (part 1's `sanitize.golden.json`) must count the same here.
    @Test func storedContentCountsAsAO3ShowsIt() throws {
        let stored = try Self.load("words.golden.json", as: Golden.self).stored
        let cleaned = try Self.load("sanitize.golden.json", as: CleanedCases.self).cases
        var checked = 0
        var wrong: [String] = []
        for item in cleaned {
            guard let html = item.content.html, case let .words(expected) = stored[item.id] else { continue }
            let counted = AO3WordCounter.count(html)
            checked += 1
            if counted != expected { wrong.append("\(item.id): AO3 \(expected), Swift \(counted)") }
        }
        #expect(checked > 1900)
        #expect(wrong.isEmpty, "\(wrong.count) differ:\n\(wrong.joined(separator: "\n"))")
    }

    /// Raw text, before AO3's cleaning: SwiftSoup's body-fragment tree is not Gumbo's for elements AO3's cleaner
    /// removes before it counts (head elements, raw-text and template contents, CDATA), so these differ on raw input
    /// and agree once cleaned (above). Everything else in the hand-written cases counts exactly as AO3 counts it.
    private static let rawOnlyDifferences: Set<String> = [
        "w-script-in-body", "w-style-in-body", "w-title-first", "w-noscript", "w-template", "w-textarea", "w-cdata",
        "w-doctype-html-body",
    ]

    @Test func handWrittenCasesCountAsAO3CountsThem() throws {
        let words = try Self.load("words.golden.json", as: Golden.self).words
        let cases = try Self.load("words-cases.json", as: Cases.self).cases
        var wrong: [String] = []
        for item in cases {
            guard case let .words(expected) = words[item.id] else {
                Issue.record("\(item.id) has no golden: run editor-core/test/golden/generate/words.rb")
                continue
            }
            let counted = AO3WordCounter.count(item.input)
            if counted != expected, !Self.rawOnlyDifferences.contains(item.id) {
                wrong.append("\(item.id): AO3 \(expected), Swift \(counted)")
            }
        }
        #expect(cases.count > 90)
        #expect(wrong.isEmpty, "\(wrong.count) differ:\n\(wrong.joined(separator: "\n"))")
    }
}
