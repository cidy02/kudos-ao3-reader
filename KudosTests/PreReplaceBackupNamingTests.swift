import Foundation
import Testing
@testable import Kudos

/// The pre-replace safety copy is the ONLY undo a Replace Library has, so the
/// rule these tests pin is narrow and absolute: **taking one must never destroy
/// another.**
///
/// It did. The name was `yyyy-MM-dd` and the write was a plain `.atomic`, and
/// the copy is taken from the Replace sheet's `onAppear` — so merely opening
/// Replace a second time on the same day (cancelling still counted) wrote the
/// already-replaced library over the original. The file that could undo the
/// first replace was destroyed by *considering* a second one.
///
/// No `.serialized` and no `PersistenceGateSuites` nesting: this is pure naming,
/// it touches no SwiftData and no process-wide gate.
@Suite
struct PreReplaceBackupNamingTests {
    private static func date(_ stamp: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return try #require(formatter.date(from: stamp))
    }

    /// The regression. Under the old date-only name these two were the same
    /// string, so the evening copy silently replaced the morning one.
    @Test func twoCopiesOnTheSameDayDoNotShareAName() throws {
        let morning = try Self.date("2026-09-20 09:15:00")
        let evening = try Self.date("2026-09-20 21:40:00")

        let first = PreReplaceBackupNaming.fileName(at: morning, attempt: 0)
        let second = PreReplaceBackupNaming.fileName(at: evening, attempt: 0)

        #expect(first != second)
    }

    /// A retry must not overwrite the attempt it is retrying for, even when both
    /// land inside one second.
    @Test func retriesWithinOneSecondEachGetTheirOwnName() throws {
        let instant = try Self.date("2026-09-20 09:15:00")

        let names = (0 ..< PreReplaceBackupNaming.attemptLimit).map {
            PreReplaceBackupNaming.fileName(at: instant, attempt: $0)
        }

        #expect(Set(names).count == names.count)
    }

    /// More than one attempt, because a single write failure is not proof the
    /// disk cannot take a copy — and the alternative to a copy is a replace that
    /// cannot be undone.
    @Test func aSafetyCopyIsAttemptedMoreThanOnce() {
        #expect(PreReplaceBackupNaming.attemptLimit > 1)
    }

    /// The copy has to be re-importable, so it must carry the extension the
    /// importer's content types accept.
    @Test func theCopyIsNamedAsAnImportableBackup() throws {
        let url = PreReplaceBackupNaming.url(
            in: URL(fileURLWithPath: "/tmp", isDirectory: true),
            at: try Self.date("2026-09-20 09:15:00"),
            attempt: 0
        )

        #expect(url.pathExtension == PreReplaceBackupNaming.fileExtension)
        #expect(url.lastPathComponent.hasPrefix("Kudos Library Before Replace "))
    }

    /// Naming alone is not the guarantee — the write refuses to clobber. This
    /// pins the option set `makePreReplaceBackup` depends on, so a later edit
    /// that drops `.withoutOverwriting` fails here rather than in someone's
    /// library.
    @Test func writingRefusesToOverwriteAnExistingCopy() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PreReplaceNaming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = PreReplaceBackupNaming.url(
            in: directory,
            at: try Self.date("2026-09-20 09:15:00"),
            attempt: 0
        )
        try Data("first".utf8).write(to: url, options: [.atomic, .withoutOverwriting])

        #expect(throws: (any Error).self) {
            try Data("second".utf8).write(to: url, options: [.atomic, .withoutOverwriting])
        }
        #expect(try Data(contentsOf: url) == Data("first".utf8))
    }
}
