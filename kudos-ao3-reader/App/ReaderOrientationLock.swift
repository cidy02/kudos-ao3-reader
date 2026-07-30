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
/// The lock is deliberately **session-only** (not `@AppStorage`): a persisted
/// lock would silently constrain the whole app on next launch, including screens
/// that never opted in. `ReadiumReaderView` releases it when the reader closes.
@MainActor
@Observable
final class ReaderOrientationLock {
    static let shared = ReaderOrientationLock()

    private(set) var isLocked = false

    /// What the delegate reports. `.all` while unlocked, so every other screen
    /// keeps its normal behaviour.
    private(set) var mask: UIInterfaceOrientationMask = .all

    private init() {}

    /// Locks to whatever orientation is on screen now, or releases the lock.
    func toggle(in scene: UIWindowScene?) {
        if isLocked {
            release()
        } else {
            lock(to: scene)
        }
    }

    func lock(to scene: UIWindowScene?) {
        guard let orientation = scene?.interfaceOrientation, orientation != .unknown else { return }
        mask = Self.mask(for: orientation)
        isLocked = true
        apply(in: scene)
    }

    /// Returns the app to free rotation. Safe to call when already unlocked, so
    /// the reader can call it unconditionally on the way out.
    func release(in scene: UIWindowScene? = nil) {
        guard isLocked else { return }
        mask = .all
        isLocked = false
        apply(in: scene ?? Self.activeScene)
    }

    /// Nudges iOS to re-ask for the supported orientations. Without this the new
    /// mask only takes effect at the next rotation the user performs.
    private func apply(in scene: UIWindowScene?) {
        guard let scene = scene ?? Self.activeScene else { return }
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
}
#endif
