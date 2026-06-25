#if os(iOS)
import UIKit

/// Captures a snapshot of what's on screen, for attaching to a bug report. Grabbed at
/// shake time (before the report sheet covers the screen) so it shows the actual bug.
enum ScreenshotCapture {
    @MainActor
    static func captureKeyWindow() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        // `afterScreenUpdates: false` captures the current frame, not the one with the
        // bug-report sheet animating in.
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}
#endif
