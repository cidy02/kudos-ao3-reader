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

    /// An inline title capped near the size the system's own title stops growing
    /// at, since the bar does not grow taller. Long subject names belong in the
    /// scrolling content: the bar can still constrain this to one line. Hide its
    /// accessibility element when that content supplies the full heading instead.
    /// `isActive: false`
    /// leaves the screen's own title as it was (a large title that only needs this
    /// at the accessibility sizes).
    @ViewBuilder
    func wrappingInlineTitle(
        _ title: String, isActive: Bool = true, accessibilityHidden: Bool = false
    ) -> some View {
        #if os(iOS)
        if isActive {
            navigationTitle(accessibilityHidden ? "" : title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.8)
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityHidden(accessibilityHidden)
                    }
                }
        } else {
            navigationTitle(title)
        }
        #else
        navigationTitle(title)
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

// MARK: - Page body rows

extension View {
    /// A `List` row that sits directly on the page wash: no card, no separator,
    /// no row background, at the screen edge.
    ///
    /// Artboard 1a's page is a stack of these, and it varies only the space
    /// above each block: prose, chips and panels all take the one 16pt edge
    /// (T-484 retired the 22pt panel and 26pt prose gutters). Naming it here
    /// keeps call sites from each spelling out an `EdgeInsets` that has to
    /// agree with the others by eye.
    func pageBodyRow(top: CGFloat, gutter: CGFloat = SubjectMetrics.gutter) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: gutter, bottom: 0, trailing: gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Filter chip rail

/// The horizontal rail of active filters and quick pills under a subject
/// header — spec 1k, 1ad, 1l and every other filtered list.
///
/// The spec pins a dashed "Filter" chip at its trailing edge. It is gone (owner,
/// 2026-10-01: one control per action, and the top chrome wins): every screen
/// that draws this rail already has the toolbar `FilterButton`, which carries
/// the active count as its badge. Callers draw the rail only when it has chips.
struct SubjectFilterRail<Chips: View>: View {
    @ViewBuilder var chips: () -> Chips

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) { chips() }
                .padding(.horizontal, SubjectMetrics.gutter)
        }
        .horizontalScrollViewport()
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}

// MARK: - Ledger row

extension Color {
    /// The star gold, on every card whatever its own accent — 1aj's filled star and
    /// the reread count on 1ah/1aj's footer. The one mark in the ledger row that is
    /// deliberately *not* the card's hue: it belongs to the star, not to the fandom.
    static let subjectFavoriteGold = Color(red: 0.949, green: 0.784, blue: 0.475)

    /// 1bj's amber, #FF9F0A: a countdown that is a warning, not an act. Fixed
    /// rather than `.orange`, which is #FF9500 in light mode.
    static let subjectAmber = Color(red: 1, green: 0.624, blue: 0.039)
}

extension EnvironmentValues {
    /// True greys a ledger row's fandom label — 1ai's Abandoned rows, which
    /// the spec draws "dropped to grey rather than a fandom accent". An
    /// environment value because the row is built three views down
    /// (`SensitiveWorkRow` → `WorkRow` → here) and only one screen sets it.
    @Entry var ledgerKickerMuted = false
    /// A queue position drawn by `.cardRow(leadingNumber:)` to the left of the
    /// row. Set by the one screen that numbers its rows, for the same
    /// three-views-down reason as `ledgerKickerMuted`. The row itself does not
    /// draw the number.
    @Entry var ledgerPositionNumber: Int?
}

/// Padding and the separator inset shared by every plain work row.
enum WorkRowMetrics {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 12
    static let columnGap: CGFloat = 12
    /// Two 24 pt tiles plus the 0.12 gap, the 51 pt the separator math uses.
    static let gridColumn: CGFloat = 51
    static let screenInset: CGFloat = 16
    /// 16 screen + 51 grid + 12 gap. The text column, on a row that is not wide
    /// and not stacked for an accessibility size. Selecting does not move it:
    /// the selection bubble stays at the trailing edge, so there is no leading
    /// check to clear.
    static let textColumnInset: CGFloat = screenInset + gridColumn + columnGap
}

/// 0.5 pt system separator. Inset is from the row's own leading edge.
struct WorkRowSeparator: View {
    var inset: CGFloat = WorkRowMetrics.textColumnInset

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 0.5)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// Caption 1 semibold, caps, 0.06 em. No rule: the title under a row label is
/// Headline, not a Title-size heading, so I-18's 16×2 mark stays off this row.
/// The colour is the fandom's, including when the label is also a search button.
struct WorkFandomLabel: View {
    var title: String
    var palette: SubjectPalette
    var additionalCount: Int = 0
    var action: (() -> Void)?

    @Environment(\.ledgerKickerMuted) private var muted
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var tracking: CGFloat = 0.72

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.borderless)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title.uppercased())
                .foregroundStyle(muted ? Color.secondary : palette.accent)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.leading)
            if additionalCount > 0 {
                Text("+\(additionalCount)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
        .tracking(tracking)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(additionalCount > 0 ? "\(title), plus \(additionalCount) more" : title)
    }
}

