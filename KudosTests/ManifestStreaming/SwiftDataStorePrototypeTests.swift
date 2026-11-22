import Foundation
import SwiftData
import XCTest
@testable import Kudos

/// T-567 P1 store prototype (opt-in, iOS simulator): does SwiftData retain dirty models in proportion to rows until
/// `KudosBackupService.restore`'s single save? Runs on the production schema, an on-disk store, autosave disabled by
/// restore itself. The decoded manifest is resident the whole time (it is today's design), so the number to read is
/// `peakAboveDecodedBytes` — model + SQLite growth above "manifest decoded, nothing restored yet".
///
/// `KUDOS_T567_STORE_ROWS` (default: the `KUDOS_T567_SIZES` fixtures) selects the row counts; `KUDOS_T567_ENTRIES`
/// filters `replace_*` and `control_*`. Results: `$KUDOS_T567_OUT/ios-store.jsonl`.
@MainActor
final class SwiftDataStorePrototypeTests: XCTestCase {
    private let fm = FileManager.default

    override func setUp() async throws {
        try XCTSkipUnless(T567Config.enabled, "T-567 P1 harness is opt-in: set TEST_RUNNER_KUDOS_T567_P1=1")
    }

    private func fixtureSets() throws -> [T567Fixtures.FixtureSet] {
        try T567Config.sizes.map { try T567Fixtures.ensure(axis: .works, mib: $0, defaults: T567Store.defaults()) }
    }

