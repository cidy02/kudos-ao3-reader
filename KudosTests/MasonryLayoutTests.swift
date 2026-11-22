import CoreGraphics
import Testing
@testable import Kudos

struct MasonryLayoutTests {
    @Test func singleColumnStacksVertically() {
        let layout = MasonryLayout(columns: 1, spacing: 10, rowSpacing: 10)
        let sizes = [
            CGSize(width: 100, height: 40),
            CGSize(width: 100, height: 60),
            CGSize(width: 100, height: 30)
        ]
        let result = layout.arrange(sizes: sizes, width: 100)

        #expect(result.origins == [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 50),
            CGPoint(x: 0, y: 120)
        ])
        #expect(result.size == CGSize(width: 100, height: 150))
    }

    @Test func twoColumnsAlternateShortestColumn() {
        let layout = MasonryLayout(columns: 2, spacing: 10, rowSpacing: 10)
        let sizes = [
            CGSize(width: 45, height: 100), // Col 0 -> height becomes 110
            CGSize(width: 45, height: 50),  // Col 1 -> height becomes 60
            CGSize(width: 45, height: 60),  // Col 1 (60 < 110) -> height becomes 60 + 60 + 10 = 130
            CGSize(width: 45, height: 40)   // Col 0 (110 < 130) -> height becomes 110 + 40 + 10 = 160
        ]
        let result = layout.arrange(sizes: sizes, width: 100)

        #expect(result.origins == [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 55, y: 0),
            CGPoint(x: 55, y: 60),
            CGPoint(x: 0, y: 110)
        ])
        // contentHeight is max(160, 130) - 10 = 150
        #expect(result.size == CGSize(width: 100, height: 150))
    }

    @Test func emptySizesReturnsZero() {
        let layout = MasonryLayout(columns: 2, spacing: 10, rowSpacing: 10)
        let result = layout.arrange(sizes: [], width: 300)
        #expect(result.origins.isEmpty)
        #expect(result.size == .zero)
    }

    @Test func guardAgainstZeroOrNegativeColumns() {
        let layoutZero = MasonryLayout(columns: 0, spacing: 10, rowSpacing: 10)
        let resultZero = layoutZero.arrange(sizes: [CGSize(width: 50, height: 50)], width: 100)
        #expect(resultZero.origins == [CGPoint(x: 0, y: 0)])
        #expect(resultZero.size == CGSize(width: 100, height: 50))

        let layoutNegative = MasonryLayout(columns: -2, spacing: 10, rowSpacing: 10)
        let resultNeg = layoutNegative.arrange(sizes: [CGSize(width: 50, height: 50)], width: 100)
        #expect(resultNeg.origins == [CGPoint(x: 0, y: 0)])
        #expect(resultNeg.size == CGSize(width: 100, height: 50))
    }

    @Test func explicitColumnSpansKeepFoldGutterClearAndMeasureEachColumnWidth() {
        let spans = [
            MasonryLayout.ColumnSpan(minX: 0, width: 439.5),
            MasonryLayout.ColumnSpan(minX: 479.5, width: 355.5)
        ]
        let layout = MasonryLayout(columns: 2, spacing: 10, rowSpacing: 8, columnSpans: spans)
        var measuredWidths: [CGFloat] = []
        let result = layout.arrange(count: 3, width: 835) { index, columnWidth in
            measuredWidths.append(columnWidth)
            return CGSize(width: columnWidth, height: index == 0 ? 120 : 100)
        }
        #expect(measuredWidths == [439.5, 355.5, 355.5])
        #expect(result.frames == [
            CGRect(x: 0, y: 0, width: 439.5, height: 120),
            CGRect(x: 479.5, y: 0, width: 355.5, height: 100),
            CGRect(x: 479.5, y: 108, width: 355.5, height: 100)
        ])
        // Nothing enters the 40 pt fold clear (439.5..<479.5).
        #expect(result.frames.allSatisfy { $0.maxX <= 439.5 || $0.minX >= 479.5 })
        #expect(result.size == CGSize(width: 835, height: 208))
    }
}
