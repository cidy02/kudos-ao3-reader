import SwiftUI

/// The redesign's shared visual language, in one file.
///
/// Every screen in the redesign spec is built from the same six parts, and each
/// of them is derived from ONE number — the subject's hue (a fandom, a queue's
/// stored colour, a scope). Keeping them here means a screen picks a subject and
/// gets the whole treatment, rather than each surface re-deriving near-miss
/// colours of its own:
///
///   1. `SubjectPalette`      — hue → wash / accent / chip / border colours
///   2. `subjectWash()`       — the full-bleed gradient behind a pushed screen
///   3. `SubjectHeaderBlock`  — kicker · rule · 32pt hero · tallies
///   4. `SectionRuleHeader`   — Home/Library's kicker · count · hairline · chevron
///   5. `SubjectStatStrip`    — the four-cell divided figure strip
///   6. `WorkProgressRing`    — the 68pt read-progress ring
///
/// Values are the spec's own, converted from CSS: a `158deg` linear gradient is
/// `.topLeading → .bottomTrailing` here (SwiftUI has no angle on `LinearGradient`
/// without a `UnitPoint` pair, and the diagonal is what the spec is drawing);
/// `#D9B26A` and its siblings are the same hue at different saturation and
/// brightness, which is why they are computed rather than listed.
///
/// The spec is a Dark-only iPhone reference. Dark/OLED follow it literally.
/// Light and Sepia take the same *structure* with their own tonal range, since
/// the app ships four themes and a hard-coded dark palette would break three.

// MARK: - Palette

/// Every colour a subject-scoped surface needs, derived from one hue.
///
/// Construct it from the theme rather than reaching for `Color(hue:…)` at a call
/// site: the saturation/brightness pairs below are what keep a gold fandom and a
/// violet queue reading as the same design at the same weight.
struct SubjectPalette {
    let hue: Double
    let theme: ReaderTheme

    init(hue: Double, theme: ReaderTheme) {
        self.hue = hue
        self.theme = theme
    }

    /// The subject's identity colour: kicker text, the short rule under it, the
    /// filled confirm button, a selected chip's text. Spec `#D9B26A` at hue 38°.
    var accent: Color {
        switch theme {
        case .dark, .oled: Color(hue: hue, saturation: 0.48, brightness: 0.86)
        // Light and Sepia put this on a pale surface, so it has to darken rather
        // than brighten to keep its contrast against the page.
        case .light: Color(hue: hue, saturation: 0.72, brightness: 0.52)
        case .sepia: Color(hue: hue, saturation: 0.60, brightness: 0.48)
        }
    }

    /// The same identity at text weight on a filled chip or a glass button —
    /// spec `#F4E4C6`, a much lighter tint of `accent` so it stays legible on
    /// the accent's own 24%-alpha fill.
    var accentOnFill: Color {
        switch theme {
        case .dark, .oled: Color(hue: hue, saturation: 0.18, brightness: 0.97)
        case .light, .sepia: Color(hue: hue, saturation: 0.86, brightness: 0.38)
        }
    }

