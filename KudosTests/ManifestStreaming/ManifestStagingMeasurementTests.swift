import Foundation
import XCTest
@testable import Kudos

/// T-567 P2 resources (opt-in, `TEST_RUNNER_KUDOS_T567_P2=1`; sizes/axes/out as in P1: `_SIZES`, `_AXES`, `_OUT`, `_RUNS`):
/// the production stager over P1's generated fixtures, with P1's thresholds asserted: peak footprint above the
/// pre-run baseline <= 64 MiB, growth 128 -> 512 MiB <= 8 MiB, 512 MiB run <= 5x the 128 MiB run, no staging left
/// behind. Also a 96 MiB opaque value (deferred, chunked) and cancellation latency on it.
/// Results: `$KUDOS_T567_OUT/ios-staging.jsonl`. Simulator, Debug build, host process: not a device result.
@MainActor
final class ManifestStagingMeasurementTests: XCTestCase {
    private let fm = FileManager.default
    private let miB = 1_048_576.0

    override func setUp() async throws {
        try XCTSkipUnless(T567Config.env["KUDOS_T567_P2"] == "1", "T-567 P2 harness is opt-in: set TEST_RUNNER_KUDOS_T567_P2=1")
    }

    private func parent() -> URL { fm.temporaryDirectory.appendingPathComponent("p2-staging-\(UUID().uuidString)", isDirectory: true) }