    /// Existing rows: unique IDs (not in the backup) saved in batches through a throwaway context, plus
    /// `sharedWithBackup` rows that share an ID with the backup and own an EPUB on disk (so Replace displaces them).
    private func populateDestination(_ container: ModelContainer, rows: Int, shared: [UUID]) throws {
        var done = 0
        while done < rows {
            try autoreleasepool {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                for i in done ..< min(rows, done + 2_000) {
                    let work = SavedWork(
                        id: ManifestFixtureGenerator.uuid(9, i, seed: 1),
                        title: "Existing \(i)", author: "Local", summary: ManifestFixtureGenerator.text(count: 400, seed: UInt64(i))
                    )
                    context.insert(work)
                }
                try context.save()
                done = min(rows, done + 2_000)
            }
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        for id in shared {
            let work = SavedWork(id: id, title: "Local copy", author: "Local")
            work.hasEPUB = true
            context.insert(work)
            try fm.createDirectory(at: work.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("local epub".utf8).write(to: work.fileURL)
        }
        try context.save()
    }

    private func downsample(_ t: [(t: Double, bytes: Int)], to n: Int = 40) -> [[Double]] {
        guard !t.isEmpty else { return [] }
        let step = max(1, t.count / n)
        return stride(from: 0, to: t.count, by: step).map { [t[$0].t, Double(t[$0].bytes) / 1_048_576] }
    }

    func testReplaceDirtyModelRetention() async throws {
        for set in try fixtureSets() {
            for dest in ["empty", "populated"] {
                for assets in ["noassets", "assets"] {
                    let name = "replace_\(dest)_\(assets)"
                    guard T567Config.wants(name) else { continue }
                    for run in 0 ... T567Config.runs {
                        try await replaceCase(name: name, set: set, populated: dest == "populated", withAssets: assets == "assets", run: run)
                    }
                }
            }
        }
    }

    private func replaceCase(
        name: String, set: T567Fixtures.FixtureSet, populated: Bool, withAssets: Bool, run: Int
    ) async throws {
        let dir = fm.temporaryDirectory.appendingPathComponent("t567s-\(UUID().uuidString)")
        defer {
            try? fm.removeItem(at: dir)
            T567Store.cleanInstalledFiles(epubIDs: set.output.epubWorkIDs, recoveryNames: T567Store.recoveryNames(set.spec))
        }
        var container: ModelContainer? = try T567Store.container(in: dir.appendingPathComponent("store"))
        let defaults = T567Store.defaults()
        if populated {
            try populateDestination(container!, rows: set.spec.works, shared: withAssets ? set.output.epubWorkIDs : [])
        }
        let label = run == 0 ? "warmup" : "run\(run)"
        let meta: [String: Any] = [
            "entry": name, "mib": Double(set.spec.targetBytes) / 1_048_576, "run": label, "incomingWorks": set.spec.works,
            "existingRows": populated ? set.spec.works : 0, "manifestBytes": set.output.bytes,
            "platform": "iOS Simulator (Debug build, host process)"
        ]
        T567Recorder.append("ios-store.jsonl", meta.merging(["phase": "started"]) { $1 })

        // Decoded contents are resident, as in Settings (preview manifest + confirmed re-read).
        var contents: KudosBackupContents? = withAssets
            ? try KudosBackupContents.read(from: set.zipURL)
            : KudosBackupContents(manifest: try KudosBackupContents.decodeManifest(Data(contentsOf: set.manifestURL, options: .mappedIfSafe)))
        let context = container!.mainContext
        let decoded = T567Memory.settledFootprint()
        let sampler = T567Sampler(diskRoots: [dir, Storage.worksDirectory])
        sampler.start(memoryInterval: 0.005)
        let t0 = DispatchTime.now()
        var outcome = "ok"
        var summary = ""
        do {
            let s = try KudosBackupService.restore(contents!, into: context, defaults: defaults, mode: .replaceLibrary)
            summary = "works=\(s.works) bookmarks=\(s.bookmarks)"
        } catch {
            outcome = "error: \(error)"
        }
        let wall = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
        let heldAfter = T567Memory.footprint()
        let result = sampler.stop()
        // Exact final state: counts through a fresh context.
        let check = ModelContext(container!)
        let live = (try? check.fetchCount(FetchDescriptor<SavedWork>(predicate: #Predicate { $0.isDeleted == false }))) ?? -1
        let all = (try? check.fetchCount(FetchDescriptor<SavedWork>())) ?? -1
        contents = nil
        let afterReleaseContents = T567Memory.settledFootprint()
        container = nil
        let afterContainerGone = T567Memory.settledFootprint()
        T567Recorder.append("ios-store.jsonl", meta.merging([
            "phase": "finished", "outcome": outcome, "summary": summary, "wallSeconds": wall,
            "decodedBytes": decoded, "peakBytes": result.peakBytes,
            "peakAboveDecodedBytes": result.peakBytes - decoded,
            "heldAfterRestoreBytes": heldAfter, "afterContentsReleasedBytes": afterReleaseContents,
            "afterContainerReleasedBytes": afterContainerGone,
            "liveWorksAfter": live, "allWorksAfter": all,
            "diskHighWaterBytes": result.diskHighWater,
            "footprintTimelineMiB": downsample(result.timeline)
        ]) { $1 })
    }

    /// Control, no restore code involved: insert N production-schema works with autosave off, one `save()` at the end,
    /// versus saving every 500 without keeping the models. Footprint is recorded at each 10% of the rows.
    func testControlInsertSeries() throws {
        for set in try fixtureSets() {
            for variant in ["single_save", "batched_500"] {
                let name = "control_\(variant)"
                guard T567Config.wants(name) else { continue }
                let dir = fm.temporaryDirectory.appendingPathComponent("t567c-\(UUID().uuidString)")
                defer { try? fm.removeItem(at: dir) }
                var container: ModelContainer? = try T567Store.container(in: dir.appendingPathComponent("store"))
                let rows = set.spec.works
                let start = T567Memory.settledFootprint()
                var series: [[Double]] = []
                let sampler = T567Sampler(diskRoots: [dir])
                sampler.start(memoryInterval: 0.005)
                let t0 = DispatchTime.now()
                var context: ModelContext? = ModelContext(container!)
                context!.autosaveEnabled = false
                for i in 0 ..< rows {
                    autoreleasepool {
                        let work = SavedWork(
                            id: ManifestFixtureGenerator.uuid(8, i, seed: 1), title: "Row \(i)", author: "A",
                            summary: ManifestFixtureGenerator.text(count: 400, seed: UInt64(i))
                        )
                        work.workTags = (0 ..< 8).map { "tag \(($0 * 13 + i) % 1_999)" }
                        context!.insert(work)
                    }
                    if variant == "batched_500", (i + 1) % 500 == 0 {
                        try? context!.save()
                        context = ModelContext(container!)
                        context!.autosaveEnabled = false
                    }
                    if (i + 1) % max(1, rows / 10) == 0 {
                        series.append([Double(i + 1), Double(T567Memory.footprint() - start) / 1_048_576])
                    }
                }
                let beforeSave = T567Memory.footprint()
                try context!.save()
                let afterSave = T567Memory.footprint()
                context = nil
                let afterContextGone = T567Memory.settledFootprint()
                let result = sampler.stop()
                let wall = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000_000
                container = nil
                T567Recorder.append("ios-store.jsonl", [
                    "entry": name, "phase": "finished", "run": "run1", "mib": Double(set.spec.targetBytes) / 1_048_576,
                    "rows": rows, "startBytes": start, "peakBytes": result.peakBytes,
                    "beforeSaveBytes": beforeSave, "afterSaveBytes": afterSave, "afterContextReleasedBytes": afterContextGone,
                    "wallSeconds": wall, "seriesRowsAndMiBAboveStart": series,
                    "platform": "iOS Simulator (Debug build, host process)"
                ])
            }
        }
    }
}
