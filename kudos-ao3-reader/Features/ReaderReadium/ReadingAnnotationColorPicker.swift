#if os(iOS)
import SwiftUI

/// Shared highlight-colour swatches for the post-highlight bar and the note editor.
struct ReadingAnnotationColorPicker: View {
    let selected: ReadingAnnotationColor
    let onSelect: (ReadingAnnotationColor) -> Void
    /// Compact row for the floating bar; the note editor uses the default size.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            ForEach(ReadingAnnotationColor.allCases, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    swatch(for: option)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected == option ? [.isSelected] : [])
            }
        }
    }

    private func swatch(for option: ReadingAnnotationColor) -> some View {
        let isSelected = selected == option
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
                isSelected ? Color.accentColor : Color.primary.opacity(0.12),
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
    let selected: ReadingAnnotationColor
    let onSelect: (ReadingAnnotationColor) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ReadingAnnotationColorPicker(
                selected: selected,
                onSelect: onSelect,
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

    /// Last colour the reader picked for a highlight; new marks start with this
    /// so the floating bar is a refine step, not a required pre-pick.
    static var lastUsed: ReadingAnnotationColor {
        get {
            let raw = UserDefaults.standard.string(forKey: lastUsedDefaultsKey) ?? ""
            return ReadingAnnotationColor(rawValue: raw) ?? .yellow
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: lastUsedDefaultsKey)
        }
    }
}
#endif