    /// The page wash behind a pushed subject screen: saturated at the top,
    /// falling to the app's own backdrop by the bottom of the header region.
    /// Spec: `linear-gradient(178deg, …)` with stops at 0 / 26 / 52 / 74 / 100%.
    var wash: LinearGradient {
        LinearGradient(
            stops: washStops,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var washStops: [Gradient.Stop] {
        switch theme {
        case .dark, .oled:
            return [
                .init(color: Color(hue: hue, saturation: 0.55, brightness: 0.29), location: 0),
                .init(color: Color(hue: hue, saturation: 0.53, brightness: 0.24), location: 0.26),
                .init(color: Color(hue: hue, saturation: 0.42, brightness: 0.17), location: 0.52),
                .init(color: Color(hue: hue, saturation: 0.26, brightness: 0.10), location: 0.74),
                .init(color: theme.cardBackdrop, location: 1),
            ]
        case .light:
            return [
                .init(color: Color(hue: hue, saturation: 0.20, brightness: 0.98), location: 0),
                .init(color: Color(hue: hue, saturation: 0.15, brightness: 0.98), location: 0.26),
                .init(color: Color(hue: hue, saturation: 0.09, brightness: 0.99), location: 0.52),
                .init(color: Color(hue: hue, saturation: 0.04, brightness: 0.99), location: 0.74),
                .init(color: theme.cardBackdrop, location: 1),
            ]
        case .sepia:
            return [
                .init(color: Color(hue: hue, saturation: 0.22, brightness: 0.92), location: 0),
                .init(color: Color(hue: hue, saturation: 0.17, brightness: 0.92), location: 0.26),
                .init(color: Color(hue: hue, saturation: 0.11, brightness: 0.92), location: 0.52),
                .init(color: Color(hue: hue, saturation: 0.05, brightness: 0.92), location: 0.74),
                .init(color: theme.cardBackdrop, location: 1),
            ]
        }
    }

    /// A work card's own diagonal wash — the 164×232 cover on Home, the hero,
    /// and the queue tile. Spec: `linear-gradient(158deg,#5B3A2A,#281A13)`, one
    /// hue at two brightnesses. Deliberately NOT a hue shift: two ends of a
    /// slightly different hue made adjacent cards read as two fandoms.
    var cardWash: LinearGradient {
        let colors: [Color]
        switch theme {
        case .dark, .oled:
            colors = [
                Color(hue: hue, saturation: 0.54, brightness: 0.36),
                Color(hue: hue, saturation: 0.52, brightness: 0.155),
            ]
        case .light:
            colors = [
                Color(hue: hue, saturation: 0.26, brightness: 0.99),
                Color(hue: hue, saturation: 0.14, brightness: 0.93),
            ]
        case .sepia:
            colors = [
                Color(hue: hue, saturation: 0.24, brightness: 0.93),
                Color(hue: hue, saturation: 0.13, brightness: 0.85),
            ]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The quieter wash a full-width ledger row takes, so a list of ten of them
    /// stays a list rather than ten posters. Spec 1k:
    /// `linear-gradient(140deg,#5B4A2A66,#2A21134D)` composited over the page.
    var rowWash: LinearGradient {
        let colors: [Color]
        switch theme {
        case .dark, .oled:
            colors = [
                Color(hue: hue, saturation: 0.53, brightness: 0.36).opacity(0.40),
                Color(hue: hue, saturation: 0.53, brightness: 0.16).opacity(0.30),
            ]
        case .light:
            colors = [
                Color(hue: hue, saturation: 0.30, brightness: 1.0).opacity(0.42),
                Color(hue: hue, saturation: 0.22, brightness: 0.96).opacity(0.30),
            ]
        case .sepia:
            colors = [
                Color(hue: hue, saturation: 0.30, brightness: 0.95).opacity(0.40),
                Color(hue: hue, saturation: 0.22, brightness: 0.88).opacity(0.30),
            ]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A compact cover card takes no hairline on the dark themes — spec 1b gives
    /// it a drop shadow and nothing else, and the wash is opaque enough to hold
    /// its own edge. Light and Sepia still need one to separate the card from a
    /// pale page.
    var cardBorder: Color {
        theme.isDarkFamily ? .clear : accent.opacity(0.16)
    }

    /// Hairline on a washed row — spec `#D9B26A38`, the accent at 22%. A row is
    /// wide and low-contrast where a card is small and saturated, so unlike
    /// `cardBorder` this one is drawn on every theme.
    var rowBorder: Color { accent.opacity(theme.isDarkFamily ? 0.22 : 0.18) }

    /// The single filled, high-contrast control on a washed card — spec 1b's
    /// Resume pill. White on the dark themes, with the card wash's own deep end
    /// as the label so the button reads as cut out of the card rather than
    /// dropped on top of it.
    var solidButtonFill: Color {
        theme.isDarkFamily ? .white : accent
    }

    var solidButtonLabel: Color {
        theme.isDarkFamily ? Color(hue: hue, saturation: 0.52, brightness: 0.155) : .white
    }

    /// Fill and stroke for a chip carrying the subject's own tint (an active
    /// filter, a selected tag). Spec: `#D9B26A3D` over `#D9B26A80`.
    var chipFill: Color { accent.opacity(theme.isDarkFamily ? 0.24 : 0.16) }
    var chipStroke: Color { accent.opacity(theme.isDarkFamily ? 0.50 : 0.40) }
}

extension ReaderTheme {
    /// True for the two themes that render on a near-black page. Their token
    /// values differ from Light/Sepia in kind (translucent white vs. translucent
    /// black), not just in degree, so most switches here fork on this rather
    /// than listing four cases that pair up two and two.
    var isDarkFamily: Bool {
        switch self {
        case .dark, .oled: true
        case .light, .sepia: false
        }
    }

    /// The translucent fill used by every piece of floating chrome and every
    /// signal tray: white on a dark page, black on a pale one. Spec
    /// `rgba(255,255,255,.12)` / `rgba(255,255,255,.10)`.
    func glassFill(_ opacity: Double = 0.12) -> Color {
        isDarkFamily ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.55)
    }

    /// The hairline that goes with `glassFill`. Spec `rgba(255,255,255,.16)`.
    func glassStroke(_ opacity: Double = 0.16) -> Color {
        isDarkFamily ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.55)
    }

    func subjectPalette(hue: Double) -> SubjectPalette {
        SubjectPalette(hue: hue, theme: self)
    }
}

// MARK: - Metrics

/// The spec's own numbers. Named so a screen asks for the role, not the value —
/// and so changing the language is one edit rather than a grep for `16`.
enum SubjectMetrics {
    /// Page gutter for full-width content on a washed screen (spec `0 16px`).
    static let gutter: CGFloat = 16
    /// The wider gutter the header block itself takes (spec `22px 26px 0`).
    static let headerGutter: CGFloat = 26
    /// Floating glass chrome buttons — spec's 34px circles.
    static let chromeButton: CGFloat = 34
    /// The short rule under a kicker: 22×2.5 on a card, 26×2.5 on a page header.
    static let kickerRuleWidth: CGFloat = 22
    static let pageRuleWidth: CGFloat = 26
    static let kickerRuleHeight: CGFloat = 2.5
    /// Read-progress ring, and the stroke it is drawn with.
    static let ringDiameter: CGFloat = 68
    static let ringStroke: CGFloat = 5
    /// Radius of a washed ledger row / work card (spec `16px`), and of the
    /// Home hero, which is one step softer (spec `18px`).
    static let rowRadius: CGFloat = 16
    static let heroRadius: CGFloat = 18
    /// Chips in the redesign are rounded rects, not capsules (spec `8px`).
    static let chipRadius: CGFloat = 8
    /// The signal tray behind a work's four status tiles (spec `10px`).
    static let trayRadius: CGFloat = 10
}

// MARK: - Kicker

/// The uppercase subject label and its short rule — the redesign's single most
/// repeated unit. It names what the surface is scoped to (a fandom on a work
/// card, "SEARCH RESULTS" on a results page, a queue's name in its details).
///
/// `trailingCount` renders the spec's dimmed `+3` for the fandoms a collapsed
/// card is not showing; it is deliberately a separate, quieter run rather than
/// part of the accent-coloured label.
struct SubjectKicker: View {
    let text: String
    let palette: SubjectPalette
    /// Additional subjects hidden by the collapsed state (0 shows nothing).
    var trailingCount: Int = 0
    /// 9pt on a compact cover, 10pt on a ledger row and page header (spec).
    var size: CGFloat = 10
    /// 22pt on a card, 26pt on a page header.
    var ruleWidth: CGFloat = SubjectMetrics.kickerRuleWidth
    /// Space between the label and its rule (spec `6px` on cards).
    var ruleSpacing: CGFloat = 6

    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: ruleSpacing) {
            HStack(spacing: 4) {
                Text(text.uppercased())
                    .foregroundStyle(palette.accent)
                if trailingCount > 0 {
                    Text("+\(trailingCount)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: size * scale, weight: .bold))
            .tracking(size * 0.11)
            .lineLimit(1)

            Capsule()
                .fill(palette.accent)
                .frame(width: ruleWidth, height: SubjectMetrics.kickerRuleHeight)
        }
        .combinedAccessibilityRow(
            trailingCount > 0 ? "\(text), plus \(trailingCount) more" : text
        )
    }
}

// MARK: - Page header

/// The header every pushed, subject-scoped screen opens with: kicker, rule,
/// a 32pt hero figure or name, and one line of tallies underneath. Sits
/// directly on the wash — no card, per the spec.
struct SubjectHeaderBlock<Trailing: View>: View {
    let kicker: String
    let title: String
    var subtitle: String?
    let palette: SubjectPalette
    /// Set by the initializers rather than inferred from `Trailing.self`:
    /// comparing metatypes to spot `EmptyView` works but reads as a trick, and
    /// this also lets a caller pass a conditional trailing view that is empty
    /// at runtime without the separator dot appearing next to nothing.
    var hasTrailing = true
    /// Drawn on the subtitle line, after a dot separator — the sort dropdown in
    /// search results, the queue's tag rail elsewhere.
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SubjectKicker(
                text: kicker,
                palette: palette,
                ruleWidth: SubjectMetrics.pageRuleWidth,
                ruleSpacing: 7
            )

            Text(title)
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.6)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            if subtitle != nil || hasTrailing {
                HStack(spacing: 8) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 15.5))
                            .foregroundStyle(.secondary)
                    }
                    if subtitle != nil, hasTrailing {
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 4, height: 4)
                    }
                    if hasTrailing {
                        trailing()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SubjectMetrics.headerGutter)
    }
}

