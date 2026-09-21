import Foundation
import SwiftData
import Testing
@testable import Kudos

/// The exact page a reader left off on, lost two different ways.
///
/// `SavedWork.readiumLocator` is a plain `String` on every platform, but the
/// backup serializer wrapped reading it in `#if canImport(ReadiumShared)` and
/// wrote nil otherwise. A backup exported from macOS — where the Readium reader
/// is not built, though the value is still stored — therefore dropped the
/// position of every work that had one. Restoring that backup onto an iPhone
/// lost it for good.
///
/// The second way is worse, because it destroys a position that was never in
/// the backup at all: `applyProgress` assigned the incoming locator
/// unconditionally, and the caller turned an absent field into `""`. A winning
/// snapshot from an older or macOS-written backup then wiped the precise
/// position the local device already had. Absent now means "carried nothing";
/// only an explicit empty string clears.
extension PersistenceGateSuites {
@MainActor
@Suite(.serialized)
struct ReadiumLocatorPreservationTests {
    private static let locator = #"{"locations":{"totalProgression":0.42}}"#

    /// Platform-independent by construction: the model holds a `String`
    /// everywhere, so the archived record must carry it everywhere. This is the
    /// assertion the `#if` guard failed on macOS.
    @Test func theArchivedRecordCarriesTheStoredLocator() {
        let work = SavedWork(title: "Placed", author: "Writer")
        work.readiumLocator = Self.locator

        let archived = KudosBackupWork(work: work)

        #expect(archived.readiumLocator == Self.locator)
    }

    /// The regression that matters most: a newer snapshot that carries progress
    /// but no locator must not take the local one with it.
    @Test func aSnapshotCarryingNoLocatorLeavesTheLocalPositionAlone() {
        let work = SavedWork(title: "Placed", author: "Writer")
        work.readiumLocator = Self.locator
        work.lastSpineIndex = 3
        work.markProgressModified(Date(timeIntervalSince1970: 100))

        SyncMerge.applyProgress(
            SyncMerge.ProgressSnapshot(
                lastSpineIndex: 7,
                lastScrollFraction: 0.5,
                readiumLocator: nil,
                lastReadDate: Date(timeIntervalSince1970: 300),
                modifiedAt: Date(timeIntervalSince1970: 300)
            ),
            to: work
        )

        // The snapshot did win — this is not a test about losing the merge.
        #expect(work.lastSpineIndex == 7)
        // ...and the position it never carried is still here.
        #expect(work.readiumLocator == Self.locator)
    }

    /// The other half of the distinction: an explicit empty locator is a real
    /// value and must still clear, or "start this work over" could never sync.
    @Test func anExplicitlyEmptyLocatorStillClearsThePosition() {
        let work = SavedWork(title: "Placed", author: "Writer")
        work.readiumLocator = Self.locator
        work.markProgressModified(Date(timeIntervalSince1970: 100))

        SyncMerge.applyProgress(
            SyncMerge.ProgressSnapshot(
                lastSpineIndex: 7,
                lastScrollFraction: 0.5,
                readiumLocator: "",
                lastReadDate: Date(timeIntervalSince1970: 300),
                modifiedAt: Date(timeIntervalSince1970: 300)
            ),
            to: work
        )

        #expect(work.readiumLocator.isEmpty)
    }

    /// A locator alone is progress: a Readium reader records position without
    /// touching the legacy spine index, so the guard must not overlook it.
    @Test func aLocatorOnItsOwnCountsAsProgress() {
        let work = SavedWork(title: "Unread", author: "Writer")

        SyncMerge.applyProgress(
            SyncMerge.ProgressSnapshot(
                lastSpineIndex: 0,
                lastScrollFraction: 0,
                readiumLocator: Self.locator,
                lastReadDate: nil,
                modifiedAt: Date(timeIntervalSince1970: 300)
            ),
            to: work
        )

        #expect(work.readiumLocator == Self.locator)
    }
}
}
