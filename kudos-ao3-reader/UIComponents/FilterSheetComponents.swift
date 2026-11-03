import SwiftUI

// MARK: - Settings-style icon tile

/// A 29×29 pt icon tile with a 7 pt corner radius, matching iOS Settings icons.
/// Used on filter sheet picker rows (spec boards 03, 12, rule I-7).
struct SettingsIconTile: View {
    let color: Color
    let systemImage: String

    init(color: Color, systemImage: String) {
        self.color = color
        self.systemImage = systemImage
    }

    init(hex: String, systemImage: String, fallback: Color = .gray) {
        self.color = Color(hex: hex) ?? fallback
        self.systemImage = systemImage
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 29, height: 29)
        .accessibilityHidden(true)
    }
}

// MARK: - Single symbol tile view (22 pt)

/// Renders a single 22 pt symbol tile inside a filter chip (rule I-2).
struct WorkSymbolTileView: View {
    let symbol: WorkSymbolTile
    var side: CGFloat = 22

    var body: some View {
        ZStack {
            if symbol.mark == .multi {
                multiQuadrants
            } else {
                symbol.fill
                glyph
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * WorkStatusIconGrid.cornerRadiusRatio, style: .continuous))
    }

    @ViewBuilder
    private var glyph: some View {
        switch symbol.mark {
        case .shield(let letter):
            let box = side * WorkSymbolTile.shieldBoxRatio
            ZStack {
                WorkSymbolTile.path(for: symbol.mark, in: box)
                    .fill(symbol.ink)
                Text(letter)
                    .font(.system(size: side * 0.36, weight: .heavy, design: .rounded))
                    .foregroundStyle(symbol.fill)
                    .offset(y: box * WorkSymbolTile.shieldBodyOffset)
            }
            .frame(width: box, height: box)
        case .exclamation, .question:
            Image(systemName: symbol.mark == .exclamation ? "exclamationmark" : "questionmark")
                .font(.system(size: side * 0.6, weight: .heavy))
                .foregroundStyle(symbol.ink)
                .frame(width: side * WorkSymbolTile.glyphBoxRatio, height: side * WorkSymbolTile.glyphBoxRatio)
        default:
            let box = side * WorkSymbolTile.glyphBoxRatio
            WorkSymbolTile.path(for: symbol.mark, in: box)
                .fill(symbol.ink)
                .frame(width: box, height: box)
        }
    }

    private var multiQuadrants: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AO3TagPalette.general
                AO3TagPalette.femaleMale
            }
            HStack(spacing: 0) {
                AO3TagPalette.femaleFemale
                AO3TagPalette.maleMale
            }
        }
    }
}

// MARK: - Two-column symbol chip card (Include → Exclude → not set)

/// Two-column symbol chip card cycling Include → Exclude → not set (boards 03, 12, rule I-11).
struct FilterSymbolChipCard: View {
    let title: String
    var fullTitle: String?
    let symbol: WorkSymbolTile
    let state: FilterSelectionState
    let onCycle: () -> Void

    @Environment(ThemeManager.self) private var theme

    private var isDark: Bool {
        theme.appTheme == .dark || theme.appTheme == .oled
    }

    var body: some View {
        Button(action: onCycle) {
            HStack(spacing: 8) {
                WorkSymbolTileView(symbol: symbol, side: 22)
                    .opacity(state == .excluded ? 0.4 : 1.0)

                // Boards 03/12 wrap long warnings ("Creator Chose Not To Use") instead of truncating.
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(foreground)
                    .strikethrough(state == .excluded, color: strokeColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                indicator
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: state == .clear ? 0 : 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(fullTitle ?? title), \(state.accessibilityStatus ?? "not set")")
        .accessibilityAddTraits(state == .included ? [.isSelected] : [])
        .accessibilityHint("Tap to \(state.nextActionLabel.lowercased())")
    }

    private var indicator: some View {
        ZStack {
            switch state {
            case .clear:
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 18, height: 18)
            case .included:
                Circle()
                    .fill(theme.appTheme.includeColor)
                    .frame(width: 18, height: 18)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            case .excluded:
                Circle()
                    .fill(theme.appTheme.excludeColor)
                    .frame(width: 18, height: 18)
                Image(systemName: "minus")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 18, height: 18)
    }

    private var foreground: Color {
        switch state {
        case .clear:
            return .primary
        case .included:
            return theme.appTheme.includeColor
        case .excluded:
            return theme.appTheme.excludeColor
        }
    }

    private var cardBackground: Color {
        switch state {
        case .clear:
            return theme.appTheme.cardBackdrop
        case .included:
            return theme.appTheme.includeColor.opacity(0.12)
        case .excluded:
            return theme.appTheme.excludeColor.opacity(0.08)
        }
    }

    private var strokeColor: Color {
        switch state {
        case .clear:
            return .clear
        case .included:
            return theme.appTheme.includeColor
        case .excluded:
            return theme.appTheme.excludeColor
        }
    }
}

// MARK: - Active filters block & chips

/// An active filter chip representation.
struct ActiveFilterItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case included
        case excluded
        case facetValue
    }

    let id: String
    let label: String
    let kind: Kind
    var onRemove: () -> Void

    static func == (lhs: ActiveFilterItem, rhs: ActiveFilterItem) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.kind == rhs.kind
    }
}

