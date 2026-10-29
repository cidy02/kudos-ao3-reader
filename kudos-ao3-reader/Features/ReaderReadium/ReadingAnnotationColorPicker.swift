#if os(iOS)
import SwiftUI

/// Shared highlight-colour swatches for the post-highlight bar and the note editor.
struct ReadingAnnotationColorPicker: View {
    @Environment(\.accentFill) private var fill
    /// A preset's raw value, or a well colour's `#RRGGBB`.
    let selectedRaw: String
    let onSelectRaw: (String) -> Void
    /// Compact row for the floating bar; the note editor uses the default size.
    var compact = false

    private var selectedPreset: ReadingAnnotationColor? {
        ReadingAnnotationColor(rawValue: selectedRaw)
    }

    private var customColor: Color? {
        ReadingAnnotationColorStorage.customHex(fromRaw: selectedRaw).flatMap(Color.init(hex:))
    }

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            ForEach(ReadingAnnotationColor.allCases, id: \.self) { option in
                Button {
                    onSelectRaw(option.rawValue)
                } label: {
                    swatch(for: option)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selectedPreset == option ? [.isSelected] : [])
            }
            CustomColorWell(
                label: "Custom colour",
                current: customColor,
                fallback: (selectedPreset ?? .yellow).tint,
                selectionRing: customColor == nil ? nil : fill,
                size: compact ? 28 : 32,
                onPick: { onSelectRaw($0.hexString) }
            )
        }
    }

    private func swatch(for option: ReadingAnnotationColor) -> some View {
        let isSelected = selectedPreset == option
        let size: CGFloat = compact ? 28 : 32
        return ZStack {
            // Underline isn't a fill, so its swatch shows a rule rather than a
            // solid disc — the swatch should look like what lands on the page.
            if option == .underline {
                Circle().strokeBorder(Color.primary.opacity(0.15))
                Rectangle()
                    .fill(option.tint)
                    .frame(width: compact ? 16 : 20, height: 3)
            } else {
                Circle().fill(option.tint)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Circle().strokeBorder(
                isSelected ? fill : Color.primary.opacity(0.12),
                lineWidth: isSelected ? 3 : 1
            )
        }
        .contentShape(Circle())
    }
}

/// Floating glass bar shown right after **Highlight**, so colour is chosen
/// without burying it in the system selection menu (which only supports flat
/// actions) or forcing a trip through the note editor.
struct ReaderHighlightColorBar: View {
    let selectedRaw: String
    let onSelectRaw: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ReadingAnnotationColorPicker(
                selectedRaw: selectedRaw,
                onSelectRaw: onSelectRaw,
                compact: true
            )

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss colour picker")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Highlight colour")
    }
}

extension ReadingAnnotationColor {
    static let lastUsedDefaultsKey = "readerHighlightColor"

    /// Last colour the reader picked: a preset name, or a well colour's `#RRGGBB`.
    /// New marks start with this so the floating bar is a refine step, not a
    /// required pre-pick. The preset-only `lastUsed` reads this and falls back
    /// to yellow when the stored value is a custom hex.
    static var lastUsedRaw: String {
        get {
            let raw = UserDefaults.standard.string(forKey: lastUsedDefaultsKey) ?? ""
            let fallback = raw.isEmpty ? ReadingAnnotationColor.yellow.rawValue : raw
            return ReadingAnnotationColorStorage.normalizedRaw(fallback)
        }
        set {
            UserDefaults.standard.set(
                ReadingAnnotationColorStorage.normalizedRaw(newValue),
                forKey: lastUsedDefaultsKey
            )
        }
    }

    static var lastUsed: ReadingAnnotationColor {
        get { ReadingAnnotationColor(rawValue: lastUsedRaw) ?? .yellow }
        set { lastUsedRaw = newValue.rawValue }
    }
}
#endif
