import SwiftUI

#if os(iOS)
extension WorkDetailPresentation {
    enum PageBlock: Hashable {
        case identity, status, summary, ao3Actions, tags, facts, archiveStats
        case comments, pageActions, series, myCopy
    }

    static let singleColumnBlocks: [PageBlock] = [
        .identity, .status, .summary, .ao3Actions, .tags, .facts, .archiveStats,
        .comments, .pageActions, .series, .myCopy
    ]

    static let leadingBlocks: [PageBlock] = [.identity, .status, .ao3Actions, .archiveStats, .pageActions]
    static let trailingBlocks: [PageBlock] = [.summary, .tags, .facts, .comments, .series, .myCopy]

    /// Minima include the existing row gutters; larger type gets a single
    /// readable region rather than squeezing two columns of enlarged controls.
    static func contentPanes(
        in regions: AdaptiveContentRegions, accessibilitySize: Bool, rightToLeft: Bool = false
    ) -> [CGRect] {
        let physical = regions.viewportPanes
        let ordered = rightToLeft ? Array(physical.reversed()) : physical
        let minimum: CGFloat = accessibilitySize ? 480 : 340
        let gutter: CGFloat = 24
        if ordered.count > 1 {
            let pair = Array(ordered.prefix(2))
            if pair.allSatisfy({ $0.width >= minimum && $0.height >= 480 }) {
                return pair.map(readablePane)
            }
            return ordered.first.map { [readablePane($0)] } ?? []
        }
        guard let pane = ordered.first else { return [] }
        guard pane.width >= minimum * 2 + gutter, pane.height >= 480 else { return [readablePane(pane)] }
        let width = (pane.width - gutter) / 2
        let pair = [
            CGRect(x: pane.minX, y: pane.minY, width: width, height: pane.height),
            CGRect(x: pane.minX + width + gutter, y: pane.minY, width: width, height: pane.height)
        ]
        return (rightToLeft ? Array(pair.reversed()) : pair).map(readablePane)
    }

    private static func readablePane(_ pane: CGRect) -> CGRect {
        let width = min(720, pane.width)
        return CGRect(x: pane.midX - width / 2, y: pane.minY, width: width, height: pane.height)
    }
}

extension WorkDetailView {
    var adaptiveDetailContent: some View {
        GeometryReader { proxy in
            // Always measure this destination, even inside a dashboard/split.
            let regions = AdaptiveContentRegions(viewport: proxy)
            let panes = WorkDetailPresentation.contentPanes(
                in: regions, accessibilitySize: dynamicTypeSize.isAccessibilitySize,
                rightToLeft: detailLayoutDirection == .rightToLeft
            )
            DashboardRegionRow(panes: panes, width: regions.viewport.width, fillsHeight: true) {
                if panes.count == 2 {
                    detailList(WorkDetailPresentation.leadingBlocks)
                        .accessibilityElement(children: .contain)
                        .accessibilitySortPriority(1)
                    detailList(WorkDetailPresentation.trailingBlocks)
                        .accessibilityElement(children: .contain)
                        .accessibilitySortPriority(0)
                } else if panes.count == 1 {
                    detailList(WorkDetailPresentation.singleColumnBlocks, singleColumn: true)
                }
            }
            .frame(width: regions.viewport.width, height: regions.viewport.height)
            .position(x: regions.viewport.midX, y: regions.viewport.midY)
        }
    }

    private func detailList(_ blocks: [WorkDetailPresentation.PageBlock], singleColumn: Bool = false) -> some View {
        List {
            ForEach(blocks, id: \.self) { block in
                switch block {
                case .identity: heroSection
                case .status: statusSection(error: singleColumn ? loadError ?? seriesLoadError : loadError)
                case .summary: summarySection
                case .ao3Actions: ao3ActionsSection
                case .tags: tagSections
                case .facts: factsCardSection
                case .archiveStats: archiveStatsSection
                case .comments: commentsSection
                case .pageActions: pageActionsSection
                case .series:
                    seriesSection
                    if !singleColumn { statusSection(error: seriesLoadError, includesQueueStatus: false) }
                case .myCopy: myCopySection
                }
            }
        }
        .cardList()
        .clipped()
    }
}
#endif