/// A removable active filter chip (struck through when excluded).
struct ActiveFilterChipView: View {
    let item: ActiveFilterItem
    @Environment(ThemeManager.self) private var theme

    private var isDark: Bool {
        theme.appTheme == .dark || theme.appTheme == .oled
    }

    var body: some View {
        Button(action: item.onRemove) {
            HStack(spacing: 4) {
                switch item.kind {
                case .included:
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                case .excluded:
                    Image(systemName: "minus")
                        .font(.caption2.weight(.bold))
                case .facetValue:
                    EmptyView()
                }

                Text(item.label)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(item.kind == .excluded, color: foreground)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 30)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.label)\(accessibilitySuffix)")
        .accessibilityHint("Removes this filter")
    }

    private var foreground: Color {
        switch item.kind {
        case .included:
            return theme.appTheme.includeColor
        case .excluded:
            return theme.appTheme.excludeColor
        case .facetValue:
            return .primary
        }
    }

    private var background: Color {
        switch item.kind {
        case .included:
            return theme.appTheme.includeColor.opacity(0.12)
        case .excluded:
            return theme.appTheme.excludeColor.opacity(0.08)
        case .facetValue:
            if isDark {
                return Color(white: 0.22)
            } else {
                return theme.appTheme.cardBackdrop
            }
        }
    }

    private var accessibilitySuffix: String {
        switch item.kind {
        case .included:
            return ", included"
        case .excluded:
            return ", excluded"
        case .facetValue:
            return ""
        }
    }
}

/// The Active filters block at the top of the filter panel (boards 03, 12).
struct ActiveFiltersBlock: View {
    let items: [ActiveFilterItem]
    let onClearAll: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Active")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(items.count) \(items.count == 1 ? "filter" : "filters")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Clear All", action: onClearAll)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.appTheme.errorColor)
                }
                .padding(.horizontal, 4)

                FlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(items) { item in
                        ActiveFilterChipView(item: item)
                    }
                }
            }
            .padding(12)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Length Presets & Word Range

/// Six length presets (boards 03, 12): Any, <1k, 1k–10k, 10k+, 50k+, Custom.
enum FilterLengthPreset: String, CaseIterable, Identifiable {
    case any = "Any"
    case under1k = "Under 1k"
    case oneTo10k = "1k–10k"
    case tenPlus = "10k+"
    case fiftyPlus = "50k+"
    case custom = "Custom"

    var id: String { rawValue }

    static func matching(from: String, to: String) -> FilterLengthPreset {
        let lowerBound = FilterTextMatching.bound(from)
        let upperBound = FilterTextMatching.bound(to)
        switch (lowerBound, upperBound) {
        case (nil, nil):
            return .any
        case (nil, 1000):
            return .under1k
        case (1000, 10000):
            return .oneTo10k
        case (10000, nil):
            return .tenPlus
        case (50000, nil):
            return .fiftyPlus
        default:
            return .custom
        }
    }

    func apply(to from: inout String, to: inout String) {
        switch self {
        case .any:
            from = ""
            to = ""
        case .under1k:
            from = ""
            to = "1000"
        case .oneTo10k:
            from = "1000"
            to = "10000"
        case .tenPlus:
            from = "10000"
            to = ""
        case .fiftyPlus:
            from = "50000"
            to = ""
        case .custom:
            break
        }
    }
}

