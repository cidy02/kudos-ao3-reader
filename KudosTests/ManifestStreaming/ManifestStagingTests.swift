import CryptoKit
import Foundation
import Testing
@testable import Kudos

/// T-567 P2 (regular gate, small): the production tokenizer + staging database against today's route.
/// Differential: for every manifest in P1's corpus (existing fixtures, generated manifests, 40+ field variants, byte-level
/// malformed cases) the staged outcome equals `JSONSerialization` + `decodeManifest`'s, and the manifest rebuilt from
/// staging equals `decodeManifest`'s result, `omittedKeys` and `LossyArray` sections included.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ManifestStagingTests {
    // MARK: Plumbing

    final class Scratch {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("t567p2-\(UUID().uuidString)", isDirectory: true)
        init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: url) }
        var options: ManifestStagingOptions {
            var o = ManifestStagingOptions()
            o.parentDirectory = url.appendingPathComponent("staging", isDirectory: true)
            return o
        }
        /// What staging left behind under this scratch folder (nothing, after a discard or a throw).
        var leftovers: [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: options.parentDirectory.path)) ?? [])
        }
    }

    /// The staged route's outcome, in today's vocabulary.
    static func stagedOutcome(_ input: ManifestInput, _ options: ManifestStagingOptions) throws -> ManifestParseOutcome {
        do {
            let run = try ManifestStager.stage(input, options: options)
            defer { run.discard() }
            return .ok(try run.manifest())
        } catch ManifestStreamError.invalidDocument(.notJSON) {
            return .notJSON
        } catch ManifestStreamError.invalidDocument(.depth) {
            return .notJSON // today's class for it (JSONSerialization); the live-file protection difference is its own test
        } catch ManifestStreamError.invalidDocument(.schema) {
            return .schema
        } catch let ManifestStreamError.unsupportedVersion(v) {
            return .unsupportedVersion(v)
        }
    }

    // MARK: Differential

    @Test func stagedOutcomeAndRebuiltManifestEqualTodaysRoute() throws {
        let scratch = Scratch()
        var compared = 0, accepted = 0
        var mismatches: [String] = []
        for (name, data) in try ManifestParserDifferentialTests.corpus() {
            let today = todaysOutcome(data)
            let staged = try Self.stagedOutcome(ManifestDataInput(data), scratch.options)
            // A fixture whose records omit fields that default to a fresh UUID/Date is not equal to itself when today's own
            // route decodes it twice; for those only the class is compared.
            let deterministic = today == todaysOutcome(data)
            let same = deterministic ? today == staged : today.label == staged.label
            if !same { mismatches.append("\(name): today=\(today.label) staged=\(staged.label)") }
            compared += 1
            if case .ok = today { accepted += 1 }
        }
        #expect(mismatches.isEmpty, "\(mismatches)")
        #expect(compared >= 79 && accepted >= 30, "compared \(compared), accepted \(accepted)")
        #expect(scratch.leftovers.isEmpty, "staging left \(scratch.leftovers)")
    }

    @Test func fileInputAndTinyChunksAndDeferredRecordsRebuildTheSameManifest() throws {
        let scratch = Scratch()
        var options = scratch.options
        options.chunkSize = 97 // many chunks per record, a chunk boundary inside multi-byte text
        var rebuilt = 0
        for (name, data) in try ManifestParserDifferentialTests.corpus() {
            let today = todaysOutcome(data)
            guard case .ok = today, today == todaysOutcome(data) else { continue }
            let file = scratch.url.appendingPathComponent("m.json")
            try data.write(to: file)
            let staged = try Self.stagedOutcome(ManifestFileInput(url: file), options)
            #expect(staged == today, "\(name)")
            rebuilt += 1
        }
        #expect(rebuilt >= 20)
        #expect(scratch.leftovers.isEmpty)
    }

    // MARK: Presence, order, keys

    @Test func presenceOrderStatusAndNaturalKeysAreStaged() throws {
        let scratch = Scratch()
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let base = try #require(corpus["gen:works"])
        let run = try ManifestStager.stage(ManifestDataInput(base), options: scratch.options)
        defer { run.discard() }
        let manifest = try KudosBackupContents.decodeManifest(base)
        #expect(run.version == manifest.version)
        let works = try run.records(of: "works")
        #expect(works.map(\.seq) == Array(0 ..< manifest.works.count))
        #expect(works.map(\.keys.id) == manifest.works.map { $0.id.uuidString.lowercased() })
        #expect(works.map(\.keys.ao3) == manifest.works.map(\.ao3WorkID))
        #expect(works.map(\.keys.url) == manifest.works.map(\.sourceURL))
        #expect(works.allSatisfy { $0.status == .decoded })
        let tombstones = try run.records(of: "tombstones")
        #expect(tombstones.map(\.keys.work) == manifest.tombstones.map { $0.recordID.uuidString.lowercased() })
        #expect(tombstones.map(\.keys.stamp) == manifest.tombstones.map { $0.lastModifiedAt.timeIntervalSince1970 })
        // Indexed: the planner uses the natural-key index, not a scan.
        var plan = ""
        try run.db.query("EXPLAIN QUERY PLAN SELECT seq FROM rec_works WHERE k_ao3 = 1") { plan += $0.text(3) }
        #expect(plan.contains("INDEX rec_works_k_ao3"), "\(plan)")

        // Presence: missing / null / present / wrong kind, per member.
        func presence(_ name: String, of key: String) throws -> ManifestPresence {
            let data = try #require(corpus[name])
            return try ManifestStager.stage(ManifestDataInput(data), options: scratch.options).use { try $0.presence(of: key) }
        }
        for key in ["collections", "readingQueues", "annotations", "savedSearches"] {
            #expect(try presence("\(key)-missing", of: key) == .missing)
            #expect(try presence("\(key)-null", of: key) == .null)
            #expect(try presence("\(key)-empty", of: key) == .present)
        }
        // A LossyArray section keeps its undecodable element as a row (status), in source order, without a payload.
        let lossyData = try #require(corpus["writingRecovery-bad-element"])
        let lossy = try ManifestStager.stage(ManifestDataInput(lossyData), options: scratch.options)
        defer { lossy.discard() }
        #expect(try lossy.records(of: "writingRecovery").map(\.status) == [.undecodable, .undecodable])
        #expect(try lossy.manifest().writingRecovery == [])
        #expect(try lossy.presence(of: "documents") != .wrongKind)
        // A wrong kind in a lossy section is absent, not a failure.
        let wrongData = try #require(corpus["writingRecovery-wrongkind"])
        let wrong = try ManifestStager.stage(ManifestDataInput(wrongData), options: scratch.options)
        defer { wrong.discard() }
        #expect(try wrong.presence(of: "writingRecovery") == .wrongKind)
        #expect(try wrong.manifest().writingRecovery == nil)
        // Unknown top-level keys are kept as members (kind and length), in source order, with no payload.
        let unknownData = try #require(corpus["unknown-top-keys"])
        let unknown = try ManifestStager.stage(ManifestDataInput(unknownData), options: scratch.options)
        defer { unknown.discard() }
        var unknownNames: [String] = []
        try unknown.forEachMember(pageSize: 2, unknownOnly: true) { unknownNames.append($0.name) }
        #expect(unknownNames.contains("zzUnknown"))
        #expect(try unknown.db.scalar("SELECT count(*) FROM payload WHERE owner = 'zzUnknown'") == 0)
    }

    @Test func oversizedValuesAreStoredInBoundedChunks() throws {
        let scratch = Scratch()
        var options = scratch.options
        options.chunkSize = 1024
        options.typedRecordBudget = 8192
        options.typedValueBudget = 8192
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let base = try #require(corpus["gen:works"])
        var obj = try #require(JSONSerialization.jsonObject(with: base) as? [String: Any])
        let big = Data(repeating: 0x41, count: 300_000).base64EncodedString()
        obj["documents"] = [["name": "big.bin", "data": big, "modifiedAt": "2026-01-01T00:00:00.000Z"]]
        let data = try JSONSerialization.data(withJSONObject: obj)
        let run = try ManifestStager.stage(ManifestDataInput(data), options: options)
        defer { run.discard() }
        let documents = try run.records(of: "documents")
        #expect(documents.map(\.status) == [.deferred])
        var chunks = 0, bytes = 0, largest = 0
        try run.forEachChunk(of: "documents", seq: 0) { chunks += 1; bytes += $0.count; largest = max(largest, $0.count) }
        #expect(largest <= 1024 && chunks == (bytes + 1023) / 1024 && bytes == documents[0].length)
        #expect(try run.manifest().documents?.first?.data.count == 300_000)
    }

    // MARK: Contract points

    @Test func nestingLimitIsFiveHundredTwelveContainersIncludingTheRoot() throws {
        let scratch = Scratch()
        func outcome(_ text: String) throws -> ManifestStreamError? { try Self.stagedFailure(Data(text.utf8), scratch.options) }
        func nested(_ n: Int) -> String { String(repeating: "[", count: n) + String(repeating: "]", count: n) }
        // Object root + n arrays = n + 1 containers. 512 is the last accepted (then it is just not a manifest: schema).
        #expect(try outcome("{\"version\":8,\"x\":\(nested(511))}") == .invalidDocument(.schema))
        #expect(try outcome("{\"version\":8,\"x\":\(nested(512))}") == .invalidDocument(.depth))
        // Array root: n containers. Root type outranks the depth limit (shared decision 18a).
        #expect(try outcome(nested(512)) == .invalidDocument(.schema))
        #expect(try outcome(nested(513)) == .invalidDocument(.schema))
        // A deep value inside a record array element counts the root, the array and the record.
        #expect(try outcome("{\"works\":[{\"a\":\(nested(509))}]}") == .invalidDocument(.schema))
        #expect(try outcome("{\"works\":[{\"a\":\(nested(510))}]}") == .invalidDocument(.depth))
        // Route rule: only a document that is not JSON may be replaced from `.bak`; depth rejection of a complete file protects it.
        #expect(ManifestStreamError.invalidDocument(.depth).isBakEligible == false)
        #expect(ManifestStreamError.invalidDocument(.notJSON).isBakEligible == true)
        #expect(ManifestStreamError.invalidDocument(.schema).isBakEligible == false)
        #expect(ManifestStreamError.unsupportedVersion(9).isBakEligible == false)
        #expect(ManifestStreamError.io("x").isBakEligible == false)
        #expect(ManifestStreamError.resourceExhausted("x").isBakEligible == false)
        #expect(try outcome("{\"version\":8,\"x\":[") == .invalidDocument(.notJSON)) // truncated: eligible
        // Precedence holds through a depth overflow: scanning goes on, so a malformed tail still reports syntax (eligible), and a
        // deeper-than-the-iterative-guard-allows tail does not crash the scanner.
        #expect(try outcome("{\"version\":8,\"x\":\(nested(512))") == .invalidDocument(.notJSON))
        #expect(try outcome("{\"version\":8,\"x\":\(nested(512))]") == .invalidDocument(.notJSON))
        #expect(try outcome("{\"version\":8,\"x\":\(String(repeating: "{\"a\":[", count: 20_000))1\(String(repeating: "]}", count: 20_000))}") == .invalidDocument(.depth))
        #expect(try outcome("{\"version\":8,\"x\":\(String(repeating: "{\"a\":[", count: 20_000))1\(String(repeating: "]}", count: 20_000))}x") == .invalidDocument(.notJSON))
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func syntaxErrorAfterASchemaFailureStillReportsNotJSON() throws {
        // Today's order: JSONSerialization first. A bad record early and a truncated tail late is `notJSON`, not `schema`.
        let scratch = Scratch()
        let data = Data("{\"works\":[5],\"bookmarks\":[],\"fonts\":[],\"version\":8,\"exportedAt\":\"2026-01-01T00:00:00Z\"".utf8)
        #expect(throws: ManifestStreamError.invalidDocument(.notJSON)) { try ManifestStager.stage(ManifestDataInput(data), options: scratch.options) }
        #expect(todaysOutcome(data).label == "notJSON")
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func anOversizedStrictRecordIsNeverAcceptedAndNeverStagedUnchecked() throws {
        let scratch = Scratch()
        var options = scratch.options
        options.typedRecordBudget = 8192
        options.typedValueBudget = 8192
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let base = try #require(corpus["gen:works"])
        var obj = try #require(JSONSerialization.jsonObject(with: base) as? [String: Any])
        // Typed-invalid (no required fields) and over the budget: today's decoder rejects it; the run must not accept it.
        obj["bookmarks"] = [["junk": String(repeating: "x", count: 12000)]]
        let invalid = try JSONSerialization.data(withJSONObject: obj)
        #expect(todaysOutcome(invalid).label == "schema")
        guard case .resourceExhausted = try Self.stagedFailure(invalid, options) else { Issue.record("invalid oversized strict record accepted"); return }
        // A typed-valid oversized strict record is also not accepted by this reader (P4 streams it field by field); same outcome.
        var works = try #require(obj["works"] as? [[String: Any]])
        works[0]["summary"] = String(repeating: "y", count: 12000)
        obj["works"] = works
        obj["bookmarks"] = [Any]()
        let valid = try JSONSerialization.data(withJSONObject: obj)
        #expect(todaysOutcome(valid).label == "ok")
        guard case .resourceExhausted = try Self.stagedFailure(valid, options) else { Issue.record("oversized strict record staged"); return }
        // Oversized single strict value (settings) likewise.
        obj["works"] = [Any](); obj["settings"] = ["pad": String(repeating: "z", count: 12000)]
        guard case .resourceExhausted = try Self.stagedFailure(try JSONSerialization.data(withJSONObject: obj), options) else { Issue.record("settings"); return }
        #expect(scratch.leftovers.isEmpty)
    }

    static func stagedFailure(_ data: Data, _ options: ManifestStagingOptions) throws -> ManifestStreamError? {
        do { try ManifestStager.stage(ManifestDataInput(data), options: options).discard(); return nil } catch { return error as? ManifestStreamError }
    }

    @Test func keyCountLimitAppliesToEveryObject() throws {
        let scratch = Scratch()
        let keys = ManifestLimits.maxKeysPerObject
        func object(_ n: Int) -> String { "{" + (0 ..< n).map { "\"k\($0)\":1" }.joined(separator: ",") + "}" }
        // Nested inside an unknown key (and inside an array), at the limit: accepted as JSON (then not a manifest: schema).
        for wrap in ["{\"x\":%@}", "{\"x\":[%@]}", "{\"x\":{\"y\":%@}}"] {
            let ok = String(format: wrap, object(keys))
            #expect(try Self.stagedFailure(Data(ok.utf8), scratch.options) == .invalidDocument(.schema), "at limit \(wrap)")
            guard case .resourceExhausted = try Self.stagedFailure(Data(String(format: wrap, object(keys + 1)).utf8), scratch.options) else {
                Issue.record("one over, nested \(wrap)"); return
            }
        }
        #expect(scratch.leftovers.isEmpty)
    }

    // MARK: Round 3 (shared contract decisions, Codex parity review)

    /// A valid manifest (P1's generated one) with `members` spliced in before the final brace.
    static func withMembers(_ members: String) throws -> Data {
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let baseData = try #require(corpus["gen:works"])
        var text = String(decoding: baseData, as: UTF8.self)
        let brace = try #require(text.lastIndex(of: "}"))
        text.insert(contentsOf: "," + members, at: brace)
        return Data(text.utf8)
    }

    @Test func firstValueWinsAtEveryDepthBeforeTypedDecode() throws {
        let scratch = Scratch()
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let baseData = try #require(corpus["gen:works"])
        let base = String(decoding: baseData, as: UTF8.self)
        // Nested duplicates, plain and escaped, inside a record: the scanner cuts the later ones, so the typed decoder sees first-wins.
        let edited = base.replacingOccurrences(of: "\"title\" : \"Fixture Work 1 ", with: "\"title\" : \"FIRST\", \"\\u0074itle\" : \"SECOND\", \"title\" : \"THIRD\", \"zz\" : {\"a\":1,\"a\":2}, \"zz\" : 5, \"titleX\" : \"Fixture Work 1 ")
        #expect(edited != base)
        let run = try ManifestStager.stage(ManifestDataInput(Data(edited.utf8)), options: scratch.options)
        defer { run.discard() }
        #expect(try run.manifest().works.contains { $0.title == "FIRST" })
        #expect(try !run.manifest().works.contains { $0.title == "SECOND" || $0.title == "THIRD" })
        // No normalisation: "é" and "e" + combining acute are different keys, so both members are kept (root level, visible as members).
        let accents = try Self.withMembers("\"\u{00E9}\":1,\"e\u{0301}\":2,\"a\":1,\"a\\u0000\":2")
        let accented = try ManifestStager.stage(ManifestDataInput(accents), options: scratch.options)
        defer { accented.discard() }
        var names: [String] = []
        try accented.forEachMember(pageSize: 2) { names.append($0.name) }
        let units = names.map { Array($0.utf16) }
        #expect(units.contains([0x00E9]) && units.contains([0x0065, 0x0301]))
        #expect(units.contains(Array("a".utf16)) && units.contains(Array("a\u{0}".utf16)))
        run.discard(); accented.discard()
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func generatedDefaultsAreMaterialisedOnceAndKeysSurviveNulAndPairs() throws {
        let scratch = Scratch()
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let baseData = try #require(corpus["gen:works"])
        var obj = try #require(JSONSerialization.jsonObject(with: baseData) as? [String: Any])
        // A pre-G6 bookmark (no id) and a session with only an id: today's decoder mints fresh UUIDs/dates on every decode.
        obj["bookmarks"] = [["title": "", "urlString": "https://x", "dateAdded": "2026-01-01T00:00:00Z"]]
        obj["readingSessions"] = [["id": "11111111-1111-4111-8111-111111111111"]]
        obj["fonts"] = [["name": "Nul\u{0}Font", "fileName": "a.ttf", "dateAdded": "2026-01-01T00:00:00Z"]]
        obj["readingFavorites"] = [
            ["id": "22222222-2222-4222-8222-222222222222", "kindRaw": "work\u{0}x", "targetKey": "y", "displayName": "", "createdAt": "2026-01-01T00:00:00Z", "lastModifiedAt": "2026-01-01T00:00:00Z"],
            ["id": "33333333-3333-4333-8333-333333333333", "kindRaw": "work", "targetKey": "x\u{0}y", "displayName": "", "createdAt": "2026-01-01T00:00:00Z", "lastModifiedAt": "2026-01-01T00:00:00Z"],
        ]
        let data = try JSONSerialization.data(withJSONObject: obj)
        let run = try ManifestStager.stage(ManifestDataInput(data), options: scratch.options)
        defer { run.discard() }
        let first = try run.manifest(), second = try run.manifest()
        #expect(first == second, "two rebuilds of one staged run differ")
        let bookmark = try #require(first.bookmarks.first)
        #expect(try run.records(of: "bookmarks").first?.keys.id == bookmark.id.uuidString.lowercased())
        let session = try #require(first.readingSessions?.first)
        #expect(try run.records(of: "readingSessions").first?.keys.work == session.workID.uuidString.lowercased())
        #expect(session.endedAt == session.startedAt)
        // NUL inside a key is part of the key; the pair identity is two columns, not a joined string.
        #expect(try run.records(of: "fonts").first?.keys.name == "nul\u{0}font")
        let favorites = try run.records(of: "readingFavorites")
        #expect(favorites.map(\.keys.text) == ["work\u{0}x", "work"] && favorites.map(\.keys.text2) == ["y", "x\u{0}y"])
    }

    @Test func outcomePrecedenceIsIOThenCancellationThenSyntaxThenResourceThenSchema() async throws {
        let scratch = Scratch()
        var options = scratch.options
        options.typedRecordBudget = 8192
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let baseData = try #require(corpus["gen:works"])
        var obj = try #require(JSONSerialization.jsonObject(with: baseData) as? [String: Any])
        // An early schema error and an oversized strict record: resource exhaustion, whatever the member order.
        obj["bookmarks"] = [["junk": 1]]
        obj["works"] = [["summary": String(repeating: "y", count: 12000)]]
        let both = try JSONSerialization.data(withJSONObject: obj)
        guard case .resourceExhausted = try Self.stagedFailure(both, options) else { Issue.record("budget must outrank schema"); return }
        // The same with a malformed tail: syntax outranks the budget.
        #expect(try Self.stagedFailure(both.dropLast(), options) == .invalidDocument(.notJSON))
        // A complete `[]` root whose tail read fails is I/O, not schema.
        let input = HookedInput(ManifestDataInput(Data("[]".utf8)))
        input.failureMessage = "tail unreadable"
        #expect(throws: ManifestStreamError.io("tail unreadable")) { try ManifestStager.stage(input, options: options) }
        // A split BOM (windows shorter than three bytes) is still a BOM.
        let small = try Self.withMembers("\"zz\":1")
        let bom = Data([0xEF, 0xBB, 0xBF]) + small
        let chopped = ChoppedInput(ManifestDataInput(bom), window: 2)
        let run = try ManifestStager.stage(chopped, options: scratch.options)
        defer { run.discard() }
        #expect(try run.manifest().works.count == KudosBackupContents.decodeManifest(small).works.count)
        run.discard()
        #expect(scratch.leftovers.isEmpty)
    }

    /// Hands out windows of at most `window` bytes.
    nonisolated final class ChoppedInput: ManifestInput {
        let inner: ManifestInput
        let window: Int
        var length: Int { inner.length }
        var failure: String? { inner.failure }
        init(_ inner: ManifestInput, window: Int) { self.inner = inner; self.window = window }
        func window(at offset: Int) -> UnsafeRawBufferPointer {
            let w = inner.window(at: offset)
            return UnsafeRawBufferPointer(rebasing: w[0 ..< min(w.count, window)])
        }
        func read(_ range: Range<Int>) -> Data { inner.read(range) }
    }

    @Test func cancellationIsPolledInWhitespaceDigitsAndAtTheFinalBoundary() async throws {
        let scratch = Scratch()
        let options = scratch.options
        for (name, body) in [("whitespace", String(repeating: " ", count: 3 << 20)), ("digits", String(repeating: "1", count: 3 << 20))] {
            let file = scratch.url.appendingPathComponent("\(name).json")
            try Data(("{\"x\":" + (name == "whitespace" ? body + "1" : body) + "}").utf8).write(to: file)
            let result = await Task.detached { () -> ManifestStreamError? in
                let input = HookedInput(try! ManifestFileInput(url: file), onWindow: { n in
                    if n == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                })
                do { _ = try ManifestStager.stage(input, options: options); return nil } catch { return error as? ManifestStreamError }
            }.value
            #expect(result == .cancelled, "\(name)")
        }
        // Even a run that parsed to the end is not handed over once cancelled: cancel inside the final disk check.
        let data = try Self.withMembers("\"zz\":1")
        var final = scratch.options
        let calls = NSLock(); nonisolated(unsafe) var count = 0
        final.availableCapacity = { _ in
            calls.lock(); count += 1; let n = count; calls.unlock()
            if n >= 2 { withUnsafeCurrentTask { $0?.cancel() } }
            return 1 << 40
        }
        let finalOptions = final
        let result = await Task.detached { () -> ManifestStreamError? in
            do { _ = try ManifestStager.stage(ManifestDataInput(data), options: finalOptions); return nil } catch { return error as? ManifestStreamError }
        }.value
        #expect(result == .cancelled)
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func diskIsRecheckedBeforeSuccess() throws {
        let scratch = Scratch()
        var options = scratch.options
        let data = try Self.withMembers("\"zz\":1")
        nonisolated(unsafe) var calls = 0
        options.availableCapacity = { _ in calls += 1; return calls == 1 ? 1 << 40 : 1 << 20 } // room at the start, gone at the end
        guard case .resourceExhausted = try Self.stagedFailure(data, options) else { Issue.record("final disk recheck"); return }
        #expect(calls >= 2)
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func totalLiveKeyMemoryIsBounded() throws {
        let scratch = Scratch()
        // 200,000 distinct 100-unit keys in one object (under the per-object count): about 53 MB of decoded keys, over the 32 MiB budget.
        let key = String(repeating: "k", count: 90)
        let members = (0 ..< 200_000).map { "\"\(key)\($0)\":0" }.joined(separator: ",")
        guard case .resourceExhausted = try Self.stagedFailure(Data("{\"x\":{\(members)}}".utf8), scratch.options) else { Issue.record("live key budget"); return }
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func keysetPagesAndPayloadRangesAreBounded() throws {
        let scratch = Scratch()
        var options = scratch.options
        options.chunkSize = 64
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let data = try #require(corpus["gen:works"])
        let run = try ManifestStager.stage(ManifestDataInput(data), options: options)
        defer { run.discard() }
        var seqs: [Int] = []
        var last = -1
        while true {
            let page = try run.recordPage(of: "works", after: last, limit: 5)
            seqs += page.map(\.seq)
            guard page.count == 5, let end = page.last else { break }
            last = end.seq
        }
        #expect(seqs == (0 ..< (try KudosBackupContents.decodeManifest(data).works.count)).map { $0 })
        var whole = Data()
        try run.readPayload(of: "works", seq: 2) { whole.append($0) }
        #expect(whole.count > 200)
        var piece = Data()
        var pieces = 0
        try run.readPayload(of: "works", seq: 2, range: 70 ..< 190) { piece.append($0); pieces += 1 }
        #expect(piece == whole.subdata(in: 70 ..< 190) && pieces >= 2)
        #expect(try run.shape(of: "works") == .nonEmpty(count: seqs.count))
    }

    @Test func presenceShapesAreExposedForApplyDecisions() throws {
        let scratch = Scratch()
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        func shape(_ name: String, _ key: String) throws -> ManifestSectionShape {
            let data = try #require(corpus[name])
            let run = try ManifestStager.stage(ManifestDataInput(data), options: scratch.options)
            defer { run.discard() }
            return try run.shape(of: key)
        }
        #expect(try shape("collections-missing", "collections") == .missing)
        #expect(try shape("collections-null", "collections") == .null)
        #expect(try shape("collections-empty", "collections") == .empty)
        #expect(try shape("writingRecovery-wrongkind", "writingRecovery") == .wrongKind)
    }

    @Test func staleSweepSparesOpenRunsAndSurfacesFailures() throws {
        let scratch = Scratch()
        let openData = try Self.withMembers("\"zz\":1")
        let open = try ManifestStager.stage(ManifestDataInput(openData), options: scratch.options)
        let openName = open.db.directory.lastPathComponent
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: open.db.directory.path)
        ManifestStager.removeStale(in: scratch.options.parentDirectory)
        #expect(scratch.leftovers == [openName], "an open run must survive the sweep")
        #expect(open.discard() == nil)
        // A directory that cannot be deleted is reported, not swallowed.
        let stuck = scratch.options.parentDirectory.appendingPathComponent("run-stuck", isDirectory: true)
        try FileManager.default.createDirectory(at: stuck, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: stuck.appendingPathComponent("f"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: stuck.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: stuck.path)
        let failures = ManifestStager.removeStale(in: scratch.options.parentDirectory)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stuck.path)
        #expect(failures.map { $0.0.lastPathComponent } == ["run-stuck"])
    }

    // MARK: Shared byte fixtures (docs/manifest-fixtures: Android's set, byte-identical; its suite reads the same cases.json)

    static func outcomeName(_ data: Data, _ options: ManifestStagingOptions) -> String {
        do {
            try ManifestStager.stage(ManifestDataInput(data), options: options).discard()
            return "ok"
        } catch ManifestStreamError.invalidDocument(.notJSON) { return "syntax"
        } catch ManifestStreamError.invalidDocument(.schema) { return "schema"
        } catch ManifestStreamError.invalidDocument(.depth) { return "resource" // Android's class for the depth policy; iOS names it `depth`
        } catch ManifestStreamError.unsupportedVersion { return "unsupportedVersion"
        } catch ManifestStreamError.resourceExhausted { return "resource"
        } catch { return "other \(error)" }
    }

    @Test func sharedFixtureCasesHoldExactly() throws {
        let scratch = Scratch()
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/manifest-fixtures")
        let index = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("cases.json"))) as? [String: Any])
        let wrapper = try #require(index["wrapper"] as? String)
        let cases = try #require(index["cases"] as? [[String: Any]])
        #expect(cases.count >= 51)
        var disagreements: [String] = []
        for c in cases {
            let id = try #require(c["id"] as? String)
            let expected = try #require(c["expect"] as? String)
            var data: Data
            if let file = c["file"] as? String {
                data = try Data(contentsOf: folder.appendingPathComponent(file))
            } else {
                let gen = try #require(c["gen"] as? [String: Any])
                let body = (gen["prefix"] as? String ?? "") + String(repeating: gen["unit"] as? String ?? "", count: gen["count"] as? Int ?? 1)
                    + (gen["suffix"] as? String ?? "")
                let wrap = gen["wrap"] as? Bool ?? false
                data = Data((wrap ? wrapper.replacingOccurrences(of: "BODY", with: body) : body).utf8)
            }
            let actual = Self.outcomeName(data, scratch.options)
            if actual != expected { disagreements.append("\(id): \(actual), expected \(expected)") }
        }
        #expect(disagreements.isEmpty, "\(disagreements.sorted())")
        #expect(scratch.leftovers.isEmpty)
    }

    // MARK: Resource limits (shared with Android)

    @Test func resourceLimitsAreResourceExhaustionAndAtTheLimitIsAccepted() throws {
        let scratch = Scratch()
        func stage(_ text: String) throws -> ManifestStreamError? {
            do { try ManifestStager.stage(ManifestDataInput(Data(text.utf8)), options: scratch.options).discard(); return nil } catch { return error as? ManifestStreamError }
        }
        let key = ManifestLimits.maxKeyUnits, number = ManifestLimits.maxNumberChars
        // At the limit: a schema failure (not a manifest), never a resource one. One over: resource exhaustion.
        #expect(try stage("{\"\(String(repeating: "k", count: key))\":1}") == .invalidDocument(.schema))
        guard case .resourceExhausted = try stage("{\"\(String(repeating: "k", count: key + 1))\":1}") else { Issue.record("key"); return }
        #expect(try stage("{\"x\":\(String(repeating: "1", count: number))}") == .invalidDocument(.schema))
        guard case .resourceExhausted = try stage("{\"x\":\(String(repeating: "1", count: number + 1))}") else { Issue.record("number"); return }
        // Units are UTF-16 code units of the decoded key: 32,768 emoji are 65,536 units (accepted), one more `a` is over; an escaped
        // spelling counts the same; the source spelling does not.
        let emoji = String(repeating: "\u{1F600}", count: key / 2)
        #expect(try stage("{\"\(emoji)\":1}") == .invalidDocument(.schema))
        guard case .resourceExhausted = try stage("{\"\(emoji)a\":1}") else { Issue.record("emoji key"); return }
        #expect(try stage("{\"\(String(repeating: "\\u0061", count: key))\":1}") == .invalidDocument(.schema))
        let keys = ManifestLimits.maxKeysPerObject
        func object(_ n: Int) -> String { "{" + (0 ..< n).map { "\"k\($0)\":1" }.joined(separator: ",") + "}" }
        #expect(try stage(object(keys)) == .invalidDocument(.schema))
        guard case .resourceExhausted = try stage(object(keys + 1)) else { Issue.record("keys"); return }
        let big = ManifestLimits.maxRootValueBytes
        #expect(try stage("{\"settings\":\"\(String(repeating: "a", count: big - 2))\"}") == .invalidDocument(.schema))
        guard case .resourceExhausted = try stage("{\"settings\":\"\(String(repeating: "a", count: big))\"}") else { Issue.record("root value"); return }
        // Leading zero and a missing comma are syntax errors, as today's route (shared with Android).
        for text in ["{\"version\":08}", "{\"version\":8 \"x\":1}"] {
            #expect(try stage(text) == .invalidDocument(.notJSON), "\(text)")
            #expect(todaysOutcome(Data(text.utf8)).label == "notJSON")
        }
        #expect(scratch.leftovers.isEmpty)
    }

    // MARK: Distinct outcomes: cancellation, I/O, resources

    /// Shared decision 19a: at the live-key limit a duplicate key costs nothing; only a new distinct key fails.
    @Test func aDuplicateKeyAtTheLiveKeyLimitIsNotResourceExhaustion() throws {
        let scratch = Scratch()
        let prefix = "{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00.000Z\",\"works\":[],\"bookmarks\":[],\"fonts\":[],"
            + "\"settings\":{\"readerFontID\":\"system\"},\"x\":{"
        let rootKeyUnits = "version exportedAt works bookmarks fonts settings x".split(separator: " ").reduce(0) { $0 + $1.count }
        let fitting = (ManifestLimits.maxLiveKeyUnits - rootKeyUnits) / 60
        func key(_ i: Int) -> String { String(format: "%06d", i) + String(repeating: "k", count: 54) }
        func document(extra: String) -> Data {
            var members = (0..<fitting).map { "\"\(key($0))\":0" }
            members.append(extra)
            return Data((prefix + members.joined(separator: ",") + "}}").utf8)
        }
        #expect(Self.outcomeName(document(extra: "\"\(key(0))\":1"), scratch.options) == "ok")
        #expect(Self.outcomeName(document(extra: "\"\(key(fitting))\":0"), scratch.options) == "resource")
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func arrayRootIsSchemaBeforeDepthOrBudget() throws {
        let scratch = Scratch()
        let deepArray = Data((String(repeating: "[", count: 513) + String(repeating: "]", count: 513)).utf8)
        #expect(try Self.stagedFailure(deepArray, scratch.options) == .invalidDocument(.schema))
        var noDisk = scratch.options
        noDisk.availableCapacity = { _ in 0 }
        #expect(try Self.stagedFailure(deepArray, noDisk) == .invalidDocument(.schema))
        #expect(try Self.stagedFailure(Data("[1".utf8), noDisk) == .invalidDocument(.notJSON))
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func validationBatchesStopAtBothRecordAndByteLimits() throws {
        let scratch = Scratch()
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let data = try #require(corpus["gen:works"])
        let run = try ManifestStager.stage(ManifestDataInput(data), options: scratch.options)
        defer { run.discard() }
        let all = try run.records(of: "works")
        let largest = try #require(all.map(\.length).max())
        let byteLimit = largest * 2
        var batches: [[ManifestRecordMeta]] = []
        try run.forEachValidationBatch(of: "works", maxRecords: 200, maxBytes: byteLimit) { batches.append($0) }
        #expect(batches.count > 1)
        #expect(batches.allSatisfy { $0.count <= 200 && $0.reduce(0) { $0 + $1.length } <= byteLimit })
        #expect(batches.flatMap { $0.map(\.seq) } == all.map(\.seq))
        var countBatches: [[ManifestRecordMeta]] = []
        try run.forEachValidationBatch(of: "works", maxRecords: 1) { countBatches.append($0) }
        #expect(countBatches.allSatisfy { $0.count == 1 })
    }

    @Test func liveKeyLimitCountsDecodedUTF16Units() throws {
        let scratch = Scratch()
        let file = scratch.url.appendingPathComponent("key-budget.json")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let writer = try FileHandle(forWritingTo: file)
        try writer.write(contentsOf: Data("{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00.000Z\",\"works\":[],\"bookmarks\":[],\"fonts\":[],\"settings\":{\"readerFontID\":\"system\"},\"manyKeys\":{".utf8))
        for start in stride(from: 0, to: 175_000, by: 1000) {
            let chunk = (start ..< start + 1000).map { "\($0 == 0 ? "" : ",")\"\(String(format: "%06d", $0))\(String(repeating: "k", count: 54))\":0" }.joined()
            try writer.write(contentsOf: Data(chunk.utf8))
        }
        try writer.write(contentsOf: Data("}}".utf8))
        try writer.close()
        do {
            try ManifestStager.stage(ManifestFileInput(url: file), options: scratch.options).discard()
            Issue.record("distinct key units exceeded the budget")
        } catch ManifestStreamError.resourceExhausted { }
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func skippedDuplicateObjectDoesNotRetainItsKeys() throws {
        let scratch = Scratch()
        let file = scratch.url.appendingPathComponent("skipped-keys.json")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let writer = try FileHandle(forWritingTo: file)
        try writer.write(contentsOf: Data("{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"works\":[],\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"x\":0,\"x\":{".utf8))
        for start in stride(from: 0, to: 175_000, by: 1000) {
            let text = (start ..< start + 1000).map { "\($0 == 0 ? "" : ",")\"\(String(format: "%06d", $0))\(String(repeating: "k", count: 54))\":0" }.joined()
            try writer.write(contentsOf: Data(text.utf8))
        }
        try writer.write(contentsOf: Data("}}".utf8)); try writer.close()
        let run = try ManifestStager.stage(ManifestFileInput(url: file), options: scratch.options)
        #expect(try run.presence(of: "x") == .present)
        run.discard()
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func unknownValueDuplicatesDoNotAccumulateRemovals() throws {
        let scratch = Scratch()
        let file = scratch.url.appendingPathComponent("nonadjacent-duplicates.json")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let writer = try FileHandle(forWritingTo: file)
        try writer.write(contentsOf: Data("{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"works\":[],\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"x\":[".utf8))
        let chunk = Data(Array(repeating: "{\"a\":0,\"a\":1}", count: 1000).joined(separator: ",").utf8)
        for part in 0 ..< 100 {
            if part > 0 { try writer.write(contentsOf: Data(",".utf8)) }
            try writer.write(contentsOf: chunk)
        }
        try writer.write(contentsOf: Data("]}".utf8)); try writer.close()
        try ManifestStager.stage(ManifestFileInput(url: file), options: scratch.options).discard()
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func compactWorkIsNotReencodedUnlessItGeneratesADefault() throws {
        let scratch = Scratch()
        let work = "{\"id\":\"00000001-0000-4000-8000-000000000001\",\"dateAdded\":\"2026-01-01T00:00:00Z\"}"
        let prefix = "{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"works\":["
        let run = try ManifestStager.stage(ManifestDataInput(Data((prefix + work + "]}").utf8)), options: scratch.options)
        var stored = Data()
        try run.readPayload(of: "works", seq: 0) { stored.append($0) }
        #expect(stored == Data(work.utf8))
        run.discard()
        let missingDate = "{\"id\":\"00000001-0000-4000-8000-000000000001\"}"
        let defaulted = try ManifestStager.stage(ManifestDataInput(Data((prefix + missingDate + "]}").utf8)), options: scratch.options)
        var canonical = Data()
        try defaulted.readPayload(of: "works", seq: 0) { canonical.append($0) }
        #expect(canonical.range(of: Data("\"dateAdded\"".utf8)) != nil)
        #expect(canonical.range(of: Data("\"workWarnings\"".utf8)) == nil)
        #expect(canonical.count < 150)
        defaulted.discard()
    }

    @Test func generatedDefaultSpliceKeepsAcceptedJSONReadableAndCompact() throws {
        let scratch = Scratch()
        let id = "00000001-0000-4000-8000-000000000001"
        let records = [
            "{\"id\":\"\(id)\", }",
            "{\"id\":\"\(id)\",\n}",
            "{\n  \"id\": \"\(id)\"\n}",
            "{\"id\":\"\(id)\",\"title\":\"a\\nb\"}",
            "{\"id\":\"\(id)\",\"title\":\"x, }\",\"ignored\":[1, ]}",
            "{\"id\":\"\(id)\",\"dateAdded\":null, }",
            "{\"id\":\"\(id)\",\"date\\u0041dded\":null,\"ignored\":{\"x\":1, }}",
        ]
        let prefix = "{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"works\":["
        for record in records {
            let run = try ManifestStager.stage(ManifestDataInput(Data((prefix + record + "]}").utf8)), options: scratch.options)
            var stored = Data()
            try run.readPayload(of: "works", seq: 0) { stored.append($0) }
            let text = String(decoding: stored, as: UTF8.self)
            #expect(try run.manifest().works.count == 1, "\(record)")
            #expect((try JSONSerialization.jsonObject(with: stored) as? [String: Any]) != nil, "\(text)")
            if record.contains("x, }") {
                #expect(try run.manifest().works[0].title == "x, }")
                #expect(!text.contains("[1, ]"), "\(text)")
            } else {
                #expect(!text.contains(", }") && !text.contains(",\n}"), "\(text)")
            }
            #expect(!text.contains("\"dateAdded\":null") && !text.contains("\"date\\u0041dded\":null"), "\(text)")
            #expect(stored.count < 180, "compact payload grew to \(stored.count) bytes: \(text)")
            run.discard()
        }
        let session = "{\"id\":\"\(id)\", }"
        let sessionText = prefix + "] ,\"readingSessions\":[" + session + "]}"
        let run = try ManifestStager.stage(ManifestDataInput(Data(sessionText.utf8)), options: scratch.options)
        defer { run.discard() }
        var stored = Data()
        try run.readPayload(of: "readingSessions", seq: 0) { stored.append($0) }
        #expect(try run.manifest().readingSessions?.count == 1)
        #expect(stored.range(of: Data("\"workID\"".utf8)) != nil)
        #expect(stored.range(of: Data("\"startedAt\"".utf8)) != nil)
        #expect((try JSONSerialization.jsonObject(with: stored) as? [String: Any]) != nil)
        #expect(stored.count < 180)
    }

    @Test func nonAdjacentDuplicateRemovalsAreSpilledInOrder() throws {
        let scratch = Scratch()
        let value = "[" + Array(repeating: "{\"a\":1,\"a\":2}", count: 1000).joined(separator: ",") + "]"
        var tokenizer = ManifestTokenizer(input: ManifestDataInput(Data(value.utf8)))
        tokenizer.removalBatchSize = 32
        let spool = ManifestRemovalSpool(directory: scratch.url, batchSize: 32)
        var largestBatch = 0
        tokenizer.onRemovalBatch = { batch in
            largestBatch = max(largestBatch, batch.count)
            try spool.append(batch)
        }
        _ = try tokenizer.skipValue()
        try spool.append(tokenizer.takeRemovals())
        var previous = -1
        var count = 0
        try spool.forEachRange { cut in
            #expect(cut.lowerBound > previous)
            previous = cut.lowerBound
            count += 1
        }
        #expect(count == 1000)
        #expect(largestBatch == 32)
        #expect(spool.peakBufferedCount <= 32)
        try spool.discard()
    }

    @Test func deferredLossyRecordStreamsNonAdjacentFirstWinsCuts() throws {
        let scratch = Scratch()
        var options = scratch.options
        options.typedRecordBudget = 64
        let ignored = Array(repeating: "{\"a\":1,\"a\":2}", count: 5000).joined(separator: ",")
        let entry = "{\"name\":\"first\",\"name\":\"second\",\"modifiedAt\":\"2026-01-01T00:00:00Z\",\"data\":\"QUFB\",\"ignored\":[\(ignored)]}"
        let text = "{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"works\":[],\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"documents\":[\(entry)]}"
        let run = try ManifestStager.stage(ManifestDataInput(Data(text.utf8)), options: options)
        defer { run.discard() }
        #expect(try run.records(of: "documents").map(\.status) == [.deferred])
        var stored = Data()
        try run.readPayload(of: "documents", seq: 0) { stored.append($0) }
        #expect(stored.range(of: Data("\"name\":\"second\"".utf8)) == nil)
        #expect(stored.range(of: Data("\"a\":2".utf8)) == nil)
        #expect(try run.manifest().documents?.first?.name == "first")
        let files = try FileManager.default.contentsOfDirectory(atPath: run.db.directory.path)
        #expect(!files.contains(where: { $0.hasPrefix("cuts-") }))
    }

    @Test func deferredLossyRecordIsAChunkedSingletonBatchAndKeepsFirstValue() throws {
        let scratch = Scratch()
        var options = scratch.options
        options.typedRecordBudget = 64
        let entry = "{\"name\":\"first\",\"name\":\"second\",\"modifiedAt\":\"2026-01-01T00:00:00Z\",\"data\":\"\(String(repeating: "QUFB", count: 500))\"}"
        let text = "{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"works\":[],\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"documents\":[\(entry)]}"
        let run = try ManifestStager.stage(ManifestDataInput(Data(text.utf8)), options: options)
        defer { run.discard() }
        var batches: [[ManifestRecordMeta]] = []
        try run.forEachValidationBatch(of: "documents", maxBytes: 100) { batches.append($0) }
        #expect(batches.count == 1 && batches[0].count == 1 && batches[0][0].status == .deferred)
        var payload = Data()
        try run.readPayload(of: "documents", seq: 0) { payload.append($0) }
        #expect(payload.range(of: Data("\"name\":\"first\"".utf8)) != nil)
        #expect(payload.range(of: Data("second".utf8)) == nil)
    }

    @Test func wrongKindLossyValueObeysKnownRootByteLimit() throws {
        let scratch = Scratch()
        let file = scratch.url.appendingPathComponent("wrong-kind-lossy.json")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let writer = try FileHandle(forWritingTo: file)
        try writer.write(contentsOf: Data("{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"works\":[],\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"documents\":\"".utf8))
        let chunk = Data(repeating: 97, count: 1 << 20)
        for _ in 0 ..< 16 { try writer.write(contentsOf: chunk) }
        try writer.write(contentsOf: Data("\"}".utf8)); try writer.close()
        do {
            try ManifestStager.stage(ManifestFileInput(url: file), options: scratch.options).discard()
            Issue.record("known root value exceeded its source-byte limit")
        } catch ManifestStreamError.resourceExhausted { }
    }

    @Test func payloadRangeSeeksItsIndexedStartingChunk() throws {
        let scratch = Scratch()
        var options = scratch.options
        options.chunkSize = 16
        let text = "{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"works\":[],\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"documents\":[{\"name\":\"x\",\"modifiedAt\":\"2026-01-01T00:00:00Z\",\"data\":\"\(String(repeating: "QUFB", count: 100))\"}]}"
        options.typedRecordBudget = 64
        let run = try ManifestStager.stage(ManifestDataInput(Data(text.utf8)), options: options)
        defer { run.discard() }
        #expect(try run.payloadStartOffset(of: "documents", seq: 0, at: 210) == 208)
        var slice = Data()
        try run.readPayload(of: "documents", seq: 0, range: 210 ..< 230) { slice.append($0) }
        #expect(slice.count == 20)
        var empty = 0
        try run.readPayload(of: "documents", seq: 0, range: 210 ..< 210) { _ in empty += 1 }
        #expect(empty == 0)
    }

    @Test func recordPageClampsUntrustedPageLimit() throws {
        let scratch = Scratch()
        let works = (0 ..< 1001).map { "{\"id\":\"\(String(format: "%08d", $0 + 1))-0000-4000-8000-000000000001\",\"dateAdded\":\"2026-01-01T00:00:00Z\"}" }.joined(separator: ",")
        let text = "{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"works\":[\(works)]}"
        let run = try ManifestStager.stage(ManifestDataInput(Data(text.utf8)), options: scratch.options)
        defer { run.discard() }
        #expect(try run.recordPage(of: "works", limit: 5000).count == 1000)
        #expect(try run.recordPage(of: "works", after: 999, limit: 5000).count == 1)
    }

    @Test func fixtureVersionClassUsesSharedLabel() throws {
        let scratch = Scratch()
        let text = "{\"version\":9,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"works\":[]}"
        #expect(Self.outcomeName(Data(text.utf8), scratch.options) == "unsupportedVersion")
    }

    @Test func contractDocStatesObservedPrecedenceAndNewDiskBudget() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("docs/MANIFEST_CONTRACT.md"), encoding: .utf8)
        #expect(text.contains("truncated or garbage-tailed arrays are `notJSON`"))
        #expect(text.contains("syntax > root-type schema > resource exhaustion"))
        #expect(text.contains("2.5 × input bytes + 32 MiB"))
        #expect(!text.contains("Pending Android-owned fixture update"))
    }

    @Test func allRecordDefaultsUseOneCapturedClock() throws {
        let scratch = Scratch()
        let base = try Self.withMembers("\"round4Unknown\":0")
        var object = try #require(JSONSerialization.jsonObject(with: base) as? [String: Any])
        var works = try #require(object["works"] as? [[String: Any]])
        works[0].removeValue(forKey: "dateAdded")
        works = [works[0], works[0]]
        object["works"] = works
        let data = try JSONSerialization.data(withJSONObject: object)
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        var calls = 0
        var options = scratch.options
        options.clock = { calls += 1; return fixed }
        let run = try ManifestStager.stage(ManifestDataInput(data), options: options)
        defer { run.discard() }
        #expect(calls == 1)
        #expect(try run.manifest().works.map(\.dateAdded) == [fixed, fixed])
    }

    @Test func fileGenerationChangeFailsBeforeRereadAndPublishesNothing() throws {
        let scratch = Scratch()
        let data = try Self.withMembers("\"sourceCheck\":0")
        let file = scratch.url.appendingPathComponent("mutable.json")
        try data.write(to: file)
        let input = try ManifestFileInput(url: file)
        var changed = data
        let marker = try #require(changed.range(of: Data("sourceCheck".utf8)))
        changed.replaceSubrange(marker, with: Data("changedName".utf8)) // same byte length
        try changed.write(to: file, options: .atomic)
        #expect(throws: ManifestStreamError.io("source changed during staging")) {
            try ManifestStager.stage(input, options: scratch.options)
        }
        try data.write(to: file, options: .atomic)
        let duringRead = HookedInput(try ManifestFileInput(url: file), onRead: { n in
            if n == 3 { try? changed.write(to: file, options: .atomic) }
        })
        #expect(throws: ManifestStreamError.io("source changed during staging")) {
            try ManifestStager.stage(duringRead, options: scratch.options)
        }
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func failedKeyRereadAcrossInputWindowIsIO() throws {
        let scratch = Scratch()
        let file = scratch.url.appendingPathComponent("cross-window.json")
        let prefix = "{\"version\":8,\"exportedAt\":\"2026-06-01T00:00:00Z\",\"works\":[],\"bookmarks\":[],\"fonts\":[],\"settings\":{},\"pad\":\""
        let count = manifestWindowSize - 4 - prefix.utf8.count - 2
        let bytes = Data((prefix + String(repeating: "a", count: count) + "\",\"crossKey\":1}").utf8)
        try bytes.write(to: file)
        let input = HookedInput(try ManifestFileInput(url: file))
        input.onRange = { range in
            if range.lowerBound < manifestWindowSize && range.upperBound > manifestWindowSize {
                try? bytes.write(to: file, options: .atomic)
            }
        }
        do {
            try ManifestStager.stage(input, options: scratch.options).discard()
            Issue.record("changed source was accepted")
        } catch ManifestStreamError.io { }
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func stagingComponentBudgetIsEnforcedDespitePlentyOfFreeSpace() throws {
        let scratch = Scratch()
        #expect(scratch.options.diskFactor == 2.5 && scratch.options.diskFloor == 32 << 20)
        var options = scratch.options
        options.availableCapacity = { _ in 1 << 40 }
        options.diskFactor = 0
        options.diskFloor = 1
        let data = try Self.withMembers("\"budget\":0")
        guard case .resourceExhausted = try Self.stagedFailure(data, options) else {
            Issue.record("staging exceeded its component budget"); return
        }
        #expect(scratch.leftovers.isEmpty)
    }

    /// Delegates to a real input and lets a test act on the Nth read or window.
    nonisolated final class HookedInput: ManifestInput {
        let inner: ManifestInput
        let onWindow: (Int) -> Void
        let onRead: (Int) -> Void
        var onRange: ((Range<Int>) -> Void)?
        var windows = 0, reads = 0
        var failureMessage: String?
        var length: Int { inner.length }
        var failure: String? { failureMessage ?? inner.failure }
        init(_ inner: ManifestInput, onWindow: @escaping (Int) -> Void = { _ in }, onRead: @escaping (Int) -> Void = { _ in }) {
            self.inner = inner; self.onWindow = onWindow; self.onRead = onRead
        }
        func window(at offset: Int) -> UnsafeRawBufferPointer {
            windows += 1; onWindow(windows)
            return failureMessage == nil ? inner.window(at: offset) : UnsafeRawBufferPointer(start: nil, count: 0)
        }
        func read(_ range: Range<Int>) -> Data { reads += 1; onRead(reads); onRange?(range); return inner.read(range) }
        func checkSource() -> Bool { failure == nil && inner.checkSource() }
    }

    @Test func cancellationStopsPromptlyAndLeavesNothing() async throws {
        let scratch = Scratch()
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let data = try #require(corpus["gen:works"])
        let options = scratch.options
        // Cancel from inside the 40th record read: deterministic, no sleeping.
        let result = await Task.detached { () -> ManifestStreamError? in
            let input = HookedInput(ManifestDataInput(data), onRead: { n in
                if n == 40 { withUnsafeCurrentTask { $0?.cancel() } }
            })
            do { _ = try ManifestStager.stage(input, options: options); return nil } catch { return error as? ManifestStreamError }
        }.value
        #expect(result == .cancelled)
        #expect(scratch.leftovers.isEmpty)

        // Inside one huge string value (no record boundary): still observed, at the next 1 MiB window.
        let file = scratch.url.appendingPathComponent("huge-string.json")
        try Data(("{\"x\":\"" + String(repeating: "a", count: 6 << 20) + "\"}").utf8).write(to: file)
        let windowResult = await Task.detached { () -> ManifestStreamError? in
            let input = HookedInput(try! ManifestFileInput(url: file), onWindow: { n in
                if n == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            })
            do { _ = try ManifestStager.stage(input, options: options); return nil } catch { return error as? ManifestStreamError }
        }.value
        #expect(windowResult == .cancelled)
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func ioFailureIsReportedAsIOAndLeavesNothing() throws {
        let scratch = Scratch()
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let data = try #require(corpus["gen:works"])
        let input = HookedInput(ManifestDataInput(data), onRead: { _ in })
        input.failureMessage = "injected read error" // the source reports a failed read, then looks like EOF
        #expect(throws: ManifestStreamError.io("injected read error")) { try ManifestStager.stage(input, options: scratch.options) }
        #expect(scratch.leftovers.isEmpty)
        // A missing file is also I/O, not an invalid document.
        #expect(throws: ManifestStreamError.self) { try ManifestFileInput(url: scratch.url.appendingPathComponent("nope.json")) }
        // A file that shrank under us (shorter than its stat said) is I/O, not "truncated JSON".
        let file = scratch.url.appendingPathComponent("short.json")
        try data.write(to: file)
        let real = try ManifestFileInput(url: file)
        try Data(data.prefix(1000)).write(to: file)
        #expect(throws: ManifestStreamError.io("file shorter than expected")) { try ManifestStager.stage(real, options: scratch.options) }
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func lowDiskIsResourceExhaustionBeforeAnythingIsCreated() throws {
        let scratch = Scratch()
        var options = scratch.options
        options.availableCapacity = { _ in 1 << 20 }
        let corpus = Dictionary(uniqueKeysWithValues: try ManifestParserDifferentialTests.corpus())
        let data = try #require(corpus["gen:works"])
        do {
            _ = try ManifestStager.stage(ManifestDataInput(data), options: options)
            Issue.record("expected resource exhaustion")
        } catch let ManifestStreamError.resourceExhausted(message) {
            #expect(message.contains("free"))
        }
        #expect(scratch.leftovers.isEmpty)
        // Enough room: the preflight does not get in the way.
        options.availableCapacity = { _ in 1 << 40 }
        try ManifestStager.stage(ManifestDataInput(data), options: options).discard()
        #expect(scratch.leftovers.isEmpty)
    }

    @Test func staleStagingDirectoriesAreSwept() throws {
        let scratch = Scratch()
        let stale = scratch.options.parentDirectory.appendingPathComponent("run-stale", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -7200)], ofItemAtPath: stale.path)
        let fresh = scratch.options.parentDirectory.appendingPathComponent("run-fresh", isDirectory: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        ManifestStager.removeStale(in: scratch.options.parentDirectory)
        #expect(scratch.leftovers == ["run-fresh"])
    }
}
}

private extension ManifestStagedRun {
    func use<T>(_ body: (ManifestStagedRun) throws -> T) rethrows -> T { defer { discard() }; return try body(self) }
}

extension ManifestStagedRun {
    /// Test convenience over the bounded API: every row of a section.
    func records(of section: String) throws -> [ManifestRecordMeta] {
        var out: [ManifestRecordMeta] = []
        try forEachRecordMeta(of: section, pageSize: 7) { out.append($0) }
        return out
    }

    func forEachChunk(of owner: String, seq: Int, _ body: (Data) throws -> Void) throws {
        try readPayload(of: owner, seq: seq, into: body)
    }
}
