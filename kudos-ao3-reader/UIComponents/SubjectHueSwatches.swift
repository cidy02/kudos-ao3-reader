import SwiftUI

/// The five colours artboard **1j** offers when a queue is created, **1h.3** offers
/// again in Queue Details, and **1bk** asks for on a local collection — "colour is
/// the collection's identity everywhere else in the app, so it is picked here
/// rather than assigned".
///
/// Stored as hues rather than as the artboard's hex values so one swatch means the
/// same thing under every theme: the app paints queues through
/// `subjectPalette(hue:)` / `carouselQueueTint(hue:)`, which derive a Sepia or
/// dark-mode colour from the hue. Pinning the hex would give a swatch that matched
/// the mock on one theme and fought the surface on the others.
///
/// The hues are the mock's own swatches measured — violet #B49BEA, mint #8FE0C4,
/// rose #E39B9B, amber #E0A883, blue #7FC9E0.
nonisolated enum SubjectHueSwatches {
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

/// A row of tappable colour swatches. `selection` is `nil` while the subject still
/// takes its colour from its name — the state every queue and collection that
/// predates this is in.
///
/// The row ends in the boards' "More colours" well (`CustomColorWell`, a SwiftUI
/// `ColorPicker`: grid, spectrum, RGB sliders, hex). The pick is stored exactly,
/// as `pickedHex` (`colorHex` on the model), with its hue in `selection` beside
/// it; a preset clears it.
struct SubjectHueSwatchRow: View {
    @Binding var selection: Double?
    @Binding var pickedHex: String?

    @Environment(ThemeManager.self) private var themeManager

    private var pickedColor: Color? { pickedHex.flatMap(Color.init(hex:)) }

    /// The custom slot's hue: a picked colour's, or a stored hue that no
    /// preset claims (an older hue-only custom colour).
    private var customHue: Double? {
        selection.flatMap { hue in
            pickedHex != nil || !SubjectHueSwatches.all.contains { SubjectHueSwatches.matches($0, hue) }
                ? hue : nil
        }
    }

    private func isSelected(_ swatch: SubjectHueSwatches.Swatch) -> Bool {
        pickedHex == nil && SubjectHueSwatches.matches(swatch, selection)
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SubjectHueSwatches.all) { swatch in
                Button {
                    selection = isSelected(swatch) ? nil : swatch.hue
                    pickedHex = nil
                } label: {
                    swatchCircle(hue: swatch.hue, isSelected: isSelected(swatch))
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(isSelected(swatch) ? [.isButton, .isSelected] : .isButton)
            }
            customWell
            Spacer(minLength: 0)
        }
    }

    /// The row's last swatch (T-471): a `ColorPicker` well for any colour. The
    /// pick is stored exactly, as `pickedHex`, with its hue in `selection` beside
    /// it; a preset clears it.
    private var customWell: some View {
        CustomColorWell(
            label: "Custom colour",
            current: customHue != nil ? pickedColor : nil,
            fallback: pickedColor
                ?? themeManager.appTheme.subjectPalette(hue: selection ?? SubjectHueSwatches.all[0].hue).accent,
            selectionRing: customHue.map { themeManager.appTheme.subjectPalette(hue: $0).accent },
            onPick: { color in
                selection = color.hueComponent
                pickedHex = color.hexString
            }
        )
        .minimumHitTarget()
    }

    /// A preset is drawn as the wash it paints.
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
