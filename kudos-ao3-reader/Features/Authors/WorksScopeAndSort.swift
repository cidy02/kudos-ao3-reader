import SwiftUI

/// Artboard **1u**'s scope pills: Works, In collections, Gifts.
///
/// "In collections" is AO3's own wording — its subnav on `/works/collected`
/// reads "Works in Collections" — rather than a name invented here. Gifts are
/// works given TO this person, which is why the segment sits third rather than
/// beside the two lists that are theirs.
struct WorksScopeSegments: View {
    @Binding var scope: AO3AuthorRoute.Content

    private static let scopes: [(AO3AuthorRoute.Content, String)] = [
        (.works, "Works"),
        (.collectedWorks, "In collections"),
        (.gifts, "Gifts")
    ]

    @Environment(ThemeManager.self) private var theme

    /// 1u draws three pills, the selected one filled in the scope accent — the
    /// same grammar as 1v's completion chips. Scrolls rather than clipping when
    /// Refine and Sort beside it leave too little width (large text, iPhone SE).
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.scopes, id: \.0) { option, title in
                    Button {
                        // A re-tap would refetch and drop select mode for nothing.
                        if scope != option { scope = option }
                    } label: {
                        SubjectChip(
                            text: title,
                            style: .pill(isSelected: scope == option),
                            palette: theme.scopePalette
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(scope == option ? [.isSelected] : [])
                }
            }
        }
    }
}

/// 1u's segment control and 1v's sort funnel, as a section that sits above the
/// works list.
///
/// A sibling of `AO3AuthorFandomFilterSection` rather than something the host
/// assembles: both hosts of `AO3AuthorWorksSection` would otherwise need the
/// same sheet state, and one of them is `AccountView`, whose type checker
/// already struggles.
///
/// `showsScopes` is off by default. AO3 serves all three indexes for any user,
/// but 1u is the *own* works screen, so the control appears where a host opts
/// in — the same way `showsPerformance` and `onOwnWorkAction` already gate the
/// own-profile extras on the section below this one.
struct AO3AuthorWorksScopeSection: View {
    var model: AO3AuthorProfileModel
    var layout: AccountWorksLayout = .list
    var showsScopes: Bool = false
    /// Runs before a change refetches (hosts use it to exit select mode).
    var onWillChange: () -> Void = {}

    @Environment(AO3AuthService.self) private var auth
    @State private var showingFilters = false

    var body: some View {
        if model.selectedTab == .works {
            if layout == .scroll {
                VStack(alignment: .leading, spacing: 8) {
                    controls
                        .padding(.horizontal, CardListMetrics.sideMargin
                            + CardListMetrics.innerHorizontal)
                }
                .filterPanelPresentation(isPresented: $showingFilters) { sortAndFilterSheet }
            } else {
                Section {
                    controls.cardRow()
                }
                .filterPanelPresentation(isPresented: $showingFilters) { sortAndFilterSheet }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if showsScopes {
                WorksScopeSegments(scope: scopeBinding)
            }
            Spacer(minLength: 0)
            sortAndFilterButton
        }
    }

    /// One funnel. The badge counts both halves: the sort, which refetches, and
    /// the facets, which narrow the loaded page. Clear still drops only the
    /// facets — the sort has no clear of its own, and a long-press that reset
    /// it would refetch a list the reader had not asked to put back.
    private var sortAndFilterButton: some View {
        FilterButton(
            filtersActive: sheetActiveCount > 0,
            showingFilters: $showingFilters,
            filterHelp: "Sort and filter the works on this page",
            onClearFilters: model.worksFilters.refineActiveCount > 0
                ? { model.applyWorksFilters(AO3SearchFilters()) }
                : nil,
            badgeCount: sheetActiveCount
        )
        .accessibilityLabel("Sort and filter")
    }

    private var sheetActiveCount: Int {
        model.worksSort.activeCount + model.worksFilters.refineActiveCount
    }

    private var sortAndFilterSheet: some View {
        AO3FilterPanel(
            filters: filtersBinding,
            mode: .refine,
            canReset: model.worksFilters.refineActiveCount > 0,
            onApply: { showingFilters = false },
            onReset: { model.applyWorksFilters(AO3SearchFilters()) },
            // The same array `AO3AuthorWorksSection` narrows, so 1au's match line
            // and the list behind it cannot disagree.
            refineSource: model.works,
            worksSort: model.worksSort,
            onApplyWorksSort: { sort in
                onWillChange()
                model.applyWorksSort(sort, auth: auth)
            }
        )
        .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
    }

    /// Writes straight through to the model. No draft copy, unlike the sort
    /// half of the same sheet: applying a facet costs no request, so the match
    /// line and the list can both move as the reader taps.
    private var filtersBinding: Binding<AO3SearchFilters> {
        Binding(
            get: { model.worksFilters },
            set: { filters in
                onWillChange()
                model.applyWorksFilters(filters)
            }
        )
    }

    private var scopeBinding: Binding<AO3AuthorRoute.Content> {
        Binding(
            get: { model.worksScope },
            set: { scope in
                onWillChange()
                model.selectWorksScope(scope, auth: auth)
            }
        )
    }
}
