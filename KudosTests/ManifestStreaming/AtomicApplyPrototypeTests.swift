import Darwin
import Foundation
import SwiftData
import XCTest
@testable import Kudos

/// T-567 P1b, part A (always runs, small stores): the journaled swap survives a kill at every step, and what a
/// ModelContainer teardown/reopen does in-process. Results of the facts test: `$KUDOS_T567_OUT/ios-p1b.jsonl`.
@MainActor
final class AtomicApplyPrototypeTests: XCTestCase {
    private let fm = FileManager.default
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("t567b-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: tmp) }

    // MARK: fixtures for the swap tests

    private enum Generation: Equatable { case old, new, mixed(String) }

    private func write(_ text: String, _ url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// Old generation: 50 rows (author Local) + EPUBs w1,w2,w3 = "old". Staged generation: the same store grown by 70
    /// rows (author New) through the bounded batch apply + EPUBs w1,w2,w4 = "new" (w3 is removed).
    private func build(_ swap: StoreSwapPrototype) throws {
        try BatchApply.populateExisting({ try T567Store.container(in: swap.live) }, rows: 50)
        try StoreSQLite.checkpoint(swap.liveStore)
        for name in ["w1", "w2", "w3"] { try write("old", swap.live.appendingPathComponent("Works/\(name).epub")) }
        try fm.createDirectory(at: swap.staging, withIntermediateDirectories: true)
        try fm.copyItem(at: swap.liveStore, to: swap.stagingStore)
        try BatchApply.upsert(
            container: { try T567Store.container(in: swap.staging) }, incoming: 70, existing: 0, batch: 25,
            recycle: .freshContainer, author: "New"
        )
        try StoreSQLite.checkpoint(swap.stagingStore)
        for name in ["w1", "w2", "w4"] { try write("new", swap.staging.appendingPathComponent("Works/\(name).epub")) }
    }

    private var journal: StoreSwapPrototype.Journal {
        .init(
            displacedWorks: ["w1.epub", "w2.epub", "w3.epub"], newWorks: ["w1.epub", "w2.epub", "w4.epub"],
            stagedStoreBytes: 0
        )
    }

    /// Opens the live store the way the app would and reads which generation it is, including the EPUBs.
    private func generation(_ swap: StoreSwapPrototype) throws -> Generation {
        var rows = 0
        var authors = Set<String>()
        try autoreleasepool {
            let container = try T567Store.container(in: swap.live)
            let context = ModelContext(container)
            let all = try context.fetch(FetchDescriptor<SavedWork>())
            rows = all.count
            authors = Set(all.map(\.author))
        }
        let works = (try? fm.contentsOfDirectory(atPath: swap.live.appendingPathComponent("Works").path)) ?? []
        var epubs: [String: String] = [:]
        for name in works {
            epubs[name] = (try? String(contentsOf: swap.live.appendingPathComponent("Works/\(name)"), encoding: .utf8)) ?? "?"
        }
        let oldEPUBs = ["w1.epub": "old", "w2.epub": "old", "w3.epub": "old"]
        let newEPUBs = ["w1.epub": "new", "w2.epub": "new", "w4.epub": "new"]
        if rows == 50, authors == ["Local"], epubs == oldEPUBs { return .old }
        if rows == 120, authors == ["Local", "New"], epubs == newEPUBs { return .new }
        return .mixed("rows=\(rows) authors=\(authors.sorted()) epubs=\(epubs.sorted { $0.key < $1.key })")
    }

    private func assertClean(_ swap: StoreSwapPrototype, file: StaticString = #filePath, line: UInt = #line) {
        for url in [swap.staging, swap.old, swap.journalURL, swap.root.appendingPathComponent("journal.json.tmp")] {
            XCTAssertFalse(fm.fileExists(atPath: url.path), "left behind: \(url.lastPathComponent)", file: file, line: line)
        }
    }

    // MARK: tests

    /// A kill after every durable step of the publish: recovery must end with exactly the old or exactly the new
    /// store (EPUBs included). Before the journal's atomic appearance the answer is old, after it new.
    func testSwapSurvivesKillAtEveryStep() throws {
        let probe = StoreSwapPrototype(root: tmp.appendingPathComponent("probe"))
        try build(probe)
        try probe.publish(journal)
        let total = probe.ticks
        XCTAssertEqual(try generation(probe), .new)
        XCTAssertGreaterThan(total, 10)
        var outcomes: [String] = []

        for k in 0 ... total {
            let swap = StoreSwapPrototype(root: tmp.appendingPathComponent("k\(k)"))
            try build(swap)
            if k == 0 {
                // Staging complete, the commit never happened (a leftover temp journal must not count).
                try write("{", swap.root.appendingPathComponent("journal.json.tmp"))
            } else {
                swap.crashAfter = k
                XCTAssertThrowsError(try swap.publish(journal)) { XCTAssertTrue($0 is StoreSwapPrototype.SimulatedCrash) }
            }
            // Restart: recovery runs before any container opens.
            try StoreSwapPrototype(root: swap.root).recover()
            if k > 0 { XCTAssertFalse(fm.fileExists(atPath: swap.liveStore.path + "-wal"), "k=\(k): stale wal beside the store") }
            assertClean(swap)
            let got = try generation(swap)
            XCTAssertEqual(got, k == 0 ? .old : .new, "k=\(k)")
            outcomes.append("\(k):\(got)")
            try? fm.removeItem(at: swap.root)
        }
        T567Recorder.append("ios-p1b.jsonl", ["entry": "swap_kill_matrix", "ticksPerPublish": total, "outcomes": outcomes])
    }

    /// A kill inside recovery itself, at every step, followed by another recovery.
    func testRecoveryIsRestartable() throws {
        let probe = StoreSwapPrototype(root: tmp.appendingPathComponent("probe"))
        try build(probe)
        try probe.publish(journal)
        let total = probe.ticks
        for k in [1, 3, 5] {
            for j in 1 ... total {
                let swap = StoreSwapPrototype(root: tmp.appendingPathComponent("k\(k)j\(j)"))
                try build(swap)
                swap.crashAfter = k
                XCTAssertThrowsError(try swap.publish(journal))
                let first = StoreSwapPrototype(root: swap.root)
                first.crashAfter = j
                do { try first.recover() } catch is StoreSwapPrototype.SimulatedCrash {}
                try StoreSwapPrototype(root: swap.root).recover()
                assertClean(swap)
                XCTAssertEqual(try generation(swap), .new, "k=\(k) j=\(j)")
                try? fm.removeItem(at: swap.root)
            }
        }
    }

    /// Can an open container be torn down and reopened on swapped files in-process, and what does a holder that was
    /// not torn down see afterwards?
    func testContainerTeardownReopenAndStaleHolder() throws {
        let swap = StoreSwapPrototype(root: tmp.appendingPathComponent("td"))
        try build(swap)
        let needle = "td/live/store.sqlite"
        var facts: [String: Any] = ["entry": "container_teardown"]

        // 1. Does dropping the container release the file handles? (with and without touching mainContext)
        for touchMain in [false, true] {
            weak var weakContainer: ModelContainer?
            var openDuring = 0
            try autoreleasepool {
                let container = try T567Store.container(in: swap.live)
                weakContainer = container
                if touchMain { _ = container.mainContext.hasChanges }
                let context = ModelContext(container)
                _ = try context.fetchCount(FetchDescriptor<SavedWork>())
                openDuring = StoreSQLite.openPaths(containing: needle).count
            }
            facts["touchMain_\(touchMain)_openFilesWhileOpen"] = openDuring
            facts["touchMain_\(touchMain)_openFilesAfterDrop"] = StoreSQLite.openPaths(containing: needle).count
            facts["touchMain_\(touchMain)_containerDeallocated"] = weakContainer == nil
        }

        // 2. Stale holder: a container and context kept alive across the swap.
        let stale = try T567Store.container(in: swap.live)
        let staleContext = ModelContext(stale)
        facts["stale_countBeforeSwap"] = try staleContext.fetchCount(FetchDescriptor<SavedWork>())
        try swap.publish(journal) // the stale container is deliberately not closed
        facts["stale_countAfterSwapSameContext"] = (try? staleContext.fetchCount(FetchDescriptor<SavedWork>())) ?? -1
        let staleFresh = ModelContext(stale)
        facts["stale_countAfterSwapNewContextOnOldContainer"] = (try? staleFresh.fetchCount(FetchDescriptor<SavedWork>())) ?? -1
        staleFresh.insert(BatchApply.makeWork(id: UUID(), i: 999, author: "StaleWrite"))
        var staleSave = "ok"
        do { try staleFresh.save() } catch { staleSave = "error: \(error)" }
        facts["stale_writeResult"] = staleSave
        facts["stale_openFilesAfterSwap"] = StoreSQLite.openPaths(containing: "td/").map {
            $0.components(separatedBy: "/td/").last ?? $0
        }

        // 3. Reopen on the swapped files.
        let reopened = try T567Store.container(in: swap.live)
        let check = ModelContext(reopened)
        let rows = try check.fetch(FetchDescriptor<SavedWork>())
        facts["reopened_rows"] = rows.count
        facts["reopened_hasStaleWrite"] = rows.contains { $0.author == "StaleWrite" }
        T567Recorder.append("ios-p1b.jsonl", facts)
        // Finding, not a requirement: a stale holder is not reliably fenced off (see ios-p1b.jsonl), so the design
        // must make every holder drop its container before the swap rather than rely on the files moving.
        XCTAssertGreaterThanOrEqual(rows.count, 120)
    }
}
