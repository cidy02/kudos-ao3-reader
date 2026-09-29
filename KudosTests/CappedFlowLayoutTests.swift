import CoreGraphics
import Testing
@testable import Kudos

/// 1g's two-row chip cluster: chips wrap, stop at two rows, and the trailing
/// "+N more" chip always keeps a place after the ones that fit.
struct CappedFlowLayoutTests {
    private let layout = CappedFlowLayout(spacing: 10, rowSpacing: 5, maxRows: 2)
    private let chip = CGSize(width: 40, height: 20)

    @Test func stopsAtTwoRowsAndKeepsTheTrailingChip() {
        // Width 100 holds two 40s per row (40 + 10 + 40). Five chips + trailing
        // need three rows, so chips drop until the trailing one fits on row two.
        let result = layout.arrange(sizes: Array(repeating: chip, count: 5), trailing: chip, width: 100)
        #expect(result.fitCount == 3)
        #expect(result.trailing == CGPoint(x: 50, y: 25))
        #expect(result.origins.compactMap { $0 } == [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 0, y: 25)])
        #expect(result.origins.suffix(2).allSatisfy { $0 == nil })
        #expect(result.size == CGSize(width: 90, height: 45))
    }

    @Test func everythingFitsWhenThereIsRoom() {
        let result = layout.arrange(sizes: [chip, chip], trailing: .zero, width: 400)
        #expect(result.fitCount == 2)
        #expect(result.size.height == 20)
    }
}
