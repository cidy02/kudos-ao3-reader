import Foundation
import SwiftUI
import Testing
@testable import Kudos

/// FID5 — Settings › Appearance (board 48)
/// Pure logic tests for theme preview tiles and accessibility labels.
struct SettingsAppearanceFid5Tests {
    @Test func tileAccessibilityLabelsMatchThemeTitles() {
        #expect(ThemePreviewTilePicker.accessibilityLabel(for: .light) == "Light theme")
        #expect(ThemePreviewTilePicker.accessibilityLabel(for: .sepia) == "Sepia theme")
        #expect(ThemePreviewTilePicker.accessibilityLabel(for: .dark) == "Dark theme")
        #expect(ThemePreviewTilePicker.accessibilityLabel(for: .oled) == "OLED theme")
    }

    @Test func columnCountSwitchesAtAccessibilitySizes() {
        #expect(ThemePreviewTilePicker.columnCount(isAccessibilitySize: false) == 4)
        #expect(ThemePreviewTilePicker.columnCount(isAccessibilitySize: true) == 2)
    }

    @Test func fractionalCapsulePathComputesExpectedWidth() {
        let capsule = FractionalCapsule(fraction: 0.70)
        let rect = CGRect(x: 10, y: 0, width: 100, height: 10)
        let path = capsule.path(in: rect)
        let bounds = path.boundingRect
        #expect(bounds.minX == 10)
        #expect(abs(bounds.width - 70) < 0.001)
        #expect(abs(bounds.height - 10) < 0.001)
    }
}
