import Foundation
import Testing
@testable import Kudos

/// E1 of docs/WRITING_EDITOR_ARCHITECTURE.md (T-262): checkpoints replace the
/// per-keystroke save, recovery writes happen off the main thread in order, and
/// pruning never reads a copy.
@MainActor
struct WritingCheckpointPolicyTests {
    @Test func checkpointsAfterTheIdleDelay() {
        let policy = WritingCheckpointPolicy()
        let start = ContinuousClock.now
        let lastEdit = start + .seconds(1)
        #expect(policy.deadline(lastEdit: lastEdit, firstPendingEdit: start)
            == lastEdit + .milliseconds(1500))
    }

    /// Continuous typing never lets the idle delay run out, so the first
    /// pending edit's deadline has to win.
    @Test func continuousTypingStillCheckpointsByTheMaximumInterval() {
        let policy = WritingCheckpointPolicy()
        let start = ContinuousClock.now
        #expect(policy.deadline(lastEdit: start + .milliseconds(19_900), firstPendingEdit: start)
            == start + .seconds(20))
    }

    @Test func theNumbersAreTheDocumentedOnes() {
        // docs/WRITING_EDITOR_ARCHITECTURE.md §8.1; Android uses the same.
        #expect(WritingCheckpointPolicy().idleDelay == .milliseconds(1500))
        #expect(WritingCheckpointPolicy().maxInterval == .seconds(20))
    }
}

@MainActor
struct WritingCheckpointSchedulerTests {
    private let quick = WritingCheckpointPolicy(idleDelay: .milliseconds(50), maxInterval: .seconds(5))

    /// Polls rather than sleeping a fixed time, so a slow machine only makes the
    /// test slower, not red.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let giveUp = clock.now + .seconds(3)
        while !condition(), clock.now < giveUp {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func firesOnceAfterTheIdleDelay() async throws {
        var fired = 0
        let scheduler = WritingCheckpointScheduler(policy: quick) { fired += 1 }
        scheduler.noteEdit()
        scheduler.noteEdit()
        #expect(fired == 0)
        try await waitUntil { fired > 0 }
        #expect(fired == 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(fired == 1)
        #expect(scheduler.checkpointCount == 1)
    }

    @Test func fireNowCheckpointsImmediatelyAndDropsThePendingTimer() async throws {
        var fired = 0
        let scheduler = WritingCheckpointScheduler(policy: quick) { fired += 1 }
        scheduler.noteEdit()
        scheduler.fireNow()
        #expect(fired == 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(fired == 1)
    }

    @Test func cancelStopsTheTimerWithoutCheckpointing() async throws {
        var fired = 0
        let scheduler = WritingCheckpointScheduler(policy: quick) { fired += 1 }
        scheduler.noteEdit()
        scheduler.cancel()
        try await Task.sleep(for: .milliseconds(200))
        #expect(fired == 0)
    }

    @Test func continuousEditsStillCheckpoint() async throws {
        var fired = 0
        let policy = WritingCheckpointPolicy(idleDelay: .milliseconds(200), maxInterval: .milliseconds(300))
        let scheduler = WritingCheckpointScheduler(policy: policy) { fired += 1 }
        let clock = ContinuousClock()
        let end = clock.now + .seconds(1)
        // An edit every 20 ms: the idle delay never runs out.
        while clock.now < end {
            scheduler.noteEdit()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fired >= 1)
    }
}

struct WritingWordCountTests {
    @Test func countsTheWordsBetweenTheTags() {
        #expect(WritingWordCount.count("<p>Hello <strong>brave</strong> world</p>\n<p>Again</p>") == 4)
        #expect(WritingWordCount.count("") == 0)
    }

    /// The point of `nonisolated`: the editor counts on a detached task.
    @Test func countsOffTheMainActor() async {
        let count = await Task.detached { WritingWordCount.count("<p>one two three</p>") }.value
        #expect(count == 3)
    }
}

struct WritingRecoveryWriterTests {
    private func makeStore() -> WritingTextRecovery {
        WritingTextRecovery(directory: URL.temporaryDirectory
            .appendingPathComponent("recovery-writer-\(UUID().uuidString)", isDirectory: true))
    }

    private func sessionURL(_ store: WritingTextRecovery, _ session: String) -> URL {
        store.fileURL(account: "writer", target: "work:7", field: "content")
            .deletingPathExtension()
            .appendingPathExtension(session)
            .appendingPathExtension("json")
    }

    @Test func writesTheTextAndTheOriginalsDigest() async throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let url = sessionURL(store, "s1")
        let writer = WritingRecoveryWriter(store: store, url: url, original: "before")
        #expect(try await writer.write("<p>after</p>", sequence: 1))
        let entry = try #require(try store.load(from: url))
        #expect(entry.text == "<p>after</p>")
        #expect(entry.originalDigest == WritingTextRecovery.digest("before"))
    }

    /// Two checkpoints' writes can reach the actor in either order; the newer
    /// one must be what stays on disk (§5.2 I5).
    @Test func anOlderCheckpointNeverReplacesANewerOne() async throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let url = sessionURL(store, "s1")
        let writer = WritingRecoveryWriter(store: store, url: url, original: "")
        #expect(try await writer.write("newer", sequence: 2))
        #expect(try await writer.write("older", sequence: 1) == false)
        #expect(try store.load(from: url)?.text == "newer")
    }

    @Test func aCorruptCopyIsSkippedNotFatal() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(text: "good one", original: "", to: sessionURL(store, "a"))
        try store.save(text: "good two", original: "", to: sessionURL(store, "b"))
        try Data("{ not json".utf8).write(to: sessionURL(store, "c"))
        let key = store.fileURL(account: "writer", target: "work:7", field: "content")
        #expect(Set(try store.copies(for: key).map(\.entry.text)) == ["good one", "good two"])
    }

    /// Pruning goes by modification date and never decodes, so an unreadable
    /// copy is pruned like any other instead of stopping pruning altogether.
    @Test func pruningKeepsTheNewestByDateWithoutReadingThem() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var urls: [URL] = []
        for index in 0 ..< 7 {
            let url = sessionURL(store, "session\(index)")
            // The second-oldest is unreadable.
            let data = index == 1 ? Data("garbage".utf8) : Data("{}".utf8)
            try data.write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: base.addingTimeInterval(Double(index) * 60)], ofItemAtPath: url.path
            )
            urls.append(url)
        }
        try store.prune(around: urls[6])
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: store.directory.path))
        #expect(left == Set(urls[2...6].map(\.lastPathComponent)))
    }

    /// The copy being written survives even when its date is not the newest
    /// (clock changes): it plus the four newest others.
    @Test func theCopyBeingWrittenAlwaysSurvives() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var urls: [URL] = []
        for index in 0 ..< 7 {
            let url = sessionURL(store, "session\(index)")
            try Data("{}".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: base.addingTimeInterval(Double(index) * 60)], ofItemAtPath: url.path
            )
            urls.append(url)
        }
        try store.prune(around: urls[0])
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: store.directory.path))
        #expect(left == Set(([urls[0]] + urls[3...6]).map(\.lastPathComponent)))
    }
}
