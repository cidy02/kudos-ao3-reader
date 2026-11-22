import Foundation
@testable import Kudos

/// T-567 P1: deterministic `manifest.json` fixtures at 8/32/128/256/512 MiB, written to disk by streaming
/// (the generator itself never holds the document). Test-target only; nothing here is wired into production.
///
/// Three axes scale one at a time, the others stay at the small `base`:
/// - `.works`    incoming rows (works + bookmarks, real `KudosBackupWork` records)
/// - `.sessions` reading sessions
/// - `.opaque`   large opaque values: `documents` (base64 `Data`) and `writingRecovery` text copies,
///               including one 20 MiB decoded recovery payload from 32 MiB up
/// Assets are small dummy EPUBs for the first `epubWorks` works (a fixed count; it is not a size axis).
///
/// Records are encoded with the production Codable types, so the JSON has the real shape. Layout and key order
/// follow `sortedKeys` like a real export (note `version` comes after the arrays).
enum ManifestScaleAxis: String, CaseIterable { case works, sessions, opaque }

struct ManifestFixtureSpec: Equatable {
    var axis: ManifestScaleAxis
    var targetBytes: Int
    var seed: UInt64 = 567
    // Fixed base.
    var baseWorks = 200
    var baseBookmarks = 100
    var baseSessions = 100
    var tombstones = 20
    var epubWorks = 50
    // Filled by `calibrated`.
    var works = 0
    var bookmarks = 0
    var sessions = 0
    var documents = 0
    var documentBytes = 192 * 1024
    var recoveryCopies = 0
    var recoveryCopyChars = 64 * 1024
    var bigRecoveryChars = 0

    static let miB = 1_048_576
    static let largeRecoveryChars = 20 * miB
}

@MainActor
enum ManifestFixtureGenerator {
    struct Output {
        let manifestURL: URL
        let bytes: Int
        let spec: ManifestFixtureSpec
        let workIDs: [UUID]
        let epubWorkIDs: [UUID]
    }

