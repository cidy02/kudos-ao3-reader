import SwiftUI

#if os(iOS)
import UIKit

extension Notification.Name {
    /// Posted when the device is physically shaken — drives shake-to-report.
    static let deviceDidShake = Notification.Name("KudosDeviceDidShake")
}

extension UIWindow {
    /// `motionEnded` is part of the responder chain; catching it on the window lets
    /// any screen offer shake-to-report without each view wiring up motion handling.
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
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