extension SubjectHeaderBlock where Trailing == EmptyView {
    init(kicker: String, title: String, subtitle: String? = nil, palette: SubjectPalette) {
        self.init(
            kicker: kicker,
            title: title,
            subtitle: subtitle,
            palette: palette,
            hasTrailing: false,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Section header

/// Home and Library's section header: the label, its count, a disclosure caret,
/// then a hairline that runs to a trailing see-all chevron. The hairline is the
/// part that makes a shelf read as a section without a heavy title bar.
///
/// `onSeeAll` nil drops the trailing chevron rather than disabling it — a
/// section with no destination should not offer one.
struct SectionRuleHeader: View {
    let title: String
    var count: Int?
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)?
    var onSeeAll: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if let onToggleCollapse {
                Button(action: onToggleCollapse) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .minimumHitTarget(30)
                .accessibilityLabel(isCollapsed ? "Expand \(title)" : "Collapse \(title)")
            }

            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 0.5)
                .padding(.horizontal, 2)

            if let onSeeAll {
                Button(action: onSeeAll) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .minimumHitTarget(30)
                .accessibilityLabel("See all \(title)")
            }
        }
        .padding(.horizontal, SubjectMetrics.gutter)
    }
}

// MARK: - Stat strip

/// The four-cell divided figure strip under a page header — works, filters,
/// pages, current page on search results; read/unread/hours elsewhere. One
/// cell is optionally highlighted in the subject accent (spec: the live page).
struct SubjectStatStrip: View {
    struct Cell: Identifiable {
        let id = UUID()
        let value: String
        let label: String
        var isHighlighted: Bool = false

