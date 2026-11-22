import Foundation

/// Pure rules for Insights D7 (time on each chapter): the JSON the sitting stores, the skim
/// judgement, and whether a sitting stopped at the end of a chapter.
///
/// Nothing here reads a clock, a store or the reader. `ReadingLogService` gathers seconds in
/// memory from locator changes and calls `skimmedChapters` once, when it saves the sitting.
nonisolated enum ChapterTiming {
    /// A chapter shorter than this is never called skimmed: there is too little text to tell.
    static let skimMinimumWords = 300
    /// Skimmed = read in under this share of the time the reader's median pace needs.
    static let skimTimeShare = 0.5
    /// Chapters of pace history needed before anything is called skimmed.
    static let minimumPaceHistory = 20
    /// A sitting that stops this far through a chapter "ended on a chapter".
    static let chapterEndFraction = 0.95
    /// "Peeked at the Ending": the last chapter was opened before this share of the work.
    static let peekProgressLimit = 0.5

    /// One chapter read whole in an earlier sitting: its words and the seconds it took.
    struct PaceSample: Equatable, Sendable {
        var words: Int
        var seconds: Double
    }

    /// Words per second of each usable sample (a sample needs words and time), median of the
    /// lot, or nil until `minimumPaceHistory` samples exist.
    static func medianWordsPerSecond(_ samples: [PaceSample]) -> Double? {
        let rates = samples.compactMap { sample -> Double? in
            guard sample.words > 0, sample.seconds > 0 else { return nil }
            return Double(sample.words) / sample.seconds
        }.sorted()
        guard rates.count >= minimumPaceHistory else { return nil }
        let middle = rates.count / 2
        return rates.count.isMultiple(of: 2) ? (rates[middle - 1] + rates[middle]) / 2 : rates[middle]
    }

    /// The spine indexes of chapters this sitting read whole that were skimmed: 300 words or
    /// more, read in under half the time the median pace needs. `nil` pace (not enough
    /// history) judges nothing, so a new reader's chapters are never called skimmed.
    static func skimmedChapters(
        seconds: [Int: Double],
        words: [Int: Int],
        medianWordsPerSecond pace: Double?
    ) -> [Int] {
        guard let pace, pace > 0 else { return [] }
        return words.keys.sorted().filter { spine in
            guard let chapterWords = words[spine], chapterWords >= skimMinimumWords else { return false }
            let needed = Double(chapterWords) / pace
            return (seconds[spine] ?? 0) < needed * skimTimeShare
        }
    }

    /// The pace samples one earlier sitting contributes: chapters it read whole, minus the
    /// ones it was judged to have skimmed (a skimmed chapter would make the pace look fast).
    static func paceSamples(
        seconds: [Int: Double],
        words: [Int: Int],
        skimmed: [Int]
    ) -> [PaceSample] {
        let skippedSet = Set(skimmed)
        return words.keys.sorted().compactMap { spine in
            guard !skippedSet.contains(spine), let chapterWords = words[spine],
                  let spent = seconds[spine] else { return nil }
            return PaceSample(words: chapterWords, seconds: spent)
        }
    }

    /// Whether the sitting stopped at a chapter's end, from the fraction through that chapter.
    static func endedAtChapterEnd(chapterFraction: Double?) -> Bool? {
        chapterFraction.map { $0 >= chapterEndFraction }
    }

    /// Opening the last chapter from somewhere before the halfway mark, by a jump rather than
    /// by reading on. `fromStoryChapter` is the chapter the reader was in (1-based);
    /// being in chapter k means at least (k - 1) / total of the work is behind them.
    static func isPeek(
        toStoryChapter: Int,
        fromStoryChapter: Int?,
        totalStoryChapters: Int,
        startProgress: Double?
    ) -> Bool {
        guard totalStoryChapters >= 3, toStoryChapter == totalStoryChapters,
              let from = fromStoryChapter, from > 0, from != toStoryChapter - 1,
              from < toStoryChapter
        else { return false }
        let behind = Double(from - 1) / Double(totalStoryChapters)
        return max(behind, startProgress ?? 0) < peekProgressLimit
    }

    // MARK: JSON

    static func encode(_ value: [Int: Double]) -> String? {
        guard !value.isEmpty else { return nil }
        let keyed = Dictionary(uniqueKeysWithValues: value.map { (String($0.key), $0.value) })
        return json(keyed)
    }

    static func encode(_ value: [Int: Int]) -> String? {
        guard !value.isEmpty else { return nil }
        let keyed = Dictionary(uniqueKeysWithValues: value.map { (String($0.key), $0.value) })
        return json(keyed)
    }

    /// An empty list encodes as `[]` ("judged, nothing skimmed"), never as nil.
    static func encode(list value: [Int]) -> String? {
        json(value.sorted())
    }

    /// Ranges an honest sitting can produce. Anything outside is damage from an archive and is
    /// dropped on decode, so no stored number can overflow the arithmetic in the figures.
    static let maximumSpineIndex = 100_000
    static let maximumChapterSeconds = 7 * 24 * 3_600.0
    static let maximumChapterWords = 10_000_000

    static func decodeDoubles(_ json: String?) -> [Int: Double] {
        guard let decoded: [String: Double] = decode(json) else { return [:] }
        return rekey(decoded) { $0.isFinite && $0 >= 0 && $0 <= maximumChapterSeconds }
    }

    static func decodeInts(_ json: String?) -> [Int: Int] {
        guard let decoded: [String: Int] = decode(json) else { return [:] }
        return rekey(decoded) { $0 >= 0 && $0 <= maximumChapterWords }
    }

    /// Distinct, in-range spine indexes, sorted: a repeated index must not count twice.
    static func decodeList(_ json: String?) -> [Int] {
        let decoded: [Int] = decode(json) ?? []
        return Array(Set(decoded.filter { $0 >= 0 && $0 <= maximumSpineIndex })).sorted()
    }

    /// Whether a transported string is well-formed JSON of the right shape *and* in range;
    /// restore keeps only strings that pass, so a damaged value never lands on a row.
    static func isValidSeconds(_ json: String?) -> Bool {
        guard let json, !json.isEmpty, let raw: [String: Double] = decode(json) else { return false }
        return rekey(raw) { $0.isFinite && $0 >= 0 && $0 <= maximumChapterSeconds }.count == raw.count
    }

    static func isValidWords(_ json: String?) -> Bool {
        guard let json, !json.isEmpty, let raw: [String: Int] = decode(json) else { return false }
        return rekey(raw) { $0 >= 0 && $0 <= maximumChapterWords }.count == raw.count
    }

    static func isValidList(_ json: String?) -> Bool {
        guard let json, !json.isEmpty, let raw: [Int] = decode(json) else { return false }
        return raw.allSatisfy { $0 >= 0 && $0 <= maximumSpineIndex }
    }

    private static func rekey<Value>(
        _ decoded: [String: Value],
        keep: (Value) -> Bool
    ) -> [Int: Value] {
        var result: [Int: Value] = [:]
        for (key, value) in decoded {
            if let index = Int(key), index >= 0, index <= maximumSpineIndex, keep(value) { result[index] = value }
        }
        return result
    }

    private static func json<Value: Encodable>(_ value: Value) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func decode<Value: Decodable>(_ json: String?) -> Value? {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
