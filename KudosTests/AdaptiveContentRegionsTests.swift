import SwiftUI
import Testing
@testable import Kudos

@MainActor
@Suite
struct AdaptiveContentRegionsTests {
    @Test func asymmetricSafeAreasAreRemovedExactlyOnce() {
        let regions = AdaptiveContentRegions(
            bounds: CGRect(x: 0, y: 0, width: 951, height: 669),
            safeAreaInsets: EdgeInsets(top: 11, leading: 27, bottom: 34, trailing: 64)
        )
        #expect(regions.safeBounds == CGRect(x: 27, y: 11, width: 860, height: 624))
        #expect(regions.panes == [regions.safeBounds])
        #expect(regions.viewportPanes == [CGRect(x: 0, y: 0, width: 860, height: 624)])
    }

    @Test func translatedDivisionUsesLocalCoordinatesRatherThanTheMidpoint() {
        let regions = AdaptiveContentRegions(
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600),
            safeAreaInsets: EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 72),
            reservations: [.init(frame: CGRect(x: 430, y: -20, width: 40, height: 640))]
        )
        #expect(regions.panes == [
            CGRect(x: 18, y: 0, width: 412, height: 600),
            CGRect(x: 470, y: 0, width: 358, height: 600)
        ])
        #expect(regions.viewportPanes[1].minX == 452)
    }

    @Test func theReservedFrameAlreadyIncludesInteractionMargins() {
        // A core division at 448...452 with 28pt margins arrives as 420...480.
        let frame = CGRect(x: 420, y: 0, width: 60, height: 600)
        let regions = AdaptiveContentRegions(
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600), reservations: [.init(frame: frame)]
        )
        #expect(regions.activeReservations == [frame])
        #expect(regions.panes.map(\.width) == [420, 420])
        #expect(regions.panes[0].maxX == 420)
        #expect(regions.panes[1].minX == 480)
    }

    @Test func inactiveAndOutsideReservationsDoNotDivideContent() {
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let regions = AdaptiveContentRegions(bounds: bounds, reservations: [
            .init(frame: CGRect(x: 430, y: 0, width: 40, height: 600), isActive: false),
            .init(frame: CGRect(x: 1000, y: 0, width: 40, height: 600))
        ])
        #expect(regions.panes == [bounds])
        #expect(regions.activeReservations.count == 1)
    }

    @Test func reservationsOnlyTouchingTheViewportDoNotConsumeIt() {
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let regions = AdaptiveContentRegions(bounds: bounds, reservations: [
            .init(frame: CGRect(x: 900, y: 200, width: 100, height: 40)),
            .init(frame: CGRect(x: 400, y: 600, width: 10, height: 50))
        ])
        #expect(regions.panes == [bounds])
    }

    @Test func activationChangesLayoutWithoutAResize() {
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let frame = CGRect(x: 430, y: 0, width: 40, height: 600)
        let open = AdaptiveContentRegions(bounds: bounds, reservations: [.init(frame: frame, isActive: false)])
        let book = AdaptiveContentRegions(bounds: bounds, reservations: [.init(frame: frame)])
        #expect(open != book)
        #expect(open.panes.count == 1)
        #expect(book.panes.count == 2)
    }

    @Test func aZeroWidthDivisionStillSeparatesPanes() {
        let regions = AdaptiveContentRegions(
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600),
            reservations: [.init(frame: CGRect(x: 420, y: 0, width: 0, height: 600))]
        )
        #expect(regions.panes.map(\.width) == [420, 480])
    }

    @Test func aHorizontalDivisionBoundsTheVerticalScrollViewport() {
        let regions = AdaptiveContentRegions(
            bounds: CGRect(x: 0, y: 0, width: 900, height: 700),
            reservations: [.init(frame: CGRect(x: 0, y: 320, width: 900, height: 40))]
        )
        #expect(regions.viewport == CGRect(x: 0, y: 360, width: 900, height: 340))
        #expect(regions.viewportPanes == [CGRect(x: 0, y: 0, width: 900, height: 340)])
    }

    @Test func anEdgeReservationShrinksAndRebasesTheOnlyViewport() {
        let regions = AdaptiveContentRegions(
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600),
            reservations: [.init(frame: CGRect(x: 0, y: 0, width: 40, height: 600))]
        )
        #expect(regions.viewport == CGRect(x: 40, y: 0, width: 860, height: 600))
        #expect(regions.viewportPanes == [CGRect(x: 0, y: 0, width: 860, height: 600)])
    }

    @Test func aFullyReservedViewportDoesNotFallBackToUnsafeBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let regions = AdaptiveContentRegions(bounds: bounds, reservations: [.init(frame: bounds)])
        #expect(regions.panes.isEmpty)
        #expect(regions.viewport.isEmpty)
    }

    @Test func columnsIncludeGuttersAndNeverForceTwoCardsThatDoNotFit() {
        #expect(AdaptiveContentRegions.columns(in: 371, cardWidth: 164) == 1)
        #expect(AdaptiveContentRegions.columns(in: 372, cardWidth: 164) == 2)
        #expect(AdaptiveContentRegions.columns(in: 900, cardWidth: 164) == 5)
        #expect(AdaptiveContentRegions.columns(in: 420, cardWidth: 720) == 1)
    }

    @Test(arguments: [0, 1, 3, 5, 12, 13])
    func panePagesKeepEveryItemOnceInOriginalOrder(count: Int) {
        let pages = AdaptiveContentRegions.shelfPages(count: count, columns: [2, 2])
        let readingOrder = pages.flatMap { panes in
            (0..<2).flatMap { row in
                panes.flatMap { Array($0.dropFirst(row * 2).prefix(2)) }
            }
        }
        #expect(readingOrder == Array(0..<count))
        #expect(pages.flatMap { $0 }.allSatisfy { $0.count <= 4 })
    }

    @Test func bookPagesAssignCardsAcrossBothPanesBeforeTheNextRow() {
        #expect(AdaptiveContentRegions.shelfPages(count: 12, columns: [2, 2]) == [
            [[0, 1, 4, 5], [2, 3, 6, 7]], [[8, 9], [10, 11]]
        ])
        #expect(AdaptiveContentRegions.shelfPages(count: 11, columns: [3, 2]) == [
            [[0, 1, 2, 5, 6, 7], [3, 4, 8, 9]], [[10], []]
        ])
    }

    @Test func aOneColumnPageKeepsLargeTypeToOneCardPerPane() {
        #expect(AdaptiveContentRegions.shelfPages(count: 3, columns: [1, 1]) == [[[0], [1]], [[2], []]])
    }

    @Test func shortWideViewportsKeepTheCompactDashboard() {
        let short = AdaptiveContentRegions(bounds: CGRect(x: 0, y: 0, width: 900, height: 300))
        #expect(!AdaptiveContentRegions.usesGroupedShelves(in: short.viewport.size))
        #expect(short.resumePanes(hasNext: true, cardWidth: 164) == nil)
        #expect(AdaptiveContentRegions.usesGroupedShelves(in: CGSize(width: 669, height: 900)))
        #expect(!AdaptiveContentRegions.usesGroupedShelves(in: CGSize(width: 434, height: 600)))
    }

    @Test func theHeroAndTwoNaturalSizeNeighboursMustBothFit() throws {
        let narrow = AdaptiveContentRegions(bounds: CGRect(x: 0, y: 0, width: 695, height: 600))
        #expect(narrow.resumePanes(hasNext: true, cardWidth: 164) == nil)
        let fitting = AdaptiveContentRegions(bounds: CGRect(x: 0, y: 0, width: 696, height: 600))
        let panes = try #require(fitting.resumePanes(hasNext: true, cardWidth: 164))
        #expect(panes[0].width >= 300)
        #expect(panes[1].width >= 372)
        #expect(panes[0].maxX + 24 == panes[1].minX)
        #expect(panes[1].maxX == 696)
        #expect(fitting.resumePanes(hasNext: false, cardWidth: 164) == nil)
        #expect(fitting.resumePanes(hasNext: true, cardWidth: 720) == nil)
    }

    @Test func bookHeroStaysInTheLogicalLeadingPaneEvenAtAX5() throws {
        let regions = AdaptiveContentRegions(
            bounds: CGRect(x: 0, y: 0, width: 900, height: 600),
            reservations: [.init(frame: CGRect(x: 430, y: 0, width: 40, height: 600))]
        )
        let panes = try #require(regions.resumePanes(hasNext: true, cardWidth: 720))
        #expect(panes == regions.viewportPanes)
        #expect(regions.resumePanes(hasNext: false, cardWidth: 720) == [panes[0]])
        #expect(regions.resumePanes(hasNext: true, cardWidth: 720, rightToLeft: true) == Array(panes.reversed()))
    }
}
