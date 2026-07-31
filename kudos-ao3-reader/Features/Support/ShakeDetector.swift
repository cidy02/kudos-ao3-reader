import SwiftUI

#if os(iOS)
import CoreMotion
import UIKit

extension Notification.Name {
    /// Posted when the device is physically shaken — drives shake-to-report.
    static let deviceDidShake = Notification.Name("KudosDeviceDidShake")
}

/// Samples user-acceleration during a system shake so we can require a slightly
/// stronger jolt than the OS default (cuts accidental walking/grip triggers).
private final class ShakeIntensityMonitor {
    static let shared = ShakeIntensityMonitor()

    /// Peak |userAcceleration| (g) during the current shake gesture.
    private(set) var peakUserAcceleration: Double = 0
    /// A little above soft jostles; a deliberate shake still clears this easily.
    static let acceptThresholdG: Double = 1.65
    private static let cooldown: TimeInterval = 1.0

    private let motion = CMMotionManager()
    private var lastAcceptedAt: Date?

    private init() {}

    func beginTracking() {
        peakUserAcceleration = 0
        guard motion.isDeviceMotionAvailable else { return }
        guard !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.userAcceleration
            let mag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            if mag > self.peakUserAcceleration {
                self.peakUserAcceleration = mag
            }
        }
    }

    func endTracking() {
        if motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }
    }

    /// Whether this shake is strong enough and outside the post-accept cooldown.
    func shouldAcceptShake() -> Bool {
        let now = Date()
        if let last = lastAcceptedAt, now.timeIntervalSince(last) < Self.cooldown {
            return false
        }
        // Simulator / no Core Motion / sampling missed the peak: trust the OS.
        if !motion.isDeviceMotionAvailable || peakUserAcceleration < 0.05 {
            lastAcceptedAt = now
            return true
        }
        let ok = peakUserAcceleration >= Self.acceptThresholdG
        if ok {
            lastAcceptedAt = now
        }
        return ok
    }
}

extension UIWindow {
    /// Start sampling acceleration as soon as the OS recognizes a shake beginning.
    override open func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            ShakeIntensityMonitor.shared.beginTracking()
        }
        super.motionBegan(motion, with: event)
    }

    /// `motionEnded` is part of the responder chain; catching it on the window lets
    /// any screen offer shake-to-report without each view wiring up motion handling.
    ///
    /// Accepts the shake only if peak user-acceleration during the gesture was
    /// above a modest threshold (~1.65g) — slightly stricter than the OS default,
    /// still a normal deliberate shake.
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            let monitor = ShakeIntensityMonitor.shared
            if monitor.shouldAcceptShake() {
                let haptic = UINotificationFeedbackGenerator()
                haptic.prepare()
                haptic.notificationOccurred(.success)
                NotificationCenter.default.post(name: .deviceDidShake, object: nil)
            }
            monitor.endTracking()
        }
        super.motionEnded(motion, with: event)
    }

    override open func motionCancelled(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            ShakeIntensityMonitor.shared.endTracking()
        }
        super.motionCancelled(motion, with: event)
    }
}

private struct ShakeDetector: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            action()
        }
    }
}

extension View {
    /// Runs `action` when the device is physically shaken. iOS only; a no-op
    /// elsewhere (macOS has no shake gesture).
    ///
    /// Filters soft accidental jostles via a modest acceleration threshold;
    /// a clear deliberate shake still triggers.
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(action: action))
    }
}
#else
extension View {
    /// No-op on platforms without a shake gesture (macOS).
    func onShake(perform _: @escaping () -> Void) -> some View {
        self
    }
}
#endif
