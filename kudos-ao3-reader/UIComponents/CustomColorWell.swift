import SwiftUI

/// Debounce/commit rules for `CustomColorWell`. A drag is pending until flush;
/// a preset (or any other external writer) drops it so it cannot overwrite that
/// choice; Cancel discards it so disappear does not save a colour the user
/// threw away. Extracted so the state machine can be tested without a picker.
struct CustomColorWellMachine {
    var pending: Color?
    var committedHex: String
    var discarded = false

    mutating func noteDrag(_ color: Color) {
        guard !discarded else { return }
        pending = color
    }

    /// Preset taps and other writers of `current`. Drops an unfinished drag so
    /// it cannot overwrite the external colour after the debounce.
    mutating func adoptExternal(_ color: Color) {
        pending = nil
        committedHex = color.hexString
    }

    mutating func flush() -> Color? {
        defer { pending = nil }
        guard !discarded, let color = pending else { return nil }
        let hex = color.hexString
        guard hex != committedHex else { return nil }
        committedHex = hex
        return color
    }

    mutating func discard() {
        pending = nil
        discarded = true
    }
}

/// Lets a parent flush or discard the well's pending drag before it reads the
/// value or dismisses. Create calls `flush()` so `options` already holds the
/// dragged colour; Cancel calls `discard()` so disappear does not write it.
@MainActor
final class CustomColorWellSession {
    var flush: () -> Void = {}
    var discard: () -> Void = {}
}

private struct CustomColorWellSessionKey: EnvironmentKey {
    static let defaultValue: CustomColorWellSession? = nil
}

extension EnvironmentValues {
    var customColorWellSession: CustomColorWellSession? {
        get { self[CustomColorWellSessionKey.self] }
        set { self[CustomColorWellSessionKey.self] = newValue }
    }
}

/// The last swatch of every colour row (T-471): a SwiftUI `ColorPicker` well for
/// any colour, drawn as the system's rainbow ring with the current colour in its
/// middle — the boards' "More colours" button. Opacity is not offered: every
/// colour stored in the app is an opaque `#RRGGBB` (`Color.hexString`), the same
/// string the presets' own custom values use.
///
/// The picker's binding fires on every step of a slider drag, and the callers
/// write straight to the store (a highlight redraws the page, a collection saves),
/// so a pick is reported once the person pauses — or when the well leaves the
/// screen — rather than on every step. The unfinished drag is never lost, unless
/// Cancel discarded it.
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

    @Environment(\.customColorWellSession) private var session
    @State private var draft: Color
    @State private var machine: CustomColorWellMachine
    @State private var commitTask: Task<Void, Never>?

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
        _machine = State(initialValue: CustomColorWellMachine(committedHex: opening.hexString))
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
                machine.noteDrag(newValue)
                bindSession()
                commitTask?.cancel()
                commitTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    reportFlush()
                }
            }
            .onChange(of: externalColorToken) { _, _ in
                adoptExternalColor()
            }
            .onAppear { bindSession() }
            .onDisappear {
                commitTask?.cancel()
                session?.flush = {}
                session?.discard = {}
                reportFlush()
            }
    }

    /// Preset taps and other writers change `current` without going through the
    /// picker. Follow them, and don't report that as a new pick.
    private var externalColorToken: String {
        (current?.hexString ?? "-") + "|" + fallback.hexString
    }

    private func adoptExternalColor() {
        commitTask?.cancel()
        let adopted = current ?? fallback
        machine.adoptExternal(adopted)
        draft = adopted
        bindSession()
    }

    private func reportFlush() {
        commitTask?.cancel()
        if let color = machine.flush() {
            onPick(color)
        }
    }

    private func discardPending() {
        commitTask?.cancel()
        machine.discard()
    }

    private func bindSession() {
        session?.flush = reportFlush
        session?.discard = discardPending
    }
}