    static let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Deterministic randomness

    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func uuid(_ kind: UInt64, _ index: Int, seed: UInt64) -> UUID {
        var rng = SplitMix(state: seed &* 1_000_003 &+ kind &* 7_919 &+ UInt64(index))
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0 ..< 16 { bytes[i] = UInt8(truncatingIfNeeded: rng.next()) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func workID(_ index: Int, seed: UInt64) -> UUID { uuid(1, index, seed: seed) }

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,.;-\n".utf8)

    /// Deterministic prose-like text of exactly `count` ASCII characters (newlines escape to `\n` in JSON).
    static func text(count: Int, seed: UInt64) -> String {
        var rng = SplitMix(state: seed)
        var bytes = [UInt8](repeating: 0, count: count)
        var i = 0
        while i < count {
            var r = rng.next()
            for _ in 0 ..< 8 where i < count {
                bytes[i] = alphabet[Int(r & 0xFF) % alphabet.count]
                r >>= 8
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func randomData(count: Int, seed: UInt64) -> Data {
        var rng = SplitMix(state: seed)
        var bytes = [UInt8](repeating: 0, count: count)
        var i = 0
        while i < count {
            var r = rng.next()
            for _ in 0 ..< 8 where i < count {
                bytes[i] = UInt8(truncatingIfNeeded: r)
                r >>= 8
                i += 1
            }
        }
        return Data(bytes)
    }

    // MARK: Records

    static func makeWork(_ index: Int, seed: UInt64, hasEPUB: Bool) -> KudosBackupWork {
        let work = SavedWork(
            id: workID(index, seed: seed),
            title: "Fixture Work \(index) \(text(count: 24, seed: seed &+ UInt64(index)))",
            author: "Author \(index % 997)",
            summary: text(count: 420, seed: seed &+ UInt64(index) &* 3),
            sourceURL: "https://archiveofourown.org/works/\(1_000_000 + index)"
        )
        work.ao3WorkID = 1_000_000 + index
        work.dateAdded = fixedDate
        work.createdAt = fixedDate
        work.lastModifiedAt = fixedDate
        work.hasEPUB = hasEPUB
        work.wordCount = 1_000 + index % 90_000
        work.workFandoms = ["Fandom \(index % 211)", "Crossover \(index % 37)"]
        work.workCharacters = (0 ..< 4).map { "Character \(($0 + index) % 503)" }
        work.workRelationships = (0 ..< 3).map { "Ship \(($0 * 7 + index) % 701) / Other \($0)" }
        work.workFreeforms = (0 ..< 8).map { "Freeform tag \(($0 * 13 + index) % 1_999)" }
        work.workTags = work.workFreeforms
        return KudosBackupWork(work: work)
    }

    static func makeBookmark(_ index: Int, seed: UInt64) -> KudosBackupBookmark {
        let bookmark = Bookmark(title: "Bookmark \(index)", urlString: "https://archiveofourown.org/tags/\(index)/works")
        bookmark.id = uuid(2, index, seed: seed)
        bookmark.dateAdded = fixedDate
        return KudosBackupBookmark(bookmark: bookmark)
    }

    static func makeSession(_ index: Int, seed: UInt64, workCount: Int) -> KudosBackupReadingSession {
        let workIndex = index % max(1, workCount)
        let start = fixedDate.addingTimeInterval(-Double(index) * 3_600)
        let session = ReadingSession(
            id: uuid(3, index, seed: seed),
            workID: workID(workIndex, seed: seed),
            ao3WorkID: 1_000_000 + workIndex,
            sourceURL: "https://archiveofourown.org/works/\(1_000_000 + workIndex)",
            workTitle: "Fixture Work \(workIndex)",
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            durationSeconds: 1_800,
            lastSpineIndex: index % 30,
            chapterTitle: "Chapter \(index % 30)",
            endingProgress: Double(index % 100) / 100,
            wordCount: 2_000 + index % 5_000,
            chapterCountAtVisit: 30,
            lastModifiedAt: fixedDate
        )
        return KudosBackupReadingSession(session: session)
    }

    static func makeTombstone(_ index: Int, seed: UInt64) -> KudosBackupTombstone {
        let tombstone = SyncTombstone(
            recordID: uuid(4, index, seed: seed), recordType: .savedWork,
            sourceURL: "https://archiveofourown.org/works/\(2_000_000 + index)", ao3WorkID: 2_000_000 + index,
            createdAt: fixedDate
        )
        tombstone.id = uuid(5, index, seed: seed)
        return KudosBackupTombstone(tombstone: tombstone)
    }

    static func recoveryFileName(_ index: Int, seed: UInt64) -> String {
        var rng = SplitMix(state: seed &+ 77 &+ UInt64(index))
        let hex = (0 ..< 8).map { _ in String(format: "%08x", UInt32(truncatingIfNeeded: rng.next())) }.joined()
        return "\(hex).json"
    }

    /// `WritingTextRecovery.Entry` text of `chars` characters.
    static func makeRecovery(_ index: Int, seed: UInt64, chars: Int) -> KudosBackupRecoveryCopy {
        KudosBackupRecoveryCopy(
            fileName: recoveryFileName(index, seed: seed),
            entry: .init(
                text: text(count: chars, seed: seed &+ 5_000 &+ UInt64(index)),
                originalDigest: "digest-\(index)", savedAt: fixedDate, accountDigest: nil
            )
        )
    }

    static func makeDocument(_ index: Int, seed: UInt64, bytes: Int) -> KudosBackupDocument {
        // An unknown name: `KudosBackupDocument.apply` skips it, so a restore never writes it to the device.
        KudosBackupDocument(
            name: "opaque/fixture-\(index).bin", data: randomData(count: bytes, seed: seed &+ 9_000 &+ UInt64(index)),
            modifiedAt: fixedDate
        )
    }

    // MARK: Encoding

    nonisolated static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// The production encoder's configuration (`KudosBackupContents.makeEncoder` is private).
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    // MARK: Calibration

    /// Fills the counts so the document lands within about 1% of `targetBytes` on the chosen axis.
    static func calibrated(axis: ManifestScaleAxis, mib: Double, seed: UInt64 = 567) throws -> ManifestFixtureSpec {
        var spec = ManifestFixtureSpec(axis: axis, targetBytes: Int(mib * Double(ManifestFixtureSpec.miB)), seed: seed)
        spec.works = spec.baseWorks
        spec.bookmarks = spec.baseBookmarks
        spec.sessions = spec.baseSessions
        // Granularity: small targets get small opaque values so the count is not 0 or 1.
        spec.documentBytes = min(spec.documentBytes, spec.targetBytes / 32)
        spec.recoveryCopyChars = min(spec.recoveryCopyChars, spec.targetBytes / 32)
        let encoder = makeEncoder()
        func averageSize<T: Encodable>(_ make: (Int) -> T) throws -> Int {
            var total = 0
            for i in 0 ..< 64 { total += try encoder.encode(make(i)).count + 2 }
            return total / 64
        }
        let baseBytes = 60_000 + spec.baseWorks * (try averageSize { makeWork($0, seed: seed, hasEPUB: false) })
            + spec.baseSessions * (try averageSize { makeSession($0, seed: seed, workCount: 200) })
            + spec.baseBookmarks * 180
        switch axis {
        case .works:
            let per = try averageSize { makeWork($0, seed: seed, hasEPUB: false) } + (180 * spec.baseBookmarks) / max(1, spec.baseWorks)
            spec.works = max(spec.baseWorks, (spec.targetBytes - baseBytes) / per + spec.baseWorks)
        case .sessions:
            let per = try averageSize { makeSession($0, seed: seed, workCount: 200) }
            spec.sessions = max(spec.baseSessions, (spec.targetBytes - baseBytes) / per + spec.baseSessions)
        case .opaque:
            var budget = max(0, spec.targetBytes - baseBytes)
            if spec.targetBytes >= 32 * ManifestFixtureSpec.miB {
                spec.bigRecoveryChars = ManifestFixtureSpec.largeRecoveryChars
                // newlines double in JSON (`\n`); the alphabet is ~1.4% newline, close enough to 1:1.
                budget -= Int(Double(spec.bigRecoveryChars) * 1.014) + 400
            }
            let docEncoded = (spec.documentBytes + 2) / 3 * 4 + 160
            let copyEncoded = Int(Double(spec.recoveryCopyChars) * 1.014) + 400
            // Half the remaining budget in each form.
            spec.documents = max(0, budget / 2 / docEncoded)
            spec.recoveryCopies = max(0, budget / 2 / copyEncoded)
        }
        return spec
    }

    // MARK: Writing

    private final class Sink {
        let handle: FileHandle
        var buffer = Data()
        var written = 0
        init(_ handle: FileHandle) { self.handle = handle; buffer.reserveCapacity(4 << 20) }
        func write(_ data: Data) throws {
            buffer.append(data)
            if buffer.count >= 4 << 20 { try flush() }
        }
        func write(_ string: String) throws { try write(Data(string.utf8)) }
        func flush() throws {
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: buffer)
            written += buffer.count
            buffer.removeAll(keepingCapacity: true)
        }
    }

    private static func writeArray<T: Encodable>(
        _ key: String, count: Int, to sink: Sink, encoder: JSONEncoder, trailingComma: Bool = true,
        make: (Int) throws -> T
    ) throws {
        try sink.write("\"\(key)\" : [")
        for i in 0 ..< count {
            if i > 0 { try sink.write(",") }
            try autoreleasepool { try sink.write(try encoder.encode(make(i))) }
        }
        try sink.write("]" + (trailingComma ? ",\n" : "\n"))
    }

    /// Streams the manifest to `url`. `exportedAt`/`version` come after the arrays, as in a real export.
    static func write(_ spec: ManifestFixtureSpec, to url: URL, defaults: UserDefaults) throws -> Output {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        guard fm.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteNoPermission) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let sink = Sink(handle)
        let encoder = makeEncoder()
        let seed = spec.seed
        let settings = try encoder.encode(KudosBackupSettings.capture(defaults: defaults))
        let pronunciations = try encoder.encode(KudosBackupPronunciations.empty)
        let sessionWorkCount = max(spec.baseWorks, 1)

        try sink.write("{\n")
        try writeArray("annotations", count: 0, to: sink, encoder: encoder) { _ in 0 }
        try writeArray("bookmarks", count: spec.bookmarks, to: sink, encoder: encoder) { makeBookmark($0, seed: seed) }
        try writeArray("collections", count: 0, to: sink, encoder: encoder) { _ in 0 }
        if spec.documents > 0 {
            try writeArray("documents", count: spec.documents, to: sink, encoder: encoder) {
                makeDocument($0, seed: seed, bytes: spec.documentBytes)
            }
        }
        try sink.write("\"exportedAt\" : \"\(formatter.string(from: fixedDate))\",\n")
        try writeArray("fandomReadWatermarks", count: 0, to: sink, encoder: encoder) { _ in 0 }
        try writeArray("fonts", count: 0, to: sink, encoder: encoder) { _ in 0 }
        try writeArray("readingFavorites", count: 0, to: sink, encoder: encoder) { _ in 0 }
        try writeArray("readingQueueMemberships", count: 0, to: sink, encoder: encoder) { _ in 0 }
        try writeArray("readingQueues", count: 0, to: sink, encoder: encoder) { _ in 0 }
        try writeArray("readingSessions", count: spec.sessions, to: sink, encoder: encoder) {
            makeSession($0, seed: seed, workCount: sessionWorkCount)
        }
        try writeArray("savedSearches", count: 0, to: sink, encoder: encoder) { _ in 0 }
        try sink.write("\"pronunciations\" : ")
        try sink.write(pronunciations)
        try sink.write(",\n\"settings\" : ")
        try sink.write(settings)
        try sink.write(",\n")
        try writeArray("tombstones", count: spec.tombstones, to: sink, encoder: encoder) { makeTombstone($0, seed: seed) }
        try sink.write("\"version\" : \(KudosBackupManifest.currentVersion),\n")
        try writeArray("works", count: spec.works, to: sink, encoder: encoder, trailingComma: spec.recoveryCopies > 0 || spec.bigRecoveryChars > 0) {
            makeWork($0, seed: seed, hasEPUB: $0 < spec.epubWorks)
        }
        let recoveryCount = spec.recoveryCopies + (spec.bigRecoveryChars > 0 ? 1 : 0)
        if recoveryCount > 0 {
            try writeArray("writingRecovery", count: recoveryCount, to: sink, encoder: encoder, trailingComma: false) { i in
                makeRecovery(i, seed: seed, chars: i == 0 && spec.bigRecoveryChars > 0 ? spec.bigRecoveryChars : spec.recoveryCopyChars)
            }
        }
        try sink.write("}\n")
        try sink.flush()
        let ids = (0 ..< spec.works).map { workID($0, seed: seed) }
        return Output(
            manifestURL: url, bytes: sink.written, spec: spec, workIDs: ids,
            epubWorkIDs: Array(ids.prefix(spec.epubWorks))
        )
    }

    /// Small deterministic EPUB for one work. Valid for `EPUBDocument.inspectPackage` so a restore installs it.
    static func dummyEPUB(for id: UUID) throws -> Data {
        try EPUBBuilder.archive(
            metadata: .init(title: "Fixture \(id.uuidString.prefix(8))"),
            chapters: [.init(title: "One", bodyXHTML: "<p>\(id.uuidString)</p>")],
            modified: Date(timeIntervalSince1970: 0)
        )
    }

    /// A `.kudosbackup` archive: the manifest streamed in from disk plus the dummy EPUBs.
    static func writeArchive(_ output: Output, to url: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        guard fm.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteNoPermission) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let writer = MiniZip.ArchiveWriter { try handle.write(contentsOf: $0) }
        try writer.append(name: "manifest.json", contentsOf: output.manifestURL)
        for id in output.epubWorkIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            try writer.append(name: "Works/\(id.uuidString).epub", data: dummyEPUB(for: id))
        }
        try writer.finish()
    }
}