    func testStagingOnFixtures() async throws {
        for axis in T567Config.axes {
            var peaks: [Double: Double] = [:], walls: [Double: Double] = [:]
            for mib in T567Config.sizes {
                let set = try T567Fixtures.ensure(axis: axis, mib: mib, defaults: T567Store.defaults())
                let range = storedFirstEntryRange(of: set.zipURL)
                let parentDirectory = parent()
                defer { try? fm.removeItem(at: parentDirectory) }
                var options = ManifestStagingOptions()
                options.parentDirectory = parentDirectory
                let meta: [String: Any] = ["kind": "stage", "axis": axis.rawValue, "mib": mib, "manifestBytes": set.output.bytes,
                                           "platform": "iOS Simulator (Debug build, host process)"]
                T567Recorder.append("ios-staging.jsonl", meta.merging(["phase": "started"]) { $1 })
                // Warm-up (a fresh process pays for first-use heap growth), then the measured run.
                for run in 0 ... 1 {
                    let input = try ManifestFileInput(url: set.zipURL, range: range)
                    let before = T567Memory.settledFootprint()
                    let sampler = T567Sampler(diskRoots: [parentDirectory])
                    sampler.start()
                    let t0 = DispatchTime.now()
                    var outcome = "ok", records = 0, deferred = 0, dbBytes = 0, wall = 0.0
                    var sampled: (peakBytes: Int, diskHighWater: Int, timeline: [(t: Double, bytes: Int)])?
                    do {
                        let staged = try ManifestStager.stage(input, options: options)
                        records = try staged.db.scalar("SELECT sum(count) FROM member")
                        deferred = try ManifestSectionSpec.all.reduce(0) { $0 + (try staged.db.scalar("SELECT count(*) FROM \($1.table) WHERE status = 2")) }
                        dbBytes = T567Sampler.diskUse([parentDirectory])
                        wall = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
                        sampled = sampler.stop()
                        // Outside the measured window: materialising the whole manifest is the oracle, not the product.
                        if mib <= 8 { XCTAssertEqual(try staged.manifest(), try KudosBackupContents.decodeManifest(Data(contentsOf: set.manifestURL))) }
                        staged.discard()
                    } catch { outcome = "error: \(error)" }
                    if sampled == nil { wall = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9; sampled = sampler.stop() }
                    let r = sampled!
                    let above = Double(r.peakBytes - before) / miB
                    let leftovers = (try? fm.contentsOfDirectory(atPath: parentDirectory.path))?.count ?? 0
                    T567Recorder.append("ios-staging.jsonl", meta.merging([
                        "phase": "finished", "run": run == 0 ? "warmup" : "measured", "outcome": outcome, "records": records, "deferred": deferred,
                        "wallSeconds": wall, "beforeBytes": before, "peakBytes": r.peakBytes, "peakAboveBeforeMiB": above,
                        "peakAtSeconds": r.timeline.max(by: { $0.bytes < $1.bytes })?.t ?? 0, "stagingDiskBytes": dbBytes, "stagingDiskHighWaterBytes": r.diskHighWater, "leftoverDirs": leftovers
                    ]) { $1 })
                    XCTAssertEqual(outcome, "ok")
                    XCTAssertEqual(leftovers, 0)
                    if run == 1 { peaks[mib] = above; walls[mib] = wall }
                    // The cold figure is the first operation in a fresh process; the thresholds apply to it too.
                    XCTAssertLessThan(above, 64, "peak above baseline \(above) MiB (axis \(axis), \(mib) MiB, run \(run))")
                }
            }
            if let p128 = peaks[128], let p512 = peaks[512], let w128 = walls[128], let w512 = walls[512] {
                T567Recorder.append("ios-staging.jsonl", ["kind": "thresholds", "axis": axis.rawValue, "growth128to512MiB": p512 - p128, "wallRatio": w512 / w128])
                XCTAssertLessThanOrEqual(p512 - p128, 8)
                XCTAssertLessThanOrEqual(w512 / w128, 5)
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
        var body = try Data(contentsOf: small)
        while let last = body.last, last == 0x0A || last == 0x20 { body.removeLast() }
        body.removeLast()
        try h.write(contentsOf: body)
        try h.write(contentsOf: Data(",\n\"documents\" : [{\"modifiedAt\":\"2026-01-01T00:00:00.000Z\",\"name\":\"opaque/big.bin\",\"data\":\"".utf8))
        let chunk = ManifestFixtureGenerator.randomData(count: 3 * 1_048_576, seed: 1).base64EncodedData()
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
        let parentDirectory = parent()
        defer { try? fm.removeItem(at: parentDirectory) }
        var options = ManifestStagingOptions()
        options.parentDirectory = parentDirectory
        let before = T567Memory.settledFootprint()
        let sampler = T567Sampler(diskRoots: [parentDirectory])
        sampler.start()
        let t0 = DispatchTime.now()
        let staged = try ManifestStager.stage(try ManifestFileInput(url: url), options: options)
        let wall = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
        let documents = try staged.records(of: "documents")
        var chunks = 0, chunkBytes = 0
        try staged.forEachChunk(of: "documents", seq: 0) { chunks += 1; chunkBytes += $0.count }
        let r = sampler.stop()
        T567Recorder.append("ios-staging.jsonl", [
            "kind": "large-value-96MiB-decoded", "fileBytes": bytes, "statuses": documents.map(\.status.rawValue), "chunks": chunks,
            "chunkBytes": chunkBytes, "wallSeconds": wall, "peakAboveBeforeMiB": Double(r.peakBytes - before) / miB,
            "stagingDiskHighWaterBytes": r.diskHighWater, "platform": "iOS Simulator (Debug build, host process)"
        ])
        XCTAssertEqual(documents.map(\.status), [.deferred])
        XCTAssertLessThan(Double(r.peakBytes - before) / miB, 64)
        staged.discard()

        // Cancellation: cancel 150 ms in; time to quiescence, then nothing left behind.
        let task = Task.detached { () -> Double in
            let t = DispatchTime.now()
            do { _ = try ManifestStager.stage(try ManifestFileInput(url: url), options: options) } catch {}
            return Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e9
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        let cancelAt = DispatchTime.now()
        task.cancel()
        _ = await task.value
        let latency = Double(DispatchTime.now().uptimeNanoseconds - cancelAt.uptimeNanoseconds) / 1e9
        let leftovers = (try? fm.contentsOfDirectory(atPath: parentDirectory.path))?.count ?? 0
        T567Recorder.append("ios-staging.jsonl", ["kind": "cancellation", "latencySeconds": latency, "limitSeconds": 1.0, "leftoverDirs": leftovers])
        XCTAssertLessThan(latency, 1.0)
        XCTAssertEqual(leftovers, 0)
    }
}
