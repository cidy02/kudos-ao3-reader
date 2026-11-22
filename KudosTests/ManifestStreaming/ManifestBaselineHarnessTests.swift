import Foundation
import SwiftData
import XCTest
@testable import Kudos

/// T-567 P1 baseline (opt-in, iOS simulator): drives today's real entry points on generated manifests and records
/// process footprint (before / peak / after), wall time by stage, and temp-disk high-water. One warm-up run, then
/// `KUDOS_T567_RUNS` measured runs. Results are JSON lines in `$KUDOS_T567_OUT/ios-baseline.jsonl`.
/// Production behaviour is unchanged; a failing entry point is an outcome, not a test failure.
@MainActor
final class ManifestBaselineHarnessTests: XCTestCase {
    private final class Ctx {
        var container: ModelContainer?
        var dir: URL
        var folder: URL?
        var defaults = T567Store.defaults()
        var retained: Any?
        init(dir: URL) { self.dir = dir }
        var context: ModelContext { container!.mainContext }
    }

    private typealias Operation = (Ctx, T567Fixtures.FixtureSet, T567Stages) async throws -> String

    private struct Entry {
        let name: String
        /// Setup that must not be measured (populating a store, building a sync folder, retaining a preview).
        let setup: (Ctx, T567Fixtures.FixtureSet) async throws -> Void
        let operation: Operation
    }

    private let fm = FileManager.default

    override func setUp() async throws {
        try XCTSkipUnless(T567Config.enabled, "T-567 P1 harness is opt-in: set TEST_RUNNER_KUDOS_T567_P1=1")
    }

    // MARK: Setup helpers

    private func freshStore(_ ctx: Ctx) throws {
        ctx.container = try T567Store.container(in: ctx.dir.appendingPathComponent("store"))
    }

    private func populate(_ ctx: Ctx, _ set: T567Fixtures.FixtureSet) throws {
        try freshStore(ctx)
        let contents = try KudosBackupContents.read(from: set.zipURL)
        _ = try KudosBackupService.restore(contents, into: ctx.context, defaults: ctx.defaults, mode: .merge)
    }

    private func syncFolder(_ ctx: Ctx, with set: T567Fixtures.FixtureSet, liveManifest: Bool, bak: Bool = false) throws {
        let folder = ctx.dir.appendingPathComponent("folder")
        let payload = folder.appendingPathComponent(FolderSyncService.syncDirectoryName)
        try fm.createDirectory(at: payload.appendingPathComponent("Works"), withIntermediateDirectories: true)
        for id in set.output.epubWorkIDs {
            try ManifestFixtureGenerator.dummyEPUB(for: id)
                .write(to: payload.appendingPathComponent("Works/\(id.uuidString).epub"))
        }
        let live = payload.appendingPathComponent(FolderSyncService.manifestFileName)
        if liveManifest {
            if bak {
                // Cut short, as an interrupted Android in-place write leaves it; the full copy sits beside it.
                try fm.copyItem(at: set.manifestURL, to: live)
                let handle = try FileHandle(forWritingTo: live)
                try handle.truncate(atOffset: UInt64(set.output.bytes / 2))
                try handle.close()
                try fm.copyItem(
                    at: set.manifestURL,
                    to: payload.appendingPathComponent(FolderSyncService.manifestBackupFileName)
                )
            } else {
                try fm.copyItem(at: set.manifestURL, to: live)
            }
        }
        ctx.folder = folder
        try FolderSyncService.connect(to: folder, defaults: ctx.defaults)
    }

