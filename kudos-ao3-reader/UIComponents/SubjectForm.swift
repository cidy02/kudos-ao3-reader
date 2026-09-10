import SwiftUI

// The form-and-settings family — the parts every filter, picker, editor and
// settings screen in the spec is built from. Roughly fifty artboards
// (1ao–1au, 1av–1ax, 1bk–1bm, 1bn–1bs, 1bt–1by, 1bz–1ch) draw almost nothing
// else, and `Scripts/redesign-spec-inventory.py` ranks their two row shapes
// third and fifth by artboard spread: 300 uses of one across 26 artboards, 127
// of the other across 24.
//
// The two rows differ in exactly one thing, and it is worth stating because it
// is the rule for choosing between them:
//
//   .value   — the label flexes and the value trails it, right-aligned, with an
//              optional chevron. Reading order is "this setting → its state".
//   .control — the label hugs and the *control* flexes. The control is the row;
//              the label just names it.
//
// The spec gives them different padding (12×14 against 11×14) and different
// gaps (10 against 12) for that reason: a trailing value wants air between it
// and the chevron, a stretched control wants air between it and the label.

/// The glass panel a group of rows sits on — shape #13, 35 artboards, and the
/// same ground `SubjectStatStrip` already draws on. One definition so a form
/// card and a figure strip on the same screen cannot end up half a point apart.
///
/// `isFilled` is off for spec 1a's grouped facts card, which is an outline over
/// the page wash rather than a panel on it: that card sits inside the work's own
/// colour and a fill would mute it.
struct SubjectPanelBackground: ViewModifier {
    var cornerRadius: CGFloat = 14
    var isFilled: Bool = true

    @Environment(ThemeManager.self) private var themeManager

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let theme = themeManager.appTheme
        return content
            .background(shape.fill(isFilled ? theme.glassFill(0.09) : Color.clear))
            .overlay(shape.strokeBorder(theme.glassStroke(0.13), lineWidth: 0.5))
    }
}

extension View {
    /// Rounded glass ground with a hairline, for a group of form rows or a
    /// figure strip.
    func subjectPanel(cornerRadius: CGFloat = 14, isFilled: Bool = true) -> some View {
        modifier(SubjectPanelBackground(cornerRadius: cornerRadius, isFilled: isFilled))
    }
}

/// The hairline between two rows in a panel.
///
/// Drawn by the row below it rather than placed between rows by the container.
/// A container that interleaves separators has to take its children as a list
/// it can index, which in SwiftUI means either `_VariadicView` or giving up the
/// ViewBuilder — and the row already knows whether something precedes it,
/// because its caller does. `inset` is the spec's own: 14pt on a filled panel so
/// the line starts under the label, 0 on an outlined card where it reads as a
/// division of the card itself.
struct SubjectRowSeparator: View {
    var inset: CGFloat = 14

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Rectangle()
            .fill(themeManager.appTheme.glassStroke(0.09))
            .frame(height: 0.5)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// One row of a settings, filter or editor panel.
///
/// Both arrangements take a tap action or none. A row with no action and no
/// chevron is a statement — "Conversion · Up to date" — and must not look
/// tappable, so the chevron is a separate flag rather than something inferred
/// from the presence of an action.
struct SubjectFormRow<Trailing: View>: View {
    /// Which of the spec's two arrangements this row takes.
    enum Arrangement {
        /// Label flexes, trailing content sits at the right edge (padding 12×14,
        /// gap 10). The common settings row.
        case value
        /// Label hugs, trailing content takes the remaining width (padding
        /// 11×14, gap 12). For a row whose control *is* the row.
        case control

        var horizontalGap: CGFloat {
            switch self {
            case .value: 10
            case .control: 12
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .value: 12
            case .control: 11
            }
        }
    }

    let label: String
    var arrangement: Arrangement = .value
    /// The spec's disclosure chevron. Independent of `action`: a row can act
    /// without pushing (a toggle) and can push without a chevron never happens,
    /// but a row can very well state a fact and do nothing at all.
    var showsDisclosure: Bool = false
    /// Dims the label and trailing content without removing the row — a filter
    /// that cannot apply to the current scope still belongs in the list, saying
    /// so, rather than vanishing and changing the shape of the panel.
    var isDisabled: Bool = false
    /// Colours the label with the system's destructive red — "Remove AO3
    /// session", "Sign out", "Delete work". A flag on the row rather than a
    /// `.foregroundStyle(.red)` at the call site, because the label sets its own
    /// colour internally and would win: a caller tinting the row from outside
    /// gets a red chevron and a black label, which is worse than no red at all.
    var isDestructive: Bool = false
    var action: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        if let action {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        // Written as a statement rather than a ternary inside `frame`: the
        // argument is `CGFloat?` and the branches are `.infinity` and `nil`,
        // which is exactly the shape that makes the type checker work for it.
        var labelWidth: CGFloat?
        if arrangement == .value {
            labelWidth = .infinity
        }
        let labelHugs: Bool = arrangement == .control
        return HStack(spacing: arrangement.horizontalGap) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(isDestructive ? Color.red : .primary)
                .frame(maxWidth: labelWidth, alignment: .leading)
                .fixedSize(horizontal: labelHugs, vertical: false)

            trailing()

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, arrangement.verticalPadding)
        .opacity(isDisabled ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}

extension SubjectFormRow where Trailing == SubjectFormValue {
    /// The overwhelmingly common row: a label and the value it currently holds.
    init(
        label: String,
        value: String,
        arrangement: Arrangement = .value,
        showsDisclosure: Bool = false,
        isDisabled: Bool = false,
        isDestructive: Bool = false,
        isMonospaced: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            label: label,
            arrangement: arrangement,
            showsDisclosure: showsDisclosure,
            isDisabled: isDisabled,
            isDestructive: isDestructive,
            action: action,
            trailing: { SubjectFormValue(text: value, isMonospaced: isMonospaced) }
        )
    }
}

/// A row's trailing value. `isMonospaced` is the spec's `500 11px ui-monospace`
/// (shape #32, 21 artboards) — reserved for figures the reader compares down a
/// column, dates and counts, where proportional digits make a ragged edge.
struct SubjectFormValue: View {
    let text: String
    var isMonospaced: Bool = false

    var body: some View {
        Text(text)
            .font(valueFont)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var valueFont: Font {
        if isMonospaced {
            return .system(size: 11, weight: .medium, design: .monospaced)
        }
        return .system(size: 15)
    }
}

/// The inline segmented control a `.control` row carries — spec 1ao's
/// Ascending / Descending, and the same shape wherever a form offers two or
/// three mutually exclusive words.
///
/// Not a `Picker(.segmented)`: the spec's is 9pt-radius over a 7pt-radius
/// selection on a glass ground, and `WorkDetailView`'s own notes record that a
/// native segmented picker clips rather than reflows at accessibility text
/// sizes. This one lets its labels scale and shrink instead.
struct SubjectSegmentedControl<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                segment(for: option)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(themeManager.appTheme.glassFill(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(themeManager.appTheme.glassStroke(0.13), lineWidth: 0.5)
                )
        )
    }

    private func segment(for option: Value) -> some View {
        let isSelected: Bool = option == selection
        return Button {
            selection = option
        } label: {
            Text(title(option))
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selectionBackground(isSelected: isSelected))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func selectionBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(themeManager.appTheme.glassFill(0.16))
        }
    }
}
