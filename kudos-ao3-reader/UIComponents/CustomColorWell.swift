import SwiftUI

/// The last swatch of every colour row (T-471): a SwiftUI `ColorPicker` well for
/// any colour, drawn as the system's rainbow ring with the current colour in its
/// middle — the boards' "More colours" button. Opacity is not offered: every
/// colour stored in the app is an opaque `#RRGGBB` (`Color.hexString`), the same
/// string the presets' own custom values use.
///
/// The picker's binding fires on every step of a slider drag, and the callers
/// write straight to the store (a highlight redraws the page, a collection saves),
/// so a pick is reported once the person pauses — or when the well leaves the
/// screen — rather than on every step. The unfinished drag is never lost.
struct CustomColorWell: View {
    /// Spoken by VoiceOver ("Custom colour").
    let label: String
    /// The stored custom colour, or `nil` while a preset (or nothing) is chosen.
    let current: Color?
    /// What the well shows, and the picker opens on, until a colour is chosen.
    let fallback: Color
    /// A ring drawn around the well while its colour is the selection, as the
    /// preset swatches draw theirs. `nil` draws none.
    var selectionRing: Color?
    var size: CGFloat = 28
    let onPick: (Color) -> Void

    @State private var draft: Color
    @State private var pending: Color?
    @State private var commitTask: Task<Void, Never>?
    /// The hex last reported, or the colour the well opened on. `ColorPicker`
    /// writes its opening colour back into the binding; that is not a choice,
    /// and storing it would turn a preset into a custom colour just by showing
    /// the well.
    @State private var committedHex: String

    init(
        label: String,
        current: Color?,
        fallback: Color,
        selectionRing: Color? = nil,
        size: CGFloat = 28,
        onPick: @escaping (Color) -> Void
    ) {
        self.label = label
        self.current = current
        self.fallback = fallback
        self.selectionRing = selectionRing
        self.size = size
        self.onPick = onPick
        let opening = current ?? fallback
        _draft = State(initialValue: opening)
        _committedHex = State(initialValue: opening.hexString)
    }

    var body: some View {
        ColorPicker(label, selection: $draft, supportsOpacity: false)
            .labelsHidden()
            .frame(width: size, height: size)
            .padding(3)
            .overlay {
                if let selectionRing {
                    Circle().strokeBorder(selectionRing, lineWidth: 2.5)
                }
            }
            .accessibilityLabel(label)
            .accessibilityValue(current?.hexString ?? "")
            .accessibilityAddTraits(current != nil ? .isSelected : [])
            .onChange(of: draft) { _, newValue in
                pending = newValue
                commitTask?.cancel()
                commitTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    flush()
                }
            }
            .onChange(of: externalColorToken) { _, _ in
                adoptExternalColor()
            }
            .onDisappear {
                commitTask?.cancel()
                flush()
            }
    }

    /// Preset taps and other writers change `current` without going through the
    /// picker. Follow them, and don't report that as a new pick.
    private var externalColorToken: String {
        (current?.hexString ?? "-") + "|" + fallback.hexString
    }

    private func adoptExternalColor() {
        guard pending == nil else { return }
        let adopted = current ?? fallback
        let hex = adopted.hexString
        guard hex != committedHex else { return }
        committedHex = hex
        draft = adopted
    }

    private func flush() {
        guard let color = pending else { return }
        pending = nil
        let hex = color.hexString
        guard hex != committedHex else { return }
        committedHex = hex
        onPick(color)
    }
}