    private func entries() -> [Entry] {
        [
            Entry(name: "preview_zip", setup: { _, _ in }, operation: { _, set, st in
                let m = try KudosBackupContents.preConfirmManifest(from: set.zipURL)
                st.mark("preConfirmManifest")
                _ = try KudosBackupContents.sourceIdentity(of: set.zipURL, manifest: m)
                st.mark("sourceIdentity")
                return "works=\(m.works.count)"
            }),
            Entry(name: "preview_dir", setup: { _, _ in }, operation: { _, set, st in
                let m = try KudosBackupContents.preConfirmManifest(from: set.directoryURL)
                st.mark("preConfirmManifest")
                return "works=\(m.works.count)"
            }),
            restoreEntry("restore_merge", .merge),
            restoreEntry("restore_reconcile", .reconcile),
            restoreEntry("restore_replace_empty", .replaceLibrary),
            Entry(name: "replace_safety_export", setup: { ctx, set in try self.populate(ctx, set) }, operation: { ctx, _, st in
                // SettingsBackupPage.makePreReplaceBackup, minus the SwiftUI @Query fetches (done here once).
                let fetched = try self.fetchAll(ctx.context)
                st.mark("fetch")
                let contents = try KudosBackupService.makeContents(
                    works: fetched.works, bookmarks: fetched.bookmarks, fonts: [], collections: [],
                    readingQueues: [], annotations: [], savedSearches: [],
                    readingSessions: fetched.sessions, readingFavorites: [], fandomReadWatermarks: [],
                    followedTags: [], tagAliases: [], tombstones: fetched.tombstones, defaults: ctx.defaults
                )
                st.mark("makeContents")
                let staged = ctx.dir.appendingPathComponent("staged.kudosbackup")
                try contents.zipData().write(to: staged, options: .atomic)
                st.mark("zipData+write")
                return "works=\(contents.manifest.works.count)"
            }),
            Entry(name: "manual_export", setup: { ctx, set in try self.populate(ctx, set) }, operation: { ctx, _, st in
                let fetched = try self.fetchAll(ctx.context)
                st.mark("fetch")
                let plan = try KudosBackupService.makeExportPlan(
                    works: fetched.works, bookmarks: fetched.bookmarks, fonts: [], readingQueues: [],
                    readingSessions: fetched.sessions, tombstones: fetched.tombstones, defaults: ctx.defaults
                )
                st.mark("makeExportPlan")
                let skipped = try KudosBackupService.writeArchive(plan, to: ctx.dir.appendingPathComponent("export.kudosbackup"))
                st.mark("writeArchive")
                return "assets=\(plan.assets.count) skipped=\(skipped.count)"
            }),
            Entry(name: "sync_down_live", setup: { ctx, set in
                try self.freshStore(ctx)
                try self.syncFolder(ctx, with: set, liveManifest: true)
            }, operation: { ctx, _, st in
                let r = try await FolderSyncService.syncDown(in: ctx.context, defaults: ctx.defaults)
                st.mark("syncDown")
                return "didRead=\(r.didReadRemoteFile)"
            }),
            Entry(name: "sync_down_bak", setup: { ctx, set in
                try self.freshStore(ctx)
                try self.syncFolder(ctx, with: set, liveManifest: true, bak: true)
            }, operation: { ctx, _, st in
                let r = try await FolderSyncService.syncDown(in: ctx.context, defaults: ctx.defaults)
                st.mark("syncDown")
                return "didRead=\(r.didReadRemoteFile)"
            }),
            Entry(name: "sync_down_legacy", setup: { ctx, set in
                try self.freshStore(ctx)
                try self.syncFolder(ctx, with: set, liveManifest: false)
                try self.fm.copyItem(
                    at: set.directoryURL,
                    to: ctx.folder!.appendingPathComponent(FolderSyncService.legacySyncFileName)
                )
            }, operation: { ctx, _, st in
                let r = try await FolderSyncService.syncDown(in: ctx.context, defaults: ctx.defaults)
                st.mark("syncDown")
                return "didRead=\(r.didReadRemoteFile)"
            }),
            Entry(name: "sync_conflict_fold", setup: { ctx, _ in try self.freshStore(ctx) }, operation: { ctx, set, st in
                // NSFileVersion conflict discovery needs iCloud and cannot be built locally; this is the part after
                // discovery: decode the conflicting manifest, then fold it as a sync restore.
                let manifest = try KudosBackupContents.decodeManifest(Data(contentsOf: set.manifestURL, options: .mappedIfSafe))
                st.mark("decodeManifest")
                let r = try FolderSyncService.foldConflictContents(
                    [KudosBackupContents(manifest: manifest)], into: ctx.context, defaults: ctx.defaults
                )
                st.mark("foldConflictContents")
                return "folded=\(r.foldedConflicts)"
            }),
            Entry(name: "sync_up_populated", setup: { ctx, set in
                try self.populate(ctx, set)
                try self.syncFolder(ctx, with: set, liveManifest: false)
                try? self.fm.removeItem(at: ctx.folder!.appendingPathComponent(FolderSyncService.syncDirectoryName))
            }, operation: { ctx, _, st in
                let r = try await FolderSyncService.syncUp(in: ctx.context, defaults: ctx.defaults)
                st.mark("syncUp(syncNow)")
                return "wrote=\(r.didWriteRemoteFile)"
            }),
            Entry(name: "sync_now_prune", setup: { ctx, set in
                try self.populate(ctx, set)
                try self.syncFolder(ctx, with: set, liveManifest: false)
                try? self.fm.removeItem(at: ctx.folder!.appendingPathComponent(FolderSyncService.syncDirectoryName))
                _ = try await FolderSyncService.syncNow(in: ctx.context, defaults: ctx.defaults)
                // Orphans this device did not list, plus a local edit so the upload is not skipped.
                let works = ctx.folder!.appendingPathComponent("\(FolderSyncService.syncDirectoryName)/Works")
                for i in 0 ..< 20 { try Data("orphan \(i)".utf8).write(to: works.appendingPathComponent("\(UUID().uuidString).epub")) }
                if let work = try ctx.context.fetch(FetchDescriptor<SavedWork>()).first {
                    work.title += " edited"
                    work.markModified()
                    try ctx.context.save()
                }
            }, operation: { ctx, _, st in
                let r = try await FolderSyncService.syncNow(in: ctx.context, defaults: ctx.defaults)
                st.mark("syncNow")
                return "wrote=\(r.didWriteRemoteFile)"
            })
        ]
    }