/// The plain work row: a leading grid, the title block, and whatever sits under
/// it. Wide results keep the grid beside the title block and let the rest run
/// the full width. An accessibility size stacks the grid above the text.
struct WorkPlainRow<Leading: View, Heading: View, Remainder: View>: View {
    var wide = false
    var showsSeparator = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var heading: () -> Heading
    @ViewBuilder var remainder: () -> Remainder

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if stacked {
                    leading()
                    heading()
                    remainder()
                } else if wide {
                    HStack(alignment: .top, spacing: WorkRowMetrics.columnGap) {
                        leading()
                        heading()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    remainder()
                } else {
                    HStack(alignment: .top, spacing: WorkRowMetrics.columnGap) {
                        leading()
                        VStack(alignment: .leading, spacing: 12) {
                            heading()
                            remainder()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, WorkRowMetrics.horizontalPadding)
            .padding(.vertical, WorkRowMetrics.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsSeparator {
                WorkRowSeparator(
                    inset: stacked || wide ? WorkRowMetrics.screenInset : WorkRowMetrics.textColumnInset
                )
            }
        }
    }
}

/// Chapter bars and the "Ch 7 · 58%" label. Empty when the work has no chapter plan.
struct WorkChapterBarLine: View {
    var items: [ChapterBarItem]
    var label: String?

    var body: some View {
        if !items.isEmpty {
            HStack(alignment: .center, spacing: 8) {
                ChapterBars(items: items, scale: .row, accessibilityLabel: spoken)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let label {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: true)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var spoken: String {
        var parts = [ChapterBarGeometry.accessibilityLabel(for: items)]
        if let label { parts.append(label) }
        return parts.joined(separator: ", ")
    }
}

/// The 3 pt read-progress bar on a standard row. Hidden at zero.
struct WorkReadProgressBar: View {
    var progress: Double

    @Environment(\.accentFill) private var accentFill

    var body: some View {
        let fraction = min(max(progress, 0), 1)
        let percent = Int((fraction * 100).rounded())
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.14))
                    Capsule()
                        .fill(accentFill)
                        .frame(width: max(fraction > 0 ? 2 : 0, geo.size.width * fraction))
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
            Text("\(percent)%")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent) percent read")
    }
}


// MARK: - Subject panel

/// A tinted block that groups other content under a heading — spec 1g's
/// per-category panel, where a name, its tallies and a cluster of fandom chips
/// share one surface in that category's hue.
///
/// Distinct from a work row, which *is* its content. A panel is a
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
        let shape = RoundedRectangle(cornerRadius: SubjectMetrics.cornerRadius, style: .continuous)
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
    /// The split display title — 1g asks for `FandomDisplayName` splitting here
    /// "so qualifiers do not wrap". The raw tag stays the caller's business: it is
    /// what the tap searches on, and splitting is not reversible.
    let title: String
    /// AO3's delimiter already stripped. Drawn dimmer and after the title, so
    /// "One Piece · All Media Types" and "One Piece · Anime & Manga" differ where
    /// the eye is already looking rather than past a truncation.
    var qualifier: String = ""
    var workCount: Int?
    /// A family's count summed across its sibling tags, which double-counts a
    /// work tagged with two of them — drawn with a leading "~".
    var isApproximateCount: Bool = false
    /// Marks a fandom the reader has actually read from, so a cluster of twenty
    /// names is not uniform. Drawn as a bar rather than a colour change: the
    /// name has to stay equally readable either way.
    var isFamiliar: Bool = false
    let palette: SubjectPalette

    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The chip is a name to tap: at the largest sizes it stayed at 12.5pt beside a
    /// category title three times its ordinary size. The cluster's layout hands a
    /// chip wider than its row the row's width, so a long name wraps or truncates.
    @ScaledMetric(relativeTo: .footnote) private var titleSize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 11
    @ScaledMetric(relativeTo: .footnote) private var barHeight: CGFloat = 14

    var body: some View {
        HStack(spacing: 7) {
            if isFamiliar {
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 2.5, height: barHeight)
            }
            // Stated as the card's own accent rather than `.primary`/`.secondary`.
            //
            // Those are *levels of the inherited foreground style*, not text
            // colours, and every one of these chips is the label of a
            // `.buttonStyle(.borderless)` — which sets that style to the app
            // accent. So the name and count resolved to the app's purple on every
            // card, whatever hue the card itself was: a pink category and a blue
            // one drew identically tinted chips. Naming the colour fixes both the
            // inheritance and the mismatch.
            Text(title)
                .font(.system(size: titleSize, weight: .medium))
                .foregroundStyle(palette.accent)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            if !qualifier.isEmpty {
                Text(qualifier)
                    .font(.system(size: detailSize))
                    .foregroundStyle(palette.accent.opacity(0.62))
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            if let workCount {
                // 1.2K rather than 1,204: the chip is for scanning, not counting.
                Text((isApproximateCount ? "~" : "") + workCount.formatted(.number.notation(.compactName)))
                    .font(.system(size: detailSize))
                    .monospacedDigit()
                    .foregroundStyle(palette.accent.opacity(0.62))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(chipBackground)
        .combinedAccessibilityRow(accessibilityText)
    }

    private var accessibilityText: String {
        var spoken = title
        if !qualifier.isEmpty { spoken += ", \(qualifier)" }
        if let workCount { spoken += ", \(isApproximateCount ? "about " : "")\(workCount.formatted()) works" }
        if isFamiliar { spoken += ", read before" }
        return spoken
    }

    private var chipBackground: some View {
        let shape = SubjectMetrics.controlShape(dynamicTypeSize)
        return shape
            .fill(themeManager.appTheme.glassFill(0.07))
            .overlay(shape.strokeBorder(themeManager.appTheme.glassStroke(0.10), lineWidth: 0.5))
    }
}
