import SwiftUI

/// Artboard **1u**'s segment control: Works, In collections, Gifts.
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

    var body: some View {
        Picker("Works scope", selection: $scope) {
            ForEach(Self.scopes, id: \.0) { scope, title in
                Text(title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// Artboard **1v**: sort and filter as a sheet over the list.
///
/// The nine sort fields collapse into a menu rather than a nine-row list, which
/// is 1v's own instruction — direction stays a segmented pair and completion
/// stays chips, so each kind of choice keeps one grammar. Cancel and Apply are
/// icon-only to match the filter popup elsewhere in the app.
///
/// The sheet edits a copy and hands it back only on Apply. A live binding would
/// refetch from AO3 on every tap of a nine-item menu.
struct WorksSortSheet: View {
    let initial: AO3WorksSort
    let onApply: (AO3WorksSort) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @State private var draft: AO3WorksSort

    init(initial: AO3WorksSort, onApply: @escaping (AO3WorksSort) -> Void) {
        self.initial = initial
        self.onApply = onApply
        self._draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            List {
                // One `List` row per control, as segments of one card. A
                // `Section`'s children are separate rows, so `.subjectPanel()`
                // and `.pageBodyRow` on the `Section` reached each of them: the
                // card drew as three panels — two rows and a stray hairline —
                // each with its own 18pt gap above it.
                Section {
                    SubjectFormRow(label: "Sort by", arrangement: .control) {
                        Menu {
                            Picker("Sort by", selection: sortColumnBinding) {
                                ForEach(AO3WorksSort.allColumns) { column in
                                    Text(column.title).tag(column)
                                }
                            }
                            .labelsHidden()
                        } label: {
                            Text(draft.column.title)
                                .font(.system(size: 14))
                        }
                    }
                    .panelSegment(0, of: 2, gutter: SubjectMetrics.accountGutter)

                    SubjectFormRow(label: "Direction", arrangement: .control) {
                        Picker("Direction", selection: $draft.direction) {
                            ForEach(AO3WorksSortDirection.allCases) { direction in
                                Text(direction.title).tag(direction)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 190)
                    }
                    .panelSegment(1, of: 2, gutter: SubjectMetrics.accountGutter)
                }

                Section {
                    completionChips
                        .subjectPanel()
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                } header: {
                    SectionRuleHeader(title: "Completion")
                        .pageBodyRow(top: 18, gutter: 0)
                } footer: {
                    Text("Completion is applied by AO3 rather than to the page already "
                        + "loaded, so it counts every match across every page.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .pageBodyRow(top: 8, gutter: SubjectMetrics.accountGutter)
                }
            }
            .cardList()
            .navigationTitle("Sort and filter")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .subjectScreenWash(palette: theme.scopePalette)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onApply(draft)
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Apply")
                        .disabled(draft == initial)
                    }
                }
        }
    }

    /// Choosing a column adopts that column's own default direction, the way AO3
    /// does when no direction is sent — so this goes through `select` rather
    /// than assigning `column` and leaving a stale direction behind.
    private var sortColumnBinding: Binding<AO3WorksSortColumn> {
        Binding(
            get: { draft.column },
            set: { draft.select($0) }
        )
    }

    private var completionChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(AO3WorksCompletion.allCases) { option in
                Button {
                    draft.completion = option
                } label: {
                    SubjectChip(
                        text: option.title,
                        style: .pill(isSelected: draft.completion == option),
                        palette: theme.scopePalette
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(draft.completion == option ? [.isSelected] : [])
            }
        }
        .padding(12)
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
    @State private var showingSort = false
    @State private var showingFilters = false

    var body: some View {
        if model.selectedTab == .works {
            if layout == .scroll {
                VStack(alignment: .leading, spacing: 8) {
                    controls
                        .padding(.horizontal, CardListMetrics.sideMargin
                            + CardListMetrics.innerHorizontal)
                }
                .sheet(isPresented: $showingSort) { sortSheet }
                .filterPanelPresentation(isPresented: $showingFilters) { refinePanel }
            } else {
                Section {
                    controls.cardRow()
                }
                .sheet(isPresented: $showingSort) { sortSheet }
                .filterPanelPresentation(isPresented: $showingFilters) { refinePanel }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if showsScopes {
                WorksScopeSegments(scope: scopeBinding)
            }
            Spacer(minLength: 0)
            refineButton
            sortButton
        }
    }

    /// Refine sits beside the sort control rather than inside its sheet. 1v draws
    /// both on one surface and merging them is the right end state, but the two
    /// carry different costs — a sort change refetches from AO3, these facets
    /// narrow pages already parsed — and the panel that renders every facet
    /// correctly already exists. Kept separate until that panel is redesigned to
    /// 1au's card grammar.
    private var refineButton: some View {
        FilterButton(
            filtersActive: model.worksFilters.refineActiveCount > 0,
            showingFilters: $showingFilters,
            filterHelp: "Refine the works on this page",
            onClearFilters: { model.applyWorksFilters(AO3SearchFilters()) },
            badgeCount: model.worksFilters.refineActiveCount
        )
    }

    private var refinePanel: some View {
        AO3FilterPanel(
            filters: filtersBinding,
            mode: .refine,
            canReset: model.worksFilters.refineActiveCount > 0,
            onApply: { showingFilters = false },
            onReset: { model.applyWorksFilters(AO3SearchFilters()) },
            // The same array `AO3AuthorWorksSection` narrows, so 1au's match line
            // and the list behind it cannot disagree.
            refineSource: model.works
        )
        .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
    }

    /// Writes straight through to the model. No draft copy, unlike the sort
    /// sheet: applying a facet costs no request, so the match line and the list
    /// can both move as the reader taps.
    private var filtersBinding: Binding<AO3SearchFilters> {
        Binding(
            get: { model.worksFilters },
            set: { filters in
                onWillChange()
                model.applyWorksFilters(filters)
            }
        )
    }

    /// Sort takes the up/down arrows and leaves the funnel to Refine beside it.
    /// Both drew `line.3.horizontal.decrease` when Refine arrived, which put two
    /// identical glyphs side by side with nothing to tell them apart.
    ///
    /// ponytail: 1v draws ONE control for both, and merging them is the right end
    /// state — the count would then ride on a single funnel as its prose says.
    /// That needs the redesigned panel to host AO3's nine sort fields, so until
    /// then two legible controls beat one ambiguous pair.
    private var sortButton: some View {
        Button {
            showingSort = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                if model.worksSort.activeCount > 0 {
                    Text("\(model.worksSort.activeCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel("Sort and filter")
        .accessibilityValue(model.worksSort.activeCount > 0
            ? "\(model.worksSort.activeCount) active"
            : "default")
    }

    private var sortSheet: some View {
        WorksSortSheet(initial: model.worksSort) { sort in
            onWillChange()
            model.applyWorksSort(sort, auth: auth)
        }
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
