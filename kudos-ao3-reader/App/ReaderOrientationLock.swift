#if os(iOS)
import SwiftUI
import UIKit

/// Pins the app to one interface orientation while reading — the reader's own
/// rotation lock, as in Apple Books.
///
/// An app cannot touch the *system* rotation lock, and shouldn't: this locks
/// only Kudos, and only while the reader asks for it. iOS decides orientation by
/// asking the app delegate for the supported mask, so the lock lives in one
/// shared place that `KudosAppDelegate` reports from, rather than being threaded
/// through view controllers that SwiftUI owns.
///
/// The lock is a **reader setting** (BUG-13, owner 2026-11-24: leaving the reader
/// must not reset it): `isLocked` and the pinned orientation persist on this device,
/// but the mask only pins the app while a reader is open. `ReadiumReaderView`
/// calls `readerDidOpen()` on the way in and `release()` on the way out, so no
/// other screen is ever constrained. Device-local on purpose (not in backups or
/// Folder Sync): an iPad pinned to landscape must not pin the iPhone.
@MainActor
@Observable
final class ReaderOrientationLock {
    static let shared = ReaderOrientationLock()
    static let lockedKey = "readerRotationLocked"
    static let orientationKey = "readerRotationLockOrientation"

    /// The reader's setting, as the Rotation Lock button shows it.
    private(set) var isLocked: Bool

    /// What the delegate reports. `.all` unless a reader is open with the lock on,
    /// so every other screen keeps its normal behaviour.
    private(set) var mask: UIInterfaceOrientationMask = .all

    private let defaults: UserDefaults
    /// The reader that last opened; only it may free the mask.
    private var owner: UUID?
    private let applyMask: @MainActor (UIWindowScene?, UIInterfaceOrientationMask) -> Void

    /// `applyMask` is injectable so tests never rotate the test host.
    init(
        defaults: UserDefaults = .standard,
        applyMask: @escaping @MainActor (UIWindowScene?, UIInterfaceOrientationMask) -> Void = ReaderOrientationLock.apply
    ) {
        self.defaults = defaults
        self.applyMask = applyMask
        isLocked = defaults.bool(forKey: Self.lockedKey)
    }

    /// Locks to whatever orientation is on screen now, or turns the lock off.
    func toggle(in scene: UIWindowScene?) {
        if isLocked {
            unlock(in: scene)
        } else if let orientation = scene?.interfaceOrientation {
            lock(to: orientation, in: scene)
        }
    }

    func lock(to orientation: UIInterfaceOrientation, in scene: UIWindowScene? = nil) {
        guard orientation != .unknown else { return }
        defaults.set(orientation.rawValue, forKey: Self.orientationKey)
        defaults.set(true, forKey: Self.lockedKey)
        isLocked = true
        mask = Self.mask(for: orientation)
        applyMask(scene, mask)
    }

    /// The reader turned the setting off.
    func unlock(in scene: UIWindowScene? = nil) {
        defaults.set(false, forKey: Self.lockedKey)
        isLocked = false
        freeMask(in: scene)
    }

    /// A reader opened: it owns the lock now, and is pinned again to the saved
    /// orientation if the setting is on.
    func readerDidOpen(owner: UUID, in scene: UIWindowScene? = nil) {
        self.owner = owner
        guard isLocked,
              let orientation = UIInterfaceOrientation(rawValue: defaults.integer(forKey: Self.orientationKey)),
              orientation != .unknown else { return }
        mask = Self.mask(for: orientation)
        applyMask(scene, mask)
    }

    /// The reader `owner` closed: free the rest of the app; the setting stays. A
    /// reader that no longer owns the lock changes nothing — Start Next Work can
    /// open the next reader before the old one disappears.
    func release(owner: UUID, in scene: UIWindowScene? = nil) {
        guard owner == self.owner else { return }
        self.owner = nil
        freeMask(in: scene)
    }

    private func freeMask(in scene: UIWindowScene?) {
        guard mask != .all else { return }
        mask = .all
        applyMask(scene, mask)
    }

    /// Nudges iOS to re-ask for the supported orientations. Without this the new
    /// mask only takes effect at the next rotation the user performs.
    static func apply(in scene: UIWindowScene?, mask: UIInterfaceOrientationMask) {
        guard let scene = scene ?? activeScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: .all
        }
    }

    static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}

/// Exists solely so iOS has someone to ask about supported orientations —
/// `ReaderOrientationLock` holds the answer.
final class KudosAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        supportedInterfaceOrientationsFor _: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { ReaderOrientationLock.shared.mask }
    }

    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == TTSDownloadManager.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor in
            TTSDownloadManager.shared.handleBackgroundURLSessionEvents(
                completionHandler: completionHandler
            )
        }
    }
}
#endif
