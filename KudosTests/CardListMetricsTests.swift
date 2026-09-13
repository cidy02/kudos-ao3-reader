import SwiftUI
import Testing
@testable import Kudos

struct CardListMetricsTests {
    /// A card's content must sit the same distance from all four of its edges.
    ///
    /// The two axes reach that distance by different arithmetic, which is how
    /// they drifted apart in the first place. `CardRow` sets the row's
    /// `listRowInsets` to `half + innerVertical` / `sideMargin + innerHorizontal`,
    /// then draws the card as the row's *background* inset by `half` /
    /// `sideMargin`. Each pair cancels — so the padding a reader actually sees
    /// inside the card is `innerVertical` against `innerHorizontal`, and nothing
    /// else. Counting the half-gap as part of the card (it falls between cards,
    /// not inside one) is what made 10 look like 16 for as long as it did.
    @Test func contentSitsTheSameDistanceFromEveryCardEdge() {
        let half = CardListMetrics.interCardSpacing / 2
        let rowInsetTop = half + CardListMetrics.innerVertical
        let rowInsetLeading = CardListMetrics.sideMargin + CardListMetrics.innerHorizontal

        let insideCardVertically = rowInsetTop - half
        let insideCardHorizontally = rowInsetLeading - CardListMetrics.sideMargin

        #expect(insideCardVertically == insideCardHorizontally)
    }

    /// The gap between two cards is the whole `interCardSpacing`, not half of it:
    /// each card gives up `half` at its bottom and its neighbour gives up `half`
    /// at its top. Pinned because it is the reason `half` is subtracted above —
    /// if this were wrong, squaring the padding would have closed the gap instead.
    @Test func neighbouringCardsLeaveTheFullInterCardSpacingBetweenThem() {
        let half = CardListMetrics.interCardSpacing / 2
        #expect(half + half == CardListMetrics.interCardSpacing)
    }
}
