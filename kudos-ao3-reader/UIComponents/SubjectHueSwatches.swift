import SwiftUI

/// The five colours artboard **1j** offers when a queue is created, and **1h.3**
/// offers again in Queue Details.
///
/// Stored as hues rather than as the artboard's hex values so one swatch means the
/// same thing under every theme: the app paints queues through
/// `subjectPalette(hue:)` / `carouselQueueTint(hue:)`, which derive a Sepia or
/// dark-mode colour from the hue. Pinning the hex would give a swatch that matched
/// the mock on one theme and fought the surface on the others.
///
/// The hues are the mock's own swatches measured — violet #B49BEA, mint #8FE0C4,
/// rose #E39B9B, amber #E0A883, blue #7FC9E0.
nonisolated enum QueueHueSwatches {
    struct Swatch: Identifiable, Hashable, Sendable {
        let name: String
        let hue: Double
        var id: String { name }
    }

    static let all: [Swatch] = [
        Swatch(name: "Violet", hue: 0.7194),
        Swatch(name: "Mint", hue: 0.4424),
        Swatch(name: "Rose", hue: 0.0),
        Swatch(name: "Amber", hue: 0.0663),
        Swatch(name: "Blue", hue: 0.5395)
    ]

    /// Whether `hue` is (near enough) this swatch. Float equality would fail on a
    /// value that has been through a backup round trip.
    static func matches(_ swatch: Swatch, _ hue: Double?) -> Bool {
        guard let hue else { return false }
        return abs(hue - swatch.hue) < 0.01
    }
}

/// A row of tappable colour swatches. `selection` is `nil` while a queue still
/// takes its colour from its name, which is the state every existing queue is in.
struct QueueHueSwatchRow: View {
    @Binding var selection: Double?
    /// Drawn with a ring when nothing is chosen, so "derived from the name" is a
    /// visible state rather than an absence.
    var fallbackHue: Double

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 10) {
            ForEach(QueueHueSwatches.all) { swatch in
                Button {
                    selection = QueueHueSwatches.matches(swatch, selection) ? nil : swatch.hue
                } label: {
                    swatchCircle(
                        hue: swatch.hue,
                        isSelected: QueueHueSwatches.matches(swatch, selection)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(
                    QueueHueSwatches.matches(swatch, selection) ? [.isButton, .isSelected] : .isButton
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func swatchCircle(hue: Double, isSelected: Bool) -> some View {
        Circle()
            .fill(themeManager.appTheme.carouselQueueTint(hue: hue))
            .frame(width: 28, height: 28)
            .overlay(
                Circle()
                    .strokeBorder(
                        themeManager.appTheme.subjectPalette(hue: hue).accent,
                        lineWidth: isSelected ? 2.5 : 0.5
                    )
            )
            .padding(3)
    }
}
