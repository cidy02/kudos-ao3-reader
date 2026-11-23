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
        options.typedRecordBudget = 300 // most records exceed it: stored deferred, decoded later by whoever reads them
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
        #expect(try unknown.memberNames().contains("zzUnknown"))
        #expect(try unknown.db.scalar("SELECT count(*) FROM payload WHERE owner = 'zzUnknown'") == 0)
    }

    @Test func oversizedValuesAreStoredInBoundedChunks() throws {
        let scratch = Scratch()
        var options = scratch.options
        options.chunkSize = 1024
        options.typedRecordBudget = 2048
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

    @Test func nestingLimitMatchesTodaysRouteAtTheBoundary() throws {
        let scratch = Scratch()
        for depth in 508 ... 516 {
            let data = Data(("{\"version\":8,\"x\":" + String(repeating: "[", count: depth) + String(repeating: "]", count: depth) + "}").utf8)
            let today = todaysOutcome(data).label
            let staged = try Self.stagedOutcome(ManifestDataInput(data), scratch.options).label
            #expect(today == staged, "depth \(depth): today \(today) staged \(staged)")
        }
        for depth in 509 ... 515 { // the same boundary with a top-level array (JSON, but not a manifest: schema)
            let data = Data((String(repeating: "[", count: depth) + String(repeating: "]", count: depth)).utf8)
            let today = todaysOutcome(data).label
            let staged = try Self.stagedOutcome(ManifestDataInput(data), scratch.options).label
            #expect(today == staged, "root array depth \(depth): today \(today) staged \(staged)")
        }
        let deep = Data(("{\"x\":" + String(repeating: "[", count: 600) + String(repeating: "]", count: 600) + "}").utf8)
        #expect(throws: ManifestStreamError.invalidDocument(.notJSON)) { try ManifestStager.stage(ManifestDataInput(deep), options: scratch.options) }
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

    // MARK: Resource limits (shared with Android)

    @Test func resourceLimitsAreResourceExhaustionAndAtTheLimitIsAccepted() throws {
        let scratch = Scratch()
        func stage(_ text: String) throws -> ManifestStreamError? {
            do { try ManifestStager.stage(ManifestDataInput(Data(text.utf8)), options: scratch.options).discard(); return nil } catch { return error as? ManifestStreamError }
        }
        let key = ManifestLimits.maxKeyChars, number = ManifestLimits.maxNumberChars
        // At the limit: a schema failure (not a manifest), never a resource one. One over: resource exhaustion.
        #expect(try stage("{\"\(String(repeating: "k", count: key))\":1}") == .invalidDocument(.schema))
        guard case .resourceExhausted = try stage("{\"\(String(repeating: "k", count: key + 1))\":1}") else { Issue.record("key"); return }
        #expect(try stage("{\"x\":\(String(repeating: "1", count: number))}") == .invalidDocument(.schema))
        guard case .resourceExhausted = try stage("{\"x\":\(String(repeating: "1", count: number + 1))}") else { Issue.record("number"); return }
        let keys = ManifestLimits.maxRootKeys
        func object(_ n: Int) -> String { "{" + (0 ..< n).map { "\"k\($0)\":1" }.joined(separator: ",") + "}" }
        #expect(try stage(object(keys)) == .invalidDocument(.schema))
        guard case .resourceExhausted = try stage(object(keys + 1)) else { Issue.record("keys"); return }
        let big = ManifestLimits.maxRootValueChars
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

    /// Delegates to a real input and lets a test act on the Nth read or window.
    nonisolated final class HookedInput: ManifestInput {
        let inner: ManifestInput
        let onWindow: (Int) -> Void
        let onRead: (Int) -> Void
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
        func read(_ range: Range<Int>) -> Data { reads += 1; onRead(reads); return inner.read(range) }
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
