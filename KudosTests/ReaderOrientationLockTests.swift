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

        lock.lock(to: .landscapeLeft)
        #expect(lock.isLocked)
        #expect(lock.mask == .landscapeLeft)

        lock.release()
        #expect(lock.isLocked, "leaving the reader must not turn Rotation Lock off")
        #expect(lock.mask == .all, "the rest of the app rotates freely")

        lock.readerDidOpen()
        #expect(lock.mask == .landscapeLeft, "the next reader is pinned again")
        #expect(applied == [.landscapeLeft, .all, .landscapeLeft])
    }

    @Test func theSettingSurvivesARelaunch() {
        let defaults = makeDefaults()
        ReaderOrientationLock(defaults: defaults) { _, _ in }.lock(to: .portrait)

        let relaunched = ReaderOrientationLock(defaults: defaults) { _, _ in }
        #expect(relaunched.isLocked)
        #expect(relaunched.mask == .all, "nothing is pinned until a reader opens")
        relaunched.readerDidOpen()
        #expect(relaunched.mask == .portrait)
    }

    @Test func turningItOffIsRemembered() {
        let defaults = makeDefaults()
        let lock = ReaderOrientationLock(defaults: defaults) { _, _ in }
        lock.lock(to: .landscapeRight)
        lock.unlock()
        #expect(!lock.isLocked)
        #expect(lock.mask == .all)

        let relaunched = ReaderOrientationLock(defaults: defaults) { _, _ in }
        relaunched.readerDidOpen()
        #expect(!relaunched.isLocked)
        #expect(relaunched.mask == .all)
    }
}
#endif
