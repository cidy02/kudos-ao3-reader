import Darwin
import Foundation
import SwiftData
import XCTest
@testable import Kudos

/// T-567 P1 measurement plumbing (test target only). Everything here is opt-in via environment variables, which
/// `xcodebuild` forwards to the simulator test process when they are prefixed `TEST_RUNNER_`:
///
/// - `KUDOS_T567_P1=1`            enables the XCTest baseline / store / parser harnesses (they `XCTSkip` otherwise)
/// - `KUDOS_T567_SIZES=8,32,128`  manifest sizes in MiB (default `8`)
/// - `KUDOS_T567_AXES=works,...`  `works`, `sessions`, `opaque` (default `works`)
/// - `KUDOS_T567_ENTRIES=a,b`     entry-point filter (default: all)
/// - `KUDOS_T567_RUNS=3`          measured runs (a warm-up always runs first and is recorded as `warmup`)
/// - `KUDOS_T567_OUT=<dir>`       where `*.jsonl` results are appended (default: the test's temporary directory)
struct T567Config {
    static let env = ProcessInfo.processInfo.environment
    static var enabled: Bool { env["KUDOS_T567_P1"] == "1" }
    static var sizes: [Double] { list("KUDOS_T567_SIZES", default: "8").compactMap(Double.init) }
    static var axes: [ManifestScaleAxis] { list("KUDOS_T567_AXES", default: "works").compactMap(ManifestScaleAxis.init) }
    static var entries: Set<String>? {
        let e = list("KUDOS_T567_ENTRIES", default: "")
        return e.isEmpty ? nil : Set(e)
    }
    static var runs: Int { Int(env["KUDOS_T567_RUNS"] ?? "") ?? 3 }
    static var outDir: URL {
        URL(fileURLWithPath: env["KUDOS_T567_OUT"] ?? NSTemporaryDirectory(), isDirectory: true)
    }
    static func list(_ key: String, default value: String) -> [String] {
        (env[key] ?? value).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    static func wants(_ entry: String) -> Bool { entries.map { $0.contains(entry) } ?? true }
}

enum T567Memory {
    /// `phys_footprint`: the number the system's memory limit (jetsam) is measured against.
    static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// Footprint after asking malloc to return freed pages, so "after" reflects what is really still held.
    static func settledFootprint() -> Int {
        malloc_zone_pressure_relief(nil, 0)
        usleep(150_000)
        malloc_zone_pressure_relief(nil, 0)
        return footprint()
    }
}

/// Samples `phys_footprint` (and, more slowly, disk use under `roots`) on a background queue while an operation runs.
final class T567Sampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "t567.sampler", qos: .userInteractive)
    private var memoryTimer: DispatchSourceTimer?
    private var diskTimer: DispatchSourceTimer?
    private let lock = NSLock()
    private var peak = 0
    private var timeline: [(t: Double, bytes: Int)] = []
    private var diskPeak = 0
    private let started = DispatchTime.now()
    let roots: [URL]
    private let diskBaseline: Int

    init(diskRoots: [URL]) {
        roots = diskRoots
        diskBaseline = Self.diskUse(diskRoots)
    }

    func start(memoryInterval: Double = 0.01, diskInterval: Double = 0.25) {
        let m = DispatchSource.makeTimerSource(queue: queue)
        m.schedule(deadline: .now(), repeating: memoryInterval)
        m.setEventHandler { [weak self] in
            guard let self else { return }
            let f = T567Memory.footprint()
            let t = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
            lock.lock()
            peak = max(peak, f)
            if timeline.count < 20_000 { timeline.append((t, f)) }
            lock.unlock()
        }
        m.resume()
        memoryTimer = m
        let d = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "t567.disk", qos: .utility))
        d.schedule(deadline: .now(), repeating: diskInterval)
        d.setEventHandler { [weak self] in
            guard let self else { return }
            let use = Self.diskUse(roots)
            lock.lock()
            diskPeak = max(diskPeak, use)
            lock.unlock()
        }
        d.resume()
        diskTimer = d
    }

    /// Stops sampling. `peakBytes` is the largest footprint seen; `diskHighWater` is the largest extra disk use.
    func stop() -> (peakBytes: Int, diskHighWater: Int, timeline: [(t: Double, bytes: Int)]) {
        memoryTimer?.cancel()
        diskTimer?.cancel()
        let finalDisk = Self.diskUse(roots)
        lock.lock()
        defer { lock.unlock() }
        peak = max(peak, T567Memory.footprint())
        diskPeak = max(diskPeak, finalDisk)
        return (peak, max(0, diskPeak - diskBaseline), timeline)
    }

    static func diskUse(_ roots: [URL]) -> Int {
        var total = 0
        let fm = FileManager.default
        for root in roots {
            guard let walker = fm.enumerator(
                at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                options: []
            ) else { continue }
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
                if values?.isRegularFile == true { total += values?.totalFileAllocatedSize ?? 0 }
            }
        }
        return total
    }
}

/// Wall time by stage.
final class T567Stages {
    private(set) var seconds: [(String, Double)] = []
    private var last = DispatchTime.now()
    func mark(_ name: String) {
        let now = DispatchTime.now()
        seconds.append((name, Double(now.uptimeNanoseconds - last.uptimeNanoseconds) / 1e9))
        last = now
    }
}

