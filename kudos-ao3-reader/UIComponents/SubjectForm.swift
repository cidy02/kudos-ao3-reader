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

/// A `List` row drawn as one segment of a `subjectPanel` card.
///
/// For lists whose rows must stay real `List` rows — `.onMove` only reorders
/// those — so the card cannot be one `VStack` with `.subjectPanel()` on it.
/// The first row rounds the card's top corners, the last its bottom, and every
/// row but the last draws the panel's inset hairline under itself, so a column
/// of these reads as the single card 1br draws. Without it the reorder screens
/// drew their rows as a full-bleed opaque band, edge to edge, under a header
/// block that sat on the wash with a gutter.
///
/// ponytail: fill and hairlines only — `subjectPanel`'s 0.5pt outer stroke is
/// not drawn, because stroking each segment would put a full-width line
/// between every pair of rows. Draw an open-edged stroke if the edge is missed.
struct SubjectPanelSegmentRow: ViewModifier {
    var isFirst: Bool
    var isLast: Bool
    var gutter: CGFloat
    /// Off for a `SubjectFormRow`, which carries its own 14pt row padding — and
    /// then the trailing inset is the card's edge, not room for a drag handle.
    var padsContent: Bool = true
    var cornerRadius: CGFloat = 14

    @Environment(ThemeManager.self) private var themeManager

    func body(content: Content) -> some View {
        let theme = themeManager.appTheme
        let top: CGFloat = isFirst ? cornerRadius : 0
        let bottom: CGFloat = isLast ? cornerRadius : 0
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
        let contentInset: CGFloat = padsContent ? 14 : 0
        let verticalInset: CGFloat = padsContent ? 11 : 0
        // With padded content the trailing inset is wider than the card's own
        // edge so the system's drag handle sits inside the card, not on its rim.
        let trailing: CGFloat = padsContent ? gutter + 8 : gutter
        return content
            .padding(.leading, contentInset)
            .padding(.vertical, verticalInset)
            .listRowInsets(EdgeInsets(top: 0, leading: gutter, bottom: 0, trailing: trailing))
            .listRowSeparator(.hidden)
            .listRowBackground(
                shape
                    .fill(theme.glassFill(0.09))
                    .overlay(alignment: .bottom) {
                        if !isLast { SubjectRowSeparator() }
                    }
                    .padding(.horizontal, gutter)
            )
    }
}

/// A row of a `SubjectPanelSegmentRow` column with the key its `ForEach` must
/// use. `List` keeps a cell's `listRowBackground` across `.onMove`, so keying
/// on the element alone left a row that stopped being first or last with its
/// old rounded corners — measured on the simulator after one drag. Folding the
/// edge position into the key rebuilds just the rows whose edge changed.
struct PanelSegment<Element> {
    let offset: Int
    let element: Element
    let key: String

    static func keyed<ID: Hashable>(_ elements: [Element], id: KeyPath<Element, ID>) -> [PanelSegment] {
        let last = elements.count - 1
        return elements.enumerated().map { offset, element in
            PanelSegment(
                offset: offset,
                element: element,
                key: "\(element[keyPath: id])|\(offset == 0)|\(offset == last)"
            )
        }
    }
}

extension View {
    /// One segment of a panel card, for a `List` row that has to stay a row.
    /// A `SubjectFormRow` as segment `index` of a `count`-row card — the
    /// shape every multi-link card needs so each link gets its own `List` row.
    func panelSegment(_ index: Int, of count: Int, gutter: CGFloat) -> some View {
        subjectPanelSegmentRow(
            isFirst: index == 0, isLast: index == count - 1, gutter: gutter, padsContent: false
        )
    }

    func subjectPanelSegmentRow(
        isFirst: Bool,
        isLast: Bool,
        gutter: CGFloat,
        padsContent: Bool = true
    ) -> some View {
        modifier(SubjectPanelSegmentRow(
            isFirst: isFirst, isLast: isLast, gutter: gutter, padsContent: padsContent
        ))
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
        // `.control`'s trailing content "takes the remaining width", as the
        // arrangement promises — which it did not: a hidden-label `Toggle`, a
        // menu `Picker` or a `Menu` label is intrinsically sized, so with the
        // label hugging too the whole row hugged. Inside a panel whose
        // separators stretch it, the VStack then CENTRED the row (New
        // collection's two toggles sat mid-card, out of line with each other);
        // a lone row shrank the panel to fit (New queue's Offline card).
        // Expanding controls — a trailing-aligned `TextField`, a segmented
        // picker — already filled the width, so this changes nothing for them.
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

            // `.control` only. Wrapped so a multi-view `trailing` is framed as
            // one group, with the gap the outer stack gave it. `.value` keeps
            // the bare closure, byte-identical to before: an
            // `HStack { EmptyView() }` would be a real zero-width child that the
            // outer stack spaces, taking 10pt of label width from the three
            // disclosure-only rows whose trailing is `EmptyView`.
            if arrangement == .control {
                HStack(spacing: arrangement.horizontalGap) {
                    trailing()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                trailing()
            }

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
