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
/// interactive pop gesture, so the scaffold reinstates a back swipe with
/// `edgeSwipeToGoBack` — the same helper the reader already uses for exactly
/// this reason.
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

    @Environment(\.dismiss) private var dismiss

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
        .safeAreaInset(edge: .top, spacing: 0) { floatingChromeRow }
        .subjectWash(palette, height: washHeight)
        .hidesFloatingTabBar()
        .navigationBarBackButtonHidden(true)
        .hidesSystemNavigationBar()
        .edgeSwipeToGoBack { dismiss() }
    }

    private var floatingChromeRow: some View {
        HStack(spacing: 9) {
            leadingChrome()
            Spacer(minLength: 8)
            trailingChrome()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
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
                GlassCircleButton(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Back")
            },
            trailingChrome: trailingChrome,
            content: content
        )
    }
}

extension View {
    /// Hides the navigation bar itself, not just its back button. Split out
    /// because `ToolbarPlacement.navigationBar` does not exist on macOS, where
    /// the app uses a sidebar split and there is no bar to hide.
    func hidesSystemNavigationBar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
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
    /// Sits at the leading edge — a `WorkProgressRing`, a position number, or
    /// nothing at all on a row with no progress to report.
    @ViewBuilder var leading: () -> Leading
    /// The trailing edge — normally the four-signal tray.
    @ViewBuilder var trailing: () -> Trailing

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
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(rowBackground)
    }

    private var metadataLine: some View {
        Text(metadataSegments.joined(separator: "  ·  "))
            .font(.system(size: 11.5))
            .foregroundStyle(Color.primary.opacity(0.72))
            .lineLimit(2)
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