/// Appends one JSON object per line. A `started` line is written before each case, so a crash or kill (which no
/// test can catch) shows up as a `started` with no matching `finished`.
enum T567Recorder {
    static func append(_ file: String, _ object: [String: Any]) {
        let dir = T567Config.outDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(file)
        if let line = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
            print("T567JSON \(file) " + String(decoding: line, as: UTF8.self)) // so a device run's results are in the test log
        }
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

/// Cached on-disk fixtures under Caches (not tmp, so the disk high-water of a run does not count them).
@MainActor
enum T567Fixtures {
    static let root: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("t567p1-fixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    struct FixtureSet {
        let output: ManifestFixtureGenerator.Output
        let zipURL: URL
        let directoryURL: URL
        var manifestURL: URL { output.manifestURL }
        var spec: ManifestFixtureSpec { output.spec }
    }

    static func name(_ axis: ManifestScaleAxis, _ mib: Double) -> String { "\(axis.rawValue)-\(mib)" }

    static func ensure(axis: ManifestScaleAxis, mib: Double, defaults: UserDefaults) throws -> FixtureSet {
        let dir = root.appendingPathComponent(name(axis, mib), isDirectory: true)
        let manifestURL = dir.appendingPathComponent("manifest.json")
        let zipURL = dir.appendingPathComponent("backup.kudosbackup")
        let legacy = dir.appendingPathComponent("legacy.kudosbackup", isDirectory: true)
        let spec = try ManifestFixtureGenerator.calibrated(axis: axis, mib: mib)
        let ids = (0 ..< spec.works).map { ManifestFixtureGenerator.workID($0, seed: spec.seed) }
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("DONE").path) {
            let bytes = (try? fm.attributesOfItem(atPath: manifestURL.path)[.size] as? Int) ?? 0
            let out = ManifestFixtureGenerator.Output(
                manifestURL: manifestURL, bytes: bytes, spec: spec, workIDs: ids,
                epubWorkIDs: Array(ids.prefix(spec.epubWorks))
            )
            return FixtureSet(output: out, zipURL: zipURL, directoryURL: legacy)
        }
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = try ManifestFixtureGenerator.write(spec, to: manifestURL, defaults: defaults)
        try ManifestFixtureGenerator.writeArchive(out, to: zipURL)
        // Legacy directory package: manifest.json + Works/ (APFS clone, no extra space until written).
        try fm.createDirectory(at: legacy.appendingPathComponent("Works"), withIntermediateDirectories: true)
        try fm.copyItem(at: manifestURL, to: legacy.appendingPathComponent("manifest.json"))
        for id in out.epubWorkIDs {
            try ManifestFixtureGenerator.dummyEPUB(for: id)
                .write(to: legacy.appendingPathComponent("Works/\(id.uuidString).epub"))
        }
        try Data().write(to: dir.appendingPathComponent("DONE"))
        T567Recorder.append("fixtures.jsonl", [
            "fixture": name(axis, mib), "dirBytes": T567Sampler.diskUse([dir]), "rootBytes": T567Sampler.diskUse([root])
        ])
        return FixtureSet(output: out, zipURL: zipURL, directoryURL: legacy)
    }
}

/// The production schema (`MyApp.sharedModelContainer`), on a throwaway on-disk store (an in-memory SQLite store
/// would count its pages as process memory).
enum T567Store {
    static func container(in dir: URL) throws -> ModelContainer {
        let schema = Schema([
            SavedWork.self, Tag.self, Bookmark.self, CustomFont.self,
            WorkCollection.self, ReadingQueue.self, ReadingQueueMembership.self,
            SavedSearch.self, QueueSavedSearchLink.self, SyncTombstone.self, ReadingAnnotation.self,
            ReadingSession.self, ReadingFavorite.self, FandomReadWatermark.self, FollowedTag.self,
            TagAlias.self, SavedSeries.self
        ])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: schema, url: dir.appendingPathComponent("store.sqlite"))
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func defaults() -> UserDefaults {
        let name = "T567.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Deletes what a restore installs outside the store: EPUBs for `ids` and the recovery copies in the manifest.
    @MainActor
    static func cleanInstalledFiles(epubIDs: [UUID], recoveryNames: [String]) {
        let fm = FileManager.default
        for id in epubIDs {
            try? fm.removeItem(at: Storage.workAssetURL(
                identifier: Storage.defaultEPUBAssetIdentifier(for: id), fallbackID: id
            ))
        }
        for name in recoveryNames {
            try? fm.removeItem(at: WritingTextRecovery.defaultDirectory.appendingPathComponent(name))
        }
    }

    static func recoveryNames(_ spec: ManifestFixtureSpec) -> [String] {
        let n = spec.recoveryCopies + (spec.bigRecoveryChars > 0 ? 1 : 0)
        return (0 ..< n).map { ManifestFixtureGenerator.recoveryFileName($0, seed: spec.seed) }
    }
}

/// `KUDOS_T567_PURGE=1`: deletes every generated fixture (a device run must leave nothing in the app sandbox) and
/// records how much storage they held.
@MainActor
final class T567FixturePurgeTests: XCTestCase {
    func testPurgeFixtures() throws {
        try XCTSkipUnless(T567Config.enabled && T567Config.env["KUDOS_T567_PURGE"] == "1", "opt-in")
        let held = T567Sampler.diskUse([T567Fixtures.root])
        try? FileManager.default.removeItem(at: T567Fixtures.root)
        T567Recorder.append("fixtures.jsonl", ["purged": true, "heldBytesBeforePurge": held])
    }
}
