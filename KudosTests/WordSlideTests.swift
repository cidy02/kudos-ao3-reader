import CoreGraphics
import Testing
@testable import Kudos

struct WordSlideTests {
    @Test func oneWordIsTwentyTwoPoints() {
        #expect(KeysBarWordSlide.pointsPerWord == 22)
        let one = KeysBarWordSlide.resolve(travel: 22, direction: 1)
        #expect(one.wordSteps == 1)
        #expect(one.remainder == 0)
    }

    @Test func shortOfAWordCarriesTheRemainder() {
        let short = KeysBarWordSlide.resolve(travel: 21, direction: 1)
        #expect(short.wordSteps == 0)
        #expect(short.remainder == 21)

        let continued = KeysBarWordSlide.resolve(travel: 21, direction: 1, carried: short.remainder)
        #expect(continued.wordSteps == 1)
        #expect(continued.remainder == 20)
    }

    @Test func oneSampleCanCrossSeveralWords() {
        let burst = KeysBarWordSlide.resolve(travel: 50, direction: 1)
        #expect(burst.wordSteps == 2)
        #expect(burst.remainder == 6)

        let twoBack = KeysBarWordSlide.resolve(travel: 44, direction: -1)
        #expect(twoBack.wordSteps == -2)
        #expect(twoBack.remainder == 0)
    }

    @Test func remainderCarriesIntoTheNextSample() {
        let first = KeysBarWordSlide.resolve(travel: 30, direction: 1)
        #expect(first.wordSteps == 1)
        #expect(first.remainder == 8)

        let second = KeysBarWordSlide.resolve(travel: 20, direction: 1, carried: first.remainder)
        #expect(second.wordSteps == 1)
        #expect(second.remainder == 6)
    }

    @Test func reversingDirectionSpendsTheCarriedRemainder() {
        let back = KeysBarWordSlide.resolve(travel: 30, direction: -1, carried: 8)
        #expect(back.wordSteps == -1)
        #expect(back.remainder == 0)
    }

    @Test func noTravelOrNoDirectionKeepsTheRemainder() {
        let still = KeysBarWordSlide.resolve(travel: 0, direction: 1, carried: 8)
        #expect(still.wordSteps == 0)
        #expect(still.remainder == 8)

        let noDirection = KeysBarWordSlide.resolve(travel: 30, direction: 0, carried: 8)
        #expect(noDirection.wordSteps == 0)
        #expect(noDirection.remainder == 8)
    }

    @Test func negativeTravelIsADistance() {
        let forward = KeysBarWordSlide.resolve(travel: -22, direction: 1)
        #expect(forward.wordSteps == 1)
        #expect(forward.remainder == 0)
    }

    @Test func twoFingerSelectStaysLatchedAndAbsorbsCentroidJumpOnFingerLift() {
        var tracker = KeysBarWordSlideTracker()
        let began = tracker.begin(translation: 22, touchCount: 2)
        #expect(began == .init(delta: 22, extend: true))

        let dragged = tracker.change(translation: 44, touchCount: 2)
        #expect(dragged == .init(delta: 22, extend: true))

        // Lifting one finger first shifts UIKit's touch centroid and drops touch count to 1:
        // selection stays extended and the jump does not emit a bogus word step.
        let oneLifted = tracker.change(translation: 74, touchCount: 1)
        #expect(oneLifted == .init(delta: 0, extend: true))

        let wiggle = tracker.change(translation: 80, touchCount: 1)
        #expect(wiggle == .init(delta: 6, extend: true))

        tracker.end()
        let nextSlide = tracker.begin(translation: 22, touchCount: 1)
        #expect(nextSlide == .init(delta: 22, extend: false))
    }

    @Test func secondFingerLandingMidSlideLatchesSelectWithoutCentroidJump() {
        var tracker = KeysBarWordSlideTracker()
        let began = tracker.begin(translation: 10, touchCount: 1)
        #expect(began == .init(delta: 10, extend: false))

        let secondLanded = tracker.change(translation: -20, touchCount: 2)
        #expect(secondLanded == .init(delta: 0, extend: true))

        let moved = tracker.change(translation: 2, touchCount: 2)
        #expect(moved == .init(delta: 22, extend: true))
    }
}
