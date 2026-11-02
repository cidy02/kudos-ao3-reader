import SwiftUI

#if os(iOS)
extension WorkDetailPresentation {
    enum PageBlock: Hashable {
        case identity, status, stats, summary, tags, series, myCopy, comments
    }

    /// Board 19's order, top to bottom.
    static let singleColumnBlocks: [PageBlock] = [
        .identity, .status, .stats, .summary, .tags, .series, .myCopy, .comments
    ]

    /// T-455's two regions: identity, Resume and the stats card lead; the
    /// summary, tags, series, My copy and Comments trail.
    static let leadingBlocks: [PageBlock] = [.identity, .status, .stats]
    static let trailingBlocks: [PageBlock] = [.summary, .tags, .series, .myCopy, .comments]

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
                        .environment(\.subjectWashScroll, nil)
                        .accessibilityElement(children: .contain)
                        .accessibilitySortPriority(0)
                } else if panes.count == 1 {
                    detailList(WorkDetailPresentation.singleColumnBlocks, singleColumn: true)
                }
            }
            .modifier(WashPaneCountReset(paneCount: panes.count))
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
                case .stats: statsSection
                case .summary: summarySection
                case .tags: tagSections
                case .series:
                    seriesSection
                    if !singleColumn { statusSection(error: seriesLoadError, includesQueueStatus: false) }
                case .comments: commentsSection
                case .myCopy: myCopySection
                }
            }
        }
        .cardList()
        .clipped()
    }
}

private struct WashPaneCountReset: ViewModifier {
    let paneCount: Int
    @Environment(\.subjectWashScroll) private var subjectWashScroll

    func body(content: Content) -> some View {
        content.onChange(of: paneCount) { subjectWashScroll?(0) }
    }
}
#endif
