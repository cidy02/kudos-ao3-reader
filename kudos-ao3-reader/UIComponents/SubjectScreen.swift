import SwiftUI

/// The scaffold every pushed, subject-scoped screen in the redesign shares:
/// a full-bleed wash, one row of floating glass chrome instead of a navigation
/// bar, the kicker / rule / 32pt header block, an optional filter chip rail, and
/// then the screen's own content.
///
/// Roughly forty of the spec's artboards are this shape — search results (1k),
/// the inbox (1l), history (1t), works (1u), a queue (1h), the account
/// subsections, the pushed Home and Library sections — which is why it is one
/// component rather than forty near-identical headers.
///
/// **Why the navigation bar is hidden rather than restyled:** the spec floats
/// 34pt glass circles directly over the wash, with the page's own 32pt title
/// scrolling underneath them. A `UINavigationBar` cannot be persuaded into that
/// arrangement without fighting its own title layout. Hiding it costs the system
/// interactive pop gesture, so the scaffold reinstates a back swipe through
/// `reinstatesBackSwipe`, which wraps `edgeSwipeToGoBack` — the same helper the
/// reader already uses for exactly this reason.
struct SubjectScreenScaffold<LeadingChrome: View, TrailingChrome: View, Content: View>: View {
    let palette: SubjectPalette
    /// The uppercase line above the title — where you came from ("HOME"), or
    /// what kind of thing this is ("SEARCH RESULTS", "QUEUE DETAILS").
    let kicker: String
    let title: String
    /// One line of tallies under the title: "4 works · most recently read first".
    var subtitle: String?
    /// How far down the saturated part of the wash reaches. The spec uses 380 for
    /// a plain list and 600–620 where a hero card sits under the header.
    var washHeight: CGFloat = 380
    /// Chrome that replaces the default back button. Nil keeps the back button.
    @ViewBuilder var leadingChrome: () -> LeadingChrome
    @ViewBuilder var trailingChrome: () -> TrailingChrome
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SubjectHeaderBlock(
                    kicker: kicker,
                    title: title,
                    subtitle: subtitle,
                    palette: palette
                )
                .padding(.top, 20)

                content()
                    .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The floating tab bar overlaps the last rows otherwise; the spec
            // reserves 96–130pt at the bottom of every one of these screens.
            .padding(.bottom, 110)
        }
        .subjectScreenChrome(
            palette: palette,
            washHeight: washHeight,
            leading: leadingChrome,
            trailing: trailingChrome
        )
    }
}

/// The chrome half of the scaffold, separated from its container so a screen
/// that must stay a `List` can have it too.
///
/// This matters more than it looks: `List` is what gives a row its swipe
/// actions, and the spec puts swipe actions on rows in 1ah, 1ai, 1bg, 1bj and
/// 1u. A `ScrollView` cannot offer them, so those screens keep their `List` and
/// reach for this modifier, while the simpler ones use `SubjectScreenScaffold`
/// and get a `ScrollView` for free.
private struct SubjectScreenChrome<Leading: View, Trailing: View>: ViewModifier {
    let palette: SubjectPalette
    let washHeight: CGFloat
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 9) {
                    leading()
                    Spacer(minLength: 8)
                    trailing()
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
            }
            .subjectWash(palette, height: washHeight)
            .hidesFloatingTabBar()
            .hidesSystemNavigationBar()
            .reinstatesBackSwipe { dismiss() }
    }
}

/// The wash and header without the chrome swap: a transparent inline navigation
/// bar is kept, so the screen's existing toolbar items (filter, overflow, Select
/// All) stay exactly where they are and keep working.
///
/// This is the *staged* form of the redesign for a pushed screen. Spec 1ad and
/// friends replace the navigation bar outright with floating glass circles, and
/// `subjectScreenChrome` does that — but it also takes every `.toolbar` item on
/// the screen with it, so a screen has to move its controls into the floating row
/// in the same change. Screens adopt this first (wash, header block, ledger
/// rows), and the chrome swap lands separately, where it can be checked on a
/// device.
private struct SubjectScreenWash: ViewModifier {
    let palette: SubjectPalette
    let washHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .subjectWash(palette, height: washHeight)
            .hidesFloatingTabBar()
            .hidesNavigationBarChrome()
    }
}

extension View {
    /// Wash plus a transparent, title-less navigation bar. Keeps the bar's own
    /// items; see `SubjectScreenWash` for why that is worth a second modifier.
    func subjectScreenWash(palette: SubjectPalette, washHeight: CGFloat = 380) -> some View {
        modifier(SubjectScreenWash(palette: palette, washHeight: washHeight))
    }

