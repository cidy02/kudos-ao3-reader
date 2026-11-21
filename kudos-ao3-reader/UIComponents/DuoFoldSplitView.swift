import SwiftUI

/// Which logical edge of a Duo split pane faces the fold, so horizontal carousels
/// mask right at the fold clearance while outer edges keep their 16 pt screen margin.
nonisolated enum DuoPaneFoldEdge: Equatable, Sendable {
    case none
    case leading
    case trailing
}

extension EnvironmentValues {
    @Entry var duoPaneFoldEdge: DuoPaneFoldEdge = .none
}

/// Two panes split at the iPhone Duo's vertical fold:
/// - Open flat (`!panes.isBookPose`): one shared `ScrollView`; both panes scroll together
///   with 40 pt clear across the fold (`Duo-Open-Home`, `Duo-Open-Library-Root`).
/// - Book pose (`panes.isBookPose`): two independent `ScrollView`s, each inset 16 pt from
///   the fold shadow (`Duo-Book-Home`).
///
/// Inside each pane, `\.dashboardContentRegions` is cleared so nested carousels render
/// single-row horizontal shelves rather than 2-row wide grids, and `.dashboardLeadingRegion()`
/// becomes a no-op so trailing-pane sections stay in the trailing pane. The fold-facing
/// built-in 16 pt section gutter is absorbed with negative edge padding while
/// `\.duoPaneFoldEdge` clips horizontal carousels cleanly at the pane edge.
struct DuoFoldSplitScrollView<Leading: View, Trailing: View>: View {
    let panes: DuoFoldPanes
    let viewportWidth: CGFloat
    var spacing: CGFloat = SubjectMetrics.sectionSpacing
    var verticalPadding: CGFloat = 12
    var onRefresh: (@Sendable () async -> Void)?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let ordered = panes.ordered(rightToLeft: layoutDirection == .rightToLeft)
        let paneRects = [ordered.leading, ordered.trailing]
        if panes.isBookPose {
            DashboardRegionRow(panes: paneRects, width: viewportWidth, fillsHeight: true) {
                paneScroll(foldEdge: .trailing, width: ordered.leading.width) { leading() }
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(1)
                paneScroll(foldEdge: .leading, width: ordered.trailing.width) { trailing() }
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(0)
            }
        } else {
            sharedScroll {
                DashboardRegionRow(panes: paneRects, width: viewportWidth) {
                    paneColumn(foldEdge: .trailing, width: ordered.leading.width) { leading() }
                        .accessibilityElement(children: .contain)
                        .accessibilitySortPriority(1)
                    paneColumn(foldEdge: .leading, width: ordered.trailing.width) { trailing() }
                        .accessibilityElement(children: .contain)
                        .accessibilitySortPriority(0)
                }
                .padding(.vertical, verticalPadding)
            }
        }
    }

    @ViewBuilder
    private func sharedScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let onRefresh {
            ScrollView { content() }
                .refreshable { await onRefresh() }
        } else {
            ScrollView { content() }
        }
    }

    @ViewBuilder
    private func paneScroll<Content: View>(
        foldEdge: DuoPaneFoldEdge,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let scroll = ScrollView {
            paneColumn(foldEdge: foldEdge, width: width) { content() }
                .padding(.vertical, verticalPadding)
        }
        if let onRefresh {
            scroll.refreshable { await onRefresh() }
        } else {
            scroll
        }
    }

    private func paneColumn<Content: View>(
        foldEdge: DuoPaneFoldEdge,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(foldEdge == .trailing ? .trailing : .leading, -SubjectMetrics.gutter)
        .frame(width: width, alignment: .topLeading)
        .environment(\.dashboardContentRegions, nil)
        .environment(\.duoPaneFoldEdge, foldEdge)
    }
}

/// Reads `\.duoLayout`, `\.dashboardContentRegions` and `\.dashboardViewportMinX`
/// *inside* `DashboardRegionHost` so dashboard screens (`HomeView`, `LibraryView`)
/// switch to two fold-split panes on the open/Book iPhone Duo and keep their exact
/// existing single-scroll layout everywhere else (iPhone, Upright, Cover, iPad, Mac,
/// or when a filter inspector narrows the host past the fold).
struct DuoFoldAdaptiveScrollHost<Leading: View, Trailing: View, Fallback: View>: View {
    var spacing: CGFloat = SubjectMetrics.sectionSpacing
    var verticalPadding: CGFloat = 12
    var onRefresh: (@Sendable () async -> Void)?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var fallback: () -> Fallback

    @Environment(\.duoLayout) private var duoLayout
    @Environment(\.dashboardContentRegions) private var regions
    @Environment(\.dashboardViewportMinX) private var viewportMinX

    private var activeVerticalDivision: CGRect? {
        regions?.divisionFrames.first { $0.height > $0.width }
    }

    var body: some View {
        if let regions,
           let panes = duoLayout.foldPanes(
               viewportWidth: regions.viewport.width,
               viewportMinX: viewportMinX,
               viewportHeight: regions.viewport.height,
               activeDivision: activeVerticalDivision
           ) {
            DuoFoldSplitScrollView(
                panes: panes,
                viewportWidth: regions.viewport.width,
                spacing: spacing,
                verticalPadding: verticalPadding,
                onRefresh: onRefresh,
                leading: leading,
                trailing: trailing
            )
        } else {
            fallback()
        }
    }
}
