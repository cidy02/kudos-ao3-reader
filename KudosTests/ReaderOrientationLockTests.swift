#if os(iOS)
import Testing
import UIKit
@testable import Kudos

/// BUG-13 (owner, 2026-11-24): "some reader settings are resetting when you exit the reader,
/// namely rotation lock". The lock is a saved setting; closing the reader frees the rest of
/// the app but must not turn the setting off.
@MainActor
struct ReaderOrientationLockTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "ReaderOrientationLockTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func closingTheReaderKeepsTheSettingAndFreesTheApp() {
        let defaults = makeDefaults()
        var applied: [UIInterfaceOrientationMask] = []
        let lock = ReaderOrientationLock(defaults: defaults) { _, mask in applied.append(mask) }

        let reader = UUID()
        lock.readerDidOpen(owner: reader)
        lock.lock(to: .landscapeLeft)
        #expect(lock.isLocked)
        #expect(lock.mask == .landscapeLeft)

        lock.release(owner: reader)
        #expect(lock.isLocked, "leaving the reader must not turn Rotation Lock off")
        #expect(lock.mask == .all, "the rest of the app rotates freely")

        lock.readerDidOpen(owner: UUID())
        #expect(lock.mask == .landscapeLeft, "the next reader is pinned again")
        #expect(applied == [.landscapeLeft, .all, .landscapeLeft])
    }

    @Test func theSettingSurvivesARelaunch() {
        let defaults = makeDefaults()
        ReaderOrientationLock(defaults: defaults) { _, _ in }.lock(to: .portrait)

        let relaunched = ReaderOrientationLock(defaults: defaults) { _, _ in }
        #expect(relaunched.isLocked)
        #expect(relaunched.mask == .all, "nothing is pinned until a reader opens")
        relaunched.readerDidOpen(owner: UUID())
        #expect(relaunched.mask == .portrait)
    }

    /// Start Next Work can show the next reader before the old one disappears.
    @Test func aReaderClosingLateDoesNotFreeTheNextOne() {
        let lock = ReaderOrientationLock(defaults: makeDefaults()) { _, _ in }
        lock.lock(to: .landscapeLeft)
        let old = UUID(), next = UUID()
        lock.readerDidOpen(owner: old)
        lock.readerDidOpen(owner: next)
        lock.release(owner: old)
        #expect(lock.mask == .landscapeLeft, "the new reader stays pinned")
        lock.release(owner: next)
        #expect(lock.mask == .all)
    }

    @Test func turningItOffIsRemembered() {
        let defaults = makeDefaults()
        let lock = ReaderOrientationLock(defaults: defaults) { _, _ in }
        lock.lock(to: .landscapeRight)
        lock.unlock()
        #expect(!lock.isLocked)
        #expect(lock.mask == .all)

        let relaunched = ReaderOrientationLock(defaults: defaults) { _, _ in }
        relaunched.readerDidOpen(owner: UUID())
        #expect(!relaunched.isLocked)
        #expect(relaunched.mask == .all)
    }
}
#endif
