#if os(iOS)
import Foundation
import Testing
@testable import Kudos

/// Diagnostic, not a gate. Runs the real packer over real works and reports
/// what the pipeline actually does to them.
///
/// Skipped unless a corpus is provided, so it costs nothing in normal runs:
///
///     TEST_RUNNER_KOKORO_CORPUS_DIR=/path/to/corpus xcodebuild test \
///       -only-testing:KudosTests/KokoroCorpusDiagnosticTests
///
/// The corpus directory holds one `.tsv` per work, each line `tag<TAB>text`
/// in spine order (`Scripts/epub-to-corpus.py` produces them). **Point it at
/// several fandoms and authors** — style varies enormously between them, and
/// a single work only characterises its own author. Quirk-typing, romaji and
/// honorifics, texting formats, epistolary works with URLs, and heavy
/// ALL-CAPS emphasis all stress different parts of the pipeline, and none of
/// them show up in a work that happens not to use them.
@Suite("Kokoro corpus diagnostic")
struct KokoroCorpusDiagnosticTests {
    private static var corpusDirectory: String {
        let env = ProcessInfo.processInfo.environment
        return env["TEST_RUNNER_KOKORO_CORPUS_DIR"] ?? env["KOKORO_CORPUS_DIR"] ?? ""
    }

    private struct Report {
        var name = ""
        var blocks = 0
        var utterances = 0
        var sizes: [Int] = []
        var pauses: [KokoroBoundary: Int] = [:]
        var capsCandidates: Set<String> = []
        var straightQuotes = 0
        var curlyQuotes = 0
    }

    @Test func reportPackingDistribution() throws {
        let dir = Self.corpusDirectory
        try #require(!dir.isEmpty, "set TEST_RUNNER_KOKORO_CORPUS_DIR to run this")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir)
            .filter { $0.hasSuffix(".tsv") }
            .sorted()
        try #require(!files.isEmpty, "no .tsv corpora in \(dir)")

        var all = Report(name: "ALL WORKS")
        var out = ""
        for file in files {
            let report = try measure(
                path: (dir as NSString).appendingPathComponent(file),
                name: file
            )
            out += Self.render(report)
            all.blocks += report.blocks
            all.utterances += report.utterances
            all.sizes += report.sizes
            all.straightQuotes += report.straightQuotes
            all.curlyQuotes += report.curlyQuotes
            all.capsCandidates.formUnion(report.capsCandidates)
            for (k, v) in report.pauses { all.pauses[k, default: 0] += v }
        }
        // Per-work `sizes` arrive sorted; concatenating them leaves the
        // aggregate only piecewise-sorted, which made its percentiles nonsense
        // (p25 above the median). Sort once here.
        all.sizes.sort()
        if files.count > 1 { out += Self.render(all) }
        // Test stdout goes to the simulator console, not xcodebuild's — write
        // the report next to the corpus so it is actually readable.
        let reportPath = (dir as NSString).appendingPathComponent("REPORT.txt")
        try out.write(toFile: reportPath, atomically: true, encoding: .utf8)
        #expect(all.utterances > 0)
    }

    private func measure(path: String, name: String) throws -> Report {
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        var report = Report(name: name)

        let units: [TTSSpeechUnit] = raw.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let text = String(parts[1])
            report.straightQuotes += text.filter { $0 == "\"" }.count
            report.curlyQuotes += text.filter { $0 == "\u{201C}" || $0 == "\u{201D}" }.count
            for word in text.split(whereSeparator: { !$0.isLetter }) where
                (2 ... 5).contains(word.count)
                && word.allSatisfy({ $0.isASCII && $0.isUppercase })
            {
                report.capsCandidates.insert(String(word))
            }
            return TTSSpeechUnit(text: text, locator: nil)
        }
        report.blocks = units.count

        let utterances = KokoroUtterancePacker.pack(units: units)
        let estimator = KokoroPhonemeEstimator()
        report.utterances = utterances.count
        report.sizes = utterances.map { estimator.estimatePhonemeLength($0.text) }.sorted()
        for utterance in utterances { report.pauses[utterance.pauseAfter, default: 0] += 1 }
        return report
    }

    private static func render(_ r: Report) -> String {
        let s = r.sizes
        func pct(_ p: Double) -> Int {
            s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * p))]
        }
        func share(_ n: Int) -> String {
            String(format: "%.1f%%", 100 * Double(n) / Double(max(s.count, 1)))
        }
        let short = s.filter { $0 < KokoroPhonemeBudget.preferredMin }.count
        let long = s.filter { $0 > KokoroPhonemeBudget.preferredMax }.count
        let rushing = s.filter { $0 > 400 }.count
        let throwing = s.filter { $0 > KokoroPhonemeBudget.modelLimit }.count
        return """

        ===== \(r.name) =====
        blocks -> utterances : \(r.blocks) -> \(r.utterances)
        est. IPA length      : min=\(s.first ?? 0) p25=\(pct(0.25)) med=\(pct(0.5)) p75=\(pct(0.75)) p95=\(pct(0.95)) max=\(s.last ?? 0)
        below preferredMin \(KokoroPhonemeBudget.preferredMin)  : \(short) (\(share(short)))
        above preferredMax \(KokoroPhonemeBudget.preferredMax)  : \(long) (\(share(long)))
        above 400 (rushing)  : \(rushing) (\(share(rushing)))
        above 510 (throws)   : \(throwing) (\(share(throwing)))
        pauses               : cont=\(r.pauses[.continuation] ?? 0) para=\(r.pauses[.paragraph] ?? 0) scene=\(r.pauses[.scene] ?? 0) chapter=\(r.pauses[.chapter] ?? 0) none=\(r.pauses[.none] ?? 0)
        quotes               : straight=\(r.straightQuotes) curly=\(r.curlyQuotes)
        all-caps 2-5 tokens  : \(r.capsCandidates.count) distinct
        """
    }
}
#endif