    /// Empties the navigation bar's title and background so the wash shows
    /// through it, without hiding the bar (and with it, the screen's toolbar).
    /// The page states its own name in `SubjectHeaderBlock` underneath.
    func hidesNavigationBarChrome() -> some View {
        #if os(iOS)
        navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Wash, floating glass chrome, no navigation bar, and a reinstated back
    /// swipe — everything `SubjectScreenScaffold` does except owning the
    /// scrolling container. Apply it to a `List` to get the redesign's chrome
    /// without giving up swipe actions.
    func subjectScreenChrome<Leading: View, Trailing: View>(
        palette: SubjectPalette,
        washHeight: CGFloat = 380,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        modifier(
            SubjectScreenChrome(
                palette: palette,
                washHeight: washHeight,
                leading: leading,
                trailing: trailing
            )
        )
    }
}

extension SubjectScreenScaffold where LeadingChrome == GlassCircleButton<Image> {
    /// The common case: a plain glass back button on the leading edge.
    init(
        palette: SubjectPalette,
        kicker: String,
        title: String,
        subtitle: String? = nil,
        washHeight: CGFloat = 380,
        onBack: @escaping () -> Void,
        @ViewBuilder trailingChrome: @escaping () -> TrailingChrome,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            palette: palette,
            kicker: kicker,
            title: title,
            subtitle: subtitle,
            washHeight: washHeight,
            leadingChrome: {
                GlassCircleButton(accessibilityName: "Back", action: onBack) {
                    Image(systemName: "chevron.left")
                }
            },
            trailingChrome: trailingChrome,
            content: content
        )
    }
}

extension View {
    /// Hides the navigation bar itself, back button included. Split out because
    /// neither `ToolbarPlacement.navigationBar` nor
    /// `navigationBarBackButtonHidden` exists on macOS, where the app uses a
    /// sidebar split and there is no bar to hide in the first place.
    func hidesSystemNavigationBar() -> some View {
        #if os(iOS)
        navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Puts back the interactive pop gesture that hiding the navigation bar
    /// takes away. `edgeSwipeToGoBack` is itself iOS-only — macOS has no screen
    /// edge to swipe from, and its sidebar navigation never lost anything.
    func reinstatesBackSwipe(_ action: @escaping () -> Void) -> some View {
        #if os(iOS)
        edgeSwipeToGoBack(perform: action)
        #else
        self
        #endif
    }
}

// MARK: - Filter chip rail

/// The horizontal rail of active filters under a subject header, with a dashed
/// "Filter" chip pinned at its trailing edge — spec 1k, 1ad, 1l and every other
/// filtered list.
///
/// The dashed chip is pinned *outside* the scrolling rail rather than appended
/// to it: it is the way to change the filters, so it must never scroll off the
/// edge just because six of them are already set.
struct SubjectFilterRail<Chips: View>: View {
    let onOpenFilters: () -> Void
    /// Count shown on the dashed chip. Zero draws the bare word.
    var activeFilterCount: Int = 0
    @ViewBuilder var chips: () -> Chips

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) { chips() }
                    .padding(.horizontal, 22)
            }

            Button(action: onOpenFilters) {
                SubjectChip(
                    text: activeFilterCount > 0 ? "Filter \(activeFilterCount)" : "Filter",
                    style: .dashed,
                    systemImage: "line.3.horizontal.decrease"
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 22)
        }
    }
}

// MARK: - Ledger row

/// The redesign's full-width work row — the "ledger row" the spec names on
/// artboards 1c/1d, 1k, 1o, 1t, 1u, 1x, 1ad, 1ah, 1ai and 1aj.
///
/// A washed card carrying, in order: a leading progress ring (or position
/// number), the fandom kicker over its rule, the title, one dot-separated
/// metadata line, and the four-signal tray at the trailing edge.
///
/// It takes already-formatted strings rather than a model, because the same row
/// has to render a local `SavedWork`, a remote `AO3WorkSummary`, a queue entry
/// and a history entry — each of which derives these facts differently. The
/// caller does the deriving; this owns the layout, so the ten screens that use
/// it cannot drift apart.
struct WorkLedgerRow<Leading: View, Trailing: View>: View {
    let palette: SubjectPalette
    /// Uppercase subject line — normally the work's primary fandom.
    var kicker: String?
    /// Fandoms beyond the first, shown as the kicker's dimmed `+N`.
    var additionalKickerCount: Int = 0
    let title: String
    /// Pre-joined by the caller; drawn with the spec's dimmed middle dots.
    var metadataSegments: [String] = []
    /// A glyph pinned before the metadata line — the spec's green tick marking a
    /// work held offline (1ad, 1ah). Kept general rather than named "offline"
    /// because 1t uses the same slot for a visit count and 1aj for a star.
    var metadataPrefixSymbol: String?
    var metadataPrefixTint: Color?
    /// Sits at the leading edge — a `WorkProgressRing`, a position number, or
    /// nothing at all on a row with no progress to report.
    @ViewBuilder var leading: () -> Leading
    /// The trailing edge — normally the four-signal tray.
    @ViewBuilder var trailing: () -> Trailing
    /// False when the row sits in a `List` whose `.cardRow(tintHue:)` already
    /// paints the same wash on the row's true outer edge. Two backgrounds would
    /// draw the hairline twice, half a point apart. Standalone contexts — a
    /// `ScrollView`, a queue grid — leave it on and get the whole card here.
    var drawsBackground: Bool = true

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            leading()