/// The Length presets buttons and From/To word count fields (boards 03, 12).
struct FilterLengthSection: View {
    @Binding var wordsFrom: String
    @Binding var wordsTo: String

    @Environment(ThemeManager.self) private var theme

    private var selectedPreset: FilterLengthPreset {
        FilterLengthPreset.matching(from: wordsFrom, to: wordsTo)
    }

    private var effectiveAccent: Color {
        theme.effectiveTint
    }

    private var unselectedPresetFill: Color {
        theme.appTheme.cardSurface
    }

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(FilterLengthPreset.allCases) { preset in
                    let isSelected = selectedPreset == preset
                    Button {
                        preset.apply(to: &wordsFrom, to: &wordsTo)
                    } label: {
                        Text(preset.rawValue)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 32)
                            .padding(.vertical, 4)
                            .background(isSelected ? effectiveAccent : unselectedPresetFill)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(preset.rawValue) word length preset")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }

            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Words")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    TextField("", text: FilterRangeSlider.digitsOnly($wordsFrom), prompt: Text("from"))
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Word count from")
                        #if !os(macOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                .padding(.horizontal, 16)

                Divider()
                    .frame(height: 24)

                HStack(spacing: 8) {
                    Text("to")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    TextField("", text: FilterRangeSlider.digitsOnly($wordsTo), prompt: Text("to"))
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("Word count to")
                        #if !os(macOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                .padding(.horizontal, 16)
            }
            .frame(minHeight: 48)
            .background(theme.appTheme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pinned Results Bar

/// Pinned bottom bar with optional Save button and "Show N Works" action (boards 03, 12).
struct FilterResultsBar: View {
    let buttonTitle: String
    var isConfirmDisabled: Bool = false
    var onSave: (() -> Void)?
    var isSaveDisabled: Bool = false
    let onConfirm: () -> Void

    @Environment(ThemeManager.self) private var theme

    private var isDark: Bool {
        theme.appTheme == .dark || theme.appTheme == .oled
    }

    private var backdropColor: Color {
        theme.appTheme.cardBackdrop
    }

    /// A disabled confirm was a faded accent fill the system dimmed again behind its white
    /// label (about 2:1 in every theme; worst on Dark/OLED). Disabled, the label is drawn in the
    /// theme's text colour on a pale tint by a style the system does not dim.
    private var drawsReadableDisabled: Bool { isConfirmDisabled }

    @ViewBuilder
    private var confirmButton: some View {
        let button = Button(action: onConfirm) {
            Text(buttonTitle)
                .font(.headline)
                .foregroundStyle(drawsReadableDisabled ? theme.appTheme.textColor : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .frame(minHeight: 52)
                .background(theme.effectiveTint.opacity(drawsReadableDisabled ? 0.15 : 1))
                // Opaque under the pale tint, so rows scrolling behind the bar don't show through.
                .background(backdropColor)
                .clipShape(Capsule())
        }
        .disabled(isConfirmDisabled)
        .accessibilityLabel(buttonTitle)
        if drawsReadableDisabled {
            button.buttonStyle(UndimmedButtonStyle())
        } else {
            button.buttonStyle(.plain)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: backdropColor.opacity(0), location: 0),
                    .init(color: backdropColor.opacity(0.96), location: 0.45)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)
            .allowsHitTesting(false)

            HStack(spacing: 10) {
                if let onSave {
                    Button(action: onSave) {
                        HStack(spacing: 6) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Save")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(minHeight: 52)
                        .background(isDark ? Color(white: 0.22) : Color.white)
                        // The readable accent ink (the fill red is ~1.2:1 on Dark's grey);
                        // disabled, plain secondary text the system does not dim further.
                        .foregroundStyle(isSaveDisabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.accentInk))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(theme.effectiveTint.opacity(0.3), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(UndimmedButtonStyle())
                    .disabled(isSaveDisabled)
                    .accessibilityLabel("Save Search")
                }

                confirmButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .background(backdropColor.opacity(0.96))
        }
    }
}

/// A button style that draws its label as given: unlike the system styles it adds no disabled dimming.
struct UndimmedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
