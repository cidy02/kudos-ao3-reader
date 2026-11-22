import Foundation
import XCTest
@testable import Kudos

/// T-567 P1 parser prototype resources (opt-in, iOS simulator): buffered vs mapped-spool over the same scanner and
/// chunked-payload interface, on the generated fixtures, plus the large-value and cancellation checks.
/// Results: `$KUDOS_T567_OUT/ios-parser.jsonl`. ENOSPC injection is not done here (filling the host disk is not safe).
@MainActor
final class ManifestParserMeasurementTests: XCTestCase {
    private let fm = FileManager.default

    override func setUp() async throws {
        try XCTSkipUnless(T567Config.enabled, "T-567 P1 harness is opt-in: set TEST_RUNNER_KUDOS_T567_P1=1")
    }

    private enum Flavour: String, CaseIterable { case buffered, mappedSpool, mappedSpoolDropBehind }

    private func makeSource(_ f: Flavour, zip: URL, spool: URL) throws -> ManifestByteSource {
        let range = storedFirstEntryRange(of: zip)
        let direct = try BufferedFileSource(url: zip, range: range)
        switch f {
        case .buffered: return direct
        case .mappedSpool: return try MappedSpoolSource(copying: direct, to: spool)
        case .mappedSpoolDropBehind: return try MappedSpoolSource(copying: direct, to: spool, dropBehind: true)
        }
    }

    func testFlavoursOnFixtures() async throws {
        for axis in T567Config.axes {
            for mib in T567Config.sizes {
                let set = try T567Fixtures.ensure(axis: axis, mib: mib, defaults: T567Store.defaults())
                for flavour in Flavour.allCases where T567Config.wants(flavour.rawValue) {
                    for run in 0 ... T567Config.runs {
                        let spool = fm.temporaryDirectory.appendingPathComponent("spool-\(UUID().uuidString).json")
                        defer { try? fm.removeItem(at: spool) }
                        let label = run == 0 ? "warmup" : "run\(run)"
                        let meta: [String: Any] = [
                            "kind": "flavour", "flavour": flavour.rawValue, "axis": axis.rawValue, "mib": mib, "run": label,
                            "manifestBytes": set.output.bytes, "platform": "iOS Simulator (Debug build, host process)"
                        ]
                        T567Recorder.append("ios-parser.jsonl", meta.merging(["phase": "started"]) { $1 })
                        let before = T567Memory.settledFootprint()
                        let sampler = T567Sampler(diskRoots: [fm.temporaryDirectory])
                        sampler.start()
                        let t0 = DispatchTime.now()
                        var outcome = "ok", records = 0, deferred = 0, spoolSeconds = 0.0
                        do {
                            let source = try makeSource(flavour, zip: set.zipURL, spool: spool)
                            spoolSeconds = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
                            let reader = try StreamingManifestReader(source: source)
                            (records, deferred) = try reader.walkAll()
                        } catch { outcome = "error: \(error)" }
                        let wall = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
                        let held = T567Memory.footprint()
                        let r = sampler.stop()
                        T567Recorder.append("ios-parser.jsonl", meta.merging([
                            "phase": "finished", "outcome": outcome, "records": records, "deferred": deferred,
                            "wallSeconds": wall, "spoolSeconds": spoolSeconds, "beforeBytes": before, "peakBytes": r.peakBytes,
                            "peakAboveBeforeBytes": r.peakBytes - before, "heldAtEndBytes": held,
                            "spoolDiskHighWaterBytes": r.diskHighWater
                        ]) { $1 })
                    }
                }
            }
        }
    }

    /// A manifest whose `documents` holds one opaque value of `valueBytes` (decoded), streamed to disk as base64.
    private func writeBigValueManifest(valueBytes: Int, to url: URL) throws -> Int {
        fm.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        let spec = try ManifestFixtureGenerator.calibrated(axis: .works, mib: 0.1)
        let small = fm.temporaryDirectory.appendingPathComponent("small-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: small) }
        _ = try ManifestFixtureGenerator.write(spec, to: small, defaults: T567Store.defaults())
        // Splice: the small manifest minus its closing brace, plus a `documents` member.
        var body = try Data(contentsOf: small)
        while let last = body.last, last == 0x0A || last == 0x20 { body.removeLast() }
        body.removeLast() // "}"
        try h.write(contentsOf: body)
        try h.write(contentsOf: Data(",\n\"documents\" : [{\"modifiedAt\":\"2026-01-01T00:00:00.000Z\",\"name\":\"opaque/big.bin\",\"data\":\"".utf8))
        let chunk = ManifestFixtureGenerator.randomData(count: 3 * 1_048_576, seed: 1).base64EncodedData() // 3 MiB -> 4 MiB
        var written = 0
        while written < valueBytes {
            try h.write(contentsOf: chunk)
            written += 3 * 1_048_576
        }
        try h.write(contentsOf: Data("\"}]}\n".utf8))
        return Int(try h.offset())
    }

    func testLargeOpaqueValueAndCancellation() async throws {
        let url = fm.temporaryDirectory.appendingPathComponent("big-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: url) }
        let bytes = try writeBigValueManifest(valueBytes: 96 * 1_048_576, to: url)
        let before = T567Memory.settledFootprint()
        let sampler = T567Sampler(diskRoots: [])
        sampler.start()
        let source = try BufferedFileSource(url: url)
        let reader = try StreamingManifestReader(source: source)
        let (records, deferred) = try reader.walkAll()
        // Chunked-payload view of the value: hash-free byte count, 64 KiB at a time.
        var chunked = 0
        if let m = reader.members["documents"] {
            try ManifestScanner.elementRanges(of: m.range, in: source) { r in
                source.forEachChunk(of: r) { chunked += $0.count }
            }
        }
        let r = sampler.stop()
        T567Recorder.append("ios-parser.jsonl", [
            "kind": "large-value-96MiB-decoded", "fileBytes": bytes, "records": records, "deferredNotTypedDecoded": deferred,
            "chunkedBytesVisited": chunked, "peakAboveBeforeBytes": r.peakBytes - before,
            "platform": "iOS Simulator (Debug build, host process)"
        ])
        XCTAssertEqual(deferred, 1)

        // Cancellation: cancel one second into a walk of the same file; time to quiescence.
        let task = Task.detached { () -> Double in
            let s = try BufferedFileSource(url: url)
            let t0 = DispatchTime.now()
            do { _ = try StreamingManifestReader(source: s).walkAll() } catch {}
            return Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        let cancelAt = DispatchTime.now()
        task.cancel()
        _ = try await task.value
        let latency = Double(DispatchTime.now().uptimeNanoseconds - cancelAt.uptimeNanoseconds) / 1e9
        T567Recorder.append("ios-parser.jsonl", ["kind": "cancellation", "latencySeconds": latency, "limitSeconds": 1.0])
        XCTAssertLessThan(latency, 1.0)
    }
}