            VStack(alignment: .leading, spacing: 5) {
                if let kicker {
                    SubjectKicker(
                        text: kicker,
                        palette: palette,
                        trailingCount: additionalKickerCount,
                        size: 9,
                        ruleSpacing: 5
                    )
                }

                Text(title)
                    .font(.system(size: 16.5, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !metadataSegments.isEmpty {
                    metadataLine
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, drawsBackground ? 16 : 0)
        .padding(.vertical, drawsBackground ? 15 : 9)
        .background {
            if drawsBackground { rowBackground }
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 5) {
            if let metadataPrefixSymbol {
                Image(systemName: metadataPrefixSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(metadataPrefixTint ?? Color.secondary)
            }
            Text(metadataSegments.joined(separator: "  ·  "))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.primary.opacity(0.72))
                .lineLimit(2)
        }
        .combinedAccessibilityRow(metadataSegments.joined(separator: ", "))
    }

    private var rowBackground: some View {
        let rowShape = RoundedRectangle(cornerRadius: SubjectMetrics.rowRadius, style: .continuous)
        return rowShape
            .fill(themeManager.appTheme.cardSurface)
            .overlay(rowShape.fill(palette.rowWash))
            .overlay(rowShape.strokeBorder(palette.rowBorder, lineWidth: 0.5))
    }
}

// MARK: - Subject panel

/// A tinted block that groups other content under a heading — spec 1g's
/// per-category panel, where a name, its tallies and a cluster of fandom chips
/// share one surface in that category's hue.
///
/// Distinct from `WorkLedgerRow`, which *is* its content. A panel is a
/// container, so it takes the much quieter `panelWash`: chips sit inside it and
/// have to stay legible against it.
struct SubjectPanel<Heading: View, Content: View>: View {
    let palette: SubjectPalette
    /// A 32pt tinted tile at the leading edge — the category's glyph in 1g. Nil
    /// drops it and the heading starts at the panel's own inset.
    var leadingSymbol: String?
    /// Drawn at the trailing edge of the heading row when the panel is tappable.
    var showsDisclosure: Bool = true
    @ViewBuilder var heading: () -> Heading
    @ViewBuilder var content: () -> Content

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let leadingSymbol {
                    Image(systemName: leadingSymbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.cardWash)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(themeManager.appTheme.glassStroke(0.14), lineWidth: 0.5)
                                )
                        )
                        .accessibilityHidden(true)
                }

                heading()
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)

            content()
                .padding(.horizontal, 16)
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
    }

    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.rowRadius, style: .continuous)
        return shape
            .fill(themeManager.appTheme.cardBackdrop)
            .overlay(shape.fill(palette.panelWash))
            .overlay(shape.strokeBorder(palette.rowBorder, lineWidth: 0.5))
    }
}

// MARK: - Fandom chip

/// A fandom in a cluster: its name, its work count, and — when you have read
/// something from it — a short bar in the subject's accent. Spec 1g.
///
/// Not a `SubjectChip` case. That type distinguishes chips by *grammar* (a rect
/// states, a pill offers) and draws one run of text; this one has three parts
/// whose relative weight is the whole point — the name reads first, the count
/// second, and the bar is a mark rather than content. Folding it in would have
/// meant three more optional parameters that no other chip uses.
struct FandomClusterChip: View {
    let name: String
    var workCount: Int?
    /// Marks a fandom the reader has actually read from, so a cluster of twenty
    /// names is not uniform. Drawn as a bar rather than a colour change: the
    /// name has to stay equally readable either way.
    var isFamiliar: Bool = false
    let palette: SubjectPalette

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 7) {
            if isFamiliar {
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 2.5, height: 14)
            }
            Text(name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let workCount {
                Text(workCount.formatted())
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(chipBackground)
        .combinedAccessibilityRow(accessibilityText)
    }

    private var accessibilityText: String {
        var spoken = name
        if let workCount { spoken += ", \(workCount.formatted()) works" }
        if isFamiliar { spoken += ", read before" }
        return spoken
    }

    private var chipBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return shape
            .fill(themeManager.appTheme.glassFill(0.07))
            .overlay(shape.strokeBorder(themeManager.appTheme.glassStroke(0.10), lineWidth: 0.5))
    }
}
