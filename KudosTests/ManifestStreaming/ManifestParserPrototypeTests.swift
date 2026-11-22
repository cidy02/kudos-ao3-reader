import Foundation
import Testing
import XCTest
@testable import Kudos

/// Differential corpus (regular gate, small): the prototype scanner + record-at-a-time typed reader must reach the
/// same outcome class and, when accepted, equal typed values as today's `JSONSerialization` + `decodeManifest` route.
/// Known disagreements are listed in `knownDisagreements` (each is a P2 contract decision, not a pass).
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ManifestParserDifferentialTests {
    static func corpus() throws -> [(String, Data)] {
        var out: [(String, Data)] = []
        let defaults = T567Store.defaults()
        func gen(_ axis: ManifestScaleAxis, _ mib: Double) throws -> Data {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("corpus-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: url) }
            _ = try ManifestFixtureGenerator.write(try ManifestFixtureGenerator.calibrated(axis: axis, mib: mib), to: url, defaults: defaults)
            return try Data(contentsOf: url)
        }
        // Existing fixtures.
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/cross-platform")
        let android = fixtures.appendingPathComponent("android-sync-folder/KudosLibrary/manifest.json")
        let androidData = try Data(contentsOf: android)
        out.append(("fixture:android-sync-folder", androidData))
        if let zip = try? Data(contentsOf: fixtures.appendingPathComponent("android-export.kudosbackup")),
           let manifest = (try? MiniZip(data: zip, limits: .backup))?.data(named: "manifest.json") {
            out.append(("fixture:android-export", manifest))
        }
        let base = try gen(.works, 0.2)
        out.append(("gen:works", base))
        out.append(("gen:sessions", try gen(.sessions, 0.2)))
        out.append(("gen:opaque", try gen(.opaque, 0.3)))
        guard var obj = try JSONSerialization.jsonObject(with: base) as? [String: Any] else { return out }
        func variant(_ name: String, _ edit: (inout [String: Any]) -> Void) throws {
            var o = obj; edit(&o)
            out.append((name, try JSONSerialization.data(withJSONObject: o)))
        }
        func text(_ s: String) -> Data { Data(s.utf8) }
        let s = String(decoding: base, as: UTF8.self)
        // Root metadata after the arrays is the generator's own layout; these vary the rest.
        try variant("version-99") { $0["version"] = 99 }
        try variant("version-missing") { $0["version"] = nil }
        try variant("version-null") { $0["version"] = NSNull() }
        try variant("version-string") { $0["version"] = "8" }
        try variant("exportedAt-bad") { $0["exportedAt"] = "yesterday" }
        try variant("works-missing") { $0["works"] = nil }
        try variant("works-null") { $0["works"] = NSNull() }
        try variant("works-object") { $0["works"] = [String: Any]() }
        try variant("works-bad-element") { var w = $0["works"] as! [Any]; w[3] = 5; $0["works"] = w }
        try variant("works-empty") { $0["works"] = [Any]() }
        for key in ["collections", "readingQueues", "annotations", "savedSearches"] {
            try variant("\(key)-missing") { $0[key] = nil }
            try variant("\(key)-null") { $0[key] = NSNull() }
            try variant("\(key)-empty") { $0[key] = [Any]() }
        }
        try variant("readingSessions-null") { $0["readingSessions"] = NSNull() }
        try variant("readingSessions-wrongkind") { $0["readingSessions"] = "x" }
        try variant("tombstones-wrongkind") { $0["tombstones"] = 7 }
        try variant("writingRecovery-wrongkind") { $0["writingRecovery"] = "x" }
        try variant("writingRecovery-bad-element") { $0["writingRecovery"] = [["fileName": 1], 5] }
        try variant("documents-null") { $0["documents"] = NSNull() }
        try variant("settings-missing") { $0["settings"] = nil }
        try variant("unknown-top-keys") { $0["zzUnknown"] = ["a": [1, 2, 3]]; $0["android"] = "x" }
        obj = [:]
        // Malformed / byte-level cases.
        out.append(("empty", Data()))
        out.append(("whitespace-only", text("  \n")))
        out.append(("top-level-array", text("[]")))
        out.append(("top-level-number", text("5")))
        out.append(("top-level-null", text("null")))
        out.append(("empty-object", text("{}")))
        out.append(("truncated-half", base.prefix(base.count / 2)))
        out.append(("truncated-last-byte", base.dropLast()))
        out.append(("trailing-garbage", base + text("x")))
        out.append(("trailing-second-doc", base + text("{}")))
        out.append(("trailing-whitespace", base + text("   \n\n")))
        out.append(("utf8-bom", Data([0xEF, 0xBB, 0xBF]) + base))
        out.append(("trailing-comma-object", text(s.replacingOccurrences(of: "\n}\n", with: ",\n}\n"))))
        out.append(("trailing-comma-array", text(s.replacingOccurrences(of: "\"fonts\" : [", with: "\"fonts\" : [,").replacingOccurrences(of: "\"fonts\" : [,]", with: "\"fonts\" : [],").replacingOccurrences(of: "\"bookmarks\" : [", with: "\"bookmarks\" : [", options: []))))
        out.append(("trailing-comma-array-2", text("[1,2,]")))
        out.append(("single-quotes", text("{'version': 8}")))
        out.append(("comment", text("/* c */ " + s)))
        out.append(("nan-number", text(s.replacingOccurrences(of: "\"version\" : 8", with: "\"version\" : NaN"))))
        out.append(("plus-number", text(s.replacingOccurrences(of: "\"version\" : 8", with: "\"version\" : +8"))))
        out.append(("leading-zero", text(s.replacingOccurrences(of: "\"version\" : 8", with: "\"version\" : 08"))))
        out.append(("exp-number-version", text(s.replacingOccurrences(of: "\"version\" : 8", with: "\"version\" : 8e0"))))
        out.append(("fraction-version", text(s.replacingOccurrences(of: "\"version\" : 8", with: "\"version\" : 8.0"))))
        out.append(("big-int-version", text(s.replacingOccurrences(of: "\"version\" : 8", with: "\"version\" : 99999999999999999999"))))
        out.append(("duplicate-version-last-wins-bad", text(s.replacingOccurrences(of: "{\n", with: "{\n\"version\" : 99,\n", options: [], range: s.startIndex ..< s.index(s.startIndex, offsetBy: 3)))))
        out.append(("duplicate-version-last-wins-good", text(s.replacingOccurrences(of: "\"version\" : 8", with: "\"version\" : 99, \"version\" : 8"))))
        out.append(("escaped-key-version", text(s.replacingOccurrences(of: "\"version\"", with: "\"vers\\u0069on\""))))
        out.append(("escaped-key-works", text(s.replacingOccurrences(of: "\"works\"", with: "\"w\\u006frks\""))))
        out.append(("lone-surrogate-escape", text(s.replacingOccurrences(of: "Fixture Work 1 ", with: "Fixture \\ud800 Work 1 "))))
        out.append(("bad-escape", text(s.replacingOccurrences(of: "Fixture Work 1 ", with: "Fixture \\q Work 1 "))))
        out.append(("bad-unicode-escape", text(s.replacingOccurrences(of: "Fixture Work 1 ", with: "Fixture \\u12G4 "))))
        out.append(("raw-newline-in-string", text(s.replacingOccurrences(of: "Fixture Work 1 ", with: "Fixture\nWork 1 "))))
        out.append(("raw-tab-in-string", text(s.replacingOccurrences(of: "Fixture Work 1 ", with: "Fixture\tWork 1 "))))
        out.append(("raw-del-in-string", text(s.replacingOccurrences(of: "Fixture Work 1 ", with: "Fixture\u{7f}Work 1 "))))
        var bad = Data(base); if let r = bad.range(of: Data("Fixture Work 1 ".utf8)) { bad.replaceSubrange(r.lowerBound + 8 ..< r.lowerBound + 9, with: [0xFF]) }
        out.append(("invalid-utf8-ff", bad))
        var overlong = Data(base); if let r = overlong.range(of: Data("Fixture Work 1 ".utf8)) { overlong.replaceSubrange(r.lowerBound + 8 ..< r.lowerBound + 9, with: [0xC0, 0x80]) }
        out.append(("invalid-utf8-overlong", overlong))
        var surrogate = Data(base); if let r = surrogate.range(of: Data("Fixture Work 1 ".utf8)) { surrogate.replaceSubrange(r.lowerBound + 8 ..< r.lowerBound + 9, with: [0xED, 0xA0, 0x80]) }
        out.append(("invalid-utf8-surrogate", surrogate))
        var truncatedSeq = Data(base); if let r = truncatedSeq.range(of: Data("Fixture Work 1 ".utf8)) { truncatedSeq.replaceSubrange(r.lowerBound + 8 ..< r.lowerBound + 9, with: [0xE2, 0x82]) }
        out.append(("invalid-utf8-truncated-seq", truncatedSeq))
        out.append(("valid-utf8-multibyte", text(s.replacingOccurrences(of: "Fixture Work 1 ", with: "Fixture 日本語 😀 Work 1 "))))
        out.append(("deep-nesting-600", text("{\"version\":8,\"x\":" + String(repeating: "[", count: 600) + String(repeating: "]", count: 600) + "}")))
        out.append(("deep-nesting-100-unknown-key", text(s.replacingOccurrences(of: "{\n", with: "{\n\"deep\":" + String(repeating: "[", count: 100) + String(repeating: "]", count: 100) + ",\n", options: [], range: s.startIndex ..< s.index(s.startIndex, offsetBy: 3)))))
        out.append(("missing-comma", text(s.replacingOccurrences(of: "\"version\" : 8,", with: "\"version\" : 8"))))
        out.append(("missing-colon", text(s.replacingOccurrences(of: "\"version\" : 8", with: "\"version\" 8"))))
        out.append(("unterminated-string", text("{\"version\": \"8")))
        out.append(("literal-typo", text(s.replacingOccurrences(of: "\"version\" : 8", with: "\"version\" : nul"))))
        return out
    }

    @Test func prototypeAgreesWithTodaysRoute() throws {
        var disagreements: [String] = []
        for (name, data) in try Self.corpus() {
            let today = todaysOutcome(data)
            let proto = prototypeOutcome(DataSource(data))
            // A fixture whose records omit fields that default to a fresh UUID/Date is not equal to itself when decoded
            // twice by today's own route; that is not a prototype difference.
            if !Self.sameOutcome(today, proto), Self.sameOutcome(today, todaysOutcome(data)) {
                if case let .ok(x) = today, case let .ok(y) = proto {
                    disagreements.append("  detail \(name): omitted \(x.omittedKeys == y.omittedKeys) wr \(x.writingRecovery == y.writingRecovery) docs \(x.documents == y.documents) works \(x.works == y.works) bm \(x.bookmarks == y.bookmarks) settings \(x.settings == y.settings) pron \(x.pronunciations == y.pronunciations) tomb \(x.tombstones == y.tombstones) sess \(x.readingSessions == y.readingSessions) ft \(String(describing: x.followedTags)) \(String(describing: y.followedTags)) ta \(String(describing: x.tagAliases)) \(String(describing: y.tagAliases)) fav \(x.readingFavorites == y.readingFavorites) wm \(x.fandomReadWatermarks == y.fandomReadWatermarks) q \(x.readingQueues == y.readingQueues)")
                }
                disagreements.append("\(name): today=\(today.label) prototype=\(proto.label)")
            }
        }
        let unexpected = disagreements.filter { d in !Self.knownDisagreements.contains { d.hasPrefix($0) } }
        #expect(unexpected.isEmpty, "\(unexpected)")
        T567Recorder.append("ios-parser.jsonl", ["kind": "differential", "cases": try Self.corpus().count, "disagreements": disagreements])
    }

    /// `==` on accepted manifests, except that the memberwise init the prototype assembles with turns an empty
    /// followedTags/tagAliases into nil (the Codable init keeps `[]`); compared through the canonical encoding.
    static func sameOutcome(_ a: ManifestParseOutcome, _ b: ManifestParseOutcome) -> Bool {
        if a == b { return true }
        guard case let .ok(x) = a, case let .ok(y) = b else { return false }
        return x.omittedKeys == y.omittedKeys && x.writingRecovery == y.writingRecovery && x.documents == y.documents
            && (try? KudosBackupContents(manifest: x).manifestData()) == (try? KudosBackupContents(manifest: y).manifestData())
    }

    /// Filled in from the first corpus run; each is a route-parity question for the P2 contract table.
    static let knownDisagreements: [String] = []
}
}
