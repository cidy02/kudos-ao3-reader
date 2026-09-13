import SwiftUI
import Testing
@testable import Kudos

struct CardListMetricsTests {
    /// What a reader actually sees between a card's edge and its content, on each
    /// of the four sides. Derived from the two inset sets `.cardRow()` really
    /// applies — the row's, which content sits inside, minus the card's, which is
    /// drawn as that row's background — rather than restated here, so the test
    /// fails if either one moves.
    private func paddingInsideCard(
        verticalPadding: CGFloat = CardListMetrics.innerVertical,
        interCardSpacing: CGFloat = CardListMetrics.interCardSpacing
    ) -> EdgeInsets {
        let row = CardListMetrics.rowInsets(
            verticalPadding: verticalPadding, interCardSpacing: interCardSpacing
        )
        let card = CardListMetrics.cardInsets(interCardSpacing: interCardSpacing)
        return EdgeInsets(
            top: row.top - card.top,
            leading: row.leading - card.leading,
            bottom: row.bottom - card.bottom,
            trailing: row.trailing - card.trailing
        )
    }

    /// Top against bottom. They come from the same two expressions, so this is
    /// really a guard against someone giving one edge a special case later.
    @Test func topAndBottomPaddingMatch() {
        let padding = paddingInsideCard()
        #expect(padding.top == padding.bottom)
    }

    /// Leading against trailing, for the same reason.
    @Test func leadingAndTrailingPaddingMatch() {
        let padding = paddingInsideCard()
        #expect(padding.leading == padding.trailing)
    }

    /// And the two axes against each other — the one that was actually wrong.
    /// `innerVertical` was 10 against `innerHorizontal`'s 16 until 2026-09-12,
    /// because the half inter-card gap in the row's vertical insets reads like
    /// part of the card's padding and is not: it falls between cards.
    @Test func everyEdgeHasTheSamePadding() {
        let padding = paddingInsideCard()
        #expect(padding.top == padding.leading)
        #expect(padding.bottom == padding.trailing)
    }

    /// The half-gap each card gives up at its top and bottom must add back up to
    /// the whole `interCardSpacing` between two neighbours. This is what makes
    /// subtracting it above correct — if the card were inset by the full spacing,
    /// squaring the padding would have closed the gap between cards instead.
    @Test func neighbouringCardsLeaveTheFullInterCardSpacingBetweenThem() {
        let card = CardListMetrics.cardInsets(interCardSpacing: CardListMetrics.interCardSpacing)
        #expect(card.bottom + card.top == CardListMetrics.interCardSpacing)
    }

    /// A caller that asks for its own vertical padding gets exactly that inside
    /// the card, with the inter-card gap still outside it — `bareListRow` and
    /// Account's compact control rows both rely on this.
    @Test func aCustomVerticalPaddingLandsInsideTheCardUntouched() {
        let padding = paddingInsideCard(verticalPadding: 4, interCardSpacing: 30)
        #expect(padding.top == 4)
        #expect(padding.bottom == 4)
    }
}
