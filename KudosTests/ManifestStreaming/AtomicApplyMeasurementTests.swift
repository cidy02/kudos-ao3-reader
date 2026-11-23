import Darwin
import Foundation
import SwiftData
import XCTest
@testable import Kudos

/// T-567 P1b part B (opt-in, `TEST_RUNNER_KUDOS_T567_P1=1`): bounded batch apply and the shadow-store swap at scale.
/// Row counts are the works-axis fixtures of 8/32/128/256/512 MiB. `KUDOS_T567_ENTRIES` filters variants
/// (`bb_<recycle>` for batches, `swap_scale` for the shadow store), `KUDOS_T567_P1B_AXES` = `incoming,existing`,
/// `KUDOS_T567_P1B_BATCH` (default 500), `KUDOS_T567_P1B_RECYCLE` (swap test, default `fresh_container`).
@MainActor
final class AtomicApplyMeasurementTests: XCTestCase {
    private let fm = FileManager.default
    private static let rowsForMiB: [Double: Int] = [8: 3_267, 32: 13_206, 128: 52_963, 256: 105_971, 512: 211_988]

    override func setUp() async throws {
        try XCTSkipUnless(T567Config.enabled, "T-567 P1 harness is opt-in: set TEST_RUNNER_KUDOS_T567_P1=1")
    }

    private var batch: Int { Int(T567Config.env["KUDOS_T567_P1B_BATCH"] ?? "") ?? 500 }
    private var axes: [String] { T567Config.list("KUDOS_T567_P1B_AXES", default: "incoming,existing") }