    private func restoreEntry(_ name: String, _ mode: BackupImportMode) -> Entry {
        Entry(name: name, setup: { ctx, set in
            try self.freshStore(ctx)
            // The Settings preview manifest is retained while the confirm sheet is open; so is it here.
            ctx.retained = try KudosBackupContents.preConfirmManifest(from: set.zipURL)
        }, operation: { ctx, set, st in
            let manifest = ctx.retained as? KudosBackupManifest
            let identity = try KudosBackupContents.sourceIdentity(of: set.zipURL, manifest: manifest)
            st.mark("sourceIdentity")
            let backup = try KudosBackupContents.readForConfirmedImport(
                from: set.zipURL, expectedIdentity: identity, manifest: manifest
            )
            st.mark("readForConfirmedImport")
            let s = try KudosBackupService.restore(backup, into: ctx.context, defaults: ctx.defaults, mode: mode)
            st.mark("restore")
            return "works=\(s.works) bookmarks=\(s.bookmarks)"
        })
    }

    private struct Fetched {
        let works: [SavedWork]
        let bookmarks: [Bookmark]
        let sessions: [ReadingSession]
        let tombstones: [SyncTombstone]
    }

    private func fetchAll(_ context: ModelContext) throws -> Fetched {
        Fetched(
            works: try context.fetch(FetchDescriptor<SavedWork>()),
            bookmarks: try context.fetch(FetchDescriptor<Bookmark>()),
            sessions: try context.fetch(FetchDescriptor<ReadingSession>()),
            tombstones: try context.fetch(FetchDescriptor<SyncTombstone>())
        )
    }

    // MARK: Measurement

    private func measure(
        _ entry: Entry, set: T567Fixtures.FixtureSet, axis: ManifestScaleAxis, mib: Double
    ) async {
        var attempts = 0
        for run in 0 ... T567Config.runs {
            let label = run == 0 ? "warmup" : "run\(run)"
            let base = fm.temporaryDirectory.appendingPathComponent("t567-\(UUID().uuidString)")
            let ctx = Ctx(dir: base)
            attempts += 1
            let meta: [String: Any] = [
                "entry": entry.name, "axis": axis.rawValue, "mib": mib, "run": label,
                "manifestBytes": set.output.bytes, "works": set.spec.works, "sessions": set.spec.sessions,
                "platform": "iOS Simulator (Debug build, host process)"
            ]
            do {
                try fm.createDirectory(at: base, withIntermediateDirectories: true)
                try await entry.setup(ctx, set)
                let roots = [fm.temporaryDirectory, base, Storage.worksDirectory]
                let before = T567Memory.settledFootprint()
                T567Recorder.append("ios-baseline.jsonl", meta.merging(["phase": "started", "beforeBytes": before]) { $1 })
                let sampler = T567Sampler(diskRoots: roots)
                let stages = T567Stages()
                sampler.start()
                let t0 = DispatchTime.now()
                var outcome = "ok"
                var note = ""
                do {
                    note = try await entry.operation(ctx, set, stages)
                } catch {
                    outcome = "error: \(error)"
                }
                let wall = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
                let heldAfter = T567Memory.footprint()
                let result = sampler.stop()
                ctx.retained = nil
                let after = T567Memory.settledFootprint()
                T567Recorder.append("ios-baseline.jsonl", meta.merging([
                    "phase": "finished", "outcome": outcome, "note": note,
                    "beforeBytes": before, "peakBytes": result.peakBytes, "afterHeldBytes": heldAfter,
                    "afterSettledBytes": after, "wallSeconds": wall,
                    "stages": stages.seconds.map { ["name": $0.0, "seconds": $0.1] },
                    "tmpDiskHighWaterBytes": result.diskHighWater
                ]) { $1 })
                if outcome != "ok" && run == 0 { cleanUp(ctx, set); break } // deterministic failure: skip the remaining runs
            } catch {
                T567Recorder.append("ios-baseline.jsonl", meta.merging(["phase": "finished", "outcome": "setup error: \(error)"]) { $1 })
                cleanUp(ctx, set)
                break
            }
            cleanUp(ctx, set)
        }
    }

    private func cleanUp(_ ctx: Ctx, _ set: T567Fixtures.FixtureSet) {
        FolderSyncService.disconnect(defaults: ctx.defaults)
        ctx.container = nil
        try? fm.removeItem(at: ctx.dir)
        T567Store.cleanInstalledFiles(epubIDs: set.output.epubWorkIDs, recoveryNames: T567Store.recoveryNames(set.spec))
    }

    func testBaseline() async throws {
        for axis in T567Config.axes {
            for mib in T567Config.sizes {
                let set = try T567Fixtures.ensure(axis: axis, mib: mib, defaults: T567Store.defaults())
                for entry in entries() where T567Config.wants(entry.name) {
                    await measure(entry, set: set, axis: axis, mib: mib)
                }
            }
        }
    }
}