        init(value: String, label: String, isHighlighted: Bool = false) {
            self.value = value
            self.label = label
            self.isHighlighted = isHighlighted
        }
    }

    let cells: [Cell]
    let palette: SubjectPalette

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                if index > 0 {
                    Rectangle()
                        .fill(themeManager.appTheme.glassStroke(0.13))
                        .frame(width: 0.5)
                }
                VStack(spacing: 5) {
                    Text(cell.value)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(cell.isHighlighted ? palette.accentOnFill : Color.primary)
                    Text(cell.label.uppercased())
                        .font(.system(size: 9))
                        .tracking(0.63)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .combinedAccessibilityRow("\(cell.value) \(cell.label)")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(themeManager.appTheme.glassFill(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(themeManager.appTheme.glassStroke(0.13), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Progress ring

/// The read-progress ring: 68pt, 5pt stroke, percentage over a state word.
/// Replaces the bar-plus-label pair on every work surface — the spec puts it in
/// the middle of a cover card, against the chapter line on the Home hero, and
/// at the leading edge of a ledger row, at three sizes but always this shape.
struct WorkProgressRing: View {
    /// 0…1. Values outside the range are clamped by the caller's own accessor.
    let progress: Double
    /// The word under the percentage. Nil drops it, for the small sizes where
    /// two lines of type inside 44pt is unreadable.
    var state: String?
    var diameter: CGFloat = SubjectMetrics.ringDiameter
    /// The 44pt ring in a ledger row prints a bare figure — spec 1d and 1ad both
    /// draw "42", not "42%". At that size the glyph costs a sixth of the width
    /// and says nothing the ring's own fill has not already said. VoiceOver still
    /// hears the full "42 percent".
    var showsPercentSuffix: Bool = true
    /// Drawn in the subject's accent on a neutral surface; white on a card that
    /// already carries the subject's wash (which is most of them).
    var tint: Color?

    @Environment(ThemeManager.self) private var themeManager

    private var clamped: Double { min(1, max(0, progress)) }
    private var percent: Int { Int((clamped * 100).rounded()) }
    private var stroke: CGFloat { max(2.5, diameter * SubjectMetrics.ringStroke / SubjectMetrics.ringDiameter) }

    private var trackColor: Color {
        themeManager.appTheme.isDarkFamily ? Color.black.opacity(0.30) : Color.black.opacity(0.12)
    }

    private var progressColor: Color {
        if let tint { return tint }
        return themeManager.appTheme.isDarkFamily ? .white : Color.primary.opacity(0.8)
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(trackColor, lineWidth: stroke)
            Circle()
                .inset(by: stroke / 2)
                .trim(from: 0, to: clamped)
                .stroke(progressColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(showsPercentSuffix ? "\(percent)%" : "\(percent)")
                    .font(.system(size: diameter * 15 / 68, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let state {
                    Text(state.uppercased())
                        .font(.system(size: diameter * 8 / 68, weight: .semibold))
                        .tracking(diameter * 0.09 * 8 / 68)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(stroke + 2)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading progress")
        .accessibilityValue(state.map { "\(percent) percent, \($0)" } ?? "\(percent) percent")
    }
}

// MARK: - Chips

/// The redesign's chip: a rounded rect, not the capsule `TagChip` draws. Used
/// for active filters, tag groups on an expanded row, and the scope rails.
///
/// `.dashed` is the spec's "add one" affordance (`+ Tag`, `Filter`) — the only
/// chip that is an invitation rather than a statement.
struct SubjectChip: View {
    enum Style {
        case neutral
        case tinted
        case dashed
    }

    let text: String
    var style: Style = .neutral
    var systemImage: String?
    /// A trailing glyph the caller can tap through — the × on an active filter.
    var trailingImage: String?
    var palette: SubjectPalette?

    @Environment(ThemeManager.self) private var themeManager

    private var theme: ReaderTheme { themeManager.appTheme }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 13, weight: style == .tinted ? .medium : .regular))
                .monospacedDigit()
                .lineLimit(1)
            if let trailingImage {
                Image(systemName: trailingImage)
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(0.75)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .foregroundStyle(foreground)
        .background(background)
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch style {
        case .neutral: .primary
        case .tinted: palette?.accentOnFill ?? .primary
        case .dashed: .secondary
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.chipRadius, style: .continuous)
        switch style {
        case .neutral:
            shape
                .fill(theme.glassFill(0.09))
                .overlay(shape.strokeBorder(theme.glassStroke(0.14), lineWidth: 0.5))
        case .tinted:
            shape
                .fill(palette?.chipFill ?? Color.accentColor.opacity(0.24))
                .overlay(shape.strokeBorder(palette?.chipStroke ?? Color.accentColor.opacity(0.5), lineWidth: 0.5))
        case .dashed:
            shape
                .strokeBorder(
                    theme.glassStroke(0.26),
                    style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
                )
        }
    }
}

// MARK: - Floating chrome

/// A 34pt circular glass button — the redesign's back, filter, select and
/// overflow controls, which float over the wash rather than sitting in a bar.
///
/// `isAccented` gives it the subject's own tint, for the one control on a
/// screen that is the point of it (Filter on results, + on a queue).
struct GlassCircleButton<Label: View>: View {
    var isAccented: Bool = false
    var palette: SubjectPalette?
    /// Rides the top-trailing corner — the active-filter count in spec 1k.
    var badge: String?
    /// Spoken name for the control. Carried as a parameter rather than left to
    /// the call site, because attaching `.accessibilityLabel` outside the button
    /// changes its type, and the convenience initialisers that pin a concrete
    /// chrome type (see `SubjectScreenScaffold`) constrain exactly that type.
    /// Named `accessibilityName` rather than `accessibilityLabel` so it never
    /// reads as a shadow of the view modifier of that name.
    var accessibilityName: String
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.appTheme
        let accent = palette?.accent ?? Color.accentColor
        Button(action: action) {
            label()
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isAccented ? (palette?.accentOnFill ?? Color.accentColor) : Color.primary)
                .frame(width: SubjectMetrics.chromeButton, height: SubjectMetrics.chromeButton)
                .background {
                    Circle()
                        .fill(isAccented ? accent.opacity(0.30) : theme.glassFill())
                        .overlay(
                            Circle().strokeBorder(
                                isAccented ? accent.opacity(0.60) : theme.glassStroke(),
                                lineWidth: 0.5
                            )
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(theme.cardBackdrop)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(accent))
                            .overlay(Capsule().strokeBorder(theme.cardBackdrop, lineWidth: 1.5))
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: - Wash background

/// Paints the subject wash behind a screen's content, full-bleed under the
/// status bar. `height` is how far down the saturated part reaches before it
/// has fully resolved to the page — the spec varies it by how much chrome the
/// screen floats over it (380pt for a plain list, 600–620pt for a hero).
private struct SubjectWash: ViewModifier {
    let palette: SubjectPalette
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .background(alignment: .top) {
                palette.wash
                    .frame(height: height)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
            }
            .background(palette.theme.cardBackdrop.ignoresSafeArea())
    }
}

extension View {
    /// The full-bleed gradient a pushed, subject-scoped screen sits on.
    func subjectWash(_ palette: SubjectPalette, height: CGFloat = 380) -> some View {
        modifier(SubjectWash(palette: palette, height: height))
    }
}