    private func mallocInUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }

    private func series(_ points: [(rows: Int, bytes: Int)], start: Int) -> [[Double]] {
        points.map { [Double($0.rows), Double($0.bytes - start) / 1_048_576] }
    }

    func testBoundedBatches() throws {
        for mib in T567Config.sizes {
            guard let n = Self.rowsForMiB[mib] else { continue }
            for recycle in BatchApply.Recycle.allCases {
                let name = "bb_\(recycle.rawValue)"
                guard T567Config.wants(name) else { continue }
                for axis in axes {
                    try runBatches(name: name, recycle: recycle, mib: mib, axis: axis, incoming: axis == "incoming" ? n : 13_206, existing: axis == "incoming" ? 0 : n)
                }
            }
        }
    }

    private func runBatches(name: String, recycle: BatchApply.Recycle, mib: Double, axis: String, incoming: Int, existing: Int) throws {
        let dir = fm.temporaryDirectory.appendingPathComponent("t567bb-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        let open = { try T567Store.container(in: dir) }
        let meta: [String: Any] = [
            "entry": name, "axis": axis, "mib": mib, "incoming": incoming, "existing": existing, "batch": batch,
            "platform": "iOS Simulator (Debug build, host process)"
        ]
        T567Recorder.append("ios-p1b.jsonl", meta.merging(["phase": "started"]) { $1 })
        if existing > 0 { try BatchApply.populateExisting(open, rows: existing) }
        // Warm: open and drop a container once so the start line includes SwiftData's fixed cost, not the rows'.
        try autoreleasepool { let c = try open(); _ = try ModelContext(c).fetchCount(FetchDescriptor<SavedWork>(predicate: #Predicate { $0.deletedAt != nil })) }
        let start = T567Memory.settledFootprint()
        let mallocStart = mallocInUse()
        let sampler = T567Sampler(diskRoots: [dir])
        sampler.start(memoryInterval: 0.005)
        var points: [(rows: Int, bytes: Int)] = []
        let step = max(1, incoming / 10)
        var nextMark = step
        let t0 = DispatchTime.now()
        var outcome = "ok"
        var batches = 0
        do {
            batches = try BatchApply.upsert(
                container: open, incoming: incoming, existing: existing, batch: batch, recycle: recycle,
                sweepExisting: existing > 0
            ) { done in
                if done >= nextMark { points.append((done, T567Memory.footprint())); nextMark += step }
            }
        } catch { outcome = "error: \(error)" }
        let wall = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
        let held = T567Memory.footprint()
        let mallocEnd = mallocInUse()
        let result = sampler.stop()
        let settled = T567Memory.settledFootprint()
        // Exact final rows through a fresh container.
        let updates = existing > 0 ? (0 ..< incoming).filter { $0 % 4 == 0 && $0 / 4 < existing }.count : 0
        var all = -1, live = -1
        try autoreleasepool {
            let context = ModelContext(try open())
            all = try context.fetchCount(FetchDescriptor<SavedWork>())
            live = try context.fetchCount(FetchDescriptor<SavedWork>(predicate: #Predicate { $0.deletedAt == nil }))
        }
        T567Recorder.append("ios-p1b.jsonl", meta.merging([
            "phase": "finished", "outcome": outcome, "batches": batches, "wallSeconds": wall, "startBytes": start,
            "peakBytes": result.peakBytes, "peakAboveStartBytes": result.peakBytes - start,
            "heldEndAboveStartBytes": held - start, "settledEndAboveStartBytes": settled - start,
            "mallocInUseStartBytes": mallocStart, "mallocInUseEndBytes": mallocEnd,
            "allRows": all, "liveRows": live, "expectedAll": existing + incoming - updates,
            "expectedLive": incoming + (existing > 0 ? updates : 0),
            "storeBytes": StoreSQLite.size(dir.appendingPathComponent("store.sqlite")),
            "diskHighWaterBytes": result.diskHighWater, "footprintAboveStartMiBAtEach10pct": series(points, start: start)
        ]) { $1 })
    }

    /// Shadow store + swap at scale: build live, checkpoint, clone, apply with the bounded path, checkpoint, check,
    /// publish by journal, reopen. Disk and time per stage; footprint over the whole thing.
    func testShadowStoreSwapAtScale() throws {
        for mib in T567Config.sizes {
            guard let n = Self.rowsForMiB[mib], T567Config.wants("swap_scale") else { continue }
            let recycle = BatchApply.Recycle(rawValue: T567Config.env["KUDOS_T567_P1B_RECYCLE"] ?? "") ?? .freshContainer
            let root = fm.temporaryDirectory.appendingPathComponent("t567sw-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: root) }
            let swap = StoreSwapPrototype(root: root)
            let meta: [String: Any] = ["entry": "swap_scale", "mib": mib, "existing": n, "incoming": n, "recycle": recycle.rawValue]
            T567Recorder.append("ios-p1b.jsonl", meta.merging(["phase": "started"]) { $1 })
            var times: [String: Double] = [:]
            var sizes: [String: Int] = [:]
            func timed<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
                let t = DispatchTime.now()
                defer { times[label] = Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e9 }
                return try body()
            }
            // 1. the live store (setup, not part of the swap cost)
            try BatchApply.populateExisting({ try T567Store.container(in: swap.live) }, rows: n)
            for i in 0 ..< 50 {
                try fm.createDirectory(at: swap.live.appendingPathComponent("Works"), withIntermediateDirectories: true)
                try Data("old".utf8).write(to: swap.live.appendingPathComponent("Works/e\(i).epub"))
            }
            try timed("checkpointLive") { try StoreSQLite.checkpoint(swap.liveStore) }
            sizes["liveStoreBytes"] = StoreSQLite.size(swap.liveStore)
            sizes["liveWalBytes"] = StoreSQLite.size(URL(fileURLWithPath: swap.liveStore.path + "-wal"))
            let baseMemory = T567Memory.settledFootprint()
            let sampler = T567Sampler(diskRoots: [root])
            sampler.start(memoryInterval: 0.005)
            // 2. staging copy: APFS clone, and for comparison a real byte copy
            try fm.createDirectory(at: swap.staging, withIntermediateDirectories: true)
            let diskBeforeClone = T567Sampler.diskUse([root])
            try timed("copyClone") { try fm.copyItem(at: swap.liveStore, to: swap.stagingStore) }
            sizes["diskAfterCloneExtraBytes"] = T567Sampler.diskUse([root]) - diskBeforeClone
            let byteCopy = swap.staging.appendingPathComponent("bytecopy.sqlite")
            try timed("copyBytes") { try StoreSQLite.byteCopy(swap.liveStore, byteCopy) }
            sizes["diskAfterByteCopyExtraBytes"] = T567Sampler.diskUse([root]) - diskBeforeClone
            try fm.removeItem(at: byteCopy)
            // 3. apply on the staging store
            let applyStart = T567Memory.footprint()
            try timed("applyToStaging") {
                try BatchApply.upsert(
                    container: { try T567Store.container(in: swap.staging) }, incoming: n, existing: n, batch: batch,
                    recycle: recycle, sweepExisting: true
                )
            }
            sizes["footprintAfterApplyAboveBaseBytes"] = T567Memory.footprint() - baseMemory
            _ = applyStart
            try timed("checkpointStaging") { try StoreSQLite.checkpoint(swap.stagingStore) }
            sizes["stagingStoreBytes"] = StoreSQLite.size(swap.stagingStore)
            let check = try timed("quickCheck") { try StoreSQLite.quickCheck(swap.stagingStore) }
            try timed("fsyncStaging") { StoreSQLite.fullSync(swap.stagingStore) }
            for i in 0 ..< 50 {
                try fm.createDirectory(at: swap.staging.appendingPathComponent("Works"), withIntermediateDirectories: true)
                try Data("new".utf8).write(to: swap.staging.appendingPathComponent("Works/e\(i).epub"))
            }
            // 4. publish by journal, 5. reopen on the new files
            let names = (0 ..< 50).map { "e\($0).epub" }
            try timed("publish") { try swap.publish(.init(displacedWorks: names, newWorks: names, stagedStoreBytes: sizes["stagingStoreBytes"] ?? 0)) }
            var liveRows = -1
            try timed("reopenAndCount") {
                try autoreleasepool {
                    let context = ModelContext(try T567Store.container(in: swap.live))
                    liveRows = try context.fetchCount(FetchDescriptor<SavedWork>())
                }
            }
            let result = sampler.stop()
            T567Recorder.append("ios-p1b.jsonl", meta.merging([
                "phase": "finished", "quickCheck": check, "liveRowsAfterSwap": liveRows, "expectedRows": 2 * n,
                "times": times, "sizes": sizes, "ticksPerPublish": swap.ticks,
                "peakFootprintAboveBaseBytes": result.peakBytes - baseMemory,
                "diskHighWaterAboveLiveBytes": result.diskHighWater,
                "diskHighWaterOverLiveStoreRatio": Double(result.diskHighWater) / Double(max(1, sizes["liveStoreBytes"] ?? 1)),
                "finalDiskBytes": T567Sampler.diskUse([root])
            ]) { $1 })
        }
    }
}
