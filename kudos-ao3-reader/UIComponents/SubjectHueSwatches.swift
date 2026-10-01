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
/// On iOS the row ends in 1j's dashed "+": the system colour picker (grid,
/// spectrum, RGB sliders, hex) that Settings' Accent Color opens. Only the
/// picked colour's hue is kept — the same as the swatches — so a custom colour
/// still takes each theme's own saturation and brightness.
struct SubjectHueSwatchRow: View {
    @Binding var selection: Double?

    @Environment(ThemeManager.self) private var themeManager
    @State private var showingCustom = false

    /// A hue that no preset swatch claims — one picked with "+".
    private var customHue: Double? {
        selection.flatMap { hue in
            SubjectHueSwatches.all.contains { SubjectHueSwatches.matches($0, hue) } ? nil : hue
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SubjectHueSwatches.all) { swatch in
                Button {
                    selection = SubjectHueSwatches.matches(swatch, selection) ? nil : swatch.hue
                } label: {
                    swatchCircle(
                        hue: swatch.hue,
                        isSelected: SubjectHueSwatches.matches(swatch, selection)
                    )
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(
                    SubjectHueSwatches.matches(swatch, selection) ? [.isButton, .isSelected] : .isButton
                )
            }
            #if os(iOS)
            customButton
            #endif
            Spacer(minLength: 0)
        }
    }

    #if os(iOS)
    /// The dashed "+" until a custom colour is picked, then that colour,
    /// selected; tapping either opens the picker.
    private var customButton: some View {
        Button {
            showingCustom = true
        } label: {
            if let customHue {
                swatchCircle(hue: customHue, isSelected: true)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle().strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                    )
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel("Custom colour")
        .accessibilityAddTraits(customHue != nil ? [.isButton, .isSelected] : .isButton)
        .background(
            SystemColorPicker(
                isPresented: $showingCustom,
                initial: themeManager.appTheme.carouselQueueTint(hue: selection ?? SubjectHueSwatches.all[0].hue),
                onPick: { color in
                    var hue: CGFloat = 0
                    color.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
                    selection = Double(hue)
                }
            )
        )
    }
    #endif

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

#if os(iOS)
/// Presents `UIColorPickerViewController` the way `ColorPicker`'s well does —
/// modally, with its own close button. (Embedded in a SwiftUI sheet it loses
/// that button and has no visible way out.) It reports only the colour a person
/// lands on, not every step of a slider drag, so a binding that writes straight
/// to the store (a collection's Colour row) saves once per pick.
private struct SystemColorPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let initial: Color
    let onPick: (UIColor) -> Void

    func makeUIViewController(context _: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = UIColorPickerViewController()
        // Resolved, or the picker previews a dynamic colour's light and dark
        // halves side by side.
        picker.selectedColor = UIColor(initial).resolvedColor(with: host.traitCollection)
        picker.supportsAlpha = false
        picker.delegate = context.coordinator
        picker.presentationController?.delegate = context.coordinator
        host.present(picker, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate,
        UIAdaptivePresentationControllerDelegate {
        var parent: SystemColorPicker

        init(parent: SystemColorPicker) { self.parent = parent }

        func colorPickerViewController(
            _: UIColorPickerViewController,
            didSelect color: UIColor,
            continuously: Bool
        ) {
            if !continuously { parent.onPick(color) }
        }

        func colorPickerViewControllerDidFinish(_: UIColorPickerViewController) {
            parent.isPresented = false
        }

        /// Swiped down rather than closed.
        func presentationControllerDidDismiss(_: UIPresentationController) {
            parent.isPresented = false
        }
    }
}
#endif
