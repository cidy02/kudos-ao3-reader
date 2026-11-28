#if os(iOS)
import SwiftUI

/// Shared highlight-colour swatches for the post-highlight bar and the note editor.
struct ReadingAnnotationColorPicker: View {
    @Environment(\.accentFill) private var fill
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?
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
        HStack(spacing: compact ? 6 : 14) {
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
                label: ReaderNoteCopy.moreColoursAccessibilityLabel,
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
        let gapColor = themeManager?.appTheme.cardSurface ?? Color(.systemBackground)
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
            if isSelected {
                Circle()
                    .strokeBorder(gapColor, lineWidth: 2)
                    .padding(1.5)
                Circle()
                    .strokeBorder(option.tint, lineWidth: 2)
            } else {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .contentShape(Circle())
    }
}

/// Floating glass bar shown right after **Highlight**, so colour, Note, and
/// Delete are reachable directly over the page (`Reader-Highlight`).
struct ReaderHighlightColorBar: View {
    let selectedRaw: String
    let onSelectRaw: (String) -> Void
    let onDismiss: () -> Void
    var onEditNote: (() -> Void)?
    var onDelete: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ThemeManager.self) private var themeManager: ThemeManager?

    private var hasTrailingActions: Bool {
        onEditNote != nil || onDelete != nil
    }

    private var deleteColor: Color {
        themeManager?.appTheme.errorColor ?? .red
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    ReadingAnnotationColorPicker(
                        selectedRaw: selectedRaw,
                        onSelectRaw: onSelectRaw,
                        compact: true
                    )
                    if hasTrailingActions {
                        HStack(spacing: 12) {
                            noteAndDeleteActions
                            dismissButton
                        }
                    } else {
                        dismissButton
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
                )
            } else {
                HStack(spacing: 4) {
                    ReadingAnnotationColorPicker(
                        selectedRaw: selectedRaw,
                        onSelectRaw: onSelectRaw,
                        compact: true
                    )
                    if hasTrailingActions {
                        Rectangle()
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 1, height: 24)
                            .padding(.horizontal, 4)
                            .accessibilityHidden(true)
                        noteAndDeleteActions
                    } else {
                        dismissButton
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 48)
                .glassEffect(.regular, in: Capsule())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ReaderNoteCopy.toolbarAccessibilityLabel)
        .accessibilityAction(.escape, onDismiss)
    }

    @ViewBuilder
    private var noteAndDeleteActions: some View {
        if let onEditNote {
            Button(action: onEditNote) {
                Text("Note")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 36)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Note")
        }

        if let onDelete {
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(deleteColor)
                    .frame(width: 34, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ReaderNoteCopy.deleteHighlightAccessibilityLabel)
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondaryInk)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss colour picker")
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
